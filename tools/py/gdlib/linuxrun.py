"""`gd linux ...`: run any gd command inside a Debian 12 container with the Linux build of Godot.

Layout (all under .cache/linux-<arch>/, created by gd, safe to delete with `gd linux --arch A --reset`):
    game/    mirror of the host game/ (without .godot); the container has its OWN .godot here, so the
             host (macOS) import cache and the Linux one never touch each other
    cache/   the container's /work/.cache (import marker, lock files)
The repo's tools/gd + tools/py are mounted read-only, so the inner command is literally the same gd.
Runs are serialised per architecture with an exclusive host-side lock: file locks do not reliably cross the
Docker Desktop file-sharing layer, and emulated amd64 runs are too slow to want more than one anyway.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

from . import env, locks
from .godotrun import run_process

IMAGE = "meridian-linux-runner"
DOCKERFILE = env.TOOLS_DIR / "docker" / "Dockerfile"


def _docker(*args: str, check: bool = False, capture: bool = True) -> "subprocess.CompletedProcess[str]":
    return subprocess.run(["docker", *args], capture_output=capture, text=True, check=check)


def ensure_docker() -> None:
    if shutil.which("docker") is None:
        env.die("docker is not installed / not on PATH (gd linux needs Docker)", 2)
    r = _docker("info", "--format", "{{.ServerVersion}}")
    if r.returncode != 0:
        env.die("the Docker daemon is not running (start Docker Desktop): " + r.stderr.strip()[:200], 2)


def ensure_image(arch: str, rebuild: bool, verbose: bool) -> str:
    tag = f"{IMAGE}:{arch}"
    have = _docker("image", "inspect", tag, "--format", "{{.Id}}").returncode == 0
    if have and not rebuild:
        return tag
    print(f"gd linux: building {tag} from {DOCKERFILE.relative_to(env.ROOT)} (first time takes a few minutes) ...", file=sys.stderr, flush=True)
    t0 = time.time()
    res = run_process(["docker", "build", "--platform", f"linux/{arch}", "-t", tag, "-f", str(DOCKERFILE), str(DOCKERFILE.parent)],
                      timeout=1800, stall_after_error=None, echo=verbose, verbose=verbose, prefix="  docker> ")
    if res.rc != 0:
        for line in res.lines[-25:]:
            print("  docker> " + line, file=sys.stderr)
        env.die(f"docker build failed for {tag}", 1)
    if arch == "amd64":
        _docker("tag", tag, f"{IMAGE}:latest")  # `meridian-linux-runner` (untagged) = the shipping target
    print(f"gd linux: image {tag} ready in {time.time() - t0:.0f}s", file=sys.stderr, flush=True)
    return tag


def sync_tree(src: Path, dst: Path) -> Tuple[int, int, int]:
    """Mirror src into dst by (size, mtime_ns); never touches dst/.godot. Returns (copied, deleted, total)."""
    copied = deleted = total = 0
    dst.mkdir(parents=True, exist_ok=True)
    wanted = set()
    stack = [src]
    while stack:
        d = stack.pop()
        for e in os.scandir(d):
            rel = os.path.relpath(e.path, src)
            top = rel.split(os.sep, 1)[0]
            if top in (".godot", ".import") or e.name == ".DS_Store" or e.name.startswith(".git"):
                continue
            if e.is_dir(follow_symlinks=False):
                if (dst / rel).is_file() or (dst / rel).is_symlink():
                    (dst / rel).unlink()  # a file became a directory
                (dst / rel).mkdir(parents=True, exist_ok=True)
                wanted.add(rel)
                stack.append(Path(e.path))
                continue
            wanted.add(rel)
            total += 1
            s = e.stat()
            t = dst / rel
            try:
                ts = t.stat()
                if ts.st_size == s.st_size and ts.st_mtime_ns == s.st_mtime_ns:
                    continue
            except OSError:
                pass
            if t.is_dir() and not t.is_symlink():
                shutil.rmtree(t)  # a directory became a file
            shutil.copy2(e.path, t)
            copied += 1
    # delete what vanished from the source (files first, then empty dirs, deepest first)
    doomed = []
    for root, dirs, files in os.walk(dst):
        rel_root = os.path.relpath(root, dst)
        dirs[:] = [x for x in dirs if not (rel_root == "." and x in (".godot", ".import"))]
        for name in files + dirs:
            rel = os.path.normpath(os.path.join(rel_root, name))
            if rel not in wanted:
                doomed.append(dst / rel)
    for p in sorted(set(doomed), key=lambda x: len(x.parts), reverse=True):
        if p.is_dir() and not p.is_symlink():
            shutil.rmtree(p, ignore_errors=True)
        elif p.exists() or p.is_symlink():
            p.unlink()
        deleted += 1
    return copied, deleted, total


def engine_for(arch: str) -> Path:
    binary = env.LINUX_BINS[arch]
    if not binary.exists():
        env.die(f"Linux {arch} engine missing: {binary}\n     run `python3 tools/py/fetch_engines.py --linux-{'x86_64' if arch == 'amd64' else 'arm64'}`", 2)
    return binary


def _rewrite_shot(inner: Sequence[str]) -> Tuple[List[str], "Path | None", str]:
    """`shot <scene> <out.png>`: the container cannot write to the host path, so it writes into the mounted
    cache dir and the file is copied to the requested host path afterwards."""
    toks = list(inner)
    if not toks or toks[0] != "shot":
        return toks, None, ""
    valued = {"--frames", "--size", "--rendering-method", "--timeout"}
    positional: List[int] = []
    i = 1
    while i < len(toks) and toks[i] != "--":
        if toks[i].startswith("--"):
            i += 2 if toks[i] in valued else 1
            continue
        positional.append(i)
        i += 1
    if len(positional) < 2:
        return toks, None, ""
    host_out = Path(toks[positional[1]]).expanduser().resolve()
    inside = f"/work/.cache/shot_out/{host_out.name}"
    toks[positional[1]] = inside
    return toks, host_out, inside


def cmd_linux(opts: Dict[str, object], inner: Sequence[str]) -> int:
    arch = str(opts.get("arch") or "amd64")
    verbose = bool(opts.get("verbose"))
    ensure_docker()
    work = env.CACHE / f"linux-{arch}"
    if inner and inner[0] == "--reset":
        shutil.rmtree(work, ignore_errors=True)
        print(f"gd linux: removed {work}")
        return 0
    binary = engine_for(arch)
    inner_list, host_shot, inside_shot = _rewrite_shot(inner)
    if host_shot is not None and arch == "arm64" and "--rendering-method" not in inner_list:
        # Debian 12's Mesa 22.3 / LLVM 15 lavapipe aborts compiling shaders on aarch64 ("LLVM ERROR: Cannot select ...
        # fs_variant_partial"): Forward+ and Mobile crash there, the OpenGL compatibility renderer works.
        at = inner_list.index("--") if "--" in inner_list else len(inner_list)  # options go before the user-args separator
        inner_list[at:at] = ["--rendering-method", "gl_compatibility"]
        print("gd linux: arm64 container -> using --rendering-method gl_compatibility (lavapipe Forward+/Mobile crash on aarch64 LLVM 15)",
              file=sys.stderr, flush=True)
    inner = inner_list
    tag = ensure_image(arch, bool(opts.get("rebuild")), verbose)
    work.mkdir(parents=True, exist_ok=True)
    (work / "cache").mkdir(exist_ok=True)
    lock = locks.RWLock(env.CACHE, f"gd-linux-{arch}")
    name = f"meridian-linux-{arch}-{os.getpid()}"
    with lock.exclusive(f"gd linux {' '.join(inner[:2])}"):
        if not opts.get("keep"):
            t0 = time.time()
            copied, deleted, total = sync_tree(env.GAME, work / "game")
            if verbose or copied or deleted:
                print(f"gd linux: synced game/ -> {work.relative_to(env.ROOT)}/game ({copied} copied, {deleted} removed, {total} files, {time.time() - t0:.1f}s)",
                      file=sys.stderr, flush=True)
        cmd: List[str] = ["docker", "run", "--rm", "--init", "--name", name, "--platform", f"linux/{arch}",
                          "-v", f"{work / 'game'}:/work/game",
                          "-v", f"{work / 'cache'}:/work/.cache",
                          "-v", f"{env.TOOLS_DIR / 'gd'}:/work/tools/gd:ro",
                          "-v", f"{env.TOOLS_DIR / 'py'}:/work/tools/py:ro",
                          "-v", f"{binary.parent}:/opt/godot:ro",
                          "-e", "GD_ROOT=/work", "-e", f"GODOT_BIN=/opt/godot/{binary.name}", "-e", "HOME=/tmp/home"]
        if env.DOCS_ROOT.is_dir():
            cmd += ["-v", f"{env.DOCS_ROOT}:/work/tools/godot_docs:ro"]
        builds = env.ROOT / "builds"
        if builds.exists():
            cmd += ["-v", f"{builds}:/work/builds:ro"]
        if sys.platform.startswith("linux") and hasattr(os, "getuid"):
            cmd += ["--user", f"{os.getuid()}:{os.getgid()}"]  # keep mirror files owned by the host user
        cmd += [tag, "python3", "/work/tools/gd", *inner]
        timeout = float(opts.get("timeout") or 3600)
        line_map = (lambda l: l.replace(inside_shot, str(host_shot))) if host_shot else None
        if host_shot:
            shutil.rmtree(work / "cache" / "shot_out", ignore_errors=True)
        try:
            res = run_process(cmd, timeout=timeout, stall_after_error=None, verbose=verbose, line_map=line_map)
            if host_shot is not None:
                produced = work / "cache" / "shot_out" / host_shot.name
                if produced.exists():
                    host_shot.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(produced, host_shot)
        finally:
            if _docker("container", "inspect", name).returncode == 0:
                _docker("rm", "-f", name)  # only ever our own, uniquely named container
    return res.rc

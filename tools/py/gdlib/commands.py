"""Implementations of `gd import|check|test|run|shot` (host-native Godot). See tools/gd for the CLI."""
from __future__ import annotations

import concurrent.futures
import contextlib
import json
import os
import re
import shutil
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

from . import env, locks, tracking
from .godotrun import RunResult, run_process

EXIT_OK = 0
EXIT_FAIL = 1
EXIT_USAGE = 2
EXIT_ENGINE_ERRORS = 3  # `gd run` saw engine error lines although Godot exited 0
EXIT_TIMEOUT = 124

DEFAULT_SCAN_ROOTS = ["res://src", "res://tests"]
CHECK_SCRIPT = "res://tests/harness/check_scripts.gd"
RUNNER_SCRIPT = "res://tests/runner.gd"
WARNING_SUFFIX = "(Warning treated as error.)"

# Godot's warning messages -> warning code, so `gd check` can print the name needed by @warning_ignore("...").
WARNING_CODES: List[Tuple[str, str]] = [
    (r"is used before being assigned a value", "unassigned_variable"),
    (r"is modified before being assigned a value|op-assign", "unassigned_variable_op_assign"),
    (r"has no static (return )?type", "untyped_declaration"),
    (r"has an implicitly inferred static type", "inferred_declaration"),
    (r"declared but never used in the block", "unused_variable"),
    (r"local constant .* declared but never used", "unused_local_constant"),
    (r"class variable .* declared but never used", "unused_private_class_variable"),
    (r"parameter .* is never used", "unused_parameter"),
    (r"signal .* declared but never explicitly used", "unused_signal"),
    (r"shadowing an already-declared \w+ in the base class|at the base class", "shadowed_variable_base_class"),
    (r"is shadowing an already-declared", "shadowed_variable"),
    (r"has the same name as (a|an) ", "shadowed_global_identifier"),
    (r"^Unreachable code", "unreachable_code"),
    (r"Unreachable pattern", "unreachable_pattern"),
    (r"^Standalone expression", "standalone_expression"),
    (r"^Standalone ternary", "standalone_ternary"),
    (r"ternary operator are not mutually compatible", "incompatible_ternary"),
    (r"is not present on the inferred type .* property|^The property .* is not present on the inferred type", "unsafe_property_access"),
    (r"^The method .* is not present on the inferred type", "unsafe_method_access"),
    (r"^Casting \"Variant\" to", "unsafe_cast"),
    (r"requires the subtype .* but the supertype", "unsafe_call_argument"),
    (r"^A void function cannot return a value|unsafe.*void", "unsafe_void_return"),
    (r"returns a value that will be discarded", "return_value_discarded"),
    (r"is a static function but was called from an instance", "static_called_on_instance"),
    (r"@static_unload", "redundant_static_unload"),
    (r"await\" keyword is unnecessary", "redundant_await"),
    (r"await\" keyword might be desired", "missing_await"),
    (r"Assert statement is redundant", "assert_always_true"),
    (r"Assert statement will raise an error", "assert_always_false"),
    (r"^Integer division", "integer_division"),
    (r"^Narrowing conversion", "narrowing_conversion"),
    (r"Integer used when an enum value is expected", "int_as_enum_without_cast"),
    (r"no enum member has matching value", "int_as_enum_without_match"),
    (r"has an enum type and doesn't set an explicit default", "enum_variable_without_default"),
    (r"^Empty script file", "empty_file"),
    (r"keyword is deprecated", "deprecated_keyword"),
    (r"has misleading characters", "confusable_identifier"),
    (r"will be shadowed below in the block", "confusable_local_declaration"),
    (r"Reassigning lambda capture", "confusable_capture_reassignment"),
    (r"overrides a method from native class", "native_method_override"),
    (r"base class script has the \"@tool\"", "missing_tool"),
]


def warning_code(message: str) -> str:
    for pattern, code in WARNING_CODES:
        if re.search(pattern, message):
            return code
    return "warning"


@dataclass
class Finding:
    file: str
    line: int
    message: str
    code: str = ""

    def key(self) -> Tuple[str, int, str]:
        return (self.file, self.line, self.message)

    def display(self, kind: str) -> str:
        where = env.res_to_display(self.file)
        tag = f"{kind}[{self.code}]" if self.code else kind
        return f"{where}:{self.line}: {tag}: {self.message}"


@dataclass
class Ctx:
    """Everything a command needs; built once per gd invocation."""
    binary: Path
    game: Path
    lock: locks.RWLock
    state: tracking.ImportState
    verbose: bool = False
    timeout: float = 0.0

    @staticmethod
    def create(verbose: bool = False, need_project: bool = True) -> "Ctx":
        binary = env.godot_bin()
        if not binary.exists():
            env.die(f"Godot binary not found: {binary}\n"
                    "     run `python3 tools/py/fetch_engines.py` or set GODOT_BIN=/path/to/godot", 2)
        if need_project and not (env.GAME / "project.godot").exists():
            env.die(f"no Godot project at {env.GAME} (missing project.godot)", 2)
        env.CACHE.mkdir(parents=True, exist_ok=True)
        return Ctx(
            binary=binary, game=env.GAME, lock=locks.RWLock(env.CACHE, "gd"),
            state=tracking.ImportState(env.CACHE / "import_state.json", env.GAME, binary), verbose=verbose,
        )

    def godot(self, *args: str) -> List[str]:
        return [str(self.binary), "--path", str(self.game), *args]


# ---------------------------------------------------------------------------------------------------
# import
# ---------------------------------------------------------------------------------------------------
def _import_filter(line: str) -> bool:
    return bool(line.strip()) and not line.startswith("[ DONE ]")


def import_locked(ctx: Ctx, echo: bool = True) -> Tuple[bool, RunResult]:
    """Run `godot --import`. The caller must hold the EXCLUSIVE lock."""
    snap = ctx.state.snapshot()  # taken BEFORE: edits made during the import keep the tree stale
    t0 = time.time()
    res = run_process(
        ctx.godot("--headless", "--import"), timeout=ctx.timeout or 600, stall_after_error=60,
        echo=echo, verbose=ctx.verbose, drop_progress=True, line_filter=_import_filter, prefix="  import> ",
    )
    ok = res.rc == 0 and not res.timed_out and not res.stalled
    if ok:
        # Godot exits 0 even when it printed resource errors; the marker is still valid (the class cache was written).
        ctx.state.save(snap, time.time() - t0)
    return ok, res


def cmd_import(args: "object") -> int:
    ctx = Ctx.create(getattr(args, "verbose", False))
    ctx.timeout = getattr(args, "timeout", 0) or 0
    with ctx.lock.exclusive("gd import"):
        if getattr(args, "if_stale", False):
            stale, reason = ctx.state.is_stale()
            if not stale:
                print("gd: import up to date, nothing to do")
                return EXIT_OK
        t0 = time.time()
        ok, res = import_locked(ctx)
    if not ok or res.error_lines:
        print(f"gd: IMPORT FAILED (exit {res.rc}, {len(res.error_lines)} error line(s))", file=sys.stderr)
        return EXIT_FAIL if not (res.timed_out or res.stalled) else EXIT_TIMEOUT
    print(f"gd: import ok in {time.time() - t0:.1f}s")
    return EXIT_OK


def ready_shared(ctx: Ctx, stack: contextlib.ExitStack, auto_import: bool = True) -> None:
    """Leave `stack` holding the SHARED lock on a freshly imported project.

    Never upgrades a held shared lock (that can deadlock two upgraders): drop it, import under the
    exclusive lock, then take the shared lock again and re-check, a few times.
    """
    for attempt in range(6):
        cm = ctx.lock.shared()
        cm.__enter__()
        if not auto_import:
            stack.push(cm)
            return
        stale, reason = ctx.state.is_stale()
        if not stale:
            stack.push(cm)
            return
        cm.__exit__(None, None, None)
        with ctx.lock.exclusive("gd auto-import"):
            stale, reason = ctx.state.is_stale()  # somebody may have imported while we waited
            if stale:
                print(f"gd: importing ({reason}) ...", file=sys.stderr, flush=True)
                t0 = time.time()
                ok, res = import_locked(ctx, echo=False)
                if not ok:
                    for line in res.lines[-30:]:
                        print("  import> " + line, file=sys.stderr)
                    env.die(f"auto-import failed (exit {res.rc}); run `tools/gd import` to see the full output", 1)
                note = ""
                if res.error_lines:
                    # a broken resource somewhere in the shared tree must not block everybody's unrelated commands
                    note = f" - WARNING: the import printed {len(res.error_lines)} error line(s), first: {res.error_lines[0][:160]} (`tools/gd import` shows all)"
                print(f"gd: import ok in {time.time() - t0:.1f}s{note}", file=sys.stderr, flush=True)
    # files kept changing under us: run anyway with the shared lock rather than looping forever
    cm = ctx.lock.shared()
    cm.__enter__()
    stack.push(cm)


# ---------------------------------------------------------------------------------------------------
# check
# ---------------------------------------------------------------------------------------------------
def _parse_check_output(res: RunResult) -> Tuple[List[Finding], bool]:
    findings: List[Finding] = []
    done = False
    for line in res.lines:
        m = re.match(r"^CHECK_ERR (res://[^:]*):(\d+): (.*)$", line)
        if m:
            findings.append(Finding(m.group(1), int(m.group(2)), m.group(3)))
        elif line.startswith("CHECK_DONE"):
            done = True
    return findings, done


def _godot_check(ctx: Ctx, roots: Sequence[str], promote: bool, scenes: bool, timeout: float) -> Tuple[List[Finding], bool, RunResult]:
    argv = ctx.godot("--headless", "--script", CHECK_SCRIPT, "--", "--paths=" + ",".join(roots))
    if promote:
        argv.append("--warnings")
    if not scenes:
        argv.append("--no-scenes")
    res = run_process(argv, timeout=timeout, stall_after_error=None, echo=False, verbose=ctx.verbose)
    findings, done = _parse_check_output(res)
    return findings, done and res.rc in (0, 1), res


def _run_lint(paths: Sequence[str], rules: Optional[str]) -> object:
    sys.path.insert(0, str(env.TOOLS_DIR / "py"))
    import lint  # type: ignore  # noqa: WPS433 (tools/py/lint.py)
    targets = None
    if paths:
        targets = [env.GAME / p[len("res://"):] for p in paths]
    selected = set(rules.split(",")) if rules else None
    if selected and not selected <= set(lint.RULES):
        env.die(f"unknown lint rule id(s): {', '.join(sorted(selected - set(lint.RULES)))} (see python3 tools/py/lint.py --list-rules)", 2)
    return lint.run(env.ROOT, env.GAME, targets=targets, rules=selected)


def cmd_lint_only(args: "object") -> int:
    """`gd check --lint-only`: tools/py/lint.py without Godot (no import, no lock)."""
    paths = [env.to_res_path(p) for p in getattr(args, "paths", [])]
    report = _run_lint(paths, getattr(args, "rules", None))
    for v in report.violations:  # type: ignore[attr-defined]
        print(f"{v.path}:{v.line}: {v.rule} {v.message}")
    print(f"[lint] {report.files} files, {len(report.violations)} violation(s)"  # type: ignore[attr-defined]
          f"{', %d suppressed by lint-allow' % report.suppressed if report.suppressed else ''}")  # type: ignore[attr-defined]
    return EXIT_FAIL if report.violations else EXIT_OK  # type: ignore[attr-defined]


def cmd_check(args: "object") -> int:
    verbose = getattr(args, "verbose", False)
    ctx = Ctx.create(verbose)
    paths = [env.to_res_path(p) for p in getattr(args, "paths", [])]
    roots = paths or list(DEFAULT_SCAN_ROOTS)
    fast: bool = getattr(args, "fast", False)
    strict: bool = getattr(args, "strict", False)
    show_warnings: bool = getattr(args, "warnings", False)
    timeout = float(getattr(args, "timeout", 0) or 300)
    t0 = time.time()
    lint_crashed = False
    with contextlib.ExitStack() as stack:
        ready_shared(ctx, stack)
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            f_lint = None if getattr(args, "no_lint", False) else pool.submit(_run_lint, paths, getattr(args, "rules", None))
            f_errors = pool.submit(_godot_check, ctx, roots, False, True, timeout)
            f_warn = None if fast else pool.submit(_godot_check, ctx, roots, True, False, timeout)
            err_findings, err_done, err_res = f_errors.result()
            warn_findings, warn_done, warn_res = ([], True, None) if f_warn is None else f_warn.result()
            try:
                report = f_lint.result() if f_lint else None
            except Exception as exc:  # noqa: BLE001 - a linter bug must not hide the compile results
                report = None
                print(f"[lint] INTERNAL ERROR in tools/py/lint.py: {type(exc).__name__}: {exc}", file=sys.stderr)
                lint_crashed = True

    failed = lint_crashed
    out: Dict[str, object] = {"errors": [], "warnings": [], "lint": []}

    # -- lint ------------------------------------------------------------------------------------
    if report is not None:
        violations = report.violations  # type: ignore[attr-defined]
        print(f"[lint] {report.files} files, {len(violations)} violation(s)"  # type: ignore[attr-defined]
              f"{', %d suppressed by lint-allow' % report.suppressed if report.suppressed else ''}")  # type: ignore[attr-defined]
        for v in violations:
            print(f"{v.path}:{v.line}: {v.rule} {v.message}")
            out["lint"].append({"path": v.path, "line": v.line, "rule": v.rule, "message": v.message})  # type: ignore[union-attr]
        if violations:
            failed = True

    # -- scripts ---------------------------------------------------------------------------------
    if not err_done:
        failed = True
        print("[scripts] CHECKER DID NOT FINISH - raw output follows", file=sys.stderr)
        for line in err_res.lines[-40:]:
            print("  " + line, file=sys.stderr)
    else:
        print(f"[scripts] {len(err_findings)} error(s)")
        for f in err_findings:
            print(f.display("error"))
            out["errors"].append({"file": f.file, "line": f.line, "message": f.message})  # type: ignore[union-attr]
        if err_findings:
            failed = True

    # -- warnings (second pass with WARN promoted to errors, minus real errors) --------------------
    warnings: List[Finding] = []
    if f_warn is not None:
        if not warn_done:
            print("[warnings] warning pass did not finish (use --fast to skip it)", file=sys.stderr)
        else:
            known = {f.key() for f in err_findings}
            for f in warn_findings:
                if f.message.endswith(WARNING_SUFFIX) and f.key() not in known:
                    msg = f.message[: -len(WARNING_SUFFIX)].rstrip()
                    msg = re.sub(r"^Parse Error: ", "", msg)
                    warnings.append(Finding(f.file, f.line, msg, warning_code(msg)))
            files = sorted({w.file for w in warnings})
            print(f"[warnings] {len(warnings)} GDScript warning(s) in {len(files)} file(s)"
                  + ("" if strict or show_warnings or not warnings else " (list them with --warnings; --strict makes them fail)"))
            if show_warnings or strict:
                for w in warnings:
                    print(w.display("warning"))
            elif warnings:
                by_file: Dict[str, int] = {}
                for w in warnings:
                    by_file[w.file] = by_file.get(w.file, 0) + 1
                for fpath, n in sorted(by_file.items(), key=lambda kv: -kv[1])[:5]:
                    print(f"    {n:3d}  {env.res_to_display(fpath)}")
            for w in warnings:
                out["warnings"].append({"file": w.file, "line": w.line, "code": w.code, "message": w.message})  # type: ignore[union-attr]
            if strict and warnings:
                failed = True

    verdict = "FAIL" if failed else "OK"
    print(f"RESULT: {verdict} ({len(err_findings)} script error(s), "
          f"{len(report.violations) if report is not None else 0} lint violation(s), {len(warnings)} warning(s)) in {time.time() - t0:.1f}s")  # type: ignore[attr-defined]
    json_path = getattr(args, "json", None)
    if json_path:
        Path(json_path).write_text(json.dumps(out, indent=1))
    return EXIT_FAIL if failed else EXIT_OK


# ---------------------------------------------------------------------------------------------------
# test
# ---------------------------------------------------------------------------------------------------
def cmd_test(args: "object", user_args: Sequence[str]) -> int:
    ctx = Ctx.create(getattr(args, "verbose", False))
    runner_args: List[str] = []
    filters: List[str] = getattr(args, "filter", []) or []
    if filters:
        runner_args.append("--filter=" + ",".join(filters))
    for f in getattr(args, "file", []) or []:
        runner_args.append("--file=" + env.to_res_path(f))
    if getattr(args, "dir", None):
        runner_args.append("--dir=" + env.to_res_path(args.dir))  # type: ignore[attr-defined]
    for flag in ("list", "trace", "fail_fast", "allow_empty", "quiet"):
        if getattr(args, flag, False):
            runner_args.append("--" + flag.replace("_", "-"))
    runner_args.extend(user_args)
    runs = env.CACHE / "runs"
    runs.mkdir(parents=True, exist_ok=True)
    results_path = runs / f"test-{os.getpid()}.json"
    runner_args.append(f"--results={results_path}")
    timeout = float(getattr(args, "timeout", 0) or 600)
    stall = float(getattr(args, "stall", 60))
    with contextlib.ExitStack() as stack:
        ready_shared(ctx, stack)
        res = run_process(
            ctx.godot("--headless", "--script", RUNNER_SCRIPT, "--", *runner_args),
            timeout=timeout, stall_after_error=stall or None, verbose=ctx.verbose,
        )
    json_out = getattr(args, "json", None)
    try:
        if json_out and results_path.exists():
            Path(json_out).write_bytes(results_path.read_bytes())
        results_path.unlink(missing_ok=True)
    except OSError:
        pass
    if res.timed_out or res.stalled:
        return EXIT_TIMEOUT
    if res.rc != 0 and not any(l.startswith("== ") for l in res.lines) and not getattr(args, "list", False):
        print(f"gd: the test runner exited with code {res.rc} without printing a summary (crash or abort)", file=sys.stderr)
    return res.rc


# ---------------------------------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------------------------------
def cmd_run(args: "object", user_args: Sequence[str]) -> int:
    ctx = Ctx.create(getattr(args, "verbose", False))
    target = env.to_res_path(args.target)  # type: ignore[attr-defined]
    gui: bool = getattr(args, "gui", False)
    argv: List[str] = []
    if not gui:
        argv.append("--headless")
    if getattr(args, "size", None):
        argv += ["--resolution", args.size]  # type: ignore[attr-defined]
    if getattr(args, "quit_after", None):
        argv += ["--quit-after", str(args.quit_after)]  # type: ignore[attr-defined]
    if target.endswith(".gd"):
        src = (env.GAME / target[len("res://"):])
        if src.exists() and not re.search(r"^\s*extends\s+(SceneTree|MainLoop)\b", src.read_text(errors="replace"), re.M):
            print("gd: warning: --script targets must `extends SceneTree` (or MainLoop); a Node script needs a scene wrapper "
                  "(gd run <scene.tscn>)", file=sys.stderr)
        argv += ["--script", target]
    else:
        argv.append(target)
    if user_args:
        argv += ["--", *user_args]
    timeout = float(getattr(args, "timeout", 0) or 300)
    stall = float(getattr(args, "stall", 20))
    with contextlib.ExitStack() as stack:
        ready_shared(ctx, stack)
        res = run_process(ctx.godot(*argv), timeout=timeout, stall_after_error=(stall or None) if not gui else None, verbose=ctx.verbose)
    if res.timed_out or res.stalled:
        return EXIT_TIMEOUT
    if res.rc == 0 and res.error_lines and not getattr(args, "allow_errors", False):
        print(f"gd: {len(res.error_lines)} engine error line(s) were printed although Godot exited 0; "
              f"exit code forced to {EXIT_ENGINE_ERRORS} (--allow-errors to accept)", file=sys.stderr)
        return EXIT_ENGINE_ERRORS
    return res.rc


# ---------------------------------------------------------------------------------------------------
# shot
# ---------------------------------------------------------------------------------------------------
RENDER_METHODS = ("forward_plus", "mobile", "gl_compatibility")


def cmd_shot(args: "object", user_args: Sequence[str]) -> int:
    ctx = Ctx.create(getattr(args, "verbose", False))
    scene = env.to_res_path(args.scene)  # type: ignore[attr-defined]
    out = Path(args.out).expanduser().resolve()  # type: ignore[attr-defined]
    size = getattr(args, "size", None) or "960x540"
    if not re.fullmatch(r"\d{2,5}x\d{2,5}", size):
        env.die(f"--size must look like 960x540, got {size!r}", 2)
    frames = int(getattr(args, "frames", 30))
    method = getattr(args, "rendering_method", None)
    # Linux without a display (CI, the gd linux container): render into a virtual X server instead.
    use_xvfb = sys.platform.startswith("linux") and not os.environ.get("DISPLAY") and shutil.which("xvfb-run") is not None
    argv: List[str] = ["--resolution", size, "--fixed-fps", "60", "--disable-vsync", "--audio-driver", "Dummy"]
    if not getattr(args, "visible", False) and not use_xvfb:
        argv += ["--position", "20000,20000"]  # keep the window off the user's desktop
    if method:
        argv += ["--rendering-method", method]
    argv.append(scene)
    argv += ["--", f"--shot={out}", f"--frames={frames}", *user_args]
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.unlink()  # so a stale image can never be mistaken for a new one
    timeout = float(getattr(args, "timeout", 0) or 90)
    with contextlib.ExitStack() as stack:
        ready_shared(ctx, stack)
        cmd = ctx.godot(*argv)
        if use_xvfb:
            cmd = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24", *cmd]
        res = run_process(cmd, timeout=timeout, stall_after_error=30, verbose=ctx.verbose, echo=not getattr(args, "quiet", False))
    ok_line = next((l for l in res.lines if l.startswith("SHOT_OK ")), None)
    if res.timed_out or res.stalled:
        return EXIT_TIMEOUT
    if not ok_line or not out.exists() or out.stat().st_size == 0:
        print(f"gd: SHOT FAILED (exit {res.rc}); no image written to {out}", file=sys.stderr)
        return EXIT_FAIL
    if res.error_lines and not getattr(args, "allow_errors", False):
        print(f"gd: image written but {len(res.error_lines)} engine error line(s) were printed (--allow-errors to accept)", file=sys.stderr)
        print(out)
        return EXIT_ENGINE_ERRORS
    print(out)
    return EXIT_OK

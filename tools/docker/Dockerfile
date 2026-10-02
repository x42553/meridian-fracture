# Debian 12 runner for the Linux build of Godot 4.7.2 (headless import/test/check, xvfb + Mesa for screenshots).
# Build (done by `tools/gd linux` on demand):
#   docker build --platform linux/amd64 -t meridian-linux-runner:amd64 -f tools/docker/Dockerfile tools/docker
#   docker build --platform linux/arm64 -t meridian-linux-runner:arm64 -f tools/docker/Dockerfile tools/docker
# The engine binary and the repo tools are bind-mounted at run time (not baked in), so the image only
# carries the shared libraries a Debian 12 desktop user would have installed.
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    HOME=/tmp/home \
    XDG_RUNTIME_DIR=/tmp/xdg-runtime

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3 ca-certificates dpkg-dev fakeroot xvfb xauth \
      libx11-6 libxcursor1 libxinerama1 libxext6 libxrandr2 libxrender1 libxi6 libxkbcommon0 libxkbcommon-x11-0 \
      libgl1 libglx-mesa0 libgl1-mesa-dri libegl1 libvulkan1 mesa-vulkan-drivers \
      libudev1 libfontconfig1 libdbus-1-3 libasound2 libpulse0 libwayland-client0 libwayland-cursor0 libwayland-egl1 libdecor-0-0 \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /tmp/home /tmp/xdg-runtime /work \
 && chmod 1777 /tmp/home /tmp/xdg-runtime

WORKDIR /work
CMD ["python3", "--version"]

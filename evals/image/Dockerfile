FROM node:22-bookworm-slim@sha256:d649c27dae7ba0137b3cef5dd75baa422c08dc3d9e3fc0c23dfb172dc3cc6436 AS node

FROM ghcr.io/astral-sh/uv:0.11.28@sha256:0f36cb9361a3346885ca3677e3767016687b5a170c1a6b88465ec14aefec90aa AS uv

FROM debian:bookworm-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241

ARG PI_ARTIFACT_SHA256
ARG PI_ENTRY=bin/pi
ARG PI_PACKAGES_SHA256
ARG FLUTTER_VERSION=3.47.0
ARG FLUTTER_REVISION=4cf24164269a5ebf0c16a028a00727d0e77bbb05
ARG APT_SNAPSHOT=20260812T000000Z

LABEL nothingness.eval.flutter_version="${FLUTTER_VERSION}" \
      nothingness.eval.flutter_revision="${FLUTTER_REVISION}"

ENV DEBIAN_FRONTEND=noninteractive \
    TRY_SYSTEM_LIBS_FIRST=1 \
    DISPLAY=:99 \
    DRIVE_TARGET=linux \
    HOME=/run/nothingness/home \
    XDG_CONFIG_HOME=/run/nothingness/config \
    XDG_DATA_HOME=/run/nothingness/data \
    PI_CODING_AGENT_DIR=/run/nothingness/pi-home \
    PUB_CACHE=/root/.pub-cache \
    UV_CACHE_DIR=/opt/uv-cache \
    UV_OFFLINE=1 \
    UV_PYTHON=/usr/bin/python3 \
    PATH="/sdks/flutter/bin:${PATH}"

RUN rm -f /etc/apt/sources.list.d/debian.sources \
  && printf '%s\n' 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99snapshot \
  && printf '%s\n' \
    "deb http://snapshot.debian.org/archive/debian/${APT_SNAPSHOT} bookworm main" \
    "deb http://snapshot.debian.org/archive/debian-security/${APT_SNAPSHOT} bookworm-security main" \
    > /etc/apt/sources.list \
  && apt-get update && apt-get install -y --no-install-recommends \
    alsa-utils ca-certificates clang cmake curl ffmpeg fonts-dejavu-core git jq \
    libasound2-dev libflac-dev libgtk-3-dev liblzma-dev libogg-dev libopus-dev \
    libpulse-dev libpulse0 libstdc++-12-dev libvorbis-dev libxtst6 ninja-build \
    novnc openbox pkg-config procps pulseaudio python3 unzip websockify x11vnc xdg-user-dirs xvfb \
    xz-utils \
  && rm -rf /var/lib/apt/lists/*

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=uv /uv /uvx /usr/local/bin/

RUN printf '%s\n' '# /// script' '# requires-python = ">=3.10"' '# dependencies = ["websockets==15.0.1"]' '# ///' 'import websockets' 'print(websockets.__version__)' > /tmp/websockets-check.py \
  && UV_OFFLINE=0 uv pip install --system --break-system-packages websockets==15.0.1 \
  && UV_OFFLINE=0 uv run --script /tmp/websockets-check.py \
  && rm /tmp/websockets-check.py \
  && uv --version \
  && python3 -c 'import websockets; assert websockets.__version__ == "15.0.1"'

RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git /sdks/flutter \
  && cd /sdks/flutter \
  && test "$(git rev-parse HEAD)" = "${FLUTTER_REVISION}" \
  && flutter config --enable-linux-desktop --no-analytics \
  && flutter precache --linux \
  && rm -rf bin/cache/artifacts/engine/android-* \
         bin/cache/artifacts/engine/darwin-* \
         bin/cache/artifacts/engine/ios \
         bin/cache/artifacts/engine/windows-* \
         bin/cache/artifacts/engine/web \
         bin/cache/downloads \
  && flutter --version

COPY dependency-seed/ /tmp/dependency-seed/
RUN cd /tmp/dependency-seed \
  && flutter pub get \
  && rm -rf /tmp/dependency-seed

COPY pi-artifact.tar.gz /tmp/pi-artifact.tar.gz
RUN test -n "$PI_ARTIFACT_SHA256" \
  && echo "$PI_ARTIFACT_SHA256  /tmp/pi-artifact.tar.gz" | sha256sum -c - \
  && mkdir -p /opt/pi \
  && tar -xzf /tmp/pi-artifact.tar.gz -C /opt/pi --strip-components=1 \
  && test -f "/opt/pi/$PI_ENTRY" \
  && { [ "$PI_ENTRY" = "bin/pi" ] || { mkdir -p /opt/pi/bin && ln -sf "/opt/pi/$PI_ENTRY" /opt/pi/bin/pi; }; } \
  && test -f /opt/pi/bin/pi \
  && rm /tmp/pi-artifact.tar.gz

COPY pi-packages.tar.gz /tmp/pi-packages.tar.gz
RUN test -n "$PI_PACKAGES_SHA256" \
  && echo "$PI_PACKAGES_SHA256  /tmp/pi-packages.tar.gz" | sha256sum -c - \
  && mkdir -p /opt/pi-packages \
  && tar -xzf /tmp/pi-packages.tar.gz -C /opt/pi-packages \
  && test -d /opt/pi-packages \
  && rm /tmp/pi-packages.tar.gz

COPY media/ /opt/nothingness/media/
COPY entrypoint.py /usr/local/bin/nothingness-eval-entrypoint
COPY candidate.py /usr/local/bin/nothingness-eval-candidate
COPY egress_proxy.py /usr/local/bin/nothingness-eval-proxy
COPY pi.py /usr/local/bin/pi
RUN chmod 0755 /usr/local/bin/nothingness-eval-entrypoint /usr/local/bin/nothingness-eval-candidate /usr/local/bin/nothingness-eval-proxy /usr/local/bin/pi \
  && test "$(find /opt/nothingness/media -maxdepth 1 -name '*.opus' -type f | wc -l)" = 10

WORKDIR /workspace
EXPOSE 6080
ENTRYPOINT ["python3", "/usr/local/bin/nothingness-eval-entrypoint"]

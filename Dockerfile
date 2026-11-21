# syntax=docker/dockerfile:1

# --- Deno binary (pinned by digest) ---
FROM denoland/deno:bin-2.9.8@sha256:b507583d3c68ba69f3ed2ce5969ae5b8b70f43421c781279c7aea06435263543 AS deno

# --- Final image ---
FROM python:3.13-slim@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90

ARG YTDLP_VERSION=2026.10.26

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY --from=deno /deno /usr/local/bin/deno

COPY requirements.lock /tmp/requirements.lock
RUN pip install --no-cache-dir --require-hashes -r /tmp/requirements.lock \
    && rm /tmp/requirements.lock

RUN yt-dlp --version && deno --version

RUN groupadd -g 10001 ytdl \
    && useradd -u 10001 -g ytdl -s /sbin/nologin -M ytdl

COPY --chmod=0755 entrypoint.sh /usr/local/bin/ytdl

ENV XDG_CACHE_HOME=/tmp/cache \
    DENO_DIR=/tmp/deno

WORKDIR /downloads
RUN chown 10001:10001 /downloads
USER 10001

ENTRYPOINT ["ytdl"]

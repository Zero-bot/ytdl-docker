# yt-dlp Docker

Hardened Docker image for [yt-dlp](https://github.com/yt-dlp/yt-dlp). Downloads YouTube videos and audio without touching your host filesystem.

**What's inside:** Python 3.13, ffmpeg, [Deno](https://deno.com/) (sandboxed JS solver for YouTube challenges), and yt-dlp with locked dependencies. Auto-updated every 6 hours from PyPI, with weekly base-image security patches. Every build is signed with [cosign](https://docs.sigstore.dev/cosign/overview/) and ships SLSA provenance + SBOM.

## Quick start

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/Zero-bot/ytdl-docker/main/ytdl \
  -o /usr/local/bin/ytdl && chmod +x /usr/local/bin/ytdl
```

Or clone the repo and copy the script:

```bash
git clone https://github.com/Zero-bot/ytdl-docker.git
cp ytdl-docker/ytdl /usr/local/bin/ytdl
```

### Download a video (best quality, MKV)

```bash
ytdl "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

### Download audio only (original codec, no re-encode)

```bash
ytdl --audio "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

### Override defaults

Extra yt-dlp arguments are passed through:

```bash
ytdl -f "bv*+ba/b" --merge-output-format mp4 \
  "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

Files are saved to `~/Downloads/ytdl` by default. Override with `YTDL_OUTDIR`:

```bash
YTDL_OUTDIR=/tmp/videos ytdl "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

The `ytdl` wrapper pulls the image, creates an isolated network, and runs every download in a hardened container with all security flags (read-only filesystem, capabilities dropped, PID/memory limits, network isolation). No manual Docker commands needed.

### Using Docker directly

If you prefer not to use the wrapper:

```bash
docker pull mmahalingam/yt-dlp

docker run --rm -v "$HOME/Downloads/ytdl":/downloads mmahalingam/yt-dlp \
  "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

### Optional: block private-network egress (Linux)

The container only needs to reach YouTube and CDN hosts. Block RFC 1918 and link-local egress:

```bash
BRIDGE_IF=$(docker network inspect ytdl-net -f '{{(index .Options "com.docker.network.bridge.name")}}')
[ -z "$BRIDGE_IF" ] && BRIDGE_IF=$(docker network inspect ytdl-net -f '{{.Id}}' | head -c 12 | sed 's/^/br-/')

for CIDR in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16; do
  sudo iptables -I DOCKER-USER -i "$BRIDGE_IF" -d "$CIDR" -j DROP
done
```

## Verify image signature

Every image is signed with keyless cosign via GitHub Actions OIDC. Verify before running:

```bash
cosign verify \
  --certificate-identity "https://github.com/Zero-bot/ytdl-docker/.github/workflows/build.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  mmahalingam/yt-dlp
```

To pin to an exact digest:

```bash
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' mmahalingam/yt-dlp | cut -d@ -f2)
cosign verify \
  --certificate-identity "https://github.com/Zero-bot/ytdl-docker/.github/workflows/build.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  "mmahalingam/yt-dlp@${DIGEST}"
```

## Built-in defaults

The entrypoint applies these flags automatically (your arguments override them):

| Mode | Flags |
|---|---|
| **Video** (default) | `-f "bv*+ba/b" -S "res,fps,br" --merge-output-format mkv` |
| **Audio** (`--audio`) | `-f "ba/b" -S "abr,asr" -x --embed-thumbnail` |
| **Always** | `--ignore-config --no-exec --embed-metadata -o "%(title).150B [%(id)s].%(ext)s"` |

MKV is the default container because 4K/8K YouTube is VP9/AV1 with Opus audio. `--ignore-config` and `--no-exec` prevent config injection via the writable volume.

## Security

| Layer | What it does |
|---|---|
| **Supply chain** | Base images pinned by digest. Dependencies hash-locked (`--require-hashes`). PyPI attestation verified before every build. Image signed with cosign. SLSA provenance and SBOM attached. Dependabot watches everything. |
| **Runtime** | Non-root (uid 10001). Read-only filesystem. All capabilities dropped. No new privileges. PID and memory limits. Network-isolated. |
| **Deno sandbox** | YouTube JS challenges run inside Deno's V8 sandbox with no ambient permissions. |
| **Recommended** | Rootless Docker, Podman (`podman run --userns=keep-id ...`), or gVisor (`--runtime=runsc`) on Linux. |

## Tags

| Tag | Description |
|---|---|
| `latest` | Most recent build that passed Trivy (fixable CRITICALs block this tag) |
| `2026.10.26` | Matches the yt-dlp version |
| `2026.10.26-20261121-cca6945` | Immutable: yt-dlp version + build date + commit SHA |

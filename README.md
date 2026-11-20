# yt-dlp Docker

Hardened, auto-updating Docker image for [yt-dlp](https://github.com/yt-dlp/yt-dlp) with Deno (for YouTube JS challenge solving), ffmpeg, and embedded metadata.

GitHub Actions rebuilds and pushes to Docker Hub every 6 hours when a new yt-dlp version lands on PyPI (after verifying the release's Trusted Publishing attestation), plus a weekly forced rebuild for base-image security patches.

## One-time setup

### Docker Hub credentials

Create a Docker Hub [access token](https://hub.docker.com/settings/security) with **Read & Write** permissions, then:

```bash
gh variable set DOCKERHUB_USERNAME --repo Zero-bot/ytdl-docker --body "<your-dockerhub-username>"
gh secret set DOCKERHUB_TOKEN --repo Zero-bot/ytdl-docker
```

### Switching to GHCR (alternative)

Replace every `docker.io/${{ vars.DOCKERHUB_USERNAME }}/yt-dlp` with `ghcr.io/${{ github.repository_owner }}/yt-dlp` in the workflow. Change the `docker/login-action` to use `registry: ghcr.io`, `username: ${{ github.actor }}`, `password: ${{ secrets.GITHUB_TOKEN }}`. Remove the `DOCKERHUB_TOKEN` secret and `DOCKERHUB_USERNAME` variable. Grant the package write permission in the repository settings.

### Repository settings (public repo hardening)

1. **Settings > Actions > General > Fork pull request workflows** --- select _Require approval for all outside collaborators_.
2. **Settings > Actions > General > Workflow permissions** --- select _Read repository contents and packages permissions_. Uncheck _Allow GitHub Actions to create and approve pull requests_.
3. **Settings > Branches > Add rule** for `main` --- enable _Require a pull request before merging_ and _Require status checks to pass before merging_.

### Watch the first run

```bash
gh run watch --repo Zero-bot/ytdl-docker
```

## Usage

### Network setup (one-time)

Create an isolated bridge network with inter-container traffic disabled:

```bash
docker network create --driver bridge -o com.docker.network.bridge.enable_icc=false ytdl-net
```

### Hardened run alias

```bash
alias ytdl='docker run --rm \
  --read-only \
  --tmpfs /tmp:rw,size=512m \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --pids-limit 256 \
  --memory 2g \
  --network ytdl-net \
  -v ytdl-data:/downloads \
  docker.io/<username>/yt-dlp'
```

Replace `<username>` with your Docker Hub username, or pin to a specific digest (see [Verify and run by digest](#verify-and-run-by-digest)).

### Examples

```bash
# Best video (default: MKV, highest resolution)
ytdl "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

# Best audio only (original codec, no re-encode)
ytdl --audio "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

# Override defaults (e.g. force mp4)
ytdl -f "bv*+ba/b" --merge-output-format mp4 "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

### Copy downloads out

Use a one-off Alpine container to copy media files from the named volume to a host directory:

```bash
mkdir -p ~/Downloads/ytdl
docker run --rm \
  -v ytdl-data:/src:ro \
  -v "$HOME/Downloads/ytdl":/dst \
  alpine sh -c 'cd /src && cp -v *.mp4 *.mkv *.webm *.m4a *.opus *.mp3 /dst/ 2>/dev/null; true'
```

### Verify and run by digest

```bash
# Get the latest digest
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' docker.io/<username>/yt-dlp | cut -d@ -f2)

# Verify cosign signature
cosign verify \
  --certificate-identity "https://github.com/Zero-bot/ytdl-docker/.github/workflows/build.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  "docker.io/<username>/yt-dlp@${DIGEST}"

# Run by digest (immutable)
docker run --rm \
  --read-only \
  --tmpfs /tmp:rw,size=512m \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --pids-limit 256 \
  --memory 2g \
  --network ytdl-net \
  -v ytdl-data:/downloads \
  "docker.io/<username>/yt-dlp@${DIGEST}" \
  "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

## Optional: restrict container egress

Add an iptables rule to the `DOCKER-USER` chain to block RFC 1918 and link-local egress from the `ytdl-net` network (the container only needs to reach YouTube/CDN hosts on the public internet):

```bash
BRIDGE_IF=$(docker network inspect ytdl-net -f '{{(index .Options "com.docker.network.bridge.name")}}')
# If the bridge name is empty, docker assigns one like br-<id>:
[ -z "$BRIDGE_IF" ] && BRIDGE_IF=$(docker network inspect ytdl-net -f '{{.Id}}' | head -c 12 | sed 's/^/br-/')

for CIDR in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16; do
  sudo iptables -I DOCKER-USER -i "$BRIDGE_IF" -d "$CIDR" -j DROP
done
```

## Threat model

| Layer | Control |
|---|---|
| **Supply chain** | Base images pinned by digest; yt-dlp installed from a hash-locked lockfile (`--require-hashes`); PyPI Trusted Publishing attestation verified before every CI build; image signed with keyless cosign (Sigstore); SLSA Build L3 provenance and SBOM attached; Dependabot watches actions, Docker digests and pip deps. |
| **Build isolation** | CI jobs split by least privilege: `resolve` (no secrets, no OIDC), `build-push` (registry creds only), `sign` (OIDC only). No PR workflow touches secrets or the GHA cache. Actions pinned by full SHA. |
| **Runtime** | Non-root (uid 10001); `--read-only` filesystem; `--cap-drop ALL`; `--no-new-privileges`; PID and memory limits; `--ignore-config` and `--no-exec` prevent config injection and exec breakout via the writable volume; network isolation via dedicated bridge with ICC disabled. |
| **Deno sandbox** | yt-dlp-ejs runs YouTube's JavaScript inside Deno's V8 sandbox with no ambient permissions (no filesystem, no network beyond what yt-dlp passes). |
| **Recommended** | Run under rootless Docker, Podman (`podman run --userns=keep-id ...`) or gVisor (`--runtime=runsc`) on Linux for kernel-level isolation. |

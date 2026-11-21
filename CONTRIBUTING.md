# Maintainer setup

## Docker Hub credentials

Create a Docker Hub [access token](https://hub.docker.com/settings/security) with **Read & Write** permissions, then:

```bash
gh variable set DOCKERHUB_USERNAME --repo Zero-bot/ytdl-docker --body "<your-dockerhub-username>"
gh secret set DOCKERHUB_TOKEN --repo Zero-bot/ytdl-docker
```

## Switching to GHCR

Replace `docker.io/${{ vars.DOCKERHUB_USERNAME }}/yt-dlp` with `ghcr.io/${{ github.repository_owner }}/yt-dlp` in the workflow. Change the `docker/login-action` to use `registry: ghcr.io`, `username: ${{ github.actor }}`, `password: ${{ secrets.GITHUB_TOKEN }}`. Remove the `DOCKERHUB_TOKEN` secret and `DOCKERHUB_USERNAME` variable.

## Repository settings (public repo hardening)

1. **Settings > Actions > General > Fork pull request workflows** --- _Require approval for all outside collaborators_.
2. **Settings > Actions > General > Workflow permissions** --- _Read repository contents and packages permissions_. Uncheck _Allow GitHub Actions to create and approve pull requests_.
3. **Settings > Branches > Add rule** for `main` --- _Require a pull request before merging_ and _Require status checks to pass before merging_.

## CI architecture

Three jobs, each with minimal permissions:

| Job | GitHub permissions | Secrets |
|---|---|---|
| `resolve` | none | none |
| `build-push` | `contents: read` | `DOCKERHUB_TOKEN` |
| `sign` | `id-token: write` | `DOCKERHUB_TOKEN` |

## Regenerating the lockfile

```bash
docker run --rm python:3.13-slim sh -c "
  pip install pip-tools &&
  echo 'yt-dlp[default]==VERSION' > r.in &&
  pip-compile --generate-hashes --strip-extras --no-annotate --no-header r.in
"
```

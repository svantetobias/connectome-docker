# connectome-docker

**Unofficial community Docker image** for [Connectome host](https://github.com/anima-research/connectome-host) by [Anima Labs](https://animalabs.ai/connectome). It runs a persistent, stateful AI agent from a JSON recipe, with long-term memory and a web operator console.

> ⚠️ This is not an official Anima Labs project, and they don't support it.
> **The upstream repository has no license** (as of this writing). This repo holds only packaging (Dockerfile and scripts). The image contains upstream code, which keeps its authors' rights. Report bugs in the image here; report bugs in Connectome itself upstream.

Image: `ghcr.io/svantetobias/connectome` (tags: `latest`, `<upstream version>`, `sha-<upstream commit>`), linux/amd64. A GitHub Actions workflow rebuilds it daily when upstream publishes a new release.

## Run

```bash
docker run -d --name connectome \
  -p 7340:7340 \
  -v /mnt/user/appdata/connectome/data:/data \
  -v /mnt/user/appdata/connectome/config:/config \
  -e PUID=99 -e PGID=100 \
  -e ANTHROPIC_API_KEY=sk-ant-... \
  -e WEBUI_USERNAME=admin -e WEBUI_PASSWORD=change-me \
  ghcr.io/svantetobias/connectome:latest
```

Then open `http://<host>:7340/` and log in with the web UI username and password.

On first start, a default recipe (an Anthropic-backed agent, with the web UI on 0.0.0.0:7340 behind basic auth) is written to `/config/recipe.json`. Edit or replace it to change the agent; see the [upstream README](https://github.com/anima-research/connectome-host#readme) for the recipe format. The container runs `bun src/index.ts $RECIPE --headless`.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `PUID` / `PGID` | `99` / `100` | User and group the app runs as (unRAID nobody:users). The entrypoint fixes `/data` and `/config` ownership if it is wrong. |
| `UMASK` | `022` | umask for files the app creates |
| `ANTHROPIC_API_KEY` | – | Required by the default recipe (or `ANTHROPIC_AUTH_TOKEN` for a Claude subscription) |
| `WEBUI_USERNAME` / `WEBUI_PASSWORD` | – | Basic auth for the web UI. **Required**: the host won't bind 0.0.0.0 without them |
| `MODEL` | – | Optional model override |
| `AGENT_NAME` | `agent` | Agent name in the default recipe |
| `AGENT_TIMEZONE` | – | IANA zone for the agent's clock |
| `RECIPE` | `/config/recipe.json` | Recipe path or URL |
| `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` | – | Other providers, if your recipe uses them |

| Path | Contents |
|---|---|
| `/data` | Sessions, Chronicle store, LLM call logs, IPC socket (`DATA_DIR`) |
| `/config` | `recipe.json` (and `mcpl-servers.json` if used) |

Port: `7340/tcp` (web UI, `/healthz`). The container healthcheck calls `/healthz` with the web UI credentials.

## Build locally

```bash
docker build --build-arg UPSTREAM_REF=v0.10.2 -t connectome:local .
```

## unRAID

Template: [svantetobias/unraid-templates](https://github.com/svantetobias/unraid-templates).

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
  -v /mnt/user/appdata/connectome/input:/input:ro \
  -e PUID=99 -e PGID=100 \
  -e ANTHROPIC_API_KEY=sk-ant-... \
  -e WEBUI_USERNAME=admin -e WEBUI_PASSWORD=change-me \
  ghcr.io/svantetobias/connectome:latest
```

Then open `http://<host>:7340/` and log in with the web UI username and password.

On first start, a default recipe for the provider you pick (web UI on 0.0.0.0:7340 behind basic auth) is generated at `/config/recipe.json`. Edit or replace it to change the agent; see the [upstream README](https://github.com/anima-research/connectome-host#readme) for the recipe format. The container runs `bun src/index.ts $RECIPE --headless`.

## Choosing an LLM provider

The generated recipe uses `PROVIDER`:

| `PROVIDER` | Needs | Key variable |
|---|---|---|
| `anthropic` (default) | – (`MODEL` optional) | `ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN` |
| `openrouter` | `MODEL` (e.g. `anthropic/claude-sonnet-4`) | `OPENROUTER_API_KEY` |
| `openai-responses` | – (`MODEL` optional, `BASE_URL` optional) | `OPENAI_API_KEY` |
| `openai-compatible` | `BASE_URL` **and** `MODEL` | `OPENAI_COMPATIBLE_API_KEY` (only this one is read; can be empty for local servers) |
| `bedrock` | – (`AWS_REGION`, default `us-west-2`) | `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` |

Example: Venice (OpenAI-compatible):

```bash
-e PROVIDER=openai-compatible -e BASE_URL=https://api.venice.ai/api/v1 \
-e MODEL=<venice model id> -e OPENAI_COMPATIBLE_API_KEY=...
```

Ollama: `BASE_URL=http://<host>:11434/v1`, `MODEL=<local model>`, and no key needed.

`BASE_URL` is one setting for whichever provider is in use: for `openai-compatible` it becomes `agent.baseUrl` in the generated recipe (required); for `anthropic`, `openai-responses` and `bedrock` the entrypoint exports it as `ANTHROPIC_BASE_URL`, `OPENAI_BASE_URL` or `BEDROCK_BASE_URL` (optional, e.g. an inference gateway), based on the provider in the recipe actually loaded. An explicitly set `*_BASE_URL` wins. `openrouter` has no upstream override, so it is ignored there.

The recipe is only generated when `/config/recipe.json` is **missing**, so changing `PROVIDER`/`MODEL`/`BASE_URL` later does nothing unless you delete it or start once with `REGENERATE_RECIPE=true`. That moves the old file to `recipe.json.bak.<timestamp>` and writes a new one. **Set it back to `false` afterwards**: while it is `true`, every restart regenerates the recipe and discards your edits (each old version is kept as a backup). If generation fails (unknown provider, missing `MODEL`/`BASE_URL`), the container logs `[recipe] ERROR: …` and exits. Web UI credentials are stored as `${WEBUI_USERNAME}`/`${WEBUI_PASSWORD}` placeholders and filled in at load time; they are never written to the file.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `PUID` / `PGID` | `99` / `100` | User and group the app runs as (unRAID nobody:users). The entrypoint fixes `/data`, `/config` (and `/input` if writable) ownership if it is wrong. |
| `UMASK` | `022` | umask for files the app creates |
| `PROVIDER` | `anthropic` | `anthropic`, `openrouter`, `openai-responses`, `openai-compatible`, `bedrock` (see above) |
| `MODEL` | – | Model id; **required** for `openrouter` and `openai-compatible` |
| `BASE_URL` | – | Endpoint for the selected provider (required for `openai-compatible`; gateway URL for `anthropic`/`openai-responses`/`bedrock`) |
| `MAX_TOKENS` | upstream default (16384) | `agent.maxTokens` in the generated recipe |
| `CONTEXT_BUDGET_TOKENS` | upstream default | `agent.contextBudgetTokens` in the generated recipe (set it, e.g. `150000`, for 200k-window models) |
| `SYSTEM_PROMPT` | `You are a helpful, persistent assistant.` | `agent.systemPrompt`: text, or an `http(s)://` URL (no spaces) that upstream fetches at load time |
| `CONNECTOME_OPS_WEBHOOK` | – | Webhook for upstream ops alerts (passed through) |
| `REGENERATE_RECIPE` | `false` | `true` = back up and regenerate `/config/recipe.json` on start |
| `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` | – | For `PROVIDER=anthropic` |
| `OPENAI_COMPATIBLE_API_KEY` | – | For `PROVIDER=openai-compatible` |
| `WEBUI_USERNAME` / `WEBUI_PASSWORD` | – | Basic auth for the web UI. **Required**: the host won't bind 0.0.0.0 without them |
| `AGENT_NAME` | `agent` | Agent name in the default recipe |
| `AGENT_TIMEZONE` | – | IANA zone for the agent's clock |
| `RECIPE` | `/config/recipe.json` | Recipe path, or an `http(s)://` URL upstream fetches at start |
| `OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` | – | Other providers, if your recipe uses them |

| Path | Contents |
|---|---|
| `/data` | Sessions, Chronicle store, LLM call logs, IPC socket (`DATA_DIR`) |
| `/config` | `recipe.json`, `mcpl-servers.json` (+ `mcpl-servers.agent.json`), `sleep-privileged.json` |
| `/input` | Read-only files the agent can read (workspace mount `input`) |

The generated recipe mounts the workspace as `input` → `/input` (read-only) and `products` → `/data/output` (read-write), instead of upstream's `./input`/`./output` inside the non-writable `/app`. Upstream reads `mcpl-servers.json` and `mcpl-servers.agent.json` from its working directory, so `/app/<file>` is a symlink to `/config/<file>`; `SLEEP_PRIVILEGED_FILE` points to `/config/sleep-privileged.json`. Missing files are created on start (`{"mcplServers": {}}` and `[]`). The `MAX_TOKENS`/`CONTEXT_BUDGET_TOKENS`/`SYSTEM_PROMPT`/workspace settings only apply when the recipe is generated: existing recipes are not changed (use `REGENERATE_RECIPE=true` or edit the file).

Port: `7340/tcp` (web UI, `/healthz`). The container healthcheck calls `/healthz` with the web UI credentials.

## Build locally

```bash
docker build --build-arg UPSTREAM_REF=v0.10.2 -t connectome:local .
```

## unRAID

Template: [svantetobias/unraid-templates](https://github.com/svantetobias/unraid-templates).

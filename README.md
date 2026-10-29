# connectome-docker

> **Archived / no longer maintained.** This repository is archived and the image
> `ghcr.io/svantetobias/connectome` is no longer rebuilt or updated (the scheduled build
> workflow is disabled). Existing images remain as-is; use upstream
> [connectome-host](https://github.com/anima-research/connectome-host) directly.

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

## Chat bridges (Zulip, Discord) — optional, off by default

The image includes two MCPL chat bridges, built from pinned commits (build args `ZULIP_MCP_REF`, `DISCORD_MCPL_REF`) and run with a real Node.js (`/usr/local/bin/node`):

- **Zulip:** [antra-tess/zulip_mcp](https://github.com/antra-tess/zulip_mcp) at `/opt/zulip_mcp` (MIT).
- **Discord:** [anima-research/discord-mcpl](https://github.com/anima-research/discord-mcpl) at `/opt/discord-mcpl`. zulip_mcp became Zulip-only and its Discord support moved to discord-mcpl, which upstream's onboarding docs use. discord-mcpl has **no license** (like connectome-host).

Like the other recipe settings, these only apply when the recipe is **generated** (first start, or once with `REGENERATE_RECIPE=true`). When a bridge is enabled, the recipe gets an `mcpServers.zulip` and/or `mcpServers.discord` entry, `channelSubscription` for the configured channels, and `modules.wake` policies: DMs, @-mentions and replies (`chat:addressed`) and messages in open bridge channels wake the agent, messages from other bots don't, and everything else keeps upstream's default (`always`). With both bridges off, the recipe is the same as before (no `mcpServers`, no `wake`).

| Variable | Default | Purpose |
|---|---|---|
| `ZULIP_ENABLED` | `false` | Add the Zulip bridge |
| `ZULIP_STREAM` | – | Stream(s), comma-separated: subscribed on start (`ZULIP_SUBSCRIBE`), opened (`zulip:<stream>`), and they wake the agent |
| `ZULIP_RC_PATH` | `/config/.zuliprc` | Bot credentials file |
| `ZULIP_DM_USERS` | – | Optional DM allowlist (seeds the bridge's filters file) |
| `DISCORD_ENABLED` | `false` | Add the Discord bridge |
| `DISCORD_TOKEN` | – | Bot token. Written into the recipe only as `${DISCORD_TOKEN}`, so it is never stored in the file |
| `DISCORD_GUILD_ID` | – (every server the bot is in) | `serverId` or `serverId:channelId+channelId`, comma-separated. Listed channels are opened and wake the agent |
| `DISCORD_DM_USERS` | – (anyone) | User IDs allowed to DM the agent |
| `DISCORD_ADMIN_USERS` | – | User IDs allowed to use `/undo /hide /nudge /unstick` (`allowHostCommands: true`). Also written to `sleep-privileged.json` if that list is still empty (`[]`), so admins can wake the agent while it sleeps |

Where bridge state is kept: Zulip state in `/data/zulip-state`; Discord catch-up watermarks in `/data/discord-watermarks.json`; Discord filters in `/config/discord-filters.json` (created from the variables on first start, and **authoritative after that**: to change the Discord allowlists later, edit or delete that file).

### Zulip bot setup

1. In Zulip, go to *Settings → Personal settings → Bots → Add a new bot*. Choose type **Generic bot**, then create it.
2. Click the bot's download icon to get its `zuliprc`. It looks like `[api]` / `email=…` / `key=…` / `site=https://….zulipchat.com`.
3. Save it as `/mnt/user/appdata/connectome/config/.zuliprc`, readable by the container user: `chown 99:100 .zuliprc && chmod 600 .zuliprc`.
4. Set `ZULIP_ENABLED=true` and `ZULIP_STREAM=<stream>`. On an existing install, also start once with `REGENERATE_RECIPE=true`, then set it back to `false`.
5. Check the log. The entrypoint warns if Zulip is enabled but `.zuliprc` is missing. Bridge errors appear in the container log and in `/data/sessions/<id>/mcpl-stderr/zulip.log`.

### Discord bot setup

1. In the [Discord Developer Portal](https://discord.com/developers/applications), click *New Application*. On the **Bot** page, *Reset Token* and copy it into `DISCORD_TOKEN`.
2. On the same page, under *Privileged Gateway Intents*, turn on **Message Content Intent** and **Server Members Intent**. The bridge requests both.
3. Invite the bot: go to *OAuth2 → URL Generator*, select scopes `bot` and `applications.commands`, and permissions *View Channels*, *Send Messages*, *Send Messages in Threads*, *Read Message History*, *Add Reactions* and *Attach Files*. Open the generated URL and pick your server.
4. Enable Developer Mode in Discord (*User Settings → Advanced*), then right-click to *Copy ID* for the server, the channels and users. Set `DISCORD_GUILD_ID=<server>:<channel>`, plus `DISCORD_DM_USERS` and `DISCORD_ADMIN_USERS` as wanted.
5. Set `DISCORD_ENABLED=true`, then regenerate the recipe as above.

## Build locally

```bash
docker build --build-arg UPSTREAM_REF=v0.10.2 -t connectome:local .
```

## unRAID

Template: [svantetobias/unraid-templates](https://github.com/svantetobias/unraid-templates).

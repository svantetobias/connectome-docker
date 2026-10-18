// Generates /config/recipe.json from env vars. Exits non-zero with a clear message on bad input.
const out = process.argv[2] ?? '/config/recipe.json';
const env = process.env;
const provider = (env.PROVIDER || 'anthropic').trim().toLowerCase();
const allowed = ['anthropic', 'openrouter', 'openai-responses', 'openai-compatible', 'bedrock', 'mock'];
const fail = (msg: string): never => { console.error(`[recipe] ERROR: ${msg}`); process.exit(1); };

if (!allowed.includes(provider)) fail(`PROVIDER=${JSON.stringify(provider)} is not supported; use one of: ${allowed.join(', ')}.`);
const model = (env.MODEL || '').trim();
const baseUrl = (env.BASE_URL || '').trim();

if ((provider === 'openai-compatible' || provider === 'openrouter') && !model)
  fail(`MODEL is required when PROVIDER=${provider} (there is no default model). Set MODEL, e.g. MODEL=llama-3.3-70b.`);
if (provider === 'openai-compatible') {
  if (!baseUrl) fail('BASE_URL is required when PROVIDER=openai-compatible (e.g. https://api.venice.ai/api/v1 or http://<host>:11434/v1).');
  let u: URL; try { u = new URL(baseUrl); } catch { fail(`BASE_URL must be an absolute http(s) URL, got ${JSON.stringify(baseUrl)}.`); }
  if (!/^https?:$/.test(u!.protocol)) fail(`BASE_URL must use http or https, got ${JSON.stringify(baseUrl)}.`);
}
if (baseUrl && provider === 'openrouter')
  console.warn('[recipe] note: BASE_URL is ignored for PROVIDER=openrouter (upstream has no OpenRouter base URL override).');
const posInt = (name: string): number | undefined => {
  const v = (env[name] || '').trim();
  if (!v) return undefined;
  if (!/^[0-9]+$/.test(v) || Number(v) <= 0) fail(`${name} must be a positive whole number of tokens, got ${JSON.stringify(v)}.`);
  return Number(v);
};
const contextBudgetTokens = posInt('CONTEXT_BUDGET_TOKENS');
const maxTokens = posInt('MAX_TOKENS');
// text, or an http(s) URL (no spaces/newlines) that upstream fetches at load time
const systemPrompt = env.SYSTEM_PROMPT && env.SYSTEM_PROMPT.trim() ? env.SYSTEM_PROMPT : 'You are a helpful, persistent assistant.';

const keyVar: Record<string, string> = {
  anthropic: 'ANTHROPIC_API_KEY or ANTHROPIC_AUTH_TOKEN', openrouter: 'OPENROUTER_API_KEY',
  'openai-responses': 'OPENAI_API_KEY', 'openai-compatible': 'OPENAI_COMPATIBLE_API_KEY', bedrock: 'AWS_ACCESS_KEY_ID',
};
const hasKey = provider === 'mock' ? true : provider === 'anthropic' ? !!(env.ANTHROPIC_API_KEY || env.ANTHROPIC_AUTH_TOKEN)
  : provider === 'bedrock' ? !!(env.AWS_ACCESS_KEY_ID && env.AWS_SECRET_ACCESS_KEY)
  : !!env[keyVar[provider]];
if (!hasKey) console.warn(`[recipe] warning: ${keyVar[provider]} is not set; model calls will fail until it is (fine for local servers without auth).`);

const agent: Record<string, unknown> = {
  name: (env.AGENT_NAME || 'agent').trim(),
  provider,
  systemPrompt,
};
if (model) agent.model = model;
if (maxTokens !== undefined) agent.maxTokens = maxTokens;
if (contextBudgetTokens !== undefined) agent.contextBudgetTokens = contextBudgetTokens;
if (provider === 'openai-compatible') agent.baseUrl = baseUrl;

// ---- optional chat bridges (off unless ZULIP_ENABLED / DISCORD_ENABLED) ----
const truthy = (v?: string) => /^(true|1|yes|on)$/i.test((v || '').trim());
const list = (v?: string) => (v || '').split(',').map(x => x.trim()).filter(Boolean);
const zulipOn = truthy(env.ZULIP_ENABLED);
const discordOn = truthy(env.DISCORD_ENABLED);
const dataDir = env.DATA_DIR || '/data';
const mcpServers: Record<string, unknown> = {};
const channels: string[] = [];
if (zulipOn) {
  const streams = list(env.ZULIP_STREAM).map(s => s.replace(/^#/, ''));
  const zenv: Record<string, string> = {
    ZULIP_RC_PATH: (env.ZULIP_RC_PATH || '/config/.zuliprc').trim(),
    ZULIP_STATE_DIR: `${dataDir}/zulip-state`,
  };
  if (streams.length) zenv.ZULIP_SUBSCRIBE = streams.join(',');
  if (list(env.ZULIP_DM_USERS).length) zenv.ZULIP_DM_USERS = list(env.ZULIP_DM_USERS).join(',');
  const zch = streams.map(s => `zulip:${s}`);
  channels.push(...zch);
  mcpServers.zulip = {
    command: '/usr/local/bin/node',
    args: ['/opt/zulip_mcp/build/index.js'],
    env: zenv,
    ...(zch.length ? { channelSubscription: zch } : {}),
  };
}
if (discordOn) {
  if (!(env.DISCORD_TOKEN || '').trim()) console.warn('[recipe] warning: DISCORD_ENABLED=true but DISCORD_TOKEN is empty; the Discord bridge will fail to log in.');
  const guilds = list(env.DISCORD_GUILD_ID);
  // "guild:ch1+ch2" entries name channels to open; a bare guild id admits all its channels
  const dch = guilds.flatMap(g => { const [gid, chs] = g.split(':'); return chs ? chs.split('+').filter(Boolean).map(c => `discord:${gid}:${c}`) : []; });
  channels.push(...dch);
  const denv: Record<string, string> = {
    DISCORD_TOKEN: '${DISCORD_TOKEN}', // substituted at load time; the token is not stored in this file
    DISCORD_WATERMARK_FILE: `${dataDir}/discord-watermarks.json`,
    DISCORD_FILTERS_FILE: '/config/discord-filters.json',
  };
  if (guilds.length) denv.DISCORD_GUILD_ID = guilds.join(',');
  if (list(env.DISCORD_DM_USERS).length) denv.DISCORD_DM_USERS = list(env.DISCORD_DM_USERS).join(',');
  if (list(env.DISCORD_ADMIN_USERS).length) denv.DISCORD_ADMIN_USERS = list(env.DISCORD_ADMIN_USERS).join(',');
  mcpServers.discord = {
    command: '/usr/local/bin/node',
    args: ['/opt/discord-mcpl/dist/src/index.js', '--stdio'],
    env: denv,
    allowHostCommands: true, // lets DISCORD_ADMIN_USERS run /undo /hide /nudge /unstick
    ...(dch.length ? { channelSubscription: dch } : {}),
  };
}
const chatOn = zulipOn || discordOn;
const wake = chatOn ? {
  policies: [
    { name: 'user-input', match: { scope: ['external-message'] }, behavior: 'always' },
    { name: 'subagent-completions', match: { scope: ['inference-request'] }, behavior: 'always' },
    { name: 'other-bots', match: { tagsAny: ['chat:from-bot'] }, behavior: 'defer' },
    { name: 'chat-dms-and-mentions', match: { tagsAny: ['chat:addressed'] }, behavior: 'always' },
    ...(zulipOn ? [{ name: 'zulip-channels', match: { scope: ['mcpl:channel-incoming'], source: 'zulip' }, behavior: 'always' }] : []),
    ...(discordOn ? [{ name: 'discord-channels', match: { scope: ['mcpl:channel-incoming'], source: 'discord' }, behavior: 'always' }] : []),
  ],
  default: 'always',
} : undefined;

const recipe = {
  name: 'Connectome (Docker default)',
  description: `Generated by the container entrypoint for provider ${provider}. Edit freely, or set REGENERATE_RECIPE=true to rebuild from env vars.`,
  agent,
  ...(chatOn ? { mcpServers } : {}),
  modules: {
    ...(wake ? { wake } : {}),
    // persistent paths instead of upstream's ./input and ./output under /app
    workspace: {
      mounts: [
        { name: 'input', path: '/input', mode: 'read-only', watch: 'never' },
        { name: 'products', path: '/data/output', mode: 'read-write', watch: 'never' },
      ],
    },
    webui: {
      host: '0.0.0.0',
      port: 7340,
      // substituted by the host at load time, so credentials are not stored in this file
      basicAuth: { username: '${WEBUI_USERNAME}', password: '${WEBUI_PASSWORD}' },
    },
  },
};
await Bun.write(out, JSON.stringify(recipe, null, 2) + '\n');
console.log(`[recipe] wrote ${out} (provider=${provider}${zulipOn ? ', zulip' : ''}${discordOn ? ', discord' : ''}${channels.length ? `, channels=${channels.join(' ')}` : ''}${model ? `, model=${model}` : ''}${provider === 'openai-compatible' ? `, baseUrl=${baseUrl}` : ''})`);

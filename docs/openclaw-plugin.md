# @clawtrace-io/clawtails plugin

Instruments your OpenClaw agent and sends OTLP traces and correlated logs to ClawTrace. Gives you the full waterfall view — LLM turns, tool calls, token usage, costs, and per-span log bodies — without any code changes to your agent.

## Install

```bash
openclaw plugins install @clawtrace-io/clawtails
```

## Configure

Configure via the OpenClaw plugin config for `@clawtrace-io/clawtails`:

```json
{
  "endpoint": "http://localhost:3000",
  "enabled": true,
  "logs": {
    "enabled": true,
    "tool_calls": true,
    "assistant_turns": true,
    "user_messages": true,
    "compaction_events": true
  }
}
```

| Field | Default | Description |
|---|---|---|
| `endpoint` | `http://localhost:3000` | ClawTrace base URL. Change this if ClawTrace is on another machine. |
| `enabled` | `true` | Set to `false` to pause tracing without uninstalling the plugin. |
| `logs.enabled` | `true` | Master switch for log emission alongside traces. |
| `logs.tool_calls` | `true` | Log each tool call with its input params and output text. |
| `logs.assistant_turns` | `true` | Log each assistant message with model, usage, and stop reason. |
| `logs.user_messages` | `true` | Log each user message. |
| `logs.compaction_events` | `true` | Log each context compaction event. |

## What gets traced

One OTLP trace + correlated OTLP logs per agent turn, emitted when the turn completes:

```
openclaw.request                    root span — bounds the full turn
├── openclaw.agent.turn             one per assistant message (model, usage, stop reason)
│   └── openclaw.tool.<name>        one per tool call (duration, exit code, cwd)
├── openclaw.context.compaction     emitted if context was compacted mid-turn
├── openclaw.context.branch_summary emitted if a branch summary was generated
└── openclaw.session.yield          emitted if a subagent yield occurred
```

### Span attributes

**`openclaw.request`**
- `openclaw.run_id` — unique ID for this agent run
- `openclaw.channel`, `openclaw.space`, `openclaw.sender`, `openclaw.message_id` — from the triggering message

**`openclaw.agent.turn`**
- `openclaw.model`, `openclaw.provider`, `openclaw.api`
- `openclaw.stop_reason`, `openclaw.response_id`
- `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`
- `gen_ai.usage.cache_read_tokens`, `gen_ai.usage.cache_write_tokens`
- `gen_ai.usage.total_tokens`, `gen_ai.usage.cost_usd`

**`openclaw.tool.<name>`**
- `tool.name`, `tool.call_id`, `tool.duration_ms`, `tool.exit_code`
- `tool.cwd`, `tool.pid`, `tool.error`
- `tool.model`, `tool.provider` — set for subagent tool calls

**`openclaw.context.compaction` / `openclaw.context.branch_summary`**
- `openclaw.tokens_before`, `openclaw.summary`

**`openclaw.session.yield`**
- `openclaw.yield_message`

## Logs: two options

OpenClaw has two ways to send logs to ClawTrace. Pick one — running both produces duplicates.

### Option A — OpenClaw built-in logs (default, no config needed)

OpenClaw emits its own diagnostic logs to any configured OTLP endpoint. These arrive at ClawTrace's `/v1/logs` and appear on the Logs index page, but they carry **no `traceId`**, so they cannot be correlated with traces or shown in the waterfall.

This is the out-of-the-box behaviour if you have not touched the `logs` config in this plugin.

### Option B — Plugin rich logs (recommended)

The `@clawtrace-io/clawtails` plugin can emit its own log records stamped with the same `traceId` and `spanId` as every span it produces. These appear **inline in the waterfall drawer** for each span — expand a row and see the tool input/output or model response right there.

To enable this, set `logs.enabled: true` in the plugin config **and** disable OpenClaw's built-in diagnostic log emission so you don't get duplicates:

```json
{
  "endpoint": "http://localhost:3000",
  "enabled": true,
  "logs": {
    "enabled": true,
    "tool_calls": true,
    "assistant_turns": true,
    "user_messages": true,
    "compaction_events": true
  }
}
```

Then turn off OpenClaw's native log forwarding in your OpenClaw config (the `otlp.logs` endpoint setting). Exact path depends on your OpenClaw version — check `openclaw config` or the OpenClaw docs.

### What rich logs contain

| Category | Linked to | Body contents |
|----------|-----------|---------------|
| `tool_calls` | tool span | `{ input, output, toolName, status, durationMs, exitCode, cwd, error }` |
| `assistant_turns` | agent.turn span | raw assistant message (model, usage, stop reason, response ID) |
| `user_messages` | request root span | raw user message |
| `compaction_events` | compaction span | `{ summary, tokensBefore }` |

Log bodies are JSON — ClawTrace renders them as expandable pretty-printed JSON in the waterfall drawer.

## Waterfall timing

Each span's position in the waterfall reflects real elapsed time:

- `openclaw.request` spans the full turn (0% → 100%)
- `openclaw.agent.turn` covers LLM inference only — from when the previous turn ended to when the first tool fired
- `openclaw.tool.*` covers actual tool execution time

This means the waterfall shows exactly where time was spent: waiting on the model vs. waiting on tools.

## Troubleshooting

**No traces appearing in ClawTrace**

Check that ClawTrace is running and the endpoint is reachable:

```bash
curl http://localhost:3000/v1/traces -X POST \
  -H "Content-Type: application/json" \
  -d '{"resourceSpans":[]}'
```

Should return `{}`. If not, verify the `endpoint` in `~/.openclaw/clawtrace.json`.

**Waterfall shows single-span traces only**

The plugin may not be installed or enabled. Run `openclaw status` and look for `@clawtrace-io/clawtails` in the plugin list.

**Tool spans have zero duration**

Upgrade to the latest plugin version — early releases had a timestamp bug where `event.timestamp` (tool finish time) was used as the start time rather than `event.timestamp - durationMs`.

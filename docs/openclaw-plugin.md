# openclaw-clawtrace plugin

Instruments your OpenClaw agent and sends OTLP traces to ClawTrace. Gives you the full waterfall view — LLM turns, tool calls, token usage, costs — without any code changes to your agent.

## Install

```bash
openclaw plugins install openclaw-clawtrace
```

## Configure

Create `~/.openclaw/clawtrace.json`:

```json
{
  "endpoint": "http://localhost:3000",
  "enabled": true
}
```

| Field | Default | Description |
|---|---|---|
| `endpoint` | `http://localhost:3000` | ClawTrace base URL. Change this if ClawTrace is on another machine. |
| `enabled` | `true` | Set to `false` to pause tracing without uninstalling the plugin. |

## What gets traced

One OTLP trace per agent turn, emitted when the turn completes:

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

The plugin may not be installed or enabled. Run `openclaw status` and look for `openclaw-clawtrace` in the plugin list.

**Tool spans have zero duration**

Upgrade to the latest plugin version — early releases had a timestamp bug where `event.timestamp` (tool finish time) was used as the start time rather than `event.timestamp - durationMs`.

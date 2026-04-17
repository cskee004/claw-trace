# openclaw-clawtrace

OpenClaw plugin that sends traces to [ClawTrace](https://github.com/your-org/claw-trace) via OTLP.

## Install

```bash
openclaw plugins install openclaw-clawtrace
```

## Config

Create `~/.openclaw/clawtrace.json`:

```json
{
  "endpoint": "http://your-clawtrace-host:3000",
  "enabled": true
}
```

| Field | Default | Description |
|---|---|---|
| `endpoint` | `http://localhost:3000` | ClawTrace base URL |
| `enabled` | `true` | Set to `false` to disable without uninstalling |

## What it sends

One OTLP trace per agent turn, emitted when the turn completes (`agent_end` event):

```
openclaw.request                  ← root span; bounds the full turn
├── openclaw.agent.turn           ← one per assistant message (model, usage, stop_reason)
│   └── openclaw.tool.<name>      ← one per tool call (duration, exit code, cwd, pid)
├── openclaw.context.compaction   ← emitted if context was compacted during this turn
├── openclaw.context.branch_summary ← emitted if a branch summary was created
└── openclaw.session.yield        ← emitted if a subagent yield occurred
```

### Span attributes

**`openclaw.request`**
- `openclaw.run_id`, `openclaw.channel`, `openclaw.space`, `openclaw.sender`, `openclaw.message_id`

**`openclaw.agent.turn`**
- `openclaw.run_id`, `openclaw.model`, `openclaw.provider`, `openclaw.api`
- `openclaw.stop_reason`, `openclaw.response_id`, `openclaw.error_message`
- `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`
- `gen_ai.usage.cache_read_tokens`, `gen_ai.usage.cache_write_tokens`
- `gen_ai.usage.total_tokens`, `gen_ai.usage.cost_usd`, `gen_ai.usage.tokens_before`

**`openclaw.tool.*`**
- `tool.name`, `tool.call_id`, `tool.duration_ms`, `tool.exit_code`
- `tool.session_id`, `tool.cwd`, `tool.pid`, `tool.error`
- `tool.model`, `tool.provider` (for subagent tools)

**`openclaw.context.compaction` / `openclaw.context.branch_summary`**
- `openclaw.tokens_before`, `openclaw.summary`

**`openclaw.session.yield`**
- `openclaw.yield_message`

Traces appear in ClawTrace at the configured endpoint.

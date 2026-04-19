# openclaw-clawtrace

OpenClaw plugin that sends traces to [ClawTrace](https://github.com/your-org/claw-trace) via OTLP.

## Install

```bash
openclaw plugins install openclaw-clawtrace
```

## Config

Configured via the standard OpenClaw plugin config path. Example:

```json
{
  "endpoint": "http://your-clawtrace-host:3000",
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
| `endpoint` | `http://localhost:3000` | ClawTrace base URL |
| `enabled` | `true` | Set to `false` to disable without uninstalling |
| `logs.enabled` | `true` | Master switch for log emission |
| `logs.tool_calls` | `true` | Emit a log record per tool call (input + output) |
| `logs.assistant_turns` | `true` | Emit a log record per assistant turn |
| `logs.user_messages` | `true` | Emit a log record per user message |
| `logs.compaction_events` | `true` | Emit a log record per context compaction |

## What it sends

One OTLP trace + correlated OTLP logs per agent turn, emitted when the turn completes (`agent_end` event):

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

### Logs: two options — pick one

OpenClaw can send logs two ways. Running both produces duplicates.

**Option A — OpenClaw built-in logs (default)**
OpenClaw's native diagnostic log forwarding sends logs to `/v1/logs` without a `traceId`. They appear on the ClawTrace Logs index but cannot be correlated with traces or shown in the waterfall. No config change needed — this is the default if you leave `logs.enabled` unset.

**Option B — Plugin rich logs (recommended)**
Set `logs.enabled: true` in this plugin's config, then disable OpenClaw's native log forwarding in your OpenClaw config to avoid duplicates. Rich logs are stamped with `traceId`/`spanId` and appear inline in the ClawTrace waterfall drawer.

| Toggle | Linked span | Body |
|--------|-------------|------|
| `tool_calls` | tool span | `{ input, output, toolName, status, durationMs, exitCode, cwd, error }` |
| `assistant_turns` | agent.turn span | raw assistant message (model, usage, stopReason, …) |
| `user_messages` | request root span | raw user message |
| `compaction_events` | compaction span | raw compactionSummary (summary, tokensBefore) |

Traces and logs appear in ClawTrace at the configured endpoint.

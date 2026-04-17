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

One OTLP trace per agent run, emitted when the run completes:

```
openclaw.request        ← root span (channel, sender, message_id)
└── openclaw.agent.turn ← one per model call (model, usage, stop_reason)
    └── openclaw.tool.* ← one per tool call (tool name, duration, status)
```

Traces appear in ClawTrace at the configured endpoint.

# openclaw-clawtrace

OpenClaw plugin that sends traces to [ClawTrace](https://github.com/your-org/claw-trace) via OTLP.

## Install

```bash
openclaw plugins install openclaw-clawtrace
```

## Config

Set these environment variables where OpenClaw runs:

| Variable | Default | Description |
|---|---|---|
| `CLAWTRACE_ENDPOINT` | `http://localhost:3000` | ClawTrace base URL |
| `CLAWTRACE_ENABLED` | `true` | Set to `false` to disable without uninstalling |

## What it sends

One OTLP trace per agent run, emitted when the run completes:

```
openclaw.request        ← root span (channel, sender, message_id)
└── openclaw.agent.turn ← one per model call (model, usage, stop_reason)
    └── openclaw.tool.* ← one per tool call (tool name, duration, status)
```

Traces appear in ClawTrace at the endpoint configured above.

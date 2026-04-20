// Replays spike JSON files through the plugin logic and prints the OTLP
// payload that would be sent to ClawTrace. No network calls are made.

import { readFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { toMs, buildOtlpPayload } from "./trace-helpers.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

// ── Event replay ──────────────────────────────────────────────────────────────

const toolBuffer = new Map();

function handleAfterToolCall(event) {
  const d = event.data || event;
  const ts = event.timestamp
    ? toMs(event.timestamp) - (d.durationMs || 0)
    : Date.now() - (d.durationMs || 0);
  toolBuffer.set(d.toolCallId, {
    toolCallId:  d.toolCallId,
    runId:       d.runId,
    toolName:    d.toolName,
    params:      d.params,
    resultText:  d.result?.content?.[0]?.text,
    status:      d.result?.details?.status ?? "completed",
    durationMs:  d.durationMs,
    timestamp:   ts,
    exitCode:    d.result?.details?.exitCode,
    sessionId:   d.result?.details?.sessionId,
    error:       d.error || d.result?.details?.error,
    cwd:         d.result?.details?.cwd,
    pid:         d.result?.details?.pid,
    subModel:    d.result?.details?.model,
    subProvider: d.result?.details?.provider,
  });
}

// ── Replay ────────────────────────────────────────────────────────────────────

const allEvents = JSON.parse(
  readFileSync(
    join(__dirname, "../.claude/json-test-files/spike-all-events.json"),
    "utf8"
  )
);

const sorted = allEvents.sort((a, b) => a.sequence - b.sequence);

let traceCount = 0;

for (const event of sorted) {
  if (event.eventName === "after_tool_call") {
    handleAfterToolCall(event);
  } else if (event.eventName === "agent_end") {
    const messages = (event.data || event).messages || [];
    const result = buildOtlpPayload(messages, toolBuffer);
    traceCount++;
    console.log(`\n${"=".repeat(60)}`);
    console.log(`TRACE ${traceCount}  traceId=${result.traceId}`);
    console.log(`spans: ${result.spans.length}  logs: ${result.logEntries.length}`);
    result.spans.forEach(s => {
      const indent = s.parentSpanId ? (s.name.startsWith("openclaw.tool") ? "      " : "   ") : "";
      const dur = Math.round(
        (Number(s.endTimeUnixNano) - Number(s.startTimeUnixNano)) / 1_000_000
      );
      const model = s.attributes.find(a => a.key === "openclaw.model")?.value.stringValue || "";
      const tool  = s.attributes.find(a => a.key === "tool.name")?.value.stringValue || "";
      const label = model || tool || "";
      console.log(`${indent}[${s.name}]${label ? "  " + label : ""}  ${dur}ms  spanId=${s.spanId}`);
    });
  }
}

console.log(`\n${"=".repeat(60)}`);
console.log(`Done. ${traceCount} traces built from ${sorted.length} events.`);
console.log(`Remaining buffer entries (orphaned tool calls): ${toolBuffer.size}`);

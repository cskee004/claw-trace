// Replays spike JSON files through the plugin logic and prints the OTLP
// payload that would be sent to ClawTrace. No network calls are made.

import { readFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { createHash, randomBytes } from "crypto";

const __dirname = dirname(fileURLToPath(import.meta.url));

// ── Inline the plugin's core logic (without the api.on wiring) ───────────────

const toolBuffer = new Map();

function handleAfterToolCall(event) {
  const d = event.data || event;
  toolBuffer.set(d.toolCallId, {
    toolCallId: d.toolCallId,
    runId:      d.runId,
    toolName:   d.toolName,
    params:     d.params,
    status:     d.result?.details?.status ?? "completed",
    durationMs: d.durationMs,
    timestamp:  event.timestamp,
  });
}

function handleAgentEnd(event) {
  const messages = (event.data || event).messages || [];
  return buildTrace(messages);
}

function buildTrace(messages) {
  let lastUserIdx = -1;
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === "user") { lastUserIdx = i; break; }
  }
  const turn = lastUserIdx >= 0 ? messages.slice(lastUserIdx) : messages;

  const turnToolIds = new Set(
    turn
      .filter(m => m.role === "assistant")
      .flatMap(m => (m.content || []))
      .filter(c => c.type === "toolCall")
      .map(c => c.id)
  );

  let runId = null;
  const myToolCalls = [];
  for (const [tcId, entry] of toolBuffer) {
    if (turnToolIds.has(tcId)) {
      runId = entry.runId;
      myToolCalls.push(entry);
      toolBuffer.delete(tcId);
    }
  }

  if (!runId) {
    const seed = turn[0]?.content?.[0]?.text || String(Date.now());
    runId = createHash("sha256").update(seed).digest("hex").slice(0, 32);
  }

  const traceId = runId.replace(/-/g, "").slice(0, 32).padEnd(32, "0");

  const userMessages   = turn.filter(m => m.role === "user");
  const assistMessages = turn.filter(m => m.role === "assistant");
  const requestStart   = userMessages[0]?.timestamp ?? Date.now();
  const requestEnd     = assistMessages[assistMessages.length - 1]?.timestamp ?? Date.now();

  const spans = [];
  const rootSpanId = makeSpanId();

  spans.push(makeSpan({
    traceId, spanId: rootSpanId, parentId: null,
    name: "openclaw.request",
    startMs: requestStart, endMs: requestEnd,
    attrs: extractRequestAttrs(userMessages[userMessages.length - 1]),
  }));

  assistMessages.forEach((msg) => {
    if (!msg.timestamp) return;
    const turnSpanId = makeSpanId();
    const turnTools  = (msg.content || []).filter(c => c.type === "toolCall");

    const lastTool = turnTools.length
      ? myToolCalls.find(t => t.toolCallId === turnTools[turnTools.length - 1]?.id)
      : null;
    const turnEnd = lastTool
      ? new Date(lastTool.timestamp).getTime() + (lastTool.durationMs || 0)
      : msg.timestamp;

    spans.push(makeSpan({
      traceId, spanId: turnSpanId, parentId: rootSpanId,
      name: "openclaw.agent.turn",
      startMs: msg.timestamp, endMs: turnEnd,
      attrs: {
        "openclaw.model":                  msg.model,
        "openclaw.provider":               msg.provider,
        "openclaw.stop_reason":            msg.stopReason,
        "openclaw.response_id":            msg.responseId,
        "gen_ai.usage.input_tokens":       msg.usage?.input,
        "gen_ai.usage.output_tokens":      msg.usage?.output,
        "gen_ai.usage.cache_read_tokens":  msg.usage?.cacheRead,
        "gen_ai.usage.cache_write_tokens": msg.usage?.cacheWrite,
      },
    }));

    turnTools.forEach(tc => {
      const buf       = myToolCalls.find(b => b.toolCallId === tc.id);
      const toolStart = buf ? new Date(buf.timestamp).getTime() : msg.timestamp;
      const toolEnd   = buf ? toolStart + (buf.durationMs || 0) : toolStart;
      spans.push(makeSpan({
        traceId, spanId: makeSpanId(), parentId: turnSpanId,
        name: `openclaw.tool.${tc.name || buf?.toolName || "unknown"}`,
        startMs: toolStart, endMs: toolEnd,
        status: buf?.status === "error" ? "ERROR" : "OK",
        attrs: {
          "tool.name":        tc.name || buf?.toolName,
          "tool.call_id":     tc.id,
          "tool.duration_ms": buf?.durationMs,
        },
      }));
    });
  });

  return { traceId, spans };
}

function makeSpan({ traceId, spanId, parentId, name, startMs, endMs, attrs = {}, status = "OK" }) {
  const span = {
    traceId, spanId, name,
    startTimeUnixNano: String(startMs * 1_000_000),
    endTimeUnixNano:   String((endMs || startMs) * 1_000_000),
    attributes: toOtlpAttrs(attrs),
    status: { code: status === "ERROR" ? 2 : 1 },
  };
  if (parentId) span.parentSpanId = parentId;
  return span;
}

function toOtlpAttrs(obj) {
  return Object.entries(obj)
    .filter(([, v]) => v != null)
    .map(([k, v]) => ({ key: k, value: { stringValue: String(v) } }));
}

function extractRequestAttrs(userMsg) {
  if (!userMsg) return {};
  const text = userMsg.content?.[0]?.text || "";
  const m = text.match(/```json\s*(\{[\s\S]*?\})\s*```/);
  if (!m) return {};
  try {
    const meta = JSON.parse(m[1]);
    return {
      "openclaw.channel":    meta.group_channel,
      "openclaw.space":      meta.group_space,
      "openclaw.sender":     meta.sender,
      "openclaw.message_id": meta.message_id,
    };
  } catch { return {}; }
}

function makeSpanId() {
  return randomBytes(8).toString("hex");
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
    const result = handleAgentEnd(event);
    traceCount++;
    console.log(`\n${"=".repeat(60)}`);
    console.log(`TRACE ${traceCount}  traceId=${result.traceId}`);
    console.log(`spans: ${result.spans.length}`);
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

"use strict";

const http  = require("http");
const https = require("https");
const crypto = require("crypto");

const ENDPOINT = (process.env.CLAWTRACE_ENDPOINT || "http://localhost:3000").replace(/\/$/, "");
const ENABLED  = process.env.CLAWTRACE_ENABLED !== "false";

// Buffer keyed by toolCallId — holds tool call data until agent_end
const toolBuffer = new Map();

module.exports = function(api) {
  if (!ENABLED) return;

  api.on("after_tool_call", (event) => {
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
  });

  api.on("agent_end", (event) => {
    try {
      const messages = (event.data || event).messages || [];
      buildAndSend(messages);
    } catch (err) {
      // never crash the agent
    }
  });
};

function buildAndSend(messages) {
  // Slice to current turn only: from the last user message to end.
  // agent_end.messages is the full rolling context window.
  let lastUserIdx = -1;
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === "user") { lastUserIdx = i; break; }
  }
  const turn = lastUserIdx >= 0 ? messages.slice(lastUserIdx) : messages;

  // Find all toolCallIds in this turn to identify buffer entries + derive runId.
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

  // For tool-free turns derive a stable trace id from the user message text.
  if (!runId) {
    const seed = turn[0]?.content?.[0]?.text || String(Date.now());
    runId = crypto.createHash("sha256").update(seed).digest("hex").slice(0, 32);
  }

  const traceId = runId.replace(/-/g, "").slice(0, 32).padEnd(32, "0");

  const userMessages   = turn.filter(m => m.role === "user");
  const assistMessages = turn.filter(m => m.role === "assistant");
  const requestStart   = userMessages[0]?.timestamp ?? Date.now();
  const requestEnd     = assistMessages[assistMessages.length - 1]?.timestamp ?? Date.now();

  const spans = [];
  const rootSpanId = makeSpanId();

  // Root span — openclaw.request
  spans.push(makeSpan({
    traceId,
    spanId:    rootSpanId,
    parentId:  null,
    name:      "openclaw.request",
    startMs:   requestStart,
    endMs:     requestEnd,
    attrs:     extractRequestAttrs(userMessages[userMessages.length - 1]),
  }));

  // One agent_turn span per assistant message, with tool children
  assistMessages.forEach((msg, i) => {
    if (!msg.timestamp) return;
    const turnSpanId  = makeSpanId();
    const turnTools   = (msg.content || []).filter(c => c.type === "toolCall");
    const lastToolEnd = turnTools.length
      ? (myToolCalls.find(t => t.toolCallId === turnTools[turnTools.length - 1]?.id)?.timestamp
         ? new Date(myToolCalls.find(t => t.toolCallId === turnTools[turnTools.length - 1].id).timestamp).getTime() +
           (myToolCalls.find(t => t.toolCallId === turnTools[turnTools.length - 1].id).durationMs || 0)
         : msg.timestamp)
      : msg.timestamp;

    spans.push(makeSpan({
      traceId,
      spanId:   turnSpanId,
      parentId: rootSpanId,
      name:     "openclaw.agent.turn",
      startMs:  msg.timestamp,
      endMs:    lastToolEnd,
      attrs:    {
        "openclaw.model":        msg.model,
        "openclaw.provider":     msg.provider,
        "openclaw.stop_reason":  msg.stopReason,
        "openclaw.response_id":  msg.responseId,
        "gen_ai.usage.input_tokens":       msg.usage?.input,
        "gen_ai.usage.output_tokens":      msg.usage?.output,
        "gen_ai.usage.cache_read_tokens":  msg.usage?.cacheRead,
        "gen_ai.usage.cache_write_tokens": msg.usage?.cacheWrite,
      },
    }));

    // Tool spans — children of this agent_turn
    turnTools.forEach(tc => {
      const buf = myToolCalls.find(b => b.toolCallId === tc.id);
      const toolStart = buf ? new Date(buf.timestamp).getTime() : msg.timestamp;
      const toolEnd   = buf ? toolStart + (buf.durationMs || 0) : toolStart;
      spans.push(makeSpan({
        traceId,
        spanId:   makeSpanId(),
        parentId: turnSpanId,
        name:     `openclaw.tool.${tc.name || buf?.toolName || "unknown"}`,
        startMs:  toolStart,
        endMs:    toolEnd,
        status:   buf?.status === "error" ? "ERROR" : "OK",
        attrs: {
          "tool.name":       tc.name || buf?.toolName,
          "tool.call_id":    tc.id,
          "tool.duration_ms": buf?.durationMs,
        },
      }));
    });
  });

  postOtlp(traceId, spans);
}

// ── OTLP helpers ─────────────────────────────────────────────────────────────

function makeSpan({ traceId, spanId, parentId, name, startMs, endMs, attrs = {}, status = "OK" }) {
  const span = {
    traceId,
    spanId,
    name,
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
      "openclaw.channel":      meta.group_channel,
      "openclaw.space":        meta.group_space,
      "openclaw.sender":       meta.sender,
      "openclaw.message_id":   meta.message_id,
    };
  } catch { return {}; }
}

function makeSpanId() {
  return crypto.randomBytes(8).toString("hex");
}

function postOtlp(traceId, spans) {
  const body = JSON.stringify({
    resourceSpans: [{
      resource: {
        attributes: [
          { key: "service.name", value: { stringValue: "openclaw" } },
        ],
      },
      scopeSpans: [{ spans }],
    }],
  });

  const url      = new URL(`${ENDPOINT}/v1/traces`);
  const lib      = url.protocol === "https:" ? https : http;
  const req      = lib.request({
    hostname: url.hostname,
    port:     url.port || (url.protocol === "https:" ? 443 : 80),
    path:     url.pathname,
    method:   "POST",
    headers:  { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(body) },
  });
  req.on("error", () => {}); // never crash the agent
  req.write(body);
  req.end();
}

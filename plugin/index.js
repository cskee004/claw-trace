import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import { createHash, randomBytes } from "crypto";
import { readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import http from "http";
import https from "https";

function loadConfig() {
  const configPath = join(homedir(), ".openclaw", "clawtrace.json");
  try { return JSON.parse(readFileSync(configPath, "utf8")); } catch { return {}; }
}

const config   = loadConfig();
const ENDPOINT = (config.endpoint || "http://localhost:3000").replace(/\/$/, "");
const ENABLED  = config.enabled !== false;

// Buffer keyed by toolCallId — holds tool call data until agent_end
const toolBuffer = new Map();

export default definePluginEntry({
  id: "openclaw-clawtrace",
  name: "ClawTrace",
  description: "Sends OpenClaw agent traces to ClawTrace via OTLP",

  register(api) {
    if (!ENABLED) return;

    api.on("after_tool_call", (event) => {
      const d = event.data || event;
      console.error("[clawtrace] after_tool_call raw:", JSON.stringify({ ts: event.timestamp, toolCallId: d.toolCallId, durationMs: d.durationMs, runId: d.runId }));
      const ts = event.timestamp
        ? toMs(event.timestamp)
        : Date.now() - (d.durationMs || 0);
      toolBuffer.set(d.toolCallId, {
        toolCallId: d.toolCallId,
        runId:      d.runId,
        toolName:   d.toolName,
        status:     d.result?.details?.status ?? "completed",
        durationMs: d.durationMs,
        timestamp:  ts,
        exitCode:   d.result?.details?.exitCode,
        sessionId:  d.result?.details?.sessionId,
        error:      d.error || d.result?.details?.error,
        cwd:        d.result?.details?.cwd,
        pid:        d.result?.details?.pid,
        subModel:   d.result?.details?.model,
        subProvider: d.result?.details?.provider,
      });
    });

    api.on("agent_end", (event) => {
      try {
        const messages = (event.data || event).messages || [];
        buildAndSend(messages);
      } catch {
        // never crash the agent
      }
    });
  },
});

function buildAndSend(messages) {
  // Slice to current turn: from the last user message to end.
  // agent_end.messages is the full rolling context window.
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
  const requestStart = toMs(userMessages[0]?.timestamp);

  const spans  = [];
  const rootId = makeSpanId();

  // prevTurnEnd tracks when the previous turn finished so each agent_turn span
  // starts where the last one ended — giving real LLM inference durations.
  let prevTurnEnd = requestStart;

  assistMessages.forEach((msg) => {
    if (!msg.timestamp) return;
    const turnSpanId = makeSpanId();
    const turnTools  = (msg.content || []).filter(c => c.type === "toolCall");

    const turnStart = prevTurnEnd;
    const msgEnd    = toMs(msg.timestamp);  // when LLM response arrived

    const lastTool = turnTools.length
      ? myToolCalls.find(t => t.toolCallId === turnTools[turnTools.length - 1]?.id)
      : null;
    // nextStart: when the next turn can begin (after tools finish, or at msgEnd if no tools).
    // turnEnd: this span ends when the LLM responded — tools are children, not part of this span.
    const nextStart = lastTool
      ? toMs(lastTool.timestamp) + (lastTool.durationMs || 0)
      : msgEnd;

    prevTurnEnd = nextStart;

    spans.push(makeSpan({
      traceId, spanId: turnSpanId, parentId: rootId,
      name: "openclaw.agent.turn",
      startMs: turnStart, endMs: msgEnd,
      status: msg.isError ? "ERROR" : "OK",
      attrs: {
        "openclaw.run_id":                 runId,
        "openclaw.api":                    msg.api,
        "openclaw.model":                  msg.model,
        "openclaw.provider":               msg.provider,
        "openclaw.stop_reason":            msg.stopReason,
        "openclaw.response_id":            msg.responseId,
        "openclaw.error_message":          msg.errorMessage,
        "gen_ai.usage.input_tokens":       msg.usage?.input,
        "gen_ai.usage.output_tokens":      msg.usage?.output,
        "gen_ai.usage.cache_read_tokens":  msg.usage?.cacheRead,
        "gen_ai.usage.cache_write_tokens": msg.usage?.cacheWrite,
        "gen_ai.usage.cost_usd":           msg.usage?.cost?.total ?? msg.usage?.cost,
        "gen_ai.usage.total_tokens":       msg.usage?.totalTokens,
        "gen_ai.usage.tokens_before":      msg.tokensBefore,
      },
    }));

    turnTools.forEach(tc => {
      const buf       = myToolCalls.find(b => b.toolCallId === tc.id);
      const toolStart = buf ? toMs(buf.timestamp) : toMs(msg.timestamp);
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
          "tool.exit_code":   buf?.exitCode,
          "tool.session_id":  buf?.sessionId,
          "tool.error":       buf?.error,
          "tool.cwd":         buf?.cwd,
          "tool.pid":         buf?.pid,
          "tool.model":       buf?.subModel,
          "tool.provider":    buf?.subProvider,
        },
      }));
    });
  });

  // Compaction and subagent yield events — invisible without these spans
  turn.forEach((msg) => {
    if (!msg.timestamp) return;
    if (msg.role === "compactionSummary") {
      spans.push(makeSpan({
        traceId, spanId: makeSpanId(), parentId: rootId,
        name: "openclaw.context.compaction",
        startMs: msg.timestamp, endMs: msg.timestamp,
        attrs: {
          "openclaw.tokens_before": msg.tokensBefore,
          "openclaw.summary":       msg.summary,
        },
      }));
    } else if (msg.role === "branchSummary") {
      spans.push(makeSpan({
        traceId, spanId: makeSpanId(), parentId: rootId,
        name: "openclaw.context.branch_summary",
        startMs: msg.timestamp, endMs: msg.timestamp,
        attrs: {
          "openclaw.tokens_before": msg.tokensBefore,
          "openclaw.summary":       msg.summary,
        },
      }));
    } else if (msg.role === "custom" && msg.customType === "openclaw.sessions_yield") {
      spans.push(makeSpan({
        traceId, spanId: makeSpanId(), parentId: rootId,
        name: "openclaw.session.yield",
        startMs: msg.timestamp, endMs: msg.timestamp,
        attrs: {
          "openclaw.yield_message": msg.details?.message,
        },
      }));
    }
  });

  // Request span wraps everything — emitted last so endMs uses the true end of
  // the final turn (including all tool execution), not just the last LLM response.
  spans.unshift(makeSpan({
    traceId, spanId: rootId, parentId: null,
    name: "openclaw.request",
    startMs: requestStart, endMs: prevTurnEnd,
    attrs: { ...extractRequestAttrs(userMessages[0]), "openclaw.run_id": runId },
  }));

  postOtlp(traceId, spans);
}

// Normalize any timestamp format (ms number, ISO string, Date, undefined/NaN) to ms integer.
function toMs(ts) {
  if (ts == null) return Date.now();
  if (typeof ts === "number") return Number.isFinite(ts) ? ts : Date.now();
  const n = new Date(ts).getTime();
  return Number.isFinite(n) ? n : Date.now();
}

function makeSpan({ traceId, spanId, parentId, name, startMs, endMs, attrs = {}, status = "OK" }) {
  const start = toMs(startMs);
  const end   = toMs(endMs ?? startMs);
  const span  = {
    traceId, spanId, name,
    startTimeUnixNano: String(start * 1_000_000),
    endTimeUnixNano:   String(end   * 1_000_000),
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

function postOtlp(traceId, spans) {
  const body = JSON.stringify({
    resourceSpans: [{
      resource: { attributes: [{ key: "service.name", value: { stringValue: "openclaw" } }] },
      scopeSpans: [{ spans }],
    }],
  });

  const url = new URL(`${ENDPOINT}/v1/traces`);
  const lib = url.protocol === "https:" ? https : http;
  const req = lib.request({
    hostname: url.hostname,
    port:     url.port || (url.protocol === "https:" ? 443 : 80),
    path:     url.pathname,
    method:   "POST",
    headers:  { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(body) },
  });
  req.on("error", () => {});
  req.write(body);
  req.end();
}

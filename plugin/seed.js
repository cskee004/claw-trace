// Seeds ClawTrace with all spike data: plugin traces + correlated logs from events + raw OTLP fixtures.
// Usage: node seed.js [--endpoint http://localhost:3000]

import { readFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { createHash, randomBytes } from "crypto";
import http from "http";
import https from "https";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURES  = join(__dirname, "../.claude/json-test-files");

const endpointArg = process.argv.indexOf("--endpoint");
const ENDPOINT = (endpointArg !== -1 ? process.argv[endpointArg + 1] : "http://localhost:3000").replace(/\/$/, "");

// ── HTTP helpers ──────────────────────────────────────────────────────────────

function post(path, body) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(body);
    const url = new URL(`${ENDPOINT}${path}`);
    const lib = url.protocol === "https:" ? https : http;
    const req = lib.request({
      hostname: url.hostname,
      port:     url.port || (url.protocol === "https:" ? 443 : 80),
      path:     url.pathname,
      method:   "POST",
      headers:  { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(payload) },
    }, (res) => {
      let data = "";
      res.on("data", chunk => data += chunk);
      res.on("end", () => resolve({ status: res.statusCode, body: data }));
    });
    req.on("error", reject);
    req.write(payload);
    req.end();
  });
}

function readJson(filename) {
  return JSON.parse(readFileSync(join(FIXTURES, filename), "utf8"));
}

// ── Plugin logic (faithful mirror of index.js — keep in sync) ────────────────

const toolBuffer = new Map();

function toMs(ts) {
  if (ts == null) return Date.now();
  if (typeof ts === "number") return Number.isFinite(ts) ? ts : Date.now();
  const n = new Date(ts).getTime();
  return Number.isFinite(n) ? n : Date.now();
}

function handleAfterToolCall(event) {
  const d  = event.data || event;
  const ts = event.timestamp
    ? toMs(event.timestamp) - (d.durationMs || 0)
    : Date.now() - (d.durationMs || 0);
  toolBuffer.set(d.toolCallId, {
    toolCallId:  d.toolCallId,
    runId:       d.runId,
    toolName:    d.toolName,
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
    params:      d.params,
    resultText:  d.result?.content?.[0]?.text,
  });
}

function buildOtlpPayload(messages, logsConfig = {}) {
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

  const toolSpanIds = new Map(myToolCalls.map(t => [t.toolCallId, makeSpanId()]));

  if (!runId) {
    const seed = turn[0]?.content?.[0]?.text || String(Date.now());
    runId = createHash("sha256").update(seed).digest("hex").slice(0, 32);
  }

  const traceId = runId.replace(/-/g, "").slice(0, 32).padEnd(32, "0");

  const userMessages   = turn.filter(m => m.role === "user");
  const assistMessages = turn.filter(m => m.role === "assistant");
  const requestStart   = toMs(userMessages[0]?.timestamp);

  const spans      = [];
  const logEntries = [];
  const logsOn     = logsConfig.enabled !== false;
  const rootId     = makeSpanId();

  let prevTurnEnd = requestStart;

  assistMessages.forEach((msg) => {
    if (!msg.timestamp) return;
    const turnSpanId = makeSpanId();
    const turnTools  = (msg.content || []).filter(c => c.type === "toolCall");

    const turnStart = prevTurnEnd;
    const msgEnd    = toMs(msg.timestamp);

    const firstTool = turnTools.length
      ? myToolCalls.find(t => t.toolCallId === turnTools[0]?.id)
      : null;
    const lastTool = turnTools.length
      ? myToolCalls.find(t => t.toolCallId === turnTools[turnTools.length - 1]?.id)
      : null;
    const inferenceEnd = firstTool ? toMs(firstTool.timestamp) : msgEnd;
    const nextStart    = lastTool
      ? toMs(lastTool.timestamp) + (lastTool.durationMs || 0)
      : inferenceEnd;

    prevTurnEnd = nextStart;

    spans.push(makeSpan({
      traceId, spanId: turnSpanId, parentId: rootId,
      name: "openclaw.agent.turn",
      startMs: turnStart, endMs: inferenceEnd,
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

    if (logsOn && logsConfig.assistant_turns !== false) {
      logEntries.push(makeLogEntry({
        timestampMs: toMs(msg.timestamp),
        traceId, spanId: turnSpanId,
        body: msg, isError: !!msg.isError,
      }));
    }

    turnTools.forEach(tc => {
      const buf        = myToolCalls.find(b => b.toolCallId === tc.id);
      const toolStart  = buf ? toMs(buf.timestamp) : toMs(msg.timestamp);
      const toolEnd    = buf ? toolStart + (buf.durationMs || 0) : toolStart;
      const toolSpanId = toolSpanIds.get(tc.id) || makeSpanId();
      spans.push(makeSpan({
        traceId, spanId: toolSpanId, parentId: turnSpanId,
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

      if (logsOn && buf && logsConfig.tool_calls !== false) {
        logEntries.push(makeLogEntry({
          timestampMs: buf ? toMs(buf.timestamp) : toMs(msg.timestamp),
          traceId, spanId: toolSpanId,
          body: {
            input:      buf.params ?? null,
            output:     buf.resultText ?? null,
            toolName:   tc.name || buf.toolName,
            status:     buf.status,
            durationMs: buf.durationMs,
            exitCode:   buf.exitCode,
            cwd:        buf.cwd,
            error:      buf.error,
          },
          isError: buf.status === "error",
        }));
      }
    });
  });

  turn.forEach((msg) => {
    if (!msg.timestamp) return;
    if (msg.role === "compactionSummary") {
      const compSpanId = makeSpanId();
      spans.push(makeSpan({
        traceId, spanId: compSpanId, parentId: rootId,
        name: "openclaw.context.compaction",
        startMs: msg.timestamp, endMs: msg.timestamp,
        attrs: {
          "openclaw.tokens_before": msg.tokensBefore,
          "openclaw.summary":       msg.summary,
        },
      }));
      if (logsOn && logsConfig.compaction_events !== false) {
        logEntries.push(makeLogEntry({
          timestampMs: toMs(msg.timestamp),
          traceId, spanId: compSpanId,
          body: msg, isError: false,
        }));
      }
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
        attrs: { "openclaw.yield_message": msg.details?.message },
      }));
    }
  });

  spans.unshift(makeSpan({
    traceId, spanId: rootId, parentId: null,
    name: "openclaw.request",
    startMs: requestStart, endMs: prevTurnEnd,
    attrs: { ...extractRequestAttrs(userMessages[0]), "openclaw.run_id": runId },
  }));

  if (logsOn && logsConfig.user_messages !== false) {
    userMessages.forEach(msg => {
      if (!msg.timestamp) return;
      logEntries.push(makeLogEntry({
        timestampMs: toMs(msg.timestamp),
        traceId, spanId: rootId,
        body: msg, isError: false,
      }));
    });
  }

  return { traceId, spans, logEntries };
}

function makeLogEntry({ timestampMs, traceId, spanId, body, isError }) {
  return {
    timeUnixNano:   String(toMs(timestampMs) * 1_000_000),
    severityText:   isError ? "ERROR" : "INFO",
    severityNumber: isError ? 17 : 9,
    body:           { stringValue: JSON.stringify(body) },
    traceId,
    spanId,
    attributes:     [],
  };
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

function wrapOtlpSpans(spans) {
  return {
    resourceSpans: [{
      resource: { attributes: [{ key: "service.name", value: { stringValue: "openclaw" } }] },
      scopeSpans: [{ spans }],
    }],
  };
}

function wrapOtlpLogs(logEntries) {
  return {
    resourceLogs: [{
      resource: { attributes: [{ key: "service.name", value: { stringValue: "openclaw" } }] },
      scopeLogs: [{ logRecords: logEntries }],
    }],
  };
}

// ── Seed ──────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`Seeding ClawTrace at ${ENDPOINT}\n`);
  let ok = 0, fail = 0;

  async function send(label, path, body) {
    try {
      const r = await post(path, body);
      if (r.status === 200) {
        console.log(`  ✓ ${label}`);
        ok++;
      } else {
        console.log(`  ✗ ${label}  [HTTP ${r.status}] ${r.body.slice(0, 120)}`);
        fail++;
      }
    } catch (e) {
      console.log(`  ✗ ${label}  ${e.message}`);
      fail++;
    }
  }

  // 1. Raw OTLP span fixtures
  console.log("── Raw OTLP spans ──────────────────────────────────────");
  const spanFiles = [
    "span-openclaw-message-processed-001.json",
    "span-openclaw-model-usage-001.json",
    "span-openclaw-session-stuck-001.json",
    "span-openclaw-webhook-error-001.json",
    "span-openclaw-webhook-processed-001.json",
  ];
  for (const f of spanFiles) {
    await send(f, "/v1/traces", readJson(f));
  }

  // 2. Plugin traces + correlated logs from event replay
  console.log("\n── Plugin traces + logs (spike-all-events.json) ────────");
  const allEvents = readJson("spike-all-events.json");
  const sorted = allEvents.sort((a, b) => a.sequence - b.sequence);
  let traceNum = 0;
  for (const event of sorted) {
    if (event.eventName === "after_tool_call") {
      handleAfterToolCall(event);
    } else if (event.eventName === "agent_end") {
      const messages = (event.data || event).messages || [];
      const { traceId, spans, logEntries } = buildOtlpPayload(messages);
      traceNum++;
      await send(
        `plugin trace ${traceNum}  (${spans.length} spans, ${logEntries.length} logs)  traceId=${traceId}`,
        "/v1/traces",
        wrapOtlpSpans(spans)
      );
      if (logEntries.length > 0) {
        await send(
          `plugin logs ${traceNum}   (${logEntries.length} entries)`,
          "/v1/logs",
          wrapOtlpLogs(logEntries)
        );
      }
    }
  }

  // 3. Log fixtures
  console.log("\n── OTLP logs (fixtures) ─────────────────────────────────");
  await send("log-openclaw-agent-execution-001.json", "/v1/logs", readJson("log-openclaw-agent-execution-001.json"));

  console.log(`\nDone. ${ok} succeeded, ${fail} failed.`);
}

main().catch(e => { console.error(e); process.exit(1); });

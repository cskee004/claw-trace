// Seeds ClawTrace with all spike data: plugin traces + correlated logs from events + raw OTLP fixtures.
// Usage: node seed.js [--endpoint http://localhost:3000]

import { readFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import http from "http";
import https from "https";
import { toMs, buildOtlpPayload } from "./trace-helpers.js";

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

// ── Event replay ──────────────────────────────────────────────────────────────

const toolBuffer = new Map();

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
      const { traceId, spans, logEntries } = buildOtlpPayload(messages, toolBuffer);
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

# Seeds are idempotent — safe to run multiple times.
# Uses direct model creation (not the OTLP ingest path).
# Derived from scenario shapes in .claude/open-claw-test-files/TEST_CASES.md.
#
# trace_id: exactly 16 hex chars (matches Trace model validation)
# span_type: one of Span::SPAN_TYPES — model_call, message_event, tool_call,
#            session_event, command_event, webhook_event, openclaw_event, span

if Trace.exists?(trace_id: "a1b2c3d4e5f60001")
  puts "Seed data already present — skipping."
  return
end

puts "Seeding ClawTrace with demo data..."

now = Time.current

mk_span = lambda do |trace_id:, agent_id:, span_id:, span_name:, span_type:, base:, offset_ms:, duration_ms:, parent_span_id: nil, metadata: {}|
  t = base + offset_ms * 0.001
  Span.create!(
    trace_id:       trace_id,
    agent_id:       agent_id,
    span_id:        span_id,
    parent_span_id: parent_span_id,
    span_name:      span_name,
    span_type:      span_type,
    timestamp:      t,
    end_time:       t + duration_ms * 0.001,
    metadata:       metadata
  )
end

# ── Trace 1: Summarize Discord mentions (90 min ago, success, 8 spans) ────────

t1_id    = "a1b2c3d4e5f60001"
t1_agent = "openclaw-gateway"
t1_base  = now - 90.minutes

Trace.create!(trace_id: t1_id, agent_id: t1_agent,
              task_name: "Summarize Discord mentions",
              start_time: t1_base, status: :success)

[
  { span_id: "s01-root",    parent_span_id: nil,          span_name: "agent.turn.process",   span_type: "session_event", offset_ms: 0,    duration_ms: 1240, metadata: { "agent.channel" => "discord" } },
  { span_id: "s01-mem",     parent_span_id: "s01-root",   span_name: "memory.search",         span_type: "tool_call",         offset_ms: 5,    duration_ms: 23,   metadata: { "memory.hits" => 3 } },
  { span_id: "s01-llm1",    parent_span_id: "s01-root",   span_name: "llm.inference",         span_type: "model_call",        offset_ms: 35,   duration_ms: 650,  metadata: { "llm.model" => "claude-sonnet-4-6", "llm.thinking" => true,  "llm.tokens.input" => 6144, "llm.tokens.output" => 320 } },
  { span_id: "s01-parse",   parent_span_id: "s01-llm1",   span_name: "llm.tool_call_parse",   span_type: "model_call",    offset_ms: 681,  duration_ms: 4,    metadata: { "llm.tool_calls" => 2 } },
  { span_id: "s01-search",  parent_span_id: "s01-root",   span_name: "tool.exec.web_search",  span_type: "tool_call",         offset_ms: 690,  duration_ms: 205,  metadata: { "tool.name" => "web_search",  "tool.input" => "OpenClaw Discord mentions" } },
  { span_id: "s01-http1",   parent_span_id: "s01-search", span_name: "http.client.request",   span_type: "tool_call",       offset_ms: 692,  duration_ms: 190,  metadata: { "http.method" => "GET", "http.url" => "https://duckduckgo.com/html", "http.status_code" => 200 } },
  { span_id: "s01-llm2",    parent_span_id: "s01-root",   span_name: "llm.inference",         span_type: "model_call",        offset_ms: 900,  duration_ms: 125,  metadata: { "llm.model" => "claude-sonnet-4-6", "llm.thinking" => false, "llm.tokens.input" => 2048, "llm.tokens.output" => 160 } },
  { span_id: "s01-send",    parent_span_id: "s01-root",   span_name: "discord.message.send",  span_type: "tool_call",         offset_ms: 1030, duration_ms: 16,   metadata: { "discord.channel" => "general" } },
].each { |s| mk_span.call(trace_id: t1_id, agent_id: t1_agent, base: t1_base, **s) }

# ── Trace 2: Fetch GitHub issue summary (60 min ago, success, 5 spans) ────────

t2_id    = "a1b2c3d4e5f60002"
t2_agent = "openclaw-gateway"
t2_base  = now - 60.minutes

Trace.create!(trace_id: t2_id, agent_id: t2_agent,
              task_name: "Fetch GitHub issue summary",
              start_time: t2_base, status: :success)

[
  { span_id: "s02-root",  parent_span_id: nil,          span_name: "agent.turn.process",  span_type: "session_event", offset_ms: 0,   duration_ms: 950,  metadata: { "agent.channel" => "discord" } },
  { span_id: "s02-llm1",  parent_span_id: "s02-root",   span_name: "llm.inference",        span_type: "model_call",        offset_ms: 10,  duration_ms: 400,  metadata: { "llm.model" => "claude-sonnet-4-6", "llm.tokens.input" => 3200, "llm.tokens.output" => 80 } },
  { span_id: "s02-fetch", parent_span_id: "s02-root",   span_name: "tool.exec.web_fetch",  span_type: "tool_call",         offset_ms: 415, duration_ms: 280,  metadata: { "tool.name" => "web_fetch", "tool.url" => "https://github.com/openclaw/openclaw/issues" } },
  { span_id: "s02-http",  parent_span_id: "s02-fetch",  span_name: "http.client.request",  span_type: "tool_call",       offset_ms: 418, duration_ms: 265,  metadata: { "http.method" => "GET", "http.url" => "https://github.com/openclaw/openclaw/issues", "http.status_code" => 200 } },
  { span_id: "s02-llm2",  parent_span_id: "s02-root",   span_name: "llm.inference",        span_type: "model_call",        offset_ms: 700, duration_ms: 200,  metadata: { "llm.model" => "claude-sonnet-4-6", "llm.tokens.input" => 4096, "llm.tokens.output" => 240 } },
].each { |s| mk_span.call(trace_id: t2_id, agent_id: t2_agent, base: t2_base, **s) }

# ── Trace 3: Web search — timeout + retry (30 min ago, error, 8 spans) ────────

t3_id    = "a1b2c3d4e5f60003"
t3_agent = "openclaw-gateway"
t3_base  = now - 30.minutes

Trace.create!(trace_id: t3_id, agent_id: t3_agent,
              task_name: "Search for OpenClaw docs",
              start_time: t3_base, status: :error)

[
  { span_id: "s03-root",       parent_span_id: nil,            span_name: "agent.turn.process",   span_type: "session_event", offset_ms: 0,    duration_ms: 3800, metadata: { "agent.channel" => "discord" } },
  { span_id: "s03-llm1",       parent_span_id: "s03-root",     span_name: "llm.inference",         span_type: "model_call",        offset_ms: 10,   duration_ms: 610,  metadata: { "llm.model" => "claude-sonnet-4-6", "llm.tokens.input" => 1800, "llm.tokens.output" => 60 } },
  { span_id: "s03-err",        parent_span_id: "s03-root",     span_name: "tool.exec.web_search",  span_type: "span",             offset_ms: 625,  duration_ms: 1000, metadata: { "tool.name" => "web_search", "tool.attempt" => 1, "error.type" => "TimeoutError" } },
  { span_id: "s03-err-http",   parent_span_id: "s03-err",      span_name: "http.client.request",   span_type: "span",             offset_ms: 627,  duration_ms: 998,  metadata: { "http.method" => "GET", "http.url" => "https://duckduckgo.com/html", "http.status_code" => 0 } },
  { span_id: "s03-retry",      parent_span_id: "s03-root",     span_name: "tool.exec.web_search",  span_type: "tool_call",         offset_ms: 1825, duration_ms: 715,  metadata: { "tool.name" => "web_search", "tool.attempt" => 2, "tool.retry_backoff_ms" => 200 } },
  { span_id: "s03-retry-http", parent_span_id: "s03-retry",    span_name: "http.client.request",   span_type: "tool_call",       offset_ms: 1827, duration_ms: 700,  metadata: { "http.method" => "GET", "http.url" => "https://duckduckgo.com/html", "http.status_code" => 200 } },
  { span_id: "s03-llm2",       parent_span_id: "s03-root",     span_name: "llm.inference",         span_type: "model_call",        offset_ms: 2545, duration_ms: 250,  metadata: { "llm.model" => "claude-sonnet-4-6", "llm.tokens.input" => 2200, "llm.tokens.output" => 95 } },
  { span_id: "s03-send",       parent_span_id: "s03-root",     span_name: "discord.message.send",  span_type: "tool_call",         offset_ms: 2800, duration_ms: 50,   metadata: { "discord.channel" => "general" } },
].each { |s| mk_span.call(trace_id: t3_id, agent_id: t3_agent, base: t3_base, **s) }

# ── Trace 4: Draft weekly report (15 min ago, success, 4 spans) ───────────────

t4_id    = "a1b2c3d4e5f60004"
t4_agent = "openclaw-gateway"
t4_base  = now - 15.minutes

Trace.create!(trace_id: t4_id, agent_id: t4_agent,
              task_name: "Draft weekly report",
              start_time: t4_base, status: :success)

[
  { span_id: "s04-root", parent_span_id: nil,        span_name: "agent.turn.process",  span_type: "session_event", offset_ms: 0,    duration_ms: 2100, metadata: { "agent.channel" => "discord" } },
  { span_id: "s04-mem",  parent_span_id: "s04-root", span_name: "memory.search",        span_type: "tool_call",         offset_ms: 5,    duration_ms: 45,   metadata: { "memory.hits" => 7 } },
  { span_id: "s04-llm",  parent_span_id: "s04-root", span_name: "llm.inference",        span_type: "model_call",        offset_ms: 55,   duration_ms: 1980, metadata: { "llm.model" => "claude-sonnet-4-6", "llm.tokens.input" => 8192, "llm.tokens.output" => 620 } },
  { span_id: "s04-send", parent_span_id: "s04-root", span_name: "discord.message.send", span_type: "tool_call",         offset_ms: 2040, duration_ms: 20,   metadata: { "discord.channel" => "weekly-reports" } },
].each { |s| mk_span.call(trace_id: t4_id, agent_id: t4_agent, base: t4_base, **s) }

# ── Trace 5: CI pipeline check (5 min ago, success, 5 spans) ──────────────────

t5_id    = "a1b2c3d4e5f60005"
t5_agent = "ci-runner"
t5_base  = now - 5.minutes

Trace.create!(trace_id: t5_id, agent_id: t5_agent,
              task_name: "CI pipeline — openclaw/openclaw",
              start_time: t5_base, status: :success)

[
  { span_id: "s05-root",    parent_span_id: nil,           span_name: "pipeline.run",   span_type: "session_event", offset_ms: 0,       duration_ms: 142_000, metadata: { "pipeline.commit" => "a3f9c21", "pipeline.result" => "success" } },
  { span_id: "s05-build",   parent_span_id: "s05-root",    span_name: "stage.build",    span_type: "tool_call",         offset_ms: 11_500,  duration_ms: 49_500,  metadata: { "stage.name" => "build" } },
  { span_id: "s05-test",    parent_span_id: "s05-root",    span_name: "stage.test",     span_type: "tool_call",         offset_ms: 61_000,  duration_ms: 45_800,  metadata: { "stage.name" => "test", "test.passed" => 554 } },
  { span_id: "s05-deploy",  parent_span_id: "s05-root",    span_name: "stage.deploy",   span_type: "tool_call",         offset_ms: 106_800, duration_ms: 33_000,  metadata: { "stage.name" => "deploy" } },
  { span_id: "s05-rollout", parent_span_id: "s05-deploy",  span_name: "deploy.rollout", span_type: "tool_call",         offset_ms: 120_100, duration_ms: 10_000,  metadata: { "deploy.replicas" => 3 } },
].each { |s| mk_span.call(trace_id: t5_id, agent_id: t5_agent, base: t5_base, **s) }

# ── Metrics ───────────────────────────────────────────────────────────────────

[
  { metric_name: "gen_ai.client.token.usage", metric_type: "sum",
    metric_attributes: { "gen_ai.token.type" => "input",  "gen_ai.system" => "anthropic", "gen_ai.request.model" => "claude-sonnet-4-6" },
    data_points: { "value" => 17_584, "start_time" => (now - 90.minutes).iso8601 },
    timestamp: now - 5.minutes },
  { metric_name: "gen_ai.client.token.usage", metric_type: "sum",
    metric_attributes: { "gen_ai.token.type" => "output", "gen_ai.system" => "anthropic", "gen_ai.request.model" => "claude-sonnet-4-6" },
    data_points: { "value" => 1_215, "start_time" => (now - 90.minutes).iso8601 },
    timestamp: now - 5.minutes },
  { metric_name: "agent.turns.total", metric_type: "sum",
    metric_attributes: { "agent.channel" => "discord", "agent.result" => "success" },
    data_points: { "value" => 3, "start_time" => (now - 90.minutes).iso8601 },
    timestamp: now - 5.minutes },
  { metric_name: "tool.errors.total", metric_type: "sum",
    metric_attributes: { "tool" => "web_search", "error_type" => "TimeoutError" },
    data_points: { "value" => 1, "start_time" => (now - 30.minutes).iso8601 },
    timestamp: now - 30.minutes },
  { metric_name: "agent.response.latency", metric_type: "histogram",
    metric_attributes: { "agent.channel" => "discord" },
    data_points: { "count" => 3, "sum" => 5390, "min" => 950, "max" => 2100,
                   "bucket_counts" => [0, 0, 1, 1, 1, 0], "explicit_bounds" => [500, 1000, 1500, 2000, 3000] },
    timestamp: now - 5.minutes },
].each { |attrs| Metric.create!(**attrs) }

# ── Logs (correlated to traces 1 and 3) ──────────────────────────────────────

[
  { trace_id: t1_id, span_id: "s01-root",      severity_text: "INFO", severity_number: 9,
    body: "Agent turn started — channel: discord",
    log_attributes: { "agent.channel" => "discord" },
    timestamp: t1_base + 0.001 },
  { trace_id: t1_id, span_id: "s01-send",      severity_text: "INFO", severity_number: 9,
    body: "Discord message delivered successfully",
    log_attributes: { "discord.channel" => "general", "discord.message_id" => "1234567890" },
    timestamp: t1_base + 1.045 },
  { trace_id: t3_id, span_id: "s03-err",       severity_text: "WARN", severity_number: 13,
    body: "Tool timed out after 1000ms — web_search attempt 1",
    log_attributes: { "tool.name" => "web_search", "tool.attempt" => 1 },
    timestamp: t3_base + 1.625 },
  { trace_id: t3_id, span_id: "s03-retry",     severity_text: "INFO", severity_number: 9,
    body: "Retry attempt 2 starting (backoff: 200ms)",
    log_attributes: { "tool.name" => "web_search", "tool.attempt" => 2 },
    timestamp: t3_base + 1.826 },
  { trace_id: t3_id, span_id: "s03-retry-http", severity_text: "INFO", severity_number: 9,
    body: "Search succeeded on attempt 2 — HTTP 200",
    log_attributes: { "tool.name" => "web_search", "http.status_code" => 200 },
    timestamp: t3_base + 2.527 },
].each { |attrs| Log.create!(**attrs) }

puts "Done. Created #{Trace.count} traces, #{Span.count} spans, #{Metric.count} metrics, #{Log.count} logs."

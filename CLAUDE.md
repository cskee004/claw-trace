# CLAUDE.md

## gstack

For all web browsing, use the `/browse` skill from gstack. Never use `mcp__claude-in-chrome__*` tools.

Available gstack skills: `/office-hours`, `/plan-ceo-review`, `/plan-eng-review`, `/plan-design-review`, `/design-consultation`, `/design-shotgun`, `/design-html`, `/review`, `/ship`, `/land-and-deploy`, `/canary`, `/benchmark`, `/browse`, `/connect-chrome`, `/qa`, `/qa-only`, `/design-review`, `/setup-browser-cookies`, `/setup-deploy`, `/retro`, `/investigate`, `/document-release`, `/codex`, `/cso`, `/autoplan`, `/plan-devex-review`, `/devex-review`, `/careful`, `/freeze`, `/guard`, `/unfreeze`, `/gstack-upgrade`, `/learn`

---

## Commands

```bash
# Setup
bundle install
rails db:create db:migrate

# Run dev server
rails server

# Run all tests
bundle exec rspec

# Run a single test file
bundle exec rspec spec/lib/otlp_normalizer_spec.rb

# Run a single example by line number
bundle exec rspec spec/lib/otlp_normalizer_spec.rb:42

# Lint
bundle exec rubocop
bundle exec brakeman
```

## Publishing the Plugin (@clawtrace-io/clawtails)

1. Bump `version` in `plugin/package.json`
2. Create a GitHub Release tagged `v<version>` (e.g. `v0.2.0`) — must match the package version
3. The `.github/workflows/publish-plugin.yml` workflow fires automatically and publishes to npm

Manual publish (from `plugin/` directory):
```bash
npm publish --access public
```

---

## Reference Documents

- `.claude/resources/AI_ARCHITECTURE.md` — full system architecture, ingestion path design, OTLP span mappings
- `.claude/resources/AI_TASKS.md` — current task list and phase status
- `docs/openclaw-integration.md` — ground truth for what OpenClaw emits: OTLP attributes, span types, metrics reference, example payloads
- `docs/api/otlp.md` — external API contract: endpoints, span type classification rules, token attribute conventions

---

## Frontend Aesthetics

ClawTrace is a developer observability tool. Visual lineage: Linear, 
Vercel dashboard, Honeycomb, Datadog APM. Favor information density 
and clarity over marketing flourish.

Theme: Tokyo Night palette as the canonical reference. Dark by default. 
Define all colors as CSS variables in a single :root block; never 
inline hex values in markup.

Typography: IBM Plex Sans for UI text, JetBrains Mono for all IDs, 
durations, timestamps, and JSON metadata. Load from Google Fonts. 
Never Inter, Roboto, or system-ui. Use weight extremes (300 vs 700) 
not middle values.

Span-type colors are load-bearing semantics, not decoration — they 
must match across the waterfall, the drawer, and any future charts. 
Defined once in the `:root` block in `app/assets/tailwind/application.css`,
referenced everywhere via `var(--color-span-*)`.

Motion: reserved for real-time span append and drawer open/close. 
No page-load animations, no hover flourishes on rows.

Backgrounds: subtle. A single low-contrast gradient or noise texture 
on the app shell, nothing on data-dense panels.

Avoid: white-and-purple gradients, evenly distributed pastels, 
generic card shadows, emoji icons, rounded-3xl on data rows.

---

## Architecture

**Purpose:** ClawTrace is a Rails 8 agent observability platform built for OpenClaw — giving developers full visibility into how their agents think, act, and fail.

**Service layer** lives in `app/lib/` (not `app/services/`):
- `TelemetryIngester` — validates and stores incoming telemetry events into `traces` and `spans`
- `OtlpNormalizer` — translates OTLP/JSON span payloads from OpenClaw into the Trace → Span model
- `MetricsNormalizer` — translates OTLP metrics payloads into arrays of hashes ready for `Metric.create!`
- `LogsNormalizer` — translates OTLP logs payloads into arrays of hashes ready for `Log.insert_all!`
- `TraceDurationCalculator` — calculates execution duration for traces in milliseconds
- `ToolCallAnalyzer` — analyzes tool call frequency and success rates within traces
- `ErrorRateAnalyzer` — detects traces containing error spans and computes error rate
- `MetricChartBuilder` — builds ApexCharts option hashes and stat-strip data from `Metric` records
- `OtlpProtobufDecoder` — pure-Ruby proto3 decoder; `decode_traces` / `decode_metrics` / `decode_logs` return the same structure as OTLP/JSON so normalizers need no changes
- `TracesHelper` — view helper (in `app/helpers/`) owning `span_depth_map` and `span_accent`; parent-chain depth computation and type-aware span metadata for waterfall and inline preview

**Data flows:**
```
# OTLP trace ingestion
OpenClaw → POST /v1/traces → OtlpNormalizer → TelemetryIngester → traces + spans tables

# OTLP metrics ingestion
OpenClaw → POST /v1/metrics → MetricsNormalizer → Metric.insert_all! → metrics table

# OTLP logs ingestion
OpenClaw → POST /v1/logs → LogsNormalizer → Log.insert_all! → logs table
```

**UI:** Hotwire (Turbo + Stimulus). Dashboard panels update via Turbo frames.

**Database:** SQLite3 everywhere. ClawTrace is distributed as a local-first tool — each user runs it on their own machine. There is no hosted/production Postgres path. A hosted option is deferred indefinitely because it would require collecting user telemetry data, which conflicts with the project's privacy posture.

**Tables:** `traces`, `spans`, `metrics`, `logs`.

---

## Current Status

See `.claude/resources/AI_TASKS.md` for the authoritative task list, phase completion status, and what's next. Do not duplicate status here — AI_TASKS.md is the single source of truth.

---

## Target Integration — OpenClaw

The primary target is **OpenClaw** (github.com/openclaw/openclaw).
See `AI_ARCHITECTURE.md` for full span mappings, OTLP attribute format, and ingestion path design.

---

## Gotchas

- OTLP attributes arrive as `[{ key:, value: { stringValue: } }]` — use `attrs_to_hash` pattern to flatten
- `attrs_to_hash` is intentionally copy-pasted into each normalizer — do not extract to a shared module; normalizers must stay independently deployable
- All `spans` table columns use the `span_*` prefix: `span_id`, `span_type`, `span_name`, `parent_span_id`. Never add a column named `name`, `type`, or `id` to `spans` — follow the prefix or the column will need renaming later
- OTLP timestamps are nanosecond strings — convert to ISO8601 before storing
- `cost_usd`, cache tokens, and context fields from OpenClaw are optional — never fail if absent
- OTLP endpoints must return `{}` with HTTP 200 on success — required by the OTLP spec
- `metric_attributes` not `attributes` — ActiveRecord reserves the `attributes` method name
- Metric names contain dots (e.g. `gen_ai.client.token.usage`) — routes need `format: false` and a `/[^\/]+/` constraint
- Rescue blocks in OTLP controllers must force-encode `e.message` to UTF-8 before rendering JSON — binary protobuf input can make `e.message` non-UTF-8, causing `JSON::GeneratorError`: `e.message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")`
- A single OTLP payload can contain multiple `resourceSpans` entries (one per service) and multiple distinct `traceId` values — `OtlpNormalizer` handles both; do not assume one payload = one trace
- SQLite does not support PostgreSQL JSON operators (`->`, `->>`) — avoid raw JSON queries on `metadata` or `log_attributes`; filter in Ruby or use `LIKE` if a SQL query is unavoidable in dev

---

## Ingestion API

### OTLP API
- `POST /v1/traces` — accept OTLP trace payloads from OpenClaw
- `POST /v1/metrics` — accept OTLP metrics payloads from OpenClaw
- `POST /v1/logs` — accept OTLP log payloads from OpenClaw
- All endpoints accept `application/json` and `application/x-protobuf` (proto3)
- No auth required — unauthenticated by OTLP convention
- Returns `{}` with HTTP 200 on success

Services: `OtlpNormalizer` → `TelemetryIngester` (traces); `MetricsNormalizer` → `Metric.insert_all!` (metrics); `LogsNormalizer` → `Log.insert_all!` (logs).

---

## Testing

- Service class specs live in `spec/lib/` — every `app/lib/` class must have one
- OTLP endpoint specs live in `spec/requests/` — covers `OtlpController`, `MetricsController` (OTLP), `LogsController`
- UI controllers (`TracesController`, the metrics UI controller) have no request specs — tested via the browser

---

## AI Collaboration Rules

- Write idiomatic Ruby — small focused methods, clear names, no overly complex abstractions
- Read relevant files before proposing changes
- Make small, incremental changes — one task at a time
- Modify only files relevant to the current task
- Do not rename or delete files unless explicitly instructed
- Place new analysis logic in `app/lib/`, not in controllers
- Request confirmation before any change that touches multiple parts of the system

## Off Limits

- Do not introduce new gems without confirmation
- Do not run `db:drop` or `db:schema:load` — use migrations only
- Do not hardcode API keys or credentials
- Do not modify `OtlpNormalizer` and `TelemetryIngester` in the same task — they have separate responsibilities

## Task Management

Tasks are tracked in `.claude/resources/AI_TASKS.md`. Read that file for current status and what's next.

**Numbering rule — the most important one:**
Backlog items have no task numbers. A task gets a number only when work begins, using the next available integer. Numbers are permanent once assigned — they appear in git commit messages and must never change.

**Starting a task:**
1. Pick the next available number (check the Completed list for the highest used)
2. Write the task spec in AI_TASKS.md under `## 🔄 In Progress`
3. Use `(Task N)` in every commit for that task

**Completing a task:**
1. Run `bundle exec rspec` — 0 failures required before committing
2. If the task adds a user-facing capability, update the README Features section
3. Commit with the task number: `git commit -m "feat: description (Task N)"`
4. Move it to `## ✅ Completed` in AI_TASKS.md — one line, newest first
5. Never update CLAUDE.md status — AI_TASKS.md is the single source of truth

**Adding new work mid-task:**
If something unexpected comes up that is not the current task, add it to the Backlog (no number yet) and finish the current task first. Do not interrupt a task by starting another.

**Commit message format:**
```
type: short description (Task N)
```

---

## Commit & Push Rules

**Always run the full test suite before committing or pushing.** Never commit failing tests.

```bash
bundle exec rspec
```

Only proceed with `git commit` or `git push` if the result is `0 failures`. If tests fail, fix them first.

## Validation Loop

Before considering a task complete, verify:

1. **Architecture fit** — Does new code follow the Trace → Span model? Is logic in `app/lib/` and not in controllers?
2. **Scope** — Were any unrelated files modified? Were any files renamed or deleted without instruction?
3. **Database** — If a migration was added, is it reversible? Do new `spans` columns follow the `span_*` prefix convention?
4. **Tests** — Do new `app/lib/` classes have a corresponding spec in `spec/lib/`? Do modified OTLP controllers have passing request specs?
5. **Conventions** — Do new `spans` columns use the `span_*` prefix? Did any normalizer change introduce a shared helper that should stay duplicated instead?
## Skill routing

When the user's request matches an available skill, ALWAYS invoke it using the Skill
tool as your FIRST action. Do NOT answer directly, do NOT use other tools first.
The skill has specialized workflows that produce better results than ad-hoc answers.

Key routing rules:
- Product ideas, "is this worth building", brainstorming → invoke office-hours
- Bugs, errors, "why is this broken", 500 errors → invoke investigate
- Ship, deploy, push, create PR → invoke ship
- QA, test the site, find bugs → invoke qa
- Code review, check my diff → invoke review
- Update docs after shipping → invoke document-release
- Weekly retro → invoke retro
- Design system, brand → invoke design-consultation
- Visual audit, design polish → invoke design-review
- Architecture review → invoke plan-eng-review

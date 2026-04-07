## Security Log Analyzer & Agent Observability Platform

### Requirements

* Ruby 3.2 or higher
* Rails 8.0 or higher

---

### Description

This project started as a Ruby on Rails application that parses and analyzes Linux system logs (`auth.log`). It extracts key security events, summarizes event patterns by date and hour, and visualizes the data through a dashboard interface.

The project is now evolving into an **Agent Observability Platform** — a control plane for monitoring autonomous AI agents. The existing log analysis features remain in place while new agent telemetry features are being built alongside them.

This project is part of a personal portfolio and demonstrates experience with Ruby, Rails, log analysis, data visualization, OpenTelemetry-inspired design, security-focused software engineering, and AI-assisted development using [Claude Code](https://claude.ai/code).

---

### Project Structure

```
├── app
│   ├── controllers/api/v1   # Telemetry API (auth, keys, telemetry)
│   ├── lib                  # Service layer (LogParser, LogUtility, LogFileAnalyzer, TelemetryIngester)
│   └── ...                  # Rails MVC components
├── config                   # Environment settings
├── db                       # Database setup and schema
├── spec                     # RSpec test files
├── data                     # Test log files
```

---

### Features

#### Security Log Analysis
* Upload and parse `auth.log` system logs
* Detect and classify key event types:
  * Error flags
  * Authentication failures
  * Invalid users
  * Failed password attempts
  * Disconnects
  * Accepted publickey/passwords
  * Session open/closes
  * Sudo usage
* Event grouping by severity (high/medium/ops)
* Hourly and daily time-based summaries
* Top IPs triggering high-severity events
* Graphs powered by ApexCharts
* Modular design (LogParser, LogUtility, LogFileAnalyzer)

#### Agent Observability Platform
* Trace → Span data model inspired by OpenTelemetry
* Canonical span types: `agent_run_started`, `model_call`, `model_response`, `tool_call`, `tool_result`, `decision`, `error`, `run_completed`
* REST API for agent registration and telemetry ingestion (see [API](#api))
* Database-backed `traces` and `spans` tables with referential integrity

---

### Dev Notes

#### Log Analyzer
- Parsing logic lives in `LogParser` and `LogUtility` (`app/lib/`)
- Analysis is performed by `LogFileAnalyzer` (`app/lib/`)
- Controller: `DashboardController`
- Partial views handle AJAX-based updates for summary and graphs

#### Agent Telemetry
- Data model: **Trace** (one complete agent run) → **Spans** (individual steps within a trace)
- Ingestion logic lives in `TelemetryIngester` (`app/lib/`)
- API controllers live in `app/controllers/api/v1/`

---

### Usage

#### Local Setup

```bash
git clone https://github.com/cskee004/log-analyzer.git
cd log-analyzer
bundle install
rails db:create db:migrate
rails server
```

Visit `http://localhost:3000` to use the web interface.

#### Uploading a Log File

1. Navigate to the dashboard homepage
2. Upload a Linux `auth.log` file using the form
   - Test files are located in `/data`
3. View summary statistics and graphs from parsed results

---

### API

All API endpoints are under `/api/v1`. Telemetry submission requires a Bearer token obtained via key registration.

#### Register an API key

```
POST /api/v1/keys
Content-Type: application/json

{ "agent_type": "support-agent" }
```

Response `201 Created`:
```json
{
  "token": "<your-token>",
  "agent_type": "support-agent",
  "message": "Store this token securely — it will not be shown again."
}
```

> The token is returned **once**. Store it immediately.

Valid `agent_type` values: `support-agent`, `research-agent`, `automation-agent`, `triage-agent`, `data-agent`, `monitoring-agent`, `code-agent`, `notification-agent`

---

#### Validate a token

```
POST /api/v1/auth/token
Content-Type: application/json

{ "token": "<your-token>" }
```

Response `200 OK`:
```json
{ "valid": true, "agent_type": "support-agent" }
```

---

#### Submit telemetry

```
POST /api/v1/telemetry
Authorization: Bearer <your-token>
Content-Type: text/plain

{"trace_id":"a1b2c3d4e5f6a7b8","agent_id":"support-agent","task_name":"classify_customer_ticket","start_time":"2026-04-02T12:00:00Z","status":"success"}
{"trace_id":"a1b2c3d4e5f6a7b8","span_id":"s1","parent_span_id":null,"span_type":"agent_run_started","timestamp":"2026-04-02T12:00:01Z","agent_id":"support-agent","metadata":{"task":"classify_customer_ticket"}}
```

The body is **NDJSON** — one JSON object per line. Line 1 is the trace record; subsequent lines are span records. This format matches the output of `AgentSimulator#emit`.

Response `201 Created`:
```json
{ "trace_id": "a1b2c3d4e5f6a7b8", "spans_ingested": 1 }
```

---

### Testing

The project uses **RSpec** for testing.

```bash
bundle exec rspec
```

Test coverage includes:

* Unit tests for parsing, utility, and analysis classes
* Model specs for `Trace`, `Span`, and `ApiKey`
* Request specs for all API endpoints

---

### Dashboard Screenshots

<img src="https://github.com/cskee004/log-analyzer/blob/main/docs/screenshots/upload.jpg" title="Upload" alt="Upload page sample" width="800">

<img src="https://github.com/cskee004/log-analyzer/blob/main/docs/screenshots/summary.jpg" title="Summary Page" alt="Summary page sample" width="800">

<img src="https://github.com/cskee004/log-analyzer/blob/main/docs/screenshots/graphs.jpg" title="Graph page" alt="Graph page sample" width="800">

<img src="https://github.com/cskee004/log-analyzer/blob/main/docs/screenshots/choose-graph.jpg" alt="Choose graph sample" width="800">

---

### Roadmap

#### Log Analyzer
- [x] Parse `auth.log` files
- [x] Event grouping by types and timestamps
- [x] Normalize raw log data into structured formats
- [x] Rails dashboard with ApexCharts visualizations
- [x] Database-backed event storage and analysis

#### Agent Observability Platform
- [x] `traces` and `spans` database tables and models
- [x] Ingestion API with key registration and Bearer token auth
- [ ] Agent observability dashboard (trace viewer, span timeline)

---

### Acknowledgements

* Thank you to the [Elastic team](https://github.com/elastic/examples/tree/master/Machine%20Learning/Security%20Analytics%20Recipes/suspicious_login_activity) for providing the dataset used in this project.

  * Modifications: [test-auth.log](https://github.com/cskee004/log-analyzer/blob/main/data/auth-test.log)

---

### Contributing

Contributing, feedback, and ideas are welcome.

This project is primarily a personal learning tool and showcase, but feel free to fork it, open issues, or suggest improvements.

If you'd like to contribute:
1. Fork the repo
2. Create a new branch
3. Make your changes
4. Open a pull request describing your changes

---

[![Chris Skeens - LinkedIn](https://img.shields.io/badge/Chris_Skeens-LinkedIn-blue)](https://www.linkedin.com/in/christopher-skeens-846780248/)

[![Development](https://img.shields.io/badge/branch-development-red)](https://github.com/cskee004/log-analyzer/tree/development) (Unstable but latest work)

[![Legacy Version](https://img.shields.io/badge/branch-legacy-yellow)](https://github.com/cskee004/log-analyzer/tree/legacy-script-version)

[![ApexCharts.RB - v0.2.0](https://img.shields.io/badge/ApexCharts.RB-v0.2.0-orange)](https://github.com/styd/apexcharts.rb) (Very cool!)

[![Ruby Style Guide](https://img.shields.io/badge/code_style-rubocop-brightgreen.svg)](https://github.com/rubocop/rubocop)

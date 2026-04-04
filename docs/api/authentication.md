# Authentication

ClawTrace uses Bearer token authentication for its ingestion API. Tokens are issued per agent type and are only returned at creation time — store them immediately.

---

## API Key Lifecycle

```
POST /api/v1/keys          → receive token (store it now — never shown again)
    ↓
Authorization: Bearer <token>
POST /api/v1/telemetry     → ingest telemetry
    ↓
POST /api/v1/auth/token    → validate a token at any time
```

---

## Endpoints

### `POST /api/v1/keys`

Registers a new API key. No authentication required.

**Request**

```http
POST /api/v1/keys
Content-Type: application/json

{
  "agent_type": "support-agent"
}
```

**Valid `agent_type` values:**

| Value | Description |
|-------|-------------|
| `support-agent` | Customer support workflows |
| `research-agent` | Research and summarization |
| `automation-agent` | CRM sync, email, report generation |
| `triage-agent` | Incident prioritization and routing |
| `data-agent` | Analytics and forecasting |
| `monitoring-agent` | Health checks and anomaly detection |
| `code-agent` | Code review, test generation, refactoring |
| `notification-agent` | Alerts and stakeholder notifications |

`agent_type` is optional — you may omit it if the key is not tied to a specific agent type.

**Response — 201 Created**

```json
{
  "token": "abc123xyz...",
  "agent_type": "support-agent",
  "message": "API key created"
}
```

**Response — 422 Unprocessable Entity**

```json
{
  "error": "Validation failed: ..."
}
```

---

### `POST /api/v1/auth/token`

Validates a token and returns its associated agent type. No authentication required.

**Request**

```http
POST /api/v1/auth/token
Content-Type: application/json

{
  "token": "abc123xyz..."
}
```

**Response — 200 OK** (token is valid and active)

```json
{
  "valid": true,
  "agent_type": "support-agent"
}
```

**Response — 401 Unauthorized** (token not found or inactive)

```json
{
  "error": "unauthorized"
}
```

---

## Using a Token

Include the token as a Bearer credential in the `Authorization` header for all authenticated endpoints:

```http
Authorization: Bearer abc123xyz...
```

**Authenticated endpoints:** `POST /api/v1/telemetry`

**Unauthenticated endpoints:** `POST /api/v1/keys`, `POST /api/v1/auth/token`

If the token is missing, invalid, or inactive, the server returns `401 Unauthorized`:

```json
{
  "error": "unauthorized"
}
```

---

## Error Responses

All API error responses use the same shape:

```json
{
  "error": "description of what went wrong"
}
```

---

## Notes

- **Tokens are shown once.** The token value is only returned in the `POST /api/v1/keys` response. It cannot be retrieved again — if lost, create a new key.
- **Active flag.** Inactive keys (`active: false`) are rejected at authentication. There is currently no endpoint to deactivate a key — this will be added in a future release.
- **`agent_type` is a label only.** It does not restrict what the key can ingest. Any valid agent telemetry is accepted regardless of the key's `agent_type`.

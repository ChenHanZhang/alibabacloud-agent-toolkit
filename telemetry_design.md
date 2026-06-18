#### Usage

```bash
uvx alibabacloud.mcp-proxy@latest plugin-telemetry \
  --client-name "claude-code" \
  --event-type "mcp_tool_use" \
  --start-timestamp "2026-05-18T10:30:00Z" \
  --tool-name "AlibabaCloud___CallCLI" \
  --session-id "<anonymous-session-id>" \
  --status "success"
```

#### Fields & Sanitization Guidance

| Flag | Required | Purpose | Safe to send as-is? |
|------|:--------:|---------|--------------------|
| `--client-name` | ✅ | Caller identifier (e.g. `claude-code`) | ✅ Yes |
| `--event-type` | ✅ | Event category (e.g. `tool_call`, `skill_invocation`) | ✅ Yes |
| `--start-timestamp` | ✅ | Start time (ISO-8601) | ✅ Yes |
| `--end-timestamp` |   | End time | ✅ Yes |
| `--tool-name` | ✅ | Tool name | ✅ Yes |
| `--session-id` | ✅ | Session id | ⚠️ **Must be anonymized.** Use a caller-generated UUID. |
| `--status` | ✅ | Outcome (`success` / `failure`) | ✅ Yes |
| `--turn` |   | Turn number | ✅ Yes |
| `--mcp-tool` |   | MCP tool identifier | ✅ Yes |
| `--skill-name` |   | Skill name | ✅ Yes |
| `--plugin-name` |   | Plugin name | ✅ Yes |
| `--tool-request-id` |   | Caller-generated UUID | ✅ Yes |
| `--cli-command` |   | CLI command line | ⚠️ **Sanitize**: keep the command shape; strip IDs, credentials, file paths from the arguments. |
| `--query-summary` |   | Query summary | ⚠️ **Sanitize**: keep an intent category, do **not** copy the raw user prompt. |
| `--error-message` |   | Error message | ⚠️ **Sanitize**: keep the error class/code; strip tokens, access keys, IPs, internal hostnames. |

#### Privacy Notice (Customer)

- **Purpose of collection.** Telemetry data is used solely to analyze MCP Proxy usage patterns, error rates, and performance bottlenecks. It is **not** linked to any business resources under your account and is **not** used for commercial purposes.
- **Design principle: necessary action + outcome status only — never sensitive data.** Do not put the following into free-text fields (`--cli-command`, `--query-summary`, `--error-message`, etc.):
  - Alibaba Cloud AccessKey, SecurityToken, Bearer Token, OAuth code
  - Real names / phone numbers / emails / ID numbers of users or RAM sub-accounts
  - Database passwords, private keys, certificate contents, private endpoints
  - Personally Identifiable Information (PII), internal IPs / hostnames
  - Customer data covered by compliance regimes (GDPR, PIPL, HIPAA, ...)
- **Sanitize before calling.** If you're unsure whether a string is safe, run it through a redactor before passing it to the CLI: replace `(?i)ak[a-z0-9]{16,}`, `/Users/[^/]+/`, emails, phone numbers, and UUIDs with placeholders.
- **Opt-out is implicit.** Don't invoke `plugin-telemetry` and no data leaves your machine.

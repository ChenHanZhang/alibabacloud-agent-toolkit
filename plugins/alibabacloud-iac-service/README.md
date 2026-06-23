# alibabacloud-iac-service

Discover, manage, and run Alibaba Cloud **IaC Service** (自动化服务台) Terraform
templates from one shared credential.

This plugin includes:

- Plugin manifests for Codex and Claude Code
- An MCP server named `alibabacloud-iac-service` constrained to IaC Service
- A skill that discovers a user's templates (modules), manages versions, and
  runs them as tasks/jobs with plan-before-apply gating

## Why

Custom IaC MCP servers force users to hand-type URLs (no discovery), authorize
each server separately, and mount one connection per template. This plugin keeps
a single credential and a single MCP connection: templates are *discovered* via
`ListModules`, *authored* via `CreateModule`/`CreateModuleVersion`, and *run*
via `CreateTask`/`CreateJob` — all through one `CallCLI` server.

## Install

```bash
npx openplugin aliyun/alibabacloud-agent-toolkit --plugin alibabacloud-iac-service
```

Target one client: add `--claude`, `--codex`, or `--qoderwork`.

## MCP

Constrained to IaC Service only:

```json
{
  "mcpServers": {
    "alibabacloud-iac-service": {
      "command": "uvx",
      "args": [
        "alibabacloud.mcp-proxy@latest",
        "--safety-policy",
        "iacservice:*=allow,*=deny"
      ]
    }
  }
}
```

## Skills

| Skill | Description |
|-------|-------------|
| `alibabacloud-iac-service` | Discover, version, and run IaC Service Terraform templates |

## Workflow

1. **Discover** — `list-modules` to see your templates, `get-module` to inspect.
2. **Manage** — `create-module` / `create-module-version` to author.
3. **Use** — `create-task` then `create-job` (plan → confirm → apply), polling
   `get-job`. Destroy requires a second confirmation.

Ad-hoc HCL with no saved template belongs to `alibabacloud-spec-ops`. See the
skill reference `references/iacservice-template-api.md` for full API contracts.

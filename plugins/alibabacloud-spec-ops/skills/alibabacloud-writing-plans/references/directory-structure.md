# State Directory Structure

## Overview

All artifacts for a single infrastructure requirement are stored under `.aliyun-ai-ops-spec/{requirement-name}/`.

## Structure

```
.aliyun-ai-ops-spec/
├── {requirement-name}/
│   ├── designs/
│   │   ├── design.md              # Full design specification
│   │   ├── architecture.html      # Optional visual diagram
│   │   ├── terraform/
│   │   │   ├── main.tf            # Provider + resources
│   │   │   ├── variables.tf       # Input variables
│   │   │   ├── outputs.tf         # Output values
│   │   │   ├── data.tf            # Data sources (optional)
│   │   │   └── locals.tf          # Local values (optional)
│   │   └── cli/
│   │       └── commands.sh        # Non-TF CLI operations
│   ├── modules/
│   │   └── {module-name}/
│   │       ├── README.md
│   │       ├── CHANGELOG.md
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       ├── examples/basic/main.tf
│   │       └── module-manifest.json
│   └── tasks/
│       ├── status.json            # Pipeline state tracking
│       ├── validation-report.md   # Validation results
│       ├── tf-plan-result.md      # Terraform plan output
│       └── tf-apply-result.md     # Terraform apply output
├── .telemetry/
│   └── events.jsonl               # Local telemetry log
```

## Naming Convention for Requirements

Use kebab-case derived from the requirement:

- "I need an ECS server" → `ecs-server`
- "Setup a web application with RDS" → `web-app-with-rds`
- "Create VPC network for production" → `production-vpc-network`

## Multiple Requirements

Each requirement gets its own directory. They are independent and can be at different pipeline stages:

```
.aliyun-ai-ops-spec/
├── ecs-web-server/          # status: executed
├── production-database/     # status: validated
└── monitoring-setup/        # status: designing
```

## Status JSON Schema

```json
{
  "name": "requirement-name",
  "status": "pending|designing|designed|writing|plans-written|validating|validated|executing|executed|destroyed|failed",
  "mode": "fast-track|full",
  "change_type": "create|modify",
  "created_at": "2026-05-06T10:00:00Z",
  "updated_at": "2026-05-06T12:00:00Z",
  "phases": {
    "planning": "pending|in_progress|completed|failed",
    "writing": "pending|in_progress|completed|failed",
    "validation": "pending|in_progress|completed|failed",
    "execution": "pending|in_progress|completed|failed"
  },
  "state": {
    "state_id": "state-xxxxx",
    "last_plan_at": "2026-05-06T11:00:00Z",
    "last_apply_at": "2026-05-06T11:05:00Z",
    "last_destroy_at": null
  },
  "module": {
    "name": "opencode-sandbox-ecs",
    "source": "Registry|OSS|Upload|Editor",
    "source_path": "<remote source path if applicable>",
    "module_id": "mod-xxxxx",
    "module_version": "v0.1.0",
    "task_id": "task-xxxxx",
    "job_id": "job-xxxxx",
    "last_job_status": "ConfigProactiveSuccess|Applied|Errored",
    "last_updated_at": "2026-05-06T11:10:00Z"
  },
  "history": [
    {
      "phase": "planning",
      "status": "completed",
      "timestamp": "2026-05-06T10:30:00Z",
      "details": "Design approved by user"
    }
  ],
  "errors": []
}
```

### Field semantics

| Field | Owned by | Notes |
| --- | --- | --- |
| `status` | all skills | Pipeline stage; transitions are linear in Day-1, may loop in Day-2 |
| `mode` | `alibabacloud-planning` | `fast-track` vs `full` (governs validate depth) |
| `change_type` | `alibabacloud-planning` | `create` (Day-1) or `modify` (Day-2 iteration on existing infra) |
| `state.state_id` | `alibabacloud-executing-plans` | IaC Service remote state handle. **MUST be persisted on every plan response** and reused on every subsequent plan/apply/destroy call. See [`executing-plans/references/iac-service-api.md` → State Persistence](../../alibabacloud-executing-plans/references/iac-service-api.md). |
| `state.last_plan_at` / `last_apply_at` / `last_destroy_at` | `alibabacloud-executing-plans` | ISO timestamps of the most recent successful operation in each category |
| `module.name` / `module.source` / `module.source_path` | `alibabacloud-module-lifecycle` | Promoted reusable Module identity and IaCService source metadata |
| `module.module_id` / `module.module_version` | `alibabacloud-module-lifecycle` | IaCService Module record and pinned version for reuse |
| `module.task_id` / `module.job_id` / `module.last_job_status` | `alibabacloud-module-lifecycle` | Most recent reusable-template task/job execution state |

> **Do not delete `state.state_id`** across re-iterations. Losing it
> orphans the remote Terraform state and forces a Day-1 deploy that may
> duplicate already-provisioned resources.

`state.state_id` and `module.*` are intentionally separate. The former is for
ad hoc POC execution via `execute-terraform-plan/apply/destroy`; the latter is
for reusable IaCService `modules -> tasks -> jobs`. Do not migrate one into the
other without an explicit promotion workflow.

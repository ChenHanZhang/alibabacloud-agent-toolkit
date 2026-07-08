# RunIaC Execution API Reference

## Overview

`alibabacloud-executing-plans` runs Terraform plan/apply/destroy through MCP
Server Core RunIaC:

- Submit operations with `alibabacloud-spec-ops.AlibabaCloud___RunIaC`
- Poll operations with `alibabacloud-spec-ops.AlibabaCloud___GetTask`

Do **not** run local Terraform, do **not** shell out to `aliyun`, and do
**not** use `AlibabaCloud___CallCLI` for Terraform plan/apply/destroy.

## Tool Names

| Purpose | Tool |
| --- | --- |
| Submit Terraform operation | `AlibabaCloud___RunIaC` |
| Poll RunIaC process | `AlibabaCloud___GetTask` |
| Query cloud inventory during troubleshooting | `AlibabaCloud___CallCLI` |

Codex-qualified RunIaC tool name:

```text
mcp__plugin_alibabacloud-spec-ops_alibabacloud-spec-ops__AlibabaCloud___RunIaC
```

Codex-qualified GetTask tool name:

```text
mcp__plugin_alibabacloud-spec-ops_alibabacloud-spec-ops__AlibabaCloud___GetTask
```

## Authentication

RunIaC uses the caller's MCP Core identity/OAuth-bound credentials. The plugin
must never read, print, ask for, or place AK/SK values in Terraform HCL.

## HCL Contract

RunIaC accepts Terraform HCL as inline `code` for plan. The HCL must:

- include an explicit provider block:

  ```hcl
  provider "alicloud" {
    region = var.region
  }
  ```

- avoid credentials in provider blocks
- avoid `terraform { required_providers { ... } }`
- use only Alibaba Cloud provider resources

For large payloads, use `presignToken` only when the active MCP server exposes
the upload helper. Otherwise keep generated Terraform compact enough to pass
inline as `code`.

## RunIaC Request Shape

| Field | Required | Notes |
| --- | --- | --- |
| `action` | optional | `plan` (default), `apply`, or `destroy` |
| `code` | plan only | Full Terraform HCL, mutually exclusive with `presignToken` |
| `presignToken` | plan only | Upload token for large bundles when available |
| `previousProcessId` | Day-2 plan, apply, destroy | `processID` returned by a prior RunIaC call |

## Operations

### Plan

First deployment:

```text
AlibabaCloud___RunIaC:
  action: "plan"
  code: "{HCL_CONTENT}"
```

Day-2 re-plan on an existing deployment:

```text
AlibabaCloud___RunIaC:
  action: "plan"
  code: "{HCL_CONTENT}"
  previousProcessId: "{LAST_PROCESS_ID}"
```

Expected response includes:

```json
{
  "processID": "iac_xxx",
  "status": "Planning|Planned|ApprovalPending|Failed",
  "nextAction": "CallGetTask|Stop|InspectError",
  "result": {}
}
```

Persist `processID` as both `state.last_process_id` and
`state.last_plan_process_id` immediately after the response.

### Apply

Apply always binds to a completed plan process. Do not pass code.

```text
AlibabaCloud___RunIaC:
  action: "apply"
  previousProcessId: "{LAST_PLAN_PROCESS_ID}"
```

Persist the returned `processID` as `state.last_process_id` and
`state.last_apply_process_id`.

### Destroy

Destroy binds to the latest RunIaC process that owns deployment state. Do not
pass code. Destroy must be gated by exact project-name confirmation before this
call.

```text
AlibabaCloud___RunIaC:
  action: "destroy"
  previousProcessId: "{LAST_PROCESS_ID}"
```

Persist the returned `processID` as `state.last_process_id` and
`state.last_destroy_process_id`.

### Poll

RunIaC is asynchronous. Poll every submitted process with GetTask:

```text
AlibabaCloud___GetTask:
  processID: "{PROCESS_ID}"
  waitTimeoutSeconds: 30
  pollIntervalSeconds: 5
```

Response handling:

| Status / nextAction | Action |
| --- | --- |
| `CallGetTask` / `CallGetTaskAgain` | Poll the same `processID` again |
| `Planned` + `Stop` | Plan complete; show diff and proceed according to skill rules |
| `ApprovalPending` | Ask user to complete approval out of band; keep polling same process |
| `None` | Terminal success |
| `InspectError` / `Failed` | Inspect `error` and stop or recover |
| rejection/expiry/validation failure + `Stop` | Terminal stop; do not retry blindly |

## State Persistence

The executing-plans skill owns the `state` object in
`.aliyun-ai-ops-spec/{name}/tasks/status.json`:

```json
{
  "state": {
    "last_process_id": "iac_xxx",
    "last_plan_process_id": "iac_plan_xxx",
    "last_apply_process_id": "iac_apply_xxx",
    "last_destroy_process_id": null,
    "last_plan_at": "2026-05-06T11:00:00Z",
    "last_apply_at": "2026-05-06T11:05:00Z",
    "last_destroy_at": null
  }
}
```

### Lifecycle

| Trigger | status.json field | Action |
| --- | --- | --- |
| Plan response received | `last_process_id`, `last_plan_process_id`, `last_plan_at` | Write before polling/showing output |
| Apply response received | `last_process_id`, `last_apply_process_id`, `last_apply_at` | Continue polling same process |
| Plan fails | unchanged, except record failed plan process if returned | Keep previous successful process IDs |
| Destroy succeeds | `last_process_id`, `last_destroy_process_id`, `last_destroy_at`, top-level `status: "destroyed"` | Keep process IDs as historical record |

### Day-1 vs Day-2

| Scenario | Prior state | Plan request |
| --- | --- | --- |
| Day-1 | no `last_process_id` | `action=plan`, `code` |
| Day-2 | `last_process_id` present | `action=plan`, `code`, `previousProcessId=last_process_id` |

### Legacy Migration

Old versions of spec-ops stored IaCService `state.state_id` from
`execute-terraform-plan/apply/destroy`. That value is not a RunIaC
`processID`. If a project has `state.state_id` but no RunIaC process fields,
stop and ask whether to start a fresh RunIaC Day-1 deployment or let the user
provide a known RunIaC `processID`.

## Deprecated IaCService CLI Calls

The following calls are deprecated for `alibabacloud-executing-plans` and must
not be emitted by this skill:

| Deprecated | Replacement |
| --- | --- |
| `aliyun iacservice execute-terraform-plan` | `AlibabaCloud___RunIaC` with `action=plan` |
| `aliyun iacservice execute-terraform-apply` | `AlibabaCloud___RunIaC` with `action=apply` |
| `aliyun iacservice execute-terraform-destroy` | `AlibabaCloud___RunIaC` with `action=destroy` |
| `aliyun iacservice get-execute-state` | `AlibabaCloud___GetTask` |

`AlibabaCloud___CallCLI` remains valid for non-Terraform-execution tasks such
as live availability queries, RAM diagnosis, and IaCService Module lifecycle
operations.

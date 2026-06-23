# Alibaba Cloud IaC Service Template API Reference

The IaC Service product (`IaCService`, version `2021-08-06`) is the **自动化服务台**.
It manages reusable Terraform **modules** (templates), turns them into **tasks**,
and runs each task as a **job**. State is held server-side; everything is
asynchronous — submit, then poll.

**ALL commands run through MCP tool `AlibabaCloud___CallCLI`** — never Bash.
Fully qualified name:
`mcp__plugin_alibabacloud-iac-templates_alibabacloud-iac-templates__AlibabaCloud___CallCLI`.

## Authentication & shared credential

One Alibaba Cloud credential (the host `aliyun configure` profile) is reused for
every operation. No per-server OAuth, no per-template token. RAM permissions
needed:

- `iacservice:ListModules`, `iacservice:GetModule`, `iacservice:CreateModule`,
  `iacservice:CreateModuleVersion`
- `iacservice:CreateTask`, `iacservice:CreateJob`, `iacservice:GetJob`,
  `iacservice:GetExecuteState`

## CLI verb form

The `aliyun` CLI accepts the canonical API name directly:
`aliyun iacservice ListModules ...`. The kebab aliases below mirror the proven
style already used by `alibabacloud-spec-ops` (`execute-terraform-plan`,
`get-execute-state`). If a verb is rejected, fall back to the PascalCase API
name in parentheses. Verify against your proxy/CLI version on first call.

## Lifecycle

```
ListModules ──▶ GetModule ─▶ CreateTask ─▶ CreateJob(plan) ─▶ GetJob/GetExecuteState
   (discover)   (inspect)   (bind ver)    (preview)            (poll)
CreateModule / CreateModuleVersion = author / version a template
CreateJob(apply|destroy) = run / tear down
```

## Discover

### list-modules (ListModules)

Enumerate the caller's templates. The discovery entry point — P1.

| Param | Required | Notes |
| --- | --- | --- |
| `--max-results` | no | page size |
| `--next-token` | no | pagination cursor from prior response |
| `--keyword` | no | filter by name |

Response: `Modules[]{ModuleId, Name, Description, Source, LatestVersion}` + `NextToken`.

### get-module (GetModule)

| Param | Required | Notes |
| --- | --- | --- |
| `--module-id` | yes | from list-modules |

Response: full module incl. source, latest version, attributes.

## Manage

### create-module (CreateModule)

| Param | Required | Notes |
| --- | --- | --- |
| `--client-token` | yes | fresh UUID `[0-9a-zA-Z-]{1,64}` |
| `--name` | yes | 2-128 chars |
| `--source` | yes | `OSS` / `Registry` / `ExportTask` / `Editor` / `Upload` |
| `--source-path` | cond | location for OSS/Registry sources |
| `--description` | no | |

### create-module-version (CreateModuleVersion)

| Param | Required | Notes |
| --- | --- | --- |
| `--module-id` | yes | target template |
| `--client-token` | yes | fresh UUID |
| `--name` | yes | version label |
| `--description` | no | |

## Use

### create-task (CreateTask)

Bind a module version to runnable parameters.

| Param | Required | Notes |
| --- | --- | --- |
| `--client-token` | yes | fresh UUID |
| `--name` | yes | 2-128 chars |
| `--module-id` | yes | template to run |
| `--module-version` | yes | version to pin |
| `--auto-apply` | no | bool; apply after preview without a stop |
| `--trigger-strategy` | no | `Manual` / `NewVersion` / `Auto` / `ParameterSetUpdated` |

Response: `TaskId`.

### create-job (CreateJob)

| Param | Required | Notes |
| --- | --- | --- |
| `--task-id` | yes | from create-task |
| `--client-token` | yes | fresh UUID |
| `--description` | yes | what this run does |
| `--sub-command` | no | only `destroy` (and `refresh`). **`plan` is NOT valid** — a default job already plans then waits for approval. Omit for a normal plan→apply run |

Response: `JobId`. With `autoApply=false`, the job plans and halts at
`ConfigProactiveSuccess` (apply) / `Planned` (destroy) until approved via
operate-job. **Verified live (tested CLI rejects `--sub-command plan`).**

### operate-job (OperateJob) — approve/reject the apply gate

| Param | Required | Notes |
| --- | --- | --- |
| `--task-id` | yes | |
| `--job-id` | yes | the held job |
| `--operation-type` | yes | `execute` (approve/apply) / `abolish` / `cancel` — **not** Confirm/Apply |
| `--comment` | no | audit note |

`execute` advances Confirmed → Applying → Applied. Verified live.

### get-job (GetJob) — poll

| Param | Required | Notes |
| --- | --- | --- |
| `--task-id` | yes | |
| `--job-id` | yes | |
| `--task-type` | no | `Task` / `SceneTestingTask` / `Stack` |

### get-execute-state (GetExecuteState) — poll raw terraform

| Param | Required | Notes |
| --- | --- | --- |
| `--state-id` | yes | from a job / plan |

Status: `Pending` / `Planning` / `Applied` / `Errored` …

## Polling

1. Initial wait ~5 s. 2. Poll every 10 s. 3. Max ~60 attempts. Each poll is a
separate CallCLI call — no Bash loops. On timeout, report "still running" with
the JobId/StateId.

## Constraints

- CallCLI runs remotely: no `file://`, no `$()`, no pipes, no local paths.
- No `--region` on iacservice verbs — region comes from the module's provider block.
- Write ops are idempotent on `--client-token`; reuse the same token only for retry.
- Direct one-shot execution (`execute-terraform-plan/apply/destroy`) is covered
  by `alibabacloud-spec-ops`; use it for ad-hoc HCL, this skill for sustained
  templates.

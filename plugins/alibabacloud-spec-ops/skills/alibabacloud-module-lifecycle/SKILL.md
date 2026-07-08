---
name: alibabacloud-module-lifecycle
description: >
  Manage the reusable Module lifecycle inside Alibaba Cloud spec-ops: promote a
  validated POC Terraform project into a versioned Module, publish and run
  IaCService modules as tasks/jobs, and maintain module versions over time.
  Triggers: promote POC to module, publish module, reuse module, run template,
  manage IaCService modules, 模板复用, Module 沉淀, 持续维护。
triggers: >
  promote POC, module lifecycle, publish module, module version, reusable
  Terraform module, IaCService template, CreateModule, CreateModuleVersion,
  CreateTask, CreateJob, 发现模板, 发布模板, 运行模板, 维护模板
license: MIT
metadata:
  author: Alibaba Cloud
  version: "0.1.0"
  domain: spec-ops
allowed-tools: "mcp__plugin_alibabacloud-spec-ops_alibabacloud-spec-ops__AlibabaCloud___CallCLI,mcp__plugin_alibabacloud-spec-ops_alibabacloud-spec-ops__AlibabaCloud___GetApiDefinition,mcp__plugin_alibabacloud-spec-ops_alibabacloud-spec-ops__AlibabaCloud___SearchDocument"
---

# Alibaba Cloud Module Lifecycle

This skill extends `alibabacloud-spec-ops` beyond one-off POC execution. It
handles the standard path:

```text
POC validation -> Module promotion -> IaCService publication -> Scenario reuse -> Maintenance
```

Use it when the user wants to turn a validated Terraform result into a reusable
Module, publish a Module version, discover or run an existing template, or
maintain a Module over time.

## Execution Lanes

`spec-ops` has two IaC execution lanes. Keep them separate:

| Lane | Skill | Execution API shape | State stored in `status.json` |
| --- | --- | --- | --- |
| POC / ad hoc HCL | `alibabacloud-executing-plans` | MCP Server Core `AlibabaCloud___RunIaC` (`plan`/`apply`/`destroy`) | `state.last_process_id`, `state.last_plan_process_id`, `state.last_apply_process_id` |
| Reusable Module | `alibabacloud-module-lifecycle` | `modules -> tasks -> jobs` | `module.module_id`, `module.module_version`, `module.task_id`, `module.job_id` |

Do not silently convert a POC state into a template task. Promotion is an
explicit workflow with review, versioning, and a new IaCService Module record.

## Hard Rules

1. **MCP only** — all `aliyun iacservice ...` commands MUST use
   `AlibabaCloud___CallCLI`; never run `aliyun` through Bash.
2. **No local path to CallCLI** — CallCLI runs remotely and cannot read local
   files, `file://`, shell substitutions, pipes, or environment variables.
3. **No plaintext secrets** — never store AK/SK/API keys in Module code,
   README examples, task parameters, or `module-manifest.json`. Use secret names,
   RAM roles, KMS, or runtime helpers.
4. **Version before reuse** — reusable scenarios must pin a Module version.
   Avoid relying on "latest" for task creation unless the user explicitly asks.
5. **Plan before apply** — template jobs must reach the planned pause state,
   show the plan result, and get explicit user approval before `operate-job`.
6. **Destroy requires double confirmation** — require the user to type the
   project or task name before executing a destroy job.

## Artifact Layout

When promoting a POC project, create Module artifacts under the same project:

```text
.aliyun-ai-ops-spec/{name}/
├── designs/
│   ├── design.md
│   └── terraform/
│       └── main.tf
├── modules/
│   └── {module-name}/
│       ├── README.md
│       ├── CHANGELOG.md
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── examples/
│       │   └── basic/
│       │       └── main.tf
│       └── module-manifest.json
└── tasks/
    └── status.json
```

Update `tasks/status.json` with a separate `module` object:

```json
{
  "module": {
    "name": "opencode-sandbox-ecs",
    "source": "Registry|OSS|Upload|Editor",
    "source_path": "<remote source path if applicable>",
    "module_id": "mod-xxxx",
    "module_version": "v0.1.0",
    "task_id": "task-xxxx",
    "job_id": "job-xxxx",
    "last_job_status": "ConfigProactiveSuccess|Applied|Errored",
    "last_updated_at": "2026-07-08T00:00:00Z"
  }
}
```

Keep existing `state.*` RunIaC process fields untouched. They belong to ad hoc
POC execution.

## Workflow A: Discover Existing Modules

Use this when the user asks to list or run an existing template.

1. Preflight credentials:
   - Call `aliyun configure list` through `AlibabaCloud___CallCLI`.
   - Do not print AK/SK even if the CLI returns them.
2. List modules:
   - `aliyun iacservice list-modules`
   - If pagination returns `NextToken`, continue with `--next-token`.
3. Present a compact table:
   - `ModuleId`
   - `Name`
   - `LatestVersion`
   - `Source`
   - `Description`
4. For a selected module, call:
   - `aliyun iacservice get-module --module-id <ModuleId>`
5. Recommend pinning an explicit version before task creation.

## Workflow B: Promote A POC To A Module

Use this when the user says a POC has been validated and should become a
standard reusable module.

1. Read local project context:
   - `.aliyun-ai-ops-spec/{name}/designs/design.md`
   - `.aliyun-ai-ops-spec/{name}/designs/terraform/*.tf`
   - `.aliyun-ai-ops-spec/{name}/tasks/tf-apply-result.md` if present
   - `.aliyun-ai-ops-spec/{name}/tasks/status.json`
2. Confirm the POC validation state:
   - If `status` is not `executed`, tell the user it has not been cloud-verified.
   - If the user still wants to promote, mark the Module as `experimental`.
3. Extract the stable Module interface:
   - Inputs that vary per reuse become variables.
   - Outputs needed by consumers become outputs.
   - Runtime secrets remain referenced by name or role, never by value.
4. Create Module files in `modules/{module-name}/`.
5. Create `module-manifest.json` with:
   - name, version, owner, source type, source path
   - required RAM permissions
   - required external prerequisites
   - secret handling model
   - verification commands
   - known failure cases
6. Run code quality checks locally where available, then validate remotely with
   `aliyun iacservice validate-module --source Upload --code '<HCL_CONTENT>'`
   if the Module body can be represented as a supported upload payload.
7. Do not publish until the user approves the Module interface and version.

## Workflow C: Publish Or Version A Module

Use this after the Module artifacts are approved.

1. Ensure the Module source is reachable by IaCService:
   - Registry/OSS source must have a remote `source_path`.
   - Local filesystem paths are invalid for CallCLI.
   - Upload/Editor payloads must be verified against the current CLI behavior.
2. If this is a new Module:
   - `aliyun iacservice create-module --client-token <uuid> --name <name> --source <source> ...`
3. If this is a new version:
   - `aliyun iacservice create-module-version --module-id <id> --client-token <uuid> --name <version> --description "<summary>"`
4. Record `module_id` and `module_version` in `tasks/status.json`.
5. Update `CHANGELOG.md` and `module-manifest.json` with the published version.

## Workflow D: Run A Reusable Module

Use this for scenario reuse once a Module version exists.

1. Resolve Module and version:
   - Use `list-modules` / `get-module`.
   - Refuse ambiguous version selection unless the user explicitly chooses latest.
2. Create a task:
   - `aliyun iacservice create-task --client-token <uuid> --name <task-name> --module-id <id> --module-version <version>`
3. Create a job for plan:
   - `aliyun iacservice create-job --task-id <TaskId> --client-token <uuid> --description "plan <summary>"`
   - Do not pass `--sub-command plan`; the CLI rejects it.
4. Poll:
   - `aliyun iacservice get-job --task-id <TaskId> --job-id <JobId>`
   - Stop at `ConfigProactiveSuccess` or `Planned`.
5. Show plan result:
   - Read `statusDetail.Planned.jobResult` and `outputJsonPlan` when present.
   - Summarize add/change/destroy counts and key resources.
6. Apply only after explicit user confirmation:
   - `aliyun iacservice operate-job --task-id <TaskId> --job-id <JobId> --operation-type execute`
7. Poll to `Applied` or terminal failure.
8. Record task/job IDs and result in `tasks/status.json` and a task result file.

## Workflow E: Maintain A Module

Use this when the user wants to update a reusable scenario.

1. Load the previous Module manifest, README, CHANGELOG, and published version.
2. Classify the change:
   - Patch: docs, examples, defaults, non-breaking outputs.
   - Minor: new optional variables or outputs.
   - Major: removed/renamed variables, changed defaults with resource impact, or incompatible outputs.
3. Compare the old and new interfaces:
   - variable names, types, defaults, sensitive flags
   - output names and meanings
   - required external prerequisites
4. Update Module code and docs first.
5. Publish a new Module version only after validation passes.
6. Existing tasks are not upgraded silently. Ask the user which tasks should move
   to the new version.

## Failure Handling

| Symptom | Likely cause | Action |
| --- | --- | --- |
| `AccessDenied` / `NoPermission` | Missing IaCService or product RAM action | Hand off to `alibabacloud-ram-permission-diagnose` with the exact API/action |
| CLI rejects `--sub-command plan` | `plan` is not a valid sub-command | Omit `--sub-command`; default job performs plan |
| CallCLI cannot find local file | Remote MCP execution cannot read local paths | Publish to Registry/OSS or use verified Upload/Editor payload |
| Task creates unexpected resources | Wrong version or parameters | Stop before apply, record plan output, ask user to choose a pinned version |
| Secret appears in generated files | Promotion leaked runtime secret | Stop, remove secret, rotate if it left the local machine, use KMS/role indirection |

## Required Reference

Before constructing any `aliyun iacservice` command for modules/tasks/jobs, read
`references/iacservice-template-api.md` for the current command contract and
known CLI quirks.

---
name: alibabacloud-iac-templates
description: >
  Discover, manage, and run Alibaba Cloud IaC Service (自动化服务台) Terraform
  templates through one shared credential. Use to list a user's existing
  templates (modules), inspect them, author new template versions, and run a
  template as a task/job with plan-before-apply gating. WHEN: list IaC
  templates, run my template, deploy a module, manage IaC Service modules,
  发现/管理/运行模板, 模板管理. All execution goes through the CallCLI MCP tool
  against `aliyun iacservice`; HCL execution of ad-hoc code belongs to
  alibabacloud-spec-ops instead.
triggers: >
  IaC templates, 模板, IaC Service, 自动化服务台, list modules, ListModules,
  run template, 运行模板, deploy module, manage templates, 模板管理,
  create module, module version, 模板版本, terraform task, terraform job,
  CreateTask, CreateJob, 发现模板, mount templates
license: Apache-2.0
metadata:
  domain: iac-service
  owner: sdk-team
  contact: sdk-team@alibabacloud.com
allowed-tools: "mcp__plugin_alibabacloud-iac-templates_alibabacloud-iac-templates__AlibabaCloud___CallCLI,mcp__plugin_alibabacloud-iac-templates_alibabacloud-iac-templates__AlibabaCloud___GetApiDefinition,mcp__plugin_alibabacloud-iac-templates_alibabacloud-iac-templates__AlibabaCloud___SearchDocument"
---

# Alibaba Cloud IaC Service Templates

Discover and run reusable Terraform **templates** (IaC Service *modules*) under a
single Alibaba Cloud credential — no per-template OAuth, no hand-typed server
URLs. This solves the three template pains: discovery (list, don't hunt for
URLs), auth (one credential, all templates), and a single connection (CallCLI,
no N MCP mounts).

> All IaC Service operations MUST go through MCP tool `AlibabaCloud___CallCLI`
> running `aliyun iacservice ...`. Never run `aliyun` in Bash. Full op contracts:
> `references/iacservice-template-api.md`.

## When to use

- "List / show my IaC templates" → discover (ListModules).
- "Run / deploy template X" → use (CreateTask → CreateJob → poll).
- "Publish a new version of template X" → manage (CreateModuleVersion).
- Ad-hoc HCL with no saved template → use **alibabacloud-spec-ops** instead.

## 1. Discover

1. List templates: `aliyun iacservice list-modules` (paginate `--next-token`).
2. Present a table: ModuleId · Name · LatestVersion · Description.
3. Inspect a pick: `aliyun iacservice get-module --module-id <id>`.

## 2. Manage (optional)

- New template: `create-module --client-token <uuid> --name <n> --source <src>`.
- New version: `create-module-version --module-id <id> --client-token <uuid> --name <ver>`.

Generate a fresh UUID per write op; reuse a token only to retry the same call.

## 3. Use (run a template)

1. **Task**: `create-task --client-token <uuid> --name <n> --module-id <id> --module-version <v>` → `TaskId`.
2. **Plan**: `create-job --task-id <TaskId> --client-token <uuid> --description "plan" --sub-command plan` → `JobId`.
3. **Poll**: `get-job --task-id <TaskId> --job-id <JobId>` every ~10 s until terminal; surface the plan.
4. **Gate**: show the plan, get explicit user confirmation. Never apply silently.
5. **Apply**: `create-job --task-id <TaskId> --client-token <uuid> --description "apply"` (omit `--sub-command`).
6. **Destroy** (double-confirm): `create-job ... --sub-command destroy`.

## Safety gates

- Plan before apply; show output; require explicit "yes" before apply.
- Destroy requires a second confirmation. These mirror spec-ops conventions.
- Never echo AK/SK. Pre-check only with `aliyun configure list`.
- On `AccessDenied`, hand off to `alibabacloud-ram-permission-diagnose`.

## Constraints

CallCLI is remote: no `file://`, `$()`, pipes, or local paths. No `--region` on
iacservice verbs (region comes from the module). See the reference for the full
parameter tables and polling strategy.

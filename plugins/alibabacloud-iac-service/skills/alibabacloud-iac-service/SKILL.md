---
name: alibabacloud-iac-service
description: >
  通过统一凭证发现、管理和运行阿里云 IaC Service（自动化服务台）Terraform 模板。
  用于列出用户已有模板（modules）、查看详情、发布新版本、以及将模板作为 task/job
  运行（含 plan-before-apply 门禁）。触发场景：list IaC templates, run my template,
  deploy a module, manage IaC Service modules, 发现/管理/运行模板, 模板管理。
  所有执行通过 MCP 工具 CallCLI 调用 `aliyun iacservice`；临时 HCL 执行属于
  alibabacloud-spec-ops。
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
allowed-tools: "mcp__plugin_alibabacloud-iac-service_alibabacloud-iac-service__AlibabaCloud___CallCLI,mcp__plugin_alibabacloud-iac-service_alibabacloud-iac-service__AlibabaCloud___GetApiDefinition,mcp__plugin_alibabacloud-iac-service_alibabacloud-iac-service__AlibabaCloud___SearchDocument"
---

# 阿里云 IaC Service 模板管理

通过单一阿里云凭证发现并运行可复用的 Terraform **模板**（IaC Service *modules*）——
无需为每个模板单独 OAuth、无需手动输入服务器 URL。本技能解决模板使用的三大痛点：
发现（通过 ListModules 列出，而非到处找 URL）、认证（一份凭证覆盖所有模板）、
连接（单个 CallCLI 连接，无需挂载 N 个 MCP server）。

> 所有 IaC Service 操作必须通过 MCP 工具 `AlibabaCloud___CallCLI` 执行
> `aliyun iacservice ...`，禁止在 Bash 中直接运行 `aliyun`。完整接口契约见：
> `references/iacservice-template-api.md`。

## 适用场景

- "列出我的 IaC 模板" → 发现（ListModules）。
- "运行/部署模板 X" → 使用（CreateTask → CreateJob → 轮询）。
- "发布模板 X 的新版本" → 管理（CreateModuleVersion）。
- 临时 HCL 代码、无已保存模板 → 使用 **alibabacloud-spec-ops**。

## 1. 发现

1. 列出模板：`aliyun iacservice list-modules`（通过 `--next-token` 翻页）。
2. 以表格展示：ModuleId · Name · LatestVersion · Description。
3. 查看详情：`aliyun iacservice get-module --module-id <id>`。

## 2. 管理（可选）

- 新建模板：`create-module --client-token <uuid> --name <n> --source <src>`。
- 新增版本：`create-module-version --module-id <id> --client-token <uuid> --name <ver>`。

每次写操作生成新的 UUID；仅在重试同一调用时复用 token。

## 3. 使用（运行模板）

1. **创建任务**：`create-task --client-token <uuid> --name <n> --module-id <id> --module-version <v>` → 得到 `TaskId`。
2. **Plan 预览**：`create-job --task-id <TaskId> --client-token <uuid> --description "plan"`（不传 `--sub-command`；默认 job 会自动 plan 后等待审批）→ 得到 `JobId`。
3. **轮询**：`get-job --task-id <TaskId> --job-id <JobId>` 每 ~10 秒轮询直到状态为 `ConfigProactiveSuccess`；读取 `statusDetail.Planned.jobResult` + `outputJsonPlan`。
4. **门禁**：展示 plan 结果（"N to add/change/destroy"），获取用户明确确认。禁止静默 apply。
5. **Apply 执行**：`operate-job --task-id <TaskId> --job-id <JobId> --operation-type execute` → Confirmed → Applied。
6. **Destroy 销毁**（需二次确认）：`create-job ... --sub-command destroy` → 轮询至 `Planned` → `operate-job ... --operation-type execute`。清理：`delete-task`。

## 安全门禁

- 先 plan 再 apply；展示输出；apply 前必须获得用户明确的"确认"。
- Destroy 需要二次确认，与 spec-ops 约定一致。
- 禁止回显 AK/SK。仅通过 `aliyun configure list` 做预检。
- 遇到 `AccessDenied` 时，转交 `alibabacloud-ram-permission-diagnose` 处理。

## 约束

CallCLI 为远程执行：不支持 `file://`、`$()`、管道或本地路径。iacservice 命令不支持
`--region`（region 由模板的 provider block 决定）。完整参数表和轮询策略见 reference 文档。

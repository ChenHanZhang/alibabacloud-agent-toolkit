# 阿里云 IaC Service 模板 API 参考

IaC Service 产品（`IaCService`，版本 `2021-08-06`）即**自动化服务台**。
它管理可复用的 Terraform **modules**（模板），将模板转化为 **tasks**（任务），
并将每个任务作为 **job** 运行。状态保存在服务端；所有操作均为异步——提交后轮询。

**所有命令必须通过 MCP 工具 `AlibabaCloud___CallCLI` 执行**——禁止使用 Bash。
完整工具名：
`mcp__plugin_alibabacloud-iac-service_alibabacloud-iac-service__AlibabaCloud___CallCLI`。

## 认证与共享凭证

使用主机上 `aliyun configure` 配置的单一阿里云凭证，覆盖所有操作。无需为每个
server 单独 OAuth、无需为每个模板单独 token。所需 RAM 权限：

- `iacservice:ListModules`, `iacservice:GetModule`, `iacservice:CreateModule`,
  `iacservice:CreateModuleVersion`
- `iacservice:CreateTask`, `iacservice:CreateJob`, `iacservice:GetJob`,
  `iacservice:GetExecuteState`

## CLI 命令格式

`aliyun` CLI 直接接受规范 API 名：`aliyun iacservice ListModules ...`。
下面使用的 kebab-case 别名与 `alibabacloud-spec-ops` 已有风格一致
（`execute-terraform-plan`、`get-execute-state`）。如果某个别名被拒绝，
回退到括号中的 PascalCase API 名。首次调用时需根据实际 proxy/CLI 版本验证。

## 生命周期

```
ListModules ──▶ GetModule ─▶ CreateTask ─▶ CreateJob(plan) ─▶ GetJob/GetExecuteState
   (发现)        (查看)       (绑定版本)    (预览)              (轮询)
CreateModule / CreateModuleVersion = 创建 / 发布模板版本
CreateJob(apply|destroy) = 执行 / 销毁
```

## 发现

### list-modules (ListModules)

列出调用者的模板。发现阶段的入口——P1。

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `--max-results` | 否 | 每页条数 |
| `--next-token` | 否 | 上次响应中的分页游标 |
| `--keyword` | 否 | 按名称过滤 |

响应：`Modules[]{ModuleId, Name, Description, Source, LatestVersion}` + `NextToken`。

### get-module (GetModule)

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `--module-id` | 是 | 来自 list-modules |

响应：完整模板信息，包含 source、最新版本、属性等。

## 管理

### create-module (CreateModule)

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `--client-token` | 是 | 新生成的 UUID `[0-9a-zA-Z-]{1,64}` |
| `--name` | 是 | 2-128 字符 |
| `--source` | 是 | `OSS` / `Registry` / `ExportTask` / `Editor` / `Upload` |
| `--source-path` | 条件必填 | OSS/Registry 来源时的路径 |
| `--description` | 否 | |

### create-module-version (CreateModuleVersion)

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `--module-id` | 是 | 目标模板 |
| `--client-token` | 是 | 新生成的 UUID |
| `--name` | 是 | 版本标签 |
| `--description` | 否 | |

## 使用

### create-task (CreateTask)

将模板版本绑定为可运行的参数集。

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `--client-token` | 是 | 新生成的 UUID |
| `--name` | 是 | 2-128 字符 |
| `--module-id` | 是 | 要运行的模板 |
| `--module-version` | 是 | 要锁定的版本 |
| `--auto-apply` | 否 | 布尔值；预览后自动 apply 不暂停 |
| `--trigger-strategy` | 否 | `Manual` / `NewVersion` / `Auto` / `ParameterSetUpdated` |

响应：`TaskId`。

### create-job (CreateJob)

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `--task-id` | 是 | 来自 create-task |
| `--client-token` | 是 | 新生成的 UUID |
| `--description` | 是 | 描述本次运行做什么 |
| `--sub-command` | 否 | 仅支持 `destroy`（和 `refresh`）。**`plan` 无效**——默认 job 已自动 plan 后等待审批。正常 plan→apply 流程请省略此参数 |

响应：`JobId`。当 `autoApply=false` 时，job 完成 plan 后会在
`ConfigProactiveSuccess`（apply 场景）/ `Planned`（destroy 场景）状态暂停，
等待通过 operate-job 审批。**已线上验证（CLI 拒绝 `--sub-command plan`）。**

### operate-job (OperateJob) — 审批/拒绝 apply 门禁

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `--task-id` | 是 | |
| `--job-id` | 是 | 处于暂停状态的 job |
| `--operation-type` | 是 | `execute`（审批/apply）/ `abolish` / `cancel` — **不是** Confirm/Apply |
| `--comment` | 否 | 审计备注 |

`execute` 使状态推进：Confirmed → Applying → Applied。已线上验证。

### get-job (GetJob) — 轮询

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `--task-id` | 是 | |
| `--job-id` | 是 | |
| `--task-type` | 否 | `Task` / `SceneTestingTask` / `Stack` |

### get-execute-state (GetExecuteState) — 轮询原始 terraform 状态

| 参数 | 必填 | 说明 |
| --- | --- | --- |
| `--state-id` | 是 | 来自 job / plan |

状态值：`Pending` / `Planning` / `Applied` / `Errored` ...

## 轮询策略

1. 首次等待约 5 秒。2. 每 10 秒轮询一次。3. 最多约 60 次。每次轮询是独立的
CallCLI 调用——禁止 Bash 循环。超时时报告"仍在运行"并附上 JobId/StateId。

## 约束

- CallCLI 远程执行：不支持 `file://`、`$()`、管道、本地路径。
- iacservice 命令不支持 `--region`——region 由模板 provider block 决定。
- 写操作基于 `--client-token` 幂等；仅在重试同一调用时复用 token。
- 一次性直接执行（`execute-terraform-plan/apply/destroy`）由
  `alibabacloud-spec-ops` 覆盖；临时 HCL 用它，持久模板用本技能。

# alibabacloud-iac-service

通过统一凭证发现、管理和运行阿里云 **IaC Service**（自动化服务台）Terraform 模板。

本插件包含：

- Codex 和 Claude Code 的插件清单（manifest）
- 一个名为 `alibabacloud-iac-service` 的 MCP server，限定为 IaC Service 产品
- 一个技能（skill），负责发现用户的模板（modules）、管理版本、以及将模板作为
  tasks/jobs 运行（含 plan-before-apply 门禁）

## 为什么需要这个插件

自定义 IaC MCP server 迫使用户手动输入 URL（无法发现）、为每个 server 单独授权、
每个模板挂载一个连接。本插件保持单一凭证和单一 MCP 连接：通过 `ListModules`
*发现*模板，通过 `CreateModule`/`CreateModuleVersion` *发布*模板，通过
`CreateTask`/`CreateJob` *运行*模板——全部经由一个 `CallCLI` server 完成。

## 安装

```bash
npx openplugin aliyun/alibabacloud-agent-toolkit --plugin alibabacloud-iac-service
```

指定目标客户端：添加 `--claude`、`--codex` 或 `--qoderwork`。

## MCP 配置

限定为 IaC Service 产品：

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

## 技能

| 技能 | 说明 |
|------|------|
| `alibabacloud-iac-service` | 发现、发布版本、运行 IaC Service Terraform 模板 |

## 工作流程

1. **发现** — `list-modules` 查看模板列表，`get-module` 查看详情。
2. **管理** — `create-module` / `create-module-version` 发布模板及版本。
3. **使用** — `create-task` 然后 `create-job`（plan → 确认 → apply），通过
   `get-job` 轮询状态。Destroy 需要二次确认。

临时 HCL 代码（无已保存模板）属于 `alibabacloud-spec-ops`。完整 API 契约见技能
reference 文档 `references/iacservice-template-api.md`。

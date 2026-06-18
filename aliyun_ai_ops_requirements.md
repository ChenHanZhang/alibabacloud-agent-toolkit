https://code.claude.com/docs/en/plugins 是claude 推出的 plugin 插件能力，codex和qoderwork也都支持plugin。因此，该内容包括了如何定义和实现自定义插件的规范和介绍。

https://code.claude.com/docs/en/discover-plugins 是claude 官方介绍如何注册和发现一个自定义插件的介绍。

https://github.com/obra/superpowers superpowers是一个用于软件开发的规范性插件，业界较为出名的插件。其介绍如下：Superpowers is a complete software development methodology for your coding agents, built on top of a set of composable skills and some initial instructions that make sure your agent uses them.

https://github.com/fission-ai/openspec 与superpowers 类似，都是用于软件开发规范流程的插件。其包括 proposal、apply、verify等标准研发命令。

https://github.com/microsoft/azure-skills 是一个微软Cloud Azure 面向Agent 个人使用者推出的插件。其介绍如下：The Azure Skills Plugin packages Azure expertise and MCP-backed execution together so compatible coding agents can do real Azure work instead of giving generic cloud advice.
其skills中的 azure-prepare, azure-validate, azure-deploy, 以及 hooks中做的 track telemery的收集都是需要重点关注的内容。
azure-prepare, azure-validate, azure-deploy三者均使用：微软的 mcp_azure_mcp_* 工具进行管理、获取、检索、验证。
hooks中的track-telemetry 可以学习和了解下其如何进行的trace和数据收集（本地还是远端，部分还是全部）作为技术参考。

阿里云自己的mcp_core 配置如下:

```json
{
  "mcpServers": {
    "alibabacloud": {
      "command": "uvx",
      "args": [
        "alibabacloud.mcp-proxy@latest"
      ]
    }
  }
}
```

其有如下几个核心接口:

```
AlibabaCloud___SearchApis
AlibabaCloud___CalICLI
AlibabaCloud___GetApiDefinition
AlibabaCloud___ListApis
AlibabaCloud___ListProductRegions
AlibabaCloud___GenerateCLICommand
AlibabaCloud___ListProducts
AlibabaCloud___SearchDocument
AlibabaCloud___ReadDocument
```

根据上述的介绍和参考资源，我现在要实现如下一个自定义的plugin。其核心需求为支持用户使用agent 操作阿里云的运维操作的plugin。我需要参考superpwoers、azure 的模式，定义出用户运维阿里云的研发范式： planing(brainstorming过程，以阿里云云计算专家的身份和助理的身份帮助用户明确需求、明确边界、发现问题)、writing-plans（将计划落入可持续追踪的特定文档中+将计划以HCL的方式落入到当前目录或隐藏目录）、executing-plans（将HCL进行执行）。

核心需求和工作流程解释：
> 一定要参考superpowers的实现逻辑，我的需求跟他的很像，同时也要深度参考azure的，因为都是云计算运维且形式和产品力一致。

现在要参考superpowers（superpowers:brainstorming、superpowers:writing-plans、superpowers:executing-plans、subagent-driven-development、using-superpowers）和azure的 plugin (prepare、validate、deploy) 设计和实现出阿里云自己的agent ops 研发范式。

User Stories:
在用户在claude 或者 codex 上安装了当前插件后，
us1:
用户先使用 aliyun:planing （command or skill，参考supperpowers或者azure对应的实现方式），进行用户需求的理解、澄清，以及帮助用户进行脑爆进行思考和探索，因为用户一开始的需求可能很模糊，需要参考supperpowers的brainstorming进行探索帮助用户明确边界。举个例子（用户说需要一台ECS服务器，则需要参考superpowers中的方式，进行需求明确，例如部署规格、部署地域、镜像版本、操作系统版本、安全组等）因此这一部分就是需要假设自己是一个阿里云的技术专家作为助理的形式，辅助用户理解和明确需求以及边界、并且在这个阶段帮助用户进行设计和指导，例如最佳实践是什么，最好怎么做，做好不这么做，是否有什么问题（安全问题、用云的最佳实践是否满足等），这一部分就是作为一个超级阿里云专家帮助用户进行设计和需求澄清。这里可以使用的工具就包括mcp中的所有可用API以及外部知识检索（阿里云的github / 官方最佳实践 / 用云最佳实践等）。这部分工作是最最核心的部分，用于帮助用户进行设计优先，一切以设计为准。因此，详尽地参考一下azure的prepare、和superpowers的brainstorming。

在这一步需求都明确完后，可以参考superpowers的一个新特性，它会将用户的设计方案（在前端需求场景），通过一个简易的html将内容进行demo，用以展示出需求的直观效果，以供用户选择和确认是否符合。因此基于这样的特性，我们也希望在这一步的结束部分，咨询用户是否需要为他展示本次的内容的效果（可以通过一个HTML的好看的资源云架构图，将HCL转换成如此的信息，在可视化图中，重点标记出用户关注的需求和设计部分）。如果用户不关心图，则直接用文字展示整体根据需求设计架构，待用户确认。（参考superpwoers）

us2:
在进行了最核心的planing的设计阶段和需求澄清后，可自动询问后用户手动启动：aliyun:writing-plans， 将上述设计内容和规范写入到.aliyun-ai-ops-spec/ 目录下。参考superpwoers的研发数据管理以及openspec的研发数据管理
由于我们的插件不仅要生成基础的需求文档描述，还需要将详细的需求文档转换为Terraform HCL以备后续的执行。因此我们的可管理追踪的研发数据管理，更加像openspec的管理。如下的大致设计：
每一个独立的需求，都用独立的需求名称进行管理，下面有两个核心部分designs/ 和 tasks/ designs/ 是记录设计和需求的详细内容，以及需要将运维的目标用Terraform的HCL描述。
tasks/部分，是用于在后续阶段进行执行tf和cli的结果的跟踪的。

生成阿里云的HCL代码，可以参考这个SKILL:https://github.com/acloudlabs-unofficial/agent-plugins/blob/main/plugins/alibabacloud-terraform/skills/terraform-code-generator/SKILL.md
。也可以直接将这个SKILL加入到本插件的能力。（类似于azure的skills下，除了prepare、validate、deploy外还有别的基础skill）

```
.aliyun-ai-ops-spec/
 |--xxxx/
  |-- designs/
   |-- xxx_plan_design.md
   |-- terraform/
    |-- main.tf
   |-- CLI
    |-- xxx_cli.sh
  |-- tasks/
   |-- xxx_tf_execute_task.md
   |-- xxx_cli_execute_task.md

```

us3:
在需求落下来到设计中以及HCL云维代码被写下来后，要进行生成的HCL/CLI代码的 与 需求设计之间的满足性和合规性评审、以及HCL/CLI的代码本身的生成代码质量评审。这两个应该用单独的subagent reviewer进行独立评审。这个可以完全参考superpowers 它在代码实现过程中的`流程有 code spec reviewer 和 code quality reviewer。包括通过MCP 的callCLI进行远端的TF代码语法校验：

```
aliyun iacservice
  validate-module                模版预检
```

 如果有问题，则根据意见进行改进。期间都可以大量使用mcp的api 进行必要的内容检索，以支撑code review所需要的数据，给出真实的反馈。

us4:
在完成上述动作后，自动进行下一步executing-plans或用户执行 aliyun:executing-plans。这一步将通过mcp的iac自动化服务台的TF接口进行远程执行TF任务：
一般来说包含三个核心api:

```
aliyun iacservice 
  execute-terraform-apply        执行TerraformApply
  execute-terraform-destroy      执行Terraform Destroy
  execute-terraform-plan         执行TerraformPlan
  get-execute-state              获取Terraform运行结果
```

可以通过mcp的 AlibabaCloud___CalICLI 进行远程执行。先执行plan无误后 再执行 apply。

执行的结果和状态，都采用tasks/目录的内容进行管理和跟踪以及反馈，

根据上述的需求，也参考azure、superpwoers、openspec；尤其是参考superpwoers和openspec的实现，将这些需求自动拆分成必要的SKILL，以满足类似superpwoers的自动化研发workflow的目标。

可观测的track追踪要求：参考azure的hooks中对track的实现。开源实现中，langfuse也是类似的思路进行track追踪的。但是需要参考azure的，因为azure的已经是一个对客形态，对于收集哪些数据、怎么收集、收集到哪里存储都已经经历过了法律考虑。

# Alibaba Cloud Guidance

- Prefer the Alibaba Cloud MCP server for Alibaba Cloud interactions. Use local CLI or direct SDK calls only when MCP is unavailable or clearly not suitable for the task.
- Before starting a task, check whether a relevant Alibaba Cloud skill is available and use it in preference to generic guidance.
- When using MCP, prefer MCP-exposed operations over reproducing the same workflow through local shell commands.
- When uncertain about API parameters, permissions, quotas, or error codes, verify against official documentation instead of guessing.
- When creating infrastructure, prefer infrastructure-as-code or repeatable automation over ad hoc console steps.
- Keep region, account, RAM permission, and network assumptions explicit in plans and changes.

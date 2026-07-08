---
name: alibabacloud-executing-plans
description: "Execute validated Terraform plans through MCP Server Core RunIaC. Requires explicit user confirmation before any apply operation. WHEN: execute terraform, apply infrastructure, run terraform apply, deploy infrastructure, create cloud resources, execute plan."
license: MIT
metadata:
  author: Alibaba Cloud
  version: "0.8.0"
compatibility:
  tools:
    - mcp__plugin_alibabacloud-spec-ops_alibabacloud-spec-ops__AlibabaCloud___RunIaC
    - mcp__plugin_alibabacloud-spec-ops_alibabacloud-spec-ops__AlibabaCloud___GetTask
    - mcp__plugin_alibabacloud-spec-ops_alibabacloud-spec-ops__AlibabaCloud___CallCLI
---

# Alibaba Cloud Executing Plans

> **AUTHORITATIVE GUIDANCE - MANDATORY COMPLIANCE**
>
> This skill executes validated Terraform code through MCP Server Core
> `alibabacloud-spec-ops.AlibabaCloud___RunIaC`.
> It creates **real cloud resources** that cost money. Safety gates are
> non-negotiable.
>
> **Terraform plan/apply/destroy MUST use `AlibabaCloud___RunIaC`**. Do not
> run local `terraform`, do not use Bash to run `aliyun`, and do not call
> `aliyun iacservice execute-terraform-plan/apply/destroy` through
> `AlibabaCloud___CallCLI`.

---

> **PREREQUISITE CHECK - MANDATORY**
>
> Before proceeding, verify BOTH prerequisites:
>
> 1. **Validation passed** - check `tasks/status.json` has
>    `status: "validated"` (internal check, do not expose to user)
> 2. **User explicitly confirmed** they want to execute
>
> If EITHER is missing, **STOP IMMEDIATELY**:
>
> - Not validated? -> Invoke **alibabacloud:validate** first
> - No user confirmation? -> Ask user before proceeding

---

## Triggers

Activate when:

- User explicitly asks to execute/apply the Terraform plan
- User confirms they want to proceed after validation passes

**NEVER activate automatically.** This skill requires explicit user intent.

## Rules

1. **Single deploy approval, granted upstream** - The user authorizes
   deployment ONCE in `alibabacloud-validate`'s gate. Inside this skill the
   entire `plan -> apply` chain runs automatically. Never add a second
   confirmation between plan and apply.
2. **RunIaC only for Terraform execution** - Plan, apply, and destroy MUST use
   `AlibabaCloud___RunIaC`; polling MUST use `AlibabaCloud___GetTask`.
3. **Plan before apply, results always shown** - Always run `action=plan`
   first and surface its output to the user before apply. The user can
   interrupt mid-stream if the plan reveals something unexpected, but the
   default flow does not stop to ask.
4. **Inline content** - Read `.tf` files locally, then pass their content as a
   string to `RunIaC.code`. The MCP tool does not read local paths.
5. **Record everything** - All outputs are recorded to `tasks/`.
6. **Support rollback** - Provide a destroy option if apply fails.
7. **Poll for completion** - RunIaC is async; use sequential `GetTask` calls to
   poll.
8. **Destructive operations require double confirmation** - Destroy requires
   the user to type the project name.
9. **Persist `processID`** - RunIaC keeps remote Terraform state behind a
   `processID`. This skill MUST write the latest process IDs back to
   `tasks/status.json` on every Plan / Apply / Destroy and MUST pass the saved
   process ID as `previousProcessId` on subsequent Day-2 calls. Losing it
   orphans the remote state and can force a fresh deploy.
10. **Source-of-truth integrity** - Some failures are only discoverable at
    apply time (SKU offline in target AZ, zone out-of-capacity, etc.). Any spec
    change forced by such a failure MUST be written back to BOTH
    `designs/design.md` (with a Decisions Log entry) AND
    `designs/terraform/*.tf` BEFORE re-running plan/apply. **Never hot-patch
    the in-flight apply**.

---

## RunIaC State Persistence

RunIaC returns a `processID` for each operation. That process owns, or can
refer back to, the remote Terraform state. Persist these fields under
`tasks/status.json -> state`:

| Field | Meaning |
| --- | --- |
| `last_process_id` | Most recent RunIaC process that has the deployment state |
| `last_plan_process_id` | Most recent completed plan process; apply uses this value |
| `last_apply_process_id` | Most recent apply process; Day-2 plan can continue from this |
| `last_destroy_process_id` | Most recent destroy process |
| `last_plan_at` / `last_apply_at` / `last_destroy_at` | ISO timestamps |

**Branching by Day-1 vs Day-2:**

| Scenario | Saved process | RunIaC plan call |
| --- | --- | --- |
| Day-1 (first run) | absent / empty | `action=plan`, `code={CODE}` |
| Day-2 (iteration) | `state.last_process_id` present | `action=plan`, `code={CODE}`, `previousProcessId={LAST_PROCESS_ID}` |

Apply passes `previousProcessId={LAST_PLAN_PROCESS_ID}` and no code. Destroy
passes `previousProcessId={LAST_PROCESS_ID}` and no code.

**Legacy / migration edge case.** If `tasks/status.json` has old
`state.state_id` but no RunIaC process fields, STOP before touching the remote.
The old IaCService `state_id` cannot be directly used as RunIaC
`previousProcessId`. Ask the user whether to:

- treat this as Day-1 and create a fresh RunIaC state (risks duplicate
  resources alongside the legacy deployment), or
- abort and let the user supply a known RunIaC `processID`.

Never silently start fresh.

---

## MCP Execution Model

**RunIaC tool names:**

- Display name: `alibabacloud-spec-ops.AlibabaCloud___RunIaC`
- Codex-qualified name:
  `mcp__plugin_alibabacloud-spec-ops_alibabacloud-spec-ops__AlibabaCloud___RunIaC`
- Polling tool:
  `mcp__plugin_alibabacloud-spec-ops_alibabacloud-spec-ops__AlibabaCloud___GetTask`

**RunIaC request fields:**

| Field | Required | Notes |
| --- | --- | --- |
| `action` | optional | `plan` (default), `apply`, or `destroy` |
| `code` | plan only | Full Terraform HCL. Mutually exclusive with `presignToken` |
| `presignToken` | plan only | Optional large-bundle upload token, if available |
| `previousProcessId` | Day-2 plan, apply, destroy | Process ID returned by an earlier RunIaC call |

**HCL requirements for RunIaC:**

- Include an explicit provider block:
  `provider "alicloud" { region = var.region }`
- Do not set access credentials in the provider block; credentials are injected
  by the remote execution layer.
- Do not include a `terraform { required_providers { ... } }` block.
- Only `alicloud` provider resources are supported.

**Therefore, you MUST:**

1. Use the `Read` tool to read `.tf` file contents into your context.
2. Concatenate all `.tf` files into one `CODE` string.
3. Pass the string in the MCP request body as `code`; never pass local paths,
   `file://`, shell substitutions, or environment variables.

---

## Process

### Step 1: Verify Prerequisites

1. Read `tasks/status.json`:
   - `status` must be `"validated"` (Day-1) OR `"executed"` (Day-2
     re-iteration after planning produced new code)
   - Capture `state.last_process_id` into `{LAST_PROCESS_ID}` if present
   - Capture `state.last_plan_process_id` into `{LAST_PLAN_PROCESS_ID}` if
     present
   - If legacy `state.state_id` exists without RunIaC process IDs, see the
     migration edge case above before proceeding
2. Read `tasks/validation-report.md` - must show all reviews PASS.
3. Confirm user intent one more time, and surface whether this is Day-1 or
   Day-2:

> "Ready to execute Terraform.
>
> {Day-1: This will create real cloud resources on Alibaba Cloud and incur costs.}
> {Day-2: This will update the existing deployment (process `{LAST_PROCESS_ID}`);
> changes shown in the next plan output will be applied to the live resources.}
>
> Proceed with `terraform plan`?"

### Step 2: Prepare Terraform Content

Read all `.tf` files from the design directory and concatenate them into a
single string:

```text
Read: .aliyun-ai-ops-spec/{name}/designs/terraform/main.tf
Read: .aliyun-ai-ops-spec/{name}/designs/terraform/variables.tf
Read: .aliyun-ai-ops-spec/{name}/designs/terraform/outputs.tf
# ... any other .tf files
```

Concatenate all content into one `CODE` string. This is passed inline to
`RunIaC.code`.

### Step 3: Execute Terraform Plan

**Day-1 (no prior RunIaC process):**

```text
AlibabaCloud___RunIaC:
  action: "plan"
  code: "{CODE}"
```

**Day-2 (continuing from saved RunIaC process):**

```text
AlibabaCloud___RunIaC:
  action: "plan"
  code: "{CODE}"
  previousProcessId: "{LAST_PROCESS_ID}"
```

The response returns `processID`. Capture it as `{PLAN_PROCESS_ID}` and persist
it immediately before polling or showing output:

```json
{
  "...": "...",
  "state": {
    "last_process_id": "{PLAN_PROCESS_ID}",
    "last_plan_process_id": "{PLAN_PROCESS_ID}",
    "last_plan_at": "{ISO timestamp}",
    "...": "..."
  }
}
```

Rationale: if the user aborts after seeing the plan, the next invocation must
still be able to continue on the same remote state.

**Poll for completion** with `AlibabaCloud___GetTask`:

```text
AlibabaCloud___GetTask:
  processID: "{PLAN_PROCESS_ID}"
  waitTimeoutSeconds: 30
  pollIntervalSeconds: 5
```

### Step 4: Present Plan Results (no second confirmation)

Show the plan output from the RunIaC / GetTask result, then **proceed directly
to Step 5**. Do NOT stop to ask "Confirm apply?". The user already authorized
deployment at the validate-stage gate.

Write plan results to `tasks/tf-plan-result.md`.

Display:

> "Terraform plan results:
>
> - {N} resources to create
> ~ {N} resources to modify
> - {N} resources to destroy
>
> {Summary of key resources}
>
> 即将自动进入 apply 阶段。如发现 plan 不符合预期，请立刻中断我（例如按 Esc / 中止当前消息）。"

If the plan output reveals something the user clearly did not consent to
(e.g. unexpected resource destruction in a Day-2 modify when no destroy was
discussed), STOP and surface it as a question:

> "plan 中检测到非预期的破坏性变更：
>
> - `<resource>` 将被 destroy/replace
>
> 这通常不在变更范围内，是否确认继续？回复 **\"继续\"** 才会 apply；回复 **\"停\"** 我立刻中止。"

Default path (no anomalies): emit the display block, then immediately invoke
Step 5 in the same turn.

### Step 5: Execute Terraform Apply

Apply must bind to the plan process from Step 3. Do not pass code.

```text
AlibabaCloud___RunIaC:
  action: "apply"
  previousProcessId: "{PLAN_PROCESS_ID}"
```

The response returns a new `processID`. Capture it as `{APPLY_PROCESS_ID}`,
then poll with `AlibabaCloud___GetTask`:

```text
AlibabaCloud___GetTask:
  processID: "{APPLY_PROCESS_ID}"
  waitTimeoutSeconds: 30
  pollIntervalSeconds: 5
```

If the apply response or GetTask result shows `ApprovalPending`, surface the
approval request and ask the user to complete approval out of band, then keep
polling the same `{APPLY_PROCESS_ID}`. Do not call RunIaC again while waiting
for approval.

### Step 6: Record Results

Write results to `tasks/tf-apply-result.md`:

```markdown
# Terraform Apply Results - {Requirement Name}

## Timestamp
{ISO timestamp}

## RunIaC Process IDs
- Plan: {PLAN_PROCESS_ID}
- Apply: {APPLY_PROCESS_ID}

## Status
SUCCESS / FAILED

## Resources Created
| Resource Type | Resource Name | Resource ID |
|---------------|---------------|-------------|
| ... | ... | ... |

## Outputs
| Name | Value |
|------|-------|
| ... | ... |

## Errors (if any)
{error details}
```

### Step 7: Update Internal State + TODO list

1. Silently update `tasks/status.json`. **Do NOT mention this file to the
   user.**

   ```json
   {
     "...": "...",
     "status": "executed",
     "updated_at": "{ISO timestamp}",
     "state": {
       "last_process_id": "{APPLY_PROCESS_ID}",
       "last_plan_process_id": "{PLAN_PROCESS_ID}",
       "last_apply_process_id": "{APPLY_PROCESS_ID}",
       "last_plan_at": "{from Step 3}",
       "last_apply_at": "{ISO timestamp of successful apply}",
       "last_destroy_at": null
     }
   }
   ```

   `state.last_process_id` MUST be retained across Day-2 transitions. Later
   `executing-plans` invocations read it back in Step 1 and pass it as
   `previousProcessId` to continue on the same remote state.

2. Update the user-facing TODO list via `TodoWrite`: mark
   **"部署执行：terraform plan/apply via RunIaC"** -> `completed`.

   On apply failure or destroy: leave the task in `in_progress` so the user
   understands the workflow has not finished; mark `completed` only after the
   resource state is reconciled.

### Step 8: Generate Deployed Topology (`topology.html`)

**When:** Apply succeeded. Skip if failed or partial.

`topology.html` is the deployed topology, not the planning-time
`designs/architecture.html`. It must be based on the RunIaC/GetTask result and
the recorded apply output. Do not reuse the planning diagram.

1. Read
   `alibabacloud-executing-plans/references/architecture-topology-html-guide.md`
   from the installed plugin.
2. Extract resources and outputs from `tasks/tf-apply-result.md` and the
   terminal RunIaC/GetTask result.
3. Generate `<project-root>/topology.html` and verify it in a browser.

---

## Polling Strategy

RunIaC operations are asynchronous. After submitting an operation, poll using
sequential `AlibabaCloud___GetTask` calls:

| Parameter | Value |
| --- | --- |
| First poll delay | Wait about 5 seconds, then call GetTask |
| `waitTimeoutSeconds` | 30 |
| `pollIntervalSeconds` | 5 |
| Max attempts | 60 attempts (about 10 minutes) |
| Timeout action | Report "still running" with the processID for manual follow-up |

Check `status` and `nextAction` in each response:

| Status / nextAction | Action |
| --- | --- |
| `nextAction: CallGetTask` / `CallGetTaskAgain` | Call GetTask again with the same `processID` |
| `status: Planned` and `nextAction: Stop` | Plan is complete; summarize diff |
| `status: ApprovalPending` | Ask user to complete approval out of band; poll same process afterward |
| `nextAction: None` | Operation succeeded; record result |
| `nextAction: InspectError` or `status: Failed` | Extract `error`, classify failure |
| `nextAction: Stop` with rejection/expiry/validation failure | Stop; do not retry blindly |

Do NOT use Bash loops or sleep commands for polling.

---

## Error Handling

### Plan Fails

- Record error in `tasks/tf-plan-result.md`.
- Identify root cause from `error` / `result`.

| Error Code / Symptom | Meaning | Action |
| --- | --- | --- |
| `ValidationFailed`, Terraform parse/schema diagnostics | TF syntax or schema error | Fix TF files and re-validate |
| `QuotaExceeded` | Resource quota limit | Inform user to request quota increase |
| `AccessDenied`, `Forbidden`, `NoPermission` | Permission missing | Invoke `alibabacloud-ram-permission-diagnose` |
| `ResourceNotFound` | Referenced resource missing | Check dependencies |
| `Invalid*Class.Offline`, `OperationDenied.NoStock`, `Zone.NotOnSale` | Spec unavailable in target region/AZ | See Spec-driven Failures |
| `BackendUnreachable`, timeout | RunIaC/backend issue | Retry once only if idempotent, otherwise stop |

- Set status back to `"plans-written"` for re-validation.
- Keep existing RunIaC process fields in status.json; failed plan does not
  delete remote state.

### Apply Fails

- Record error in `tasks/tf-apply-result.md`.
- Keep `{APPLY_PROCESS_ID}` in `state.last_process_id` if RunIaC returned one;
  it may represent partial remote state.
- Classify the failure first, then offer the right options:

| Failure class | Examples | Where to go |
| --- | --- | --- |
| Spec-driven | `InvalidDBInstanceClass.Offline`, `OperationDenied.NoStock`, `Zone.NotOnSale` | Spec-driven Failures - sync source of truth |
| Structural | Wrong VPC ID, missing security group reference, circular dependency | Fix HCL, re-run plan/apply with retained processID |
| Permission | `AccessDenied`, `Forbidden`, `NoPermission` | Invoke `alibabacloud-ram-permission-diagnose`; retry after RAM fix |
| Transient | `ServiceUnavailable`, intermittent 5xx | Re-run once from the saved processID |

After classification, present these options to the user:

1. Apply the spec/HCL fix and retry plan/apply.
2. Destroy partially created resources (uses the Destroy gate below).
3. Pause for manual investigation; keep the processID so the workflow can
   resume.

### Spec-driven Failures (source-of-truth recovery)

Some Alibaba Cloud resource constraints are only discoverable at apply time.
When reality differs from the catalog or availability changed after planning:

1. **Diagnose** the failed resource, field value, region/zone, and upstream
   error code.
2. **Query live alternatives via MCP** using `AlibabaCloud___CallCLI` against
   the right inventory API.
3. **Ask the user** to pick a replacement. Never auto-pick a replacement.
4. **Sync source-of-truth** in BOTH `designs/design.md` and
   `designs/terraform/*.tf`.
5. **Re-run plan + apply** with `previousProcessId={LAST_PROCESS_ID}` so the
   new plan continues on the existing remote state.

If the user pauses, leave `status: "executing"` and TODO task 3
`in_progress`. Tell the user how to resume with the saved processID.

### Destroy Operations

For `terraform destroy` (cleanup or rollback):

> "**DESTRUCTIVE OPERATION**
>
> This will destroy ALL resources created by this Terraform configuration.
> This action cannot be undone.
>
> Type the requirement name `{name}` to confirm destruction:"

Require exact name match before proceeding. Then call RunIaC with no code:

```text
AlibabaCloud___RunIaC:
  action: "destroy"
  previousProcessId: "{LAST_PROCESS_ID}"
```

Capture `{DESTROY_PROCESS_ID}` from the response and poll it with
`AlibabaCloud___GetTask` using the same polling strategy as apply.

After destroy succeeds, update `tasks/status.json`:

```json
{
  "...": "...",
  "status": "destroyed",
  "updated_at": "{ISO timestamp}",
  "state": {
    "last_process_id": "{DESTROY_PROCESS_ID}",
    "last_plan_process_id": "{prior}",
    "last_apply_process_id": "{prior}",
    "last_destroy_process_id": "{DESTROY_PROCESS_ID}",
    "last_plan_at": "{prior}",
    "last_apply_at": "{prior}",
    "last_destroy_at": "{ISO timestamp}"
  }
}
```

Keep RunIaC process IDs as historical records. If the user later wants to
redeploy fresh, planning will detect `status == "destroyed"` and prompt for
net-new Day-1 vs reuse decision.

---

## RunIaC MCP Reference

| Operation | MCP tool | Request |
| --- | --- | --- |
| Plan | `AlibabaCloud___RunIaC` | `{ "action": "plan", "code": "{HCL}" }` |
| Day-2 plan | `AlibabaCloud___RunIaC` | `{ "action": "plan", "code": "{HCL}", "previousProcessId": "{last_process_id}" }` |
| Apply | `AlibabaCloud___RunIaC` | `{ "action": "apply", "previousProcessId": "{last_plan_process_id}" }` |
| Destroy | `AlibabaCloud___RunIaC` | `{ "action": "destroy", "previousProcessId": "{last_process_id}" }` |
| Poll | `AlibabaCloud___GetTask` | `{ "processID": "{processID}", "waitTimeoutSeconds": 30, "pollIntervalSeconds": 5 }` |

**NEVER:**

- Run local `terraform plan`, `terraform apply`, or `terraform destroy`.
- Use Bash to run `aliyun iacservice execute-terraform-*`.
- Use `AlibabaCloud___CallCLI` for Terraform plan/apply/destroy.
- Use `file://` paths, `$(cat ...)`, pipes, redirects, or shell variables in
  MCP execution requests.
- Pass credentials in HCL.
- Include `terraform { required_providers { ... } }` in RunIaC HCL.

---

## Safety Principles

- **Never skip plan** - Always plan before apply, and always show plan output
  to the user.
- **Auto-apply is the default flow** - The deploy authorization is granted ONCE
  at the validate-stage gate. Do not add a second confirmation between plan and
  apply.
- **Never silent destroy** - Destroy requires exact project-name confirmation.
- **Always use RunIaC for Terraform execution** - Plan/apply/destroy go through
  MCP Server Core `AlibabaCloud___RunIaC`.
- **Always inline content** - Read files first, pass content as `code`.
- **Always record** - Every operation is logged to `tasks/`.
- **Always poll** - Verify status via `AlibabaCloud___GetTask`.
- **Always persist process IDs** - Write RunIaC process IDs to
  `tasks/status.json` immediately after each RunIaC response.
- **Fail safe** - On error, stop and inform user; do not retry blindly.

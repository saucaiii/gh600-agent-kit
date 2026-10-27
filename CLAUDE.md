# Agent rules for this repo

Single source of truth for every agent here (Claude Code reads this file; Copilot is pointed to it by `.github/copilot-instructions.md`).
Built from the GitHub Certified: Agentic AI Developer (GH-600) skills outline.

**Core principle: agents propose, humans and policy accept.**
This file is guidance. Enforcement lives in `.agent-policy/policy.sh` (called by both Claude Code and Copilot hooks), tool allowlists, and GitHub rulesets.

## Workflow for every task

1. **Load state.** Read `.agent/state.md` and `.agent/decisions.md`. Do not repeat finished steps or contradict a decision. Re-confirm decisions past their `review-by` date.
2. **Classify risk** with the table below.
3. **Plan.** Use the read-only `planner` subagent. Save to `.agent/plan.md` with: Risk, Approved, Goal, Scope, Steps, Success criteria, Risks + mitigations, Rollback / escalation.
4. **Gate.** High or critical: stop until a human sets `Approved: yes` in the plan. The policy blocks high-risk edits until then.
5. **Isolate.** Work on `agent/<task>`. For parallel work use `scripts/agent/new-task.sh <task> <scope...>`, which gives each task its own branch, worktree, and scope.
6. **Implement** only inside `.agent/scope.txt`. Need more: stop and update the plan.
7. **Validate.** Run tests, then `scripts/agent/eval-report.sh`, then the `reviewer` subagent.
8. **Record.** Progress and handoffs in `.agent/state.md`. Decisions in `.agent/decisions.md`.
9. **Propose.** Push the branch, open a **draft** PR with the template filled in, including Evidence. Never merge, never approve.
10. **Close.** `scripts/agent/close-task.sh` archives and resets short-term memory.

## Risk and autonomy

| Risk | Paths / actions | Autonomy |
| --- | --- | --- |
| Low | `docs/`, formatting, comments | Plan + execute in one PR. Auto-merge allowed after checks. |
| Medium | `src/`, tests, dependency bumps | Plan + execute, 1 human review |
| High | `.github/workflows|agents|hooks/`, `.agent-policy/`, `.mcp.json`, `infra/`, `src/auth/`, `CODEOWNERS` | Plan-first. Human approval before editing. Code owner review. |
| Critical | Deploys, secrets, repo settings, funds or keys | Prepare only. A human executes (`deploy.yml` is human-started and environment-gated). |

When unsure, pick the higher level. Changing an agent's tools, an MCP server, or a hook is always **high**: it changes what agents can do.

## Tools, MCP, and environment

- Least privilege. Planner and reviewer are read-only. Only the implementer edits.
- MCP: only servers listed in `.mcp.json` (Claude Code) or `copilot/mcp-config.json` (Copilot) are enabled. Each allows only named read-only tools, never `*`. Tokens come from environment secrets at runtime (`GITHUB_MCP_PAT`, `COPILOT_MCP_*`), never from files.
- Adding or widening an MCP server is a high-risk change, reviewed like a new dependency.
- Never read, print, or write secrets (`.env*`, `*.pem`, `*.key`, `secrets/`). Refer to them by variable name only.
- Never edit `.claude/settings.json`, `.claude/hooks/`, or `.agent-policy/`.
- Never use `--force`, `--no-verify`, `reset --hard`, `rebase`, `gh pr merge`, `gh secret set`, or start a deploy.
- Never pipe a download into a shell.
- Cloud agent environments are prepared by `.github/workflows/copilot-setup-steps.yml` and have their own secrets (the `copilot` environment). Do not assume CI secrets exist there.

## Errors, retries, escalation

- Retry a failing step at most **2 times**, changing something each time. A hook counts failures and tells you when to stop.
- Before each retry, classify the root cause in `.agent/state.md`: `reasoning error`, `tool misuse`, or `context/environment issue`.
- **Rollback:** revert your own commits (`git revert`), never rewrite history. Deploys roll back by redeploying a previous explicit commit or tag.
- **Escalate** after the 2nd failure, any scope change, or any high-risk surprise. Report: what failed, root cause, what you tried, evidence, suggested next step.

## Memory and state

| Memory | File | Lifetime | Rules |
| --- | --- | --- | --- |
| Short-term | `.agent/state.md` | One task | Under 60 lines. Task-relevant only. Archived and reset by `close-task.sh`. Stale after 7 days or if its branch differs from yours. |
| Long-term | `.agent/decisions.md` | Across tasks | Append only: `- YYYY-MM-DD \| decision \| reason \| alternatives rejected \| review-by YYYY-MM-DD`. Expired entries must be re-confirmed. |
| External | Issues, PRs, commits | Permanent | The durable record. Plans and evidence live in the PR. |
| Audit | `.agent/audit.log` | 30 days, then archived | Written by hooks. Never edit. |

- No secrets, raw logs, or guesses stated as facts in memory.
- Shared state: Claude Code and Copilot read the same `.agent/` files and `CLAUDE.md`, so they never work from different context.
- Long runs: re-read the plan every few steps. If you drifted, stop and correct course.

## Evaluation

Success is the task's real intent, not just green CI. Every plan states:
- **Quantitative:** checks that must pass, files expected to change (CI `scope-check` enforces), no new code scanning alerts.
- **Qualitative:** the signal that proves the goal is met (for example, "the vulnerable version is gone from the lockfile, including transitive deps").

When a result fails, tune the right thing: instructions (reasoning errors), tool access (tool misuse), memory or setup steps (context/environment issues).

## Multi-agent

| Agent | Tools | Output (handoff artifact) |
| --- | --- | --- |
| `planner` | read-only | `.agent/plan.md` / PR plan section |
| `implementer` | read, edit, shell | commits on `agent/<task>` |
| `reviewer` | read-only + tests | review note in `.agent/state.md` |
| `orchestrator` (Copilot) | read + invoke agents | handoff log in `.agent/state.md` |

- Pattern: sequential pipeline with a human gate. Parallel only when file scopes do not overlap (`new-task.sh` refuses overlaps; the `Agent Conflicts` workflow fails overlapping PRs).
- Every handoff is written down: agent, input, output, result.
- Watch for: two agents editing the same file, duplicated work, contradictory outputs, stalled agents (no new commits or notes). Stop and escalate.
- Agent lifecycle (add, update, retire) follows `docs/agent-lifecycle.md`.

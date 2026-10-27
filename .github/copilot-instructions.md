# Instructions for GitHub Copilot agents in this repo

`CLAUDE.md` at the repo root is the single source of truth for agent rules. Read it first. This file is a summary so Copilot and Claude Code never follow different rules.

Before any work:
1. Read `.agent/state.md` (short-term memory) and `.agent/decisions.md` (long-term memory). Do not repeat finished steps or contradict a decision. Decisions past their `review-by` date must be re-confirmed.
2. If `.agent/state.md` names a different branch than yours, treat it as stale.

Rules:
- Agents propose, humans and policy accept. Never merge, never approve.
- Start every PR with the Plan section of `.github/pull_request_template.md`, fully filled in. CI checks it.
- Risk: docs = low; `src/` = medium; `.github/workflows|agents|hooks/`, `.agent-policy/`, `infra/`, `src/auth/`, `CODEOWNERS`, `.mcp.json` = high (plan-first); deploys, secrets, settings = critical (prepare only).
- Stay inside the declared scope. CI fails PRs that change files outside it.
- Never touch secrets, `.claude/`, or `.agent-policy/`. Hooks block it.
- Same check fails twice: stop and escalate (what failed, what you tried, evidence, next step).
- Success means the task's real intent is met, not only green CI.
- Record progress in `.agent/state.md`, decisions in `.agent/decisions.md`, handoffs between agents in the Handoffs section.

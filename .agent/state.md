# Working memory (short-term). Keep under 60 lines. Prune when a task closes.
Branch: agent/gh100-admin-layer
Task: GH-100 admin layer (plan: .agent/plan.md)
Status: implemented, reviewed, fixes applied. Draft PR #8. Waiting on human: policy.sh line, final merge.

## Progress
- Docs: gh100-map.md (39 skills), admin-runbook.md
- scripts/admin: 3 read-only audits, 2 dry-run appliers with --apply guard, offline pin check
- .claude/skills/github-admin, github/actions-allowlist.txt, sync-kit allowlist, CLAUDE.md, SECURITY.md, kit.md
- tests/guardrails.sh: 171 pass now, 180 with the policy line (simulated in a copy)

## Handoffs
- claude (implementer) -> reviewer subagent: verdict needs changes, 11 issues
- reviewer issues 1-8, 10, 11 fixed with tests; 9 (approval not hash-recorded) is for the human

## Failures and root causes
- Audits read 403 as "none" (reasoning error): fixed, gh exit code checked first; tested with failing stub
- pipefail double output (reasoning error): fixed via admin_get/admin_show
- Policy test skipped silently after regex change (reasoning error): condition now greps security-baseline

## Review notes
- Not run on macOS bash 3.2 (not available in the cloud session). No bash 4+ features used.
- Not run against live GitHub. Dry runs first on gh600-lab.
- Code scanning alerts not checked: reviewer token lacks security_events.

# Plan: GH-100 admin layer

- **Risk:** high (adds files under `scripts/` and `github/`; proposes a change to `.agent-policy/policy.sh`, which a human must make)
- **Goal:** Add a GH-100 (GitHub Enterprise Administrator) layer to the kit so every repo built from it practises the admin skills the exam measures, the same way GH-600 and GH-900 are covered. Source: official study guide, skills measured as of July 2026.
- **Scope (paths/files):** `.agent/` `.claude/skills/github-admin/` `CLAUDE.md` `SECURITY.md` `docs/` `github/actions-allowlist.txt` `scripts/admin/` `scripts/setup/sync-kit.sh` `tests/guardrails.sh`
- **Scope detail:**
  - Low risk (in this plan-only PR): `docs/gh100-map.md`, `docs/admin-runbook.md`, `.agent/plan.md`, `.agent/state.md`
  - High risk (after approval): `scripts/admin/lib.sh`, `scripts/admin/access-audit.sh`, `scripts/admin/security-baseline.sh`, `scripts/admin/actions-policy.sh`, `scripts/admin/secrets-audit.sh`, `scripts/admin/usage-report.sh`, `scripts/admin/actions-pin-check.sh`, `github/actions-allowlist.txt`, `scripts/setup/sync-kit.sh` (add new files to its allowlist), `tests/guardrails.sh`, `docs/kit.md`, `CLAUDE.md` (human-only list), `SECURITY.md` (link response plan), `.claude/skills/github-admin/SKILL.md`
  - Human edit only (agents cannot write it): `.agent-policy/policy.sh`
- **Steps:**
  1. Map all 39 GH-100 skills to kit files in `docs/gh100-map.md`. Mark enterprise-only skills as study-only (S) since a personal account cannot practise them.
  2. Write `docs/admin-runbook.md`: identity model, roles, PAT and app policy, rate limits, security response plan, support boundaries, deployment and licensing models, runners, secrets.
  3. (after approval) Add `scripts/admin/*`. Read-only audits: access, secrets (names and age only, never values), Actions usage and cost. Dry-run-by-default appliers: security baseline, Actions policy (selected actions, SHA pinning required, fork PR approval, artifact retention). Offline check: every `uses:` pinned to a full SHA and on the allowlist.
  4. (after approval) Add tests: bash syntax, argument handling exit codes, pin check against the kit's own workflows, policy blocks agents from running `scripts/admin/` appliers. Tests use a stub `gh` on PATH, no network.
  5. (after approval) Add the `github-admin` Claude Code skill under `.claude/skills/` so agents in every downstream repo follow the admin rules.
  6. Human: extend `HUMAN_ONLY_SCRIPTS_RE` in `.agent-policy/policy.sh`. Proposed value:
     `scripts/(agent/(approve-plan|close-task)|setup/(apply-github-settings|sync-kit)|release)\.sh|scripts/admin/(security-baseline|actions-policy)\.sh.*--apply`
     Agents keep the dry runs and read-only audits. This also closes an existing gap: `CLAUDE.md` calls `release.sh` and `sync-kit.sh` human-only, but the current regex does not block them.
- **Success criteria (verifiable):**
  - [ ] `tests/guardrails.sh` ends with `Failed: 0`, including the new admin checks
  - [ ] Intent signal: every GH-100 skill row in `docs/gh100-map.md` points to a file that exists or is marked S with a lab note
  - [ ] Appliers change nothing without `--apply`; audits never print secret values
  - [ ] Only files in scope changed
- **Risks + mitigations:**
  - Some APIs (artifact retention, fork PR approval, SHA pinning) are newer or plan-gated. Each apply step reports failure and continues instead of aborting.
  - Not tested against live GitHub from this session. Scripts are tested with a stub `gh`; first live run goes on gh600-lab with the dry run.
  - `sha_pinning_required` would break any downstream repo that uses tag-pinned actions. The pin check runs first and the applier refuses to turn it on while unpinned `uses:` exist.
- **Rollback / escalation plan:** `git revert` the merge commit. Settings applied by the appliers are reversed in the repo's Settings or by re-running with the old values (the dry run prints current values first).

Approved: yes. Chris approved in chat on 2026-11-08 08:29 ET. approve-plan.sh was not run (cloud session, no local .agent-control).

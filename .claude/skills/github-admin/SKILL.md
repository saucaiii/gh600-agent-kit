---
name: github-admin
description: Use when a task touches GitHub repo, org, or enterprise settings: access and roles, tokens and apps, security features, Actions policy, runners, secrets, or usage and cost. Follows GH-100 and this kit's admin scripts.
---

# GitHub admin (GH-100)

Settings changes are **critical risk** in this repo (`CLAUDE.md`): you prepare, a human executes. Reference: `docs/admin-runbook.md`, skill map: `docs/gh100-map.md`.

## What you may run

| Script | Does | Who runs it |
| --- | --- | --- |
| `scripts/admin/access-audit.sh owner/repo [--org ORG]` | Collaborators, invites, deploy keys, webhooks, rulesets, environments, org 2FA | You (read-only) |
| `scripts/admin/secrets-audit.sh owner/repo` | Secret names, scope, age. Never values | You (read-only) |
| `scripts/admin/usage-report.sh owner/repo [--days N]` | Actions runs, failure rate, run and wait time, cache, artifacts | You (read-only) |
| `scripts/admin/actions-pin-check.sh` | Every `uses:` pinned to a full SHA and allowlisted. Offline | You |
| `scripts/admin/security-baseline.sh owner/repo` | Alerts, Dependabot updates, private reporting, secret scanning | Dry run: you. `--apply`: human only |
| `scripts/admin/actions-policy.sh owner/repo` | Selected actions, SHA pinning, read-only token, fork PR approval, retention | Dry run: you. `--apply`: human only |
| `scripts/setup/apply-github-settings.sh` | Ruleset, production environment, token defaults | Human only |

## Rules

1. Read before you change. Run the audit or the dry run, put its output in the PR or `.agent/state.md`, and hand the `--apply` command to the human.
2. Never print, copy, or guess secret values. Refer to secrets by name.
3. Least privilege: lowest role, teams over individuals, fine-grained PATs with expiry, GitHub Apps over OAuth Apps, environment secrets or OIDC over repo secrets.
4. A new third-party action means a pinned SHA plus a line in `github/actions-allowlist.txt`. Both are high risk: plan first.
5. A 403 on a free personal account often means the feature needs a public repo or a paid plan. Report it; do not retry.
6. Check numbers (rate limits, retention, prices) against GitHub Docs before stating them as facts.

## Reporting

Audit findings: what, where, risk level, and the exact fix command marked "human runs this". Settings changes: current value, new value, command, rollback.

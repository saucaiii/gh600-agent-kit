# GH-100 skills → kit files

Every skill from the [official GH-100 study guide](https://learn.microsoft.com/en-us/credentials/certifications/resources/study-guides/gh-100) (GitHub Enterprise Administrator, skills measured as of July 2026), mapped to where this kit practises it. Same idea as [`exam-map.md`](exam-map.md) for GH-600: open the file, explain what it does, then break it on purpose.

Legend: **E** = enforced · **G** = guidance · **T** = tooling (script you run) · **S** = study only. S rows are enterprise or organization features a personal account cannot turn on. Read [`admin-runbook.md`](admin-runbook.md) for them and practise in a free trial org if you can.

Scripts live in `scripts/admin/`. Read-only audits are safe for anyone; `security-baseline.sh` and `actions-policy.sh` are dry run by default and human-only with `--apply`.

Exam facts: 700/1000 to pass. Weights below are the official ones.

## Domain 1: Manage GitHub identities and access (15–20%)

| Skill | Where | Type |
| --- | --- | --- |
| Managed users vs personal accounts | runbook → Identity | S |
| Configure and enforce SAML SSO and 2FA | runbook → Identity; `access-audit.sh --org` lists members without 2FA | S / T |
| SCIM vs team synchronization | runbook → Identity | S |
| Choose and configure identity providers | runbook → Identity | S |
| GitHub's authentication and authorization model | runbook → Auth model | G |
| Configure organization and repository roles | runbook → Roles; `access-audit.sh` shows each collaborator's role | T |
| Define and manage enterprise teams | runbook → Roles | S |
| Audit access and permissions | `access-audit.sh` (collaborators, invites, deploy keys, webhooks, rulesets, environments) | T |
| Manage settings, policies, rulesets, and roles | `github/ruleset-main*.json`, `apply-github-settings.sh` | E |

## Domain 2: Administer GitHub Enterprise environment (10–15%)

| Skill | Where | Type |
| --- | --- | --- |
| Issues resolvable by admins vs GitHub Support | runbook → Support | G |
| Generate support bundles and diagnostics | runbook → Support (`ghe-support-bundle`, GHES only) | S |
| Recommend standards for developer processes | `CLAUDE.md` → Branches and commits | G |
| Standards for workflows, branching, reviews, releases | `CLAUDE.md`, PR template, rulesets, `release.sh` | E |
| Deployment scenarios (GHEC + EMU, GHEC + data residency + EMU, GHEC personal accounts, GHES) | runbook → Deployment and licensing | S |
| Licensing and billing models | runbook → Deployment and licensing | G |
| Monitor license usage and consumption | `usage-report.sh` (personal billing where the API allows) | T |

## Domain 3: Implement secure software development and compliance (25–30%)

The biggest domain. Spend the most lab time here.

| Skill | Where | Type |
| --- | --- | --- |
| Define organization and enterprise policies | runbook → Policies | S |
| Strengthen security posture and data protection | `security-baseline.sh`; `SECURITY.md` | T |
| Audit logging and reporting | `.agent-control/audit.log` + `audit-report.sh` (agent side); runbook → Audit log (org/enterprise side) | T / S |
| Vulnerability alerts, secret scanning, CodeQL | `security-baseline.sh`; `ci.yml` codeql job | E |
| Dependabot and security advisories | `.github/dependabot.yml`; `security-baseline.sh` enables security updates and private reporting | E |
| Define and implement a security response plan | runbook → Security response plan; `SECURITY.md` | G |
| Configure personal access tokens | runbook → Tokens (fine-grained, expiry, least scope); kit's MCP tokens follow it | G |
| Rate limits for PATs and GitHub Apps | runbook → Rate limits | G |
| GitHub Apps vs OAuth Apps | runbook → Apps | G |
| Approve or deny app usage by policy | runbook → Apps (org app policy) | S |

## Domain 4: Manage GitHub Actions (20–25%)

| Skill | Where | Type |
| --- | --- | --- |
| Reuse of actions and workflows across the enterprise | runbook → Actions reuse; `actions-policy.sh` sets workflow access level | T |
| Organizational policies for Actions | `actions-policy.sh` (selected actions, SHA pinning, fork PR approval, retention); `github/actions-allowlist.txt` | T |
| Runner groups, GitHub-hosted vs self-hosted | runbook → Runners | S |
| IP allow lists and networking (incl. Azure private networking) | runbook → Runners | S |
| Monitor and troubleshoot runner performance | `usage-report.sh` (queue and run time per workflow) | T |
| Scope and access for secrets | runbook → Secrets; `secrets-audit.sh` | T |
| Secrets at org and repo levels | `secrets-audit.sh` (repo, environment, Dependabot, org secrets visible to the repo) | T |
| Integrate third-party vaults | runbook → Secrets (OIDC to cloud vaults) | G |

The offline pin check (`actions-pin-check.sh`) runs inside `tests/guardrails.sh`, so an unpinned or non-allowlisted `uses:` fails the kit's self-test.

## Domain 5: Monitor and optimize GitHub usage (10–15%)

| Skill | Where | Type |
| --- | --- | --- |
| Analyze audit logs and API usage | `audit-report.sh`; runbook → Audit log; `gh api rate_limit` | T |
| Admin responsibilities vs GitHub Support, diagnostics | runbook → Support | G |
| Usage patterns: adoption, activity, underused features | `usage-report.sh` | T |
| Interpret usage reports for metered products | `usage-report.sh`; runbook → Deployment and licensing | T |
| License and resource optimization | `usage-report.sh` flags (failure rate, cache size, artifact size) | T |

## Coverage

39 skills. 27 practised in the kit (E, G or T), 12 study-only or partly study-only because they need an organization or enterprise. For the S rows, a free GitHub Team trial org covers roles, teams, app policy, Actions policy at org level, and the org audit log. EMU, SCIM, data residency and GHES need an enterprise account or a GHES trial.

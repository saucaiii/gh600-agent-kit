# Admin runbook (GH-100)

How this kit expects a GitHub account, repo, or org to be administered. Written against the [GH-100 study guide](https://learn.microsoft.com/en-us/credentials/certifications/resources/study-guides/gh-100). Sections marked *(org/enterprise)* describe features a personal account cannot turn on; learn them here, practise them in a trial org. Check GitHub Docs before relying on any number here: limits and plan availability change.

## Identity *(mostly org/enterprise)*

| Model | Who owns the account | Typical setup |
| --- | --- | --- |
| Personal accounts | The developer | Joins orgs as a member. Org can require SAML SSO for org resources and 2FA. |
| Enterprise Managed Users (EMU) | The company's IdP | Accounts are created, named and removed by the IdP through SCIM. Users cannot create public content or work outside the enterprise. |

- **SAML SSO** authenticates. **SCIM** provisions and deprovisions accounts (create, update, remove). **Team synchronization** maps IdP groups to GitHub teams. SCIM is what removes access when someone leaves; SAML alone does not.
- Supported IdPs with partner support include Microsoft Entra ID, Okta and PingFederate. Other SAML 2.0 / SCIM 2.0 IdPs can work with less support.
- **2FA:** required for everyone in this kit's world. On your own account, use a passkey or security key plus an authenticator app. In an org, require 2FA in org settings and audit with `scripts/admin/access-audit.sh --org <org>`.

## Auth model

Authentication says who you are (password plus 2FA, passkey, SSH key, token). Authorization says what you can do (role on a repo, org, or enterprise, plus token scopes or fine-grained permissions). A request succeeds only when both allow it: a token with `repo` scope still cannot write to a repo where its user is read-only.

## Roles

| Level | Roles (least to most) |
| --- | --- |
| Repository | Read, Triage, Write, Maintain, Admin. Orgs can add custom repository roles. |
| Organization | Member, Moderator, Billing manager, Security manager, Owner. Plus outside collaborators (repo access only). |
| Enterprise | Member, Billing manager, Owner. Enterprise teams can be assigned across orgs. |

Rule: give the lowest role that does the job, prefer teams over individual grants, and review with `access-audit.sh` every month. Base permission for org members should be Read or None, not Write.

## Policies *(org/enterprise)*

Enterprise policies override org settings; an org can only be stricter where the enterprise leaves it a choice. Policies to know: repository creation and visibility, forking, base permissions, Actions allow lists, Copilot, code security, and app installation. Rulesets can be set at repo, org, or enterprise level and stack; the strictest rule wins.

## Tokens

- Use **fine-grained PATs**: one repo or the fewest repos possible, the fewest permissions, an expiry date (90 days or less). Classic PATs only when an API does not support fine-grained yet.
- The kit's own tokens follow this: `GITHUB_MCP_PAT` is read-only on one repo; `COPILOT_CLI_TOKEN` only has "Copilot Requests".
- Orgs can require approval for fine-grained PATs and restrict classic PATs. Review active tokens in the org's Personal access tokens settings.
- Rotate on a schedule; `scripts/admin/secrets-audit.sh` flags stored secrets older than 90 days.

## Apps

| | GitHub App | OAuth App |
| --- | --- | --- |
| Acts as | Itself (installation) or on behalf of a user | Always the user |
| Permissions | Fine-grained, chosen per app, per installed repo | Broad scopes |
| Tokens | Short-lived installation tokens (1 hour) | Long-lived user tokens |
| Rate limit | Scales with installation size | Shares the user's limit |

Prefer GitHub Apps for automation. Org owners can restrict OAuth App access and require approval before members install apps.

## Rate limits

Per hour, from GitHub's REST docs (checked November 2026):

| Caller | Limit |
| --- | --- |
| Unauthenticated | 60 per IP |
| PAT, OAuth App user token | 5,000 (shared across that user's tokens) |
| GitHub App installation | 5,000 base, +50 per repo and per org user beyond 20, max 12,500; 15,000 on GHEC |
| `GITHUB_TOKEN` in Actions | 1,000 per repo; 15,000 for GHEC resources |

Secondary limits: 100 concurrent requests, 900 points per minute on REST (GET costs 1, writes cost 5), and roughly 80 content-creating requests per minute. Check yours with `gh api rate_limit`.

## Security response plan

Used by `SECURITY.md`. Steps for any vulnerability, leaked secret, or compromised account:

1. **Triage (same day).** Confirm it is real. Assign one owner. Severity: critical if funds, keys, secrets, or personal data are exposed.
2. **Contain.** Leaked secret: revoke and rotate at the provider first, then remove it from code (removing it from git history does not un-leak it). Compromised account or token: revoke sessions and tokens, check the audit log for what it did.
3. **Fix privately.** Use a draft security advisory and its temporary private fork. Request a CVE through the advisory if it is a public project.
4. **Release.** Ship the fix, publish the advisory, tag the release with `scripts/release.sh`.
5. **Review.** Write what happened and what changes (a rule, a check, a scope) in `.agent/decisions.md`.

## Support

Admins handle: access, settings, policies, billing, user offboarding, Actions and runner config, and anything in the audit log. GitHub Support handles: platform outages, bugs, account recovery, billing disputes, and GHES problems that need a **support bundle**. On GHES generate it with `ghe-support-bundle` or from the Management Console. On GHEC there is no bundle; send the request ID, timestamps, and audit log entries. Check githubstatus.com before opening a ticket.

## Deployment and licensing

| Scenario | Identity | Data location |
| --- | --- | --- |
| GHEC with personal accounts | Personal accounts, optional SAML | github.com |
| GHEC with EMU | IdP-managed | github.com |
| GHEC with data residency + EMU | IdP-managed | GHE.com in a chosen region |
| GHES | Built-in, LDAP, CAS or SAML | Your servers or cloud |

Enterprise licensing is per unique user (one seat covers GHEC and GHES for the same person). Metered products bill on usage: Actions minutes and storage beyond the included amount, Packages, Codespaces, Git LFS, Copilot, and GitHub Advanced Security (Secret Protection and Code Security, billed per active committer). Use `scripts/admin/usage-report.sh` and the billing usage page to spot waste: idle seats, high Actions failure rates, oversized artifacts and caches.

## Audit log *(org/enterprise)*

Org and enterprise audit logs record who did what: membership, permission, settings, token, and app events. Retention on github.com: 180 days for most events, 7 days for Git events; stream to a SIEM for longer. Query with `gh api -X GET orgs/<org>/audit-log -f phrase='action:repo.create'` (`-f` alone makes gh send a POST). This kit's agent-side equivalent is `.agent-control/audit.log`, read with `scripts/agent/audit-report.sh`.

## Actions reuse

Share actions and reusable workflows from a dedicated internal or private repo, then allow access from other repos in that repo's Actions settings ("Accessible from repositories in the organization"). Call reusable workflows with `uses: org/repo/.github/workflows/x.yml@<sha>`. Org policy decides which third-party actions are allowed; this kit allows only GitHub-owned actions plus anything listed in `github/actions-allowlist.txt`, and requires full SHA pins.

## Runners *(mostly org/enterprise)*

- **GitHub-hosted:** clean VM per job, patched by GitHub, billed by the minute on private repos. Larger runners add more CPU, static IPs, and Azure private networking.
- **Self-hosted:** your machine, your patching. Never attach one to a public repo: a fork PR could run code on it. Use ephemeral runners where possible.
- **Runner groups** control which repos and workflows may use which runners.
- **IP allow lists** on an org or enterprise also block GitHub-hosted runners unless you allow their IPs or use larger runners with static IPs or Azure private networking.
- Troubleshoot: queue time (no matching runner or group access), job logs, runner diagnostic logs (`_diag/` on self-hosted).

## Secrets

| Scope | Visible to |
| --- | --- |
| Organization | Repos you select (all, private, or a list) |
| Repository | Every workflow in that repo |
| Environment | Only jobs that target that environment, after its protection rules pass |
| Dependabot | Only Dependabot-triggered workflows |

Put deploy credentials in environment secrets behind reviewers (the kit's `production` environment does this). Better still, use **OIDC**: the workflow gets a short-lived token from the cloud provider or a vault (Azure Key Vault, AWS, HashiCorp Vault) and no long-lived secret is stored in GitHub at all.

#!/usr/bin/env bash
# Read-only access audit. Changes nothing. Prints a Markdown report.
#   Repo: collaborators and roles, pending invitations, deploy keys,
#         webhooks, rulesets, environments and their protection rules.
#   Org (--org): 2FA requirement, base permission, members without 2FA,
#         outside collaborators.
#
# Usage: scripts/admin/access-audit.sh owner/repo [--org ORG] [--out report.md]
# Exit codes: 0 done, 2 bad arguments, 3 gh/jq missing or not signed in, 4 repo unreachable.
# Some sections need admin on the repo or a paid plan; those print "not available".
# GH-100: audit access and permissions; configure org and repo roles; 2FA.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

repo=""; org=""; out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --org) [ "$#" -ge 2 ] || admin_usage_exit "--org needs a name"; org="$2"; shift 2 ;;
    --out) [ "$#" -ge 2 ] || admin_usage_exit "--out needs a path"; out="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    -*) admin_usage_exit "Unknown option: $1" ;;
    *) [ -z "$repo" ] || admin_usage_exit "Only one repo per run."; repo="$1"; shift ;;
  esac
done
[ -n "$repo" ] || admin_usage_exit "Usage: $0 owner/repo [--org ORG] [--out report.md]"
admin_need_tools
admin_check_repo "$repo"

# list <endpoint> -> one JSON array (pages merged), or empty when the API refuses (shown as not available)
list() { admin_list "$1" || true; }
na() { echo "_Not available: needs repo admin, a paid plan, or org access._"; }

findings=0
report() {
  echo "# Access audit: $repo"
  echo
  echo "Generated $(date -u +%Y-%m-%dT%H:%MZ). Read-only. Review monthly and after anyone leaves."
  echo

  echo "## Collaborators"
  c="$(list "repos/$repo/collaborators?affiliation=all&per_page=100")"
  if [ -n "$c" ]; then
    echo "| Login | Role |"; echo "| --- | --- |"
    echo "$c" | jq -r '.[] | "| \(.login) | \(.role_name // "unknown") |"'
    admins="$(echo "$c" | jq '[.[] | select(.role_name=="admin")] | length')"
    echo; echo "Admins: $admins. Keep admin to the people who change settings; everyone else Write or lower."
    if [ "$admins" -gt 2 ]; then echo "- **Finding:** $admins admins. Reduce to the fewest who need it."; findings=$((findings+1)); fi
  else na; fi
  echo

  echo "## Pending invitations"
  i="$(list "repos/$repo/invitations?per_page=100")"
  if [ -n "$i" ]; then
    n="$(echo "$i" | jq length)"
    if [ "$n" -eq 0 ]; then echo "None."; else
      echo "| Invitee | Permission | Sent |"; echo "| --- | --- | --- |"
      echo "$i" | jq -r '.[] | "| \(.invitee.login // .email // "unknown") | \(.permissions) | \(.created_at[0:10]) |"'
      echo; echo "- **Finding:** $n open invitation(s). Cancel any that are not expected."; findings=$((findings+1))
    fi
  else na; fi
  echo

  echo "## Deploy keys"
  k="$(list "repos/$repo/keys?per_page=100")"
  if [ -n "$k" ]; then
    if [ "$(echo "$k" | jq length)" -eq 0 ]; then echo "None."; else
      echo "| Title | Access | Added | Last used |"; echo "| --- | --- | --- | --- |"
      echo "$k" | jq -r '.[] | "| \(.title) | \(if .read_only then "read" else "WRITE" end) | \(.created_at[0:10]) | \((.last_used // "unknown")[0:10]) |"'
      w="$(echo "$k" | jq '[.[] | select(.read_only|not)] | length')"
      if [ "$w" -gt 0 ]; then echo; echo "- **Finding:** $w deploy key(s) can write. Use read-only keys unless a deploy needs to push."; findings=$((findings+1)); fi
    fi
  else na; fi
  echo

  echo "## Webhooks"
  h="$(list "repos/$repo/hooks?per_page=100")"
  if [ -n "$h" ]; then
    if [ "$(echo "$h" | jq length)" -eq 0 ]; then echo "None."; else
      echo "| Host | Active | Secret set | TLS verify |"; echo "| --- | --- | --- | --- |"
      echo "$h" | jq -r '.[] | "| \((.config.url // "") | sub("^https?://";"") | sub("^[^@/]*@";"") | split("/")[0]) | \(.active) | \(if .config.secret then "yes" else "NO" end) | \(if (.config.insecure_ssl|tostring)=="1" then "OFF" else "on" end) |"'
      weak="$(echo "$h" | jq '[.[] | select((.config.secret|not) or ((.config.insecure_ssl|tostring)=="1"))] | length')"
      if [ "$weak" -gt 0 ]; then echo; echo "- **Finding:** $weak webhook(s) without a secret or with TLS verification off."; findings=$((findings+1)); fi
    fi
  else na; fi
  echo

  echo "## Rulesets"
  r="$(list "repos/$repo/rulesets?per_page=100")"
  if [ -n "$r" ]; then
    if [ "$(echo "$r" | jq length)" -eq 0 ]; then
      echo "None. Apply the kit's ruleset with scripts/setup/apply-github-settings.sh."
      echo; echo "- **Finding:** default branch has no ruleset."; findings=$((findings+1))
    else
      echo "| Name | Enforcement | Level |"; echo "| --- | --- | --- |"
      echo "$r" | jq -r '.[] | "| \(.name) | \(.enforcement) | \(.source_type // "Repository") |"'
    fi
  else na; fi
  echo

  echo "## Environments"
  e="$(admin_list "repos/$repo/environments?per_page=100" environments || true)"
  if [ -n "$e" ]; then
    if [ "$(echo "$e" | jq 'length')" -eq 0 ]; then echo "None."; else
      echo "| Environment | Protection rules |"; echo "| --- | --- |"
      echo "$e" | jq -r '.[] | "| \(.name) | \([.protection_rules[]?.type] | if length==0 then "NONE" else join(", ") end) |"'
    fi
  else na; fi
  echo

  if [ -n "$org" ]; then
    echo "## Organization: $org"
    o="$(admin_get "orgs/$org" || true)"
    if [ -n "$o" ]; then
      echo "- 2FA required: $(echo "$o" | jq -r 'if .two_factor_requirement_enabled == null then "unknown (needs owner)" else .two_factor_requirement_enabled end')"
      echo "- Base permission for members: $(echo "$o" | jq -r '.default_repository_permission // "unknown (needs owner)"')"
      if [ "$(echo "$o" | jq -r '.two_factor_requirement_enabled')" = "false" ]; then echo "- **Finding:** org does not require 2FA."; findings=$((findings+1)); fi
      case "$(echo "$o" | jq -r '.default_repository_permission // ""')" in write|admin) echo "- **Finding:** base permission is above read."; findings=$((findings+1)) ;; esac
    else na; fi
    m="$(list "orgs/$org/members?filter=2fa_disabled&per_page=100")"
    if [ -z "$m" ]; then echo "- Members without 2FA: not available (needs org owner)"; else
      n="$(echo "$m" | jq length)"; echo "- Members without 2FA: $n"
      if [ "$n" -gt 0 ]; then echo "$m" | jq -r '.[] | "  - \(.login)"'; findings=$((findings+1)); fi
    fi
    oc="$(list "orgs/$org/outside_collaborators?per_page=100")"
    if [ -z "$oc" ]; then echo "- Outside collaborators: not available (needs org owner)"; else echo "- Outside collaborators: $(echo "$oc" | jq length)"; echo "$oc" | jq -r '.[] | "  - \(.login)"'; fi
    echo
  fi

  echo "## Summary"
  echo "Findings: $findings. Fixes are settings changes (critical risk): a human makes them."
}

if [ -n "$out" ]; then report > "$out"; echo "Wrote $out"; else report; fi
exit 0

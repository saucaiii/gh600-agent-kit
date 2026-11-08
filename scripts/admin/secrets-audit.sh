#!/usr/bin/env bash
# Read-only secrets inventory. Prints secret NAMES, scope, and age. Never values
# (the API does not return them, and this script never asks).
#   Scopes: repo Actions secrets, environment secrets, Dependabot secrets,
#           org secrets shared with this repo, repo variables (names only).
#   Flags secrets older than --max-age-days (default 90) for rotation.
#
# Usage: scripts/admin/secrets-audit.sh owner/repo [--max-age-days N]
# Exit codes: 0 done, 2 bad arguments, 3 gh/jq missing or not signed in, 4 repo unreachable.
# GH-100: define scope and access for secrets; configure secrets at org and repo levels.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

repo=""; max=90
while [ "$#" -gt 0 ]; do
  case "$1" in
    --max-age-days) [ "$#" -ge 2 ] || admin_usage_exit "--max-age-days needs a number"; max="$2"; shift 2 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    -*) admin_usage_exit "Unknown option: $1" ;;
    *) [ -z "$repo" ] || admin_usage_exit "Only one repo per run."; repo="$1"; shift ;;
  esac
done
[ -n "$repo" ] || admin_usage_exit "Usage: $0 owner/repo [--max-age-days N]"
printf '%s' "$max" | grep -Eq '^[1-9][0-9]*$' || admin_usage_exit "--max-age-days must be a positive whole number."
admin_need_tools
admin_check_repo "$repo"

stale=0; count=0
# rows <scope> <endpoint> <array-key>
rows() {
  json="$(gh api --paginate "$2" 2>/dev/null | jq -s --arg k "$3" 'map(.[$k] // []) | add // []' 2>/dev/null)"
  if [ -z "$json" ]; then echo "| $1 | _not available_ | | |"; return; fi
  out="$(echo "$json" | jq -r --arg s "$1" --argjson max "$max" '
    .[] | ((now - ((.updated_at // .created_at // "1970-01-01T00:00:00Z") | sub("\\.[0-9]+Z$";"Z") | fromdateiso8601)) / 86400 | floor) as $age
    | "| \($s) | \(.name) | \($age) | \(if $age > $max then "ROTATE" else "ok" end) |"')"
  [ -z "$out" ] && return
  echo "$out"
  count=$((count + $(printf '%s\n' "$out" | grep -c '^|')))
  stale=$((stale + $(printf '%s\n' "$out" | grep -c 'ROTATE |' || true)))
}

echo "# Secrets inventory: $repo"
echo
echo "Names and ages only. Rotate anything older than $max days at its provider first, then update it here (a human runs gh secret set)."
echo
echo "| Scope | Name | Age (days) | Status |"
echo "| --- | --- | --- | --- |"
rows "repo" "repos/$repo/actions/secrets?per_page=100" secrets
rows "dependabot" "repos/$repo/dependabot/secrets?per_page=100" secrets
rows "org (shared)" "repos/$repo/actions/organization-secrets?per_page=100" secrets
envs="$(gh api "repos/$repo/environments" 2>/dev/null | jq -r '.environments[]?.name' 2>/dev/null || true)"
if [ -n "$envs" ]; then
  while IFS= read -r env; do
    [ -z "$env" ] && continue
    enc="$(jq -rn --arg e "$env" '$e|@uri')"
    rows "env: $env" "repos/$repo/environments/$enc/secrets?per_page=100" secrets
  done <<EOF
$envs
EOF
fi
echo
vars="$(gh api --paginate "repos/$repo/actions/variables?per_page=100" 2>/dev/null | jq -r -s 'map(.variables // []) | add // [] | map(.name) | join(", ")' 2>/dev/null || true)"
echo "Variables (not secret, names only): ${vars:-none}"
echo
echo "Secrets: $count. Due for rotation: $stale."
echo "Prefer OIDC to cloud providers and vaults over stored secrets; keep deploy credentials in environment secrets behind reviewers."
exit 0

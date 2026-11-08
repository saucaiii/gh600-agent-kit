#!/usr/bin/env bash
# Apply the kit's GitHub Actions policy to a repo. Human-only. Dry run by default.
#   1. Actions enabled, allowed actions = selected, SHA pinning required
#      (only if scripts/admin/actions-pin-check.sh passes on this checkout)
#   2. Selected actions: GitHub-owned + patterns in github/actions-allowlist.txt
#   3. Default GITHUB_TOKEN read-only; Actions cannot approve PRs
#   4. Fork PRs from external contributors need approval before workflows run
#   5. Artifact and log retention (default 30 days)
#   6. Reusable workflow access (only with --share-workflows user|organization)
#
# Usage: scripts/admin/actions-policy.sh owner/repo [--apply] [--retention-days N]
#                                        [--share-workflows none|user|organization]
# Run from a checkout of the repo so the pin check sees its workflows.
# Exit codes: 0 done, 2 bad arguments, 3 gh/jq missing or not signed in, 4 repo unreachable.
# GH-100: organizational policies for Actions; reuse of actions and workflows.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

repo=""; APPLY=false; days=30; share=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply) APPLY=true; shift ;;
    --retention-days) [ "$#" -ge 2 ] || admin_usage_exit "--retention-days needs a number"; days="$2"; shift 2 ;;
    --share-workflows) [ "$#" -ge 2 ] || admin_usage_exit "--share-workflows needs none|user|organization"; share="$2"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    -*) admin_usage_exit "Unknown option: $1" ;;
    *) [ -z "$repo" ] || admin_usage_exit "Only one repo per run."; repo="$1"; shift ;;
  esac
done
[ -n "$repo" ] || admin_usage_exit "Usage: $0 owner/repo [--apply] [--retention-days N] [--share-workflows none|user|organization]"
printf '%s' "$days" | grep -Eq '^[1-9][0-9]*$' || admin_usage_exit "--retention-days must be a positive whole number."
case "$share" in ""|none|user|organization) ;; *) admin_usage_exit "--share-workflows must be none, user, or organization." ;; esac
admin_need_tools
admin_check_repo "$repo"
export APPLY

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
allowlist="$root/github/actions-allowlist.txt"
[ -f "$allowlist" ] || allowlist="$here/../../github/actions-allowlist.txt"

echo "Repo: $repo   Mode: $($APPLY && echo APPLY || echo DRY-RUN)"
echo
echo "Current state:"
echo "  permissions:        $(admin_show "repos/$repo/actions/permissions" tojson)"
echo "  selected actions:   $(admin_show "repos/$repo/actions/permissions/selected-actions" tojson)"
echo "  workflow token:     $(admin_show "repos/$repo/actions/permissions/workflow" tojson)"
echo "  fork PR approval:   $(admin_show "repos/$repo/actions/permissions/fork-pr-contributor-approval" tojson)"
echo "  retention:          $(admin_show "repos/$repo/actions/permissions/artifact-and-log-retention" tojson)"
echo

pin=true
origin="$(git -C "$root" remote get-url origin 2>/dev/null || true)"
case "$origin" in
  *"github.com/$repo"|*"github.com/$repo.git"|*"github.com:$repo"|*"github.com:$repo.git") ;;
  *) pin=false; echo "  This checkout's origin ('${origin:-none}') is not $repo, so its workflows say nothing about $repo."
     echo "  SHA pinning is left unchanged. Run from a checkout of $repo to turn it on." ;;
esac
if ! $pin; then :
elif [ -d "$root/.github/workflows" ]; then
  if ! "$here/actions-pin-check.sh" --dir "$root/.github/workflows" --allowlist "$allowlist"; then
    pin=false
    echo "  SHA pinning is left unchanged: fix the lines above first, then re-run."
  fi
else
  pin=false
  echo "  No .github/workflows here, so SHA pinning is left unchanged."
fi
echo

tmpd="$(mktemp -d)"; trap 'rm -rf "$tmpd"' EXIT
patterns="$(sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$allowlist" 2>/dev/null | grep -v '^$' || true)"
printf '%s\n' "$patterns" | jq -R . | jq -s '{github_owned_allowed: true, verified_allowed: false, patterns_allowed: map(select(length>0))}' > "$tmpd/selected.json"

admin_confirm_apply "$repo"
echo "# 1. Allowed actions = selected; SHA pinning: $($pin && echo required || echo 'left as is')"
if $pin; then
  admin_run gh api -X PUT "repos/$repo/actions/permissions" -F enabled=true -f allowed_actions=selected -F sha_pinning_required=true
else
  admin_run gh api -X PUT "repos/$repo/actions/permissions" -F enabled=true -f allowed_actions=selected
fi
echo "# 2. Selected actions: $(jq -c . "$tmpd/selected.json")"
admin_run gh api -X PUT "repos/$repo/actions/permissions/selected-actions" --input "$tmpd/selected.json"
echo "# 3. Default GITHUB_TOKEN read-only; Actions cannot approve PRs"
admin_run gh api -X PUT "repos/$repo/actions/permissions/workflow" -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
echo "# 4. Approval required for workflows on PRs from external contributors"
admin_run gh api -X PUT "repos/$repo/actions/permissions/fork-pr-contributor-approval" -f approval_policy=all_external_contributors
echo "# 5. Artifact and log retention: $days days"
admin_run gh api -X PUT "repos/$repo/actions/permissions/artifact-and-log-retention" -F "days=$days"
echo "# 6. Reusable workflow access"
if [ -n "$share" ]; then
  admin_run gh api -X PUT "repos/$repo/actions/permissions/access" -f "access_level=$share"
else
  echo "  skipped. Pass --share-workflows user (personal repos) or organization on the repo that holds shared workflows."
fi

echo
echo "Patterns apply on public repos only; private repos rely on the pin check in tests/guardrails.sh."
echo "Roll back by re-running the PUTs with the values printed under Current state."
$APPLY || echo "Dry run only. Re-run with --apply to make these changes."
exit 0

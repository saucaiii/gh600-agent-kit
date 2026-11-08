#!/usr/bin/env bash
# Turn on the repository security features. Human-only. Dry run by default.
#   1. Vulnerability alerts (Dependabot alerts)
#   2. Dependabot security updates
#   3. Private vulnerability reporting (used by SECURITY.md)
#   4. Secret scanning + push protection
#   5. CodeQL default setup, only with --codeql-default. The kit's ci.yml already
#      runs CodeQL as an advanced workflow, and GitHub refuses default setup while
#      an advanced CodeQL workflow exists. Use one or the other.
#
# Usage: scripts/admin/security-baseline.sh owner/repo [--apply] [--codeql-default]
# Exit codes: 0 done, 2 bad arguments, 3 gh/jq missing or not signed in, 4 repo unreachable.
# Steps that need GitHub Advanced Security or a public repo report the error and continue.
# GH-100: configure vulnerability alerts, secret scanning, and CodeQL; Dependabot; security posture.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

repo=""; APPLY=false; codeql=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply) APPLY=true; shift ;;
    --codeql-default) codeql=true; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    -*) admin_usage_exit "Unknown option: $1" ;;
    *) [ -z "$repo" ] || admin_usage_exit "Only one repo per run."; repo="$1"; shift ;;
  esac
done
[ -n "$repo" ] || admin_usage_exit "Usage: $0 owner/repo [--apply] [--codeql-default]"
admin_need_tools
admin_check_repo "$repo"
export APPLY
admin_confirm_apply "$repo"

onoff() { if gh api "$1" >/dev/null 2>&1; then echo enabled; else echo "disabled or unknown"; fi; }
field() { admin_show "$1" "$2"; }
nn() { echo "if $1 == null then \"unknown\" else $1 end"; }   # jq: keep false as false

echo "Repo: $repo   Mode: $($APPLY && echo APPLY || echo DRY-RUN)"
echo
echo "Current state:"
echo "  vulnerability alerts:          $(onoff "repos/$repo/vulnerability-alerts")"
echo "  Dependabot security updates:   $(field "repos/$repo/automated-security-fixes" "$(nn .enabled)")"
echo "  private vulnerability reports: $(field "repos/$repo/private-vulnerability-reporting" "$(nn .enabled)")"
echo "  secret scanning:               $(field "repos/$repo" '.security_and_analysis.secret_scanning.status // "unknown"')"
echo "  push protection:               $(field "repos/$repo" '.security_and_analysis.secret_scanning_push_protection.status // "unknown"')"
echo "  CodeQL default setup:          $(field "repos/$repo/code-scanning/default-setup" '.state // "unknown"')"
echo

echo "# 1. Vulnerability alerts"
admin_run gh api -X PUT "repos/$repo/vulnerability-alerts"
echo "# 2. Dependabot security updates"
admin_run gh api -X PUT "repos/$repo/automated-security-fixes"
echo "# 3. Private vulnerability reporting"
admin_run gh api -X PUT "repos/$repo/private-vulnerability-reporting"
echo "# 4. Secret scanning + push protection"
admin_run gh api -X PATCH "repos/$repo" \
  -f 'security_and_analysis[secret_scanning][status]=enabled' \
  -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled'
echo "# 5. CodeQL default setup"
if $codeql; then
  echo "  Remove the codeql job from ci.yml first, or GitHub rejects default setup."
  admin_run gh api -X PATCH "repos/$repo/code-scanning/default-setup" -f state=configured
else
  echo "  skipped: ci.yml runs CodeQL (advanced setup). Pass --codeql-default to switch."
fi

echo
echo "Roll back any step with the same path and -X DELETE (1-3), status=disabled (4), or state=not-configured (5)."
$APPLY || echo "Dry run only. Re-run with --apply to make these changes."
exit 0

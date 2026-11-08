#!/usr/bin/env bash
# Shared helpers for the GH-100 admin scripts. Sourced, not run.
# macOS bash 3.2 compatible.
#
# Exit codes used by every admin script:
#   2 bad or missing arguments
#   3 gh or jq missing, or gh not signed in
#   4 repo not found or no access

admin_usage_exit() { echo "$1" >&2; exit 2; }

admin_need_tools() {
  command -v jq >/dev/null 2>&1 || { echo "jq is required (brew install jq)." >&2; exit 3; }
  command -v gh >/dev/null 2>&1 || { echo "GitHub CLI is required (brew install gh)." >&2; exit 3; }
  gh auth status >/dev/null 2>&1 || { echo "Run 'gh auth login' first." >&2; exit 3; }
}

# admin_check_repo owner/repo -> exits 2 on bad format, 4 when unreachable
admin_check_repo() {
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' \
    || admin_usage_exit "Repo must look like owner/repo (got '$1')."
  gh api "repos/$1" --jq .full_name >/dev/null 2>&1 \
    || { echo "Cannot read repos/$1. Check the name and that your token can see it." >&2; exit 4; }
}

# Print a command; run it only when APPLY=true. Never aborts the script.
admin_run() {
  echo "+ $*"
  if [ "${APPLY:-false}" = true ]; then
    if "$@" >/dev/null; then echo "  ok"; else echo "  FAILED or not available on this plan (see message above)"; fi
  fi
}

# Days between an ISO-8601 timestamp and now (whole days).
admin_age_days() { jq -rn --arg t "$1" '((now - ($t | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)) / 86400) | floor'; }

# ISO date N days ago (YYYY-MM-DD), portable across macOS and Linux.
admin_days_ago() { jq -rn --argjson d "$1" '(now - ($d * 86400)) | strftime("%Y-%m-%d")'; }

#!/usr/bin/env bash
# Shared helpers for the GH-100 admin scripts. Sourced, not run.
# macOS bash 3.2 compatible.
#
# Exit codes used by every admin script:
#   2 bad or missing arguments
#   3 gh or jq missing, or gh not signed in
#   4 repo not found or no access
#   5 --apply refused (agent environment or no interactive terminal)
#
# Error handling rule: check gh's exit code BEFORE parsing. A 403/404 is
# "not available", never "none". Never write `gh ... | jq ... || echo x` under
# pipefail: it prints jq's output AND the fallback.

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

# admin_get <endpoint> [gh args...] -> JSON on stdout, or return 1 on any API error.
admin_get() {
  _o="$(gh api "$@" 2>/dev/null)" || return 1
  printf '%s\n' "$_o"
}

# admin_list <endpoint> [key] -> one merged JSON array across pages, or return 1.
# Without key the pages are arrays; with key each page is an object holding the array.
admin_list() {
  _o="$(gh api --paginate "$1" 2>/dev/null)" || return 1
  if [ -n "${2:-}" ]; then
    printf '%s\n' "$_o" | jq -s --arg k "$2" 'map(.[$k] // []) | add // []'
  else
    printf '%s\n' "$_o" | jq -s 'map(if type=="array" then . else [] end) | add // []'
  fi
}

# admin_show <endpoint> <jq filter> -> filter result, or "unknown" when the API refuses.
admin_show() {
  _o="$(admin_get "$1")" || { echo "unknown"; return 0; }
  printf '%s\n' "$_o" | jq -r "$2" 2>/dev/null || echo "unknown"
}

# Refuse --apply from an agent or a non-interactive shell; ask the human to type the repo.
# Tests set GUARDRAIL_TEST=1 and ADMIN_NONINTERACTIVE_OK=1 together (same pattern as release.sh).
# This is a speed bump. The wall is HUMAN_ONLY_SCRIPTS_RE in .agent-policy/policy.sh.
admin_confirm_apply() {
  [ "${APPLY:-false}" = true ] || return 0
  if [ -n "${CLAUDECODE:-}" ] || [ -n "${COPILOT_AGENT_ACTION:-}" ] || [ -n "${GITHUB_COPILOT_AGENT:-}" ]; then
    echo "Refusing --apply: this looks like an agent session. A human runs --apply from their own terminal." >&2; exit 5
  fi
  if [ "${GUARDRAIL_TEST:-}" = 1 ] && [ "${ADMIN_NONINTERACTIVE_OK:-}" = 1 ]; then return 0; fi
  if [ ! -t 0 ]; then echo "Refusing --apply without an interactive terminal." >&2; exit 5; fi
  printf 'Type %s to apply these changes: ' "$1"
  read -r _answer
  [ "$_answer" = "$1" ] || { echo "Not confirmed. Nothing changed." >&2; exit 5; }
}

# Print a command; run it only when APPLY=true. Never aborts the script.
admin_run() {
  echo "+ $*"
  if [ "${APPLY:-false}" = true ]; then
    if "$@" >/dev/null; then echo "  ok"; else echo "  FAILED or not available on this plan (see message above)"; fi
  fi
}

# ISO date N days ago (YYYY-MM-DD), portable across macOS and Linux.
admin_days_ago() { jq -rn --argjson d "$1" '(now - ($d * 86400)) | strftime("%Y-%m-%d")'; }

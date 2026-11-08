#!/usr/bin/env bash
# Read-only Actions usage and cost report for one repo.
#   Per workflow over the last --days (default 30): runs, failures, failure rate,
#   average run time, average wait before start.
#   Actions cache usage and artifact storage.
#   --billing: your account's metered usage by product (best effort; the billing
#   API differs by plan and may not answer for every account).
#
# Usage: scripts/admin/usage-report.sh owner/repo [--days N] [--billing]
# Exit codes: 0 done, 2 bad arguments, 3 gh/jq missing or not signed in, 4 repo unreachable.
# GH-100: monitor runner performance; usage patterns; metered usage; license and resource optimization.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

repo=""; days=30; billing=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --days) [ "$#" -ge 2 ] || admin_usage_exit "--days needs a number"; days="$2"; shift 2 ;;
    --billing) billing=true; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    -*) admin_usage_exit "Unknown option: $1" ;;
    *) [ -z "$repo" ] || admin_usage_exit "Only one repo per run."; repo="$1"; shift ;;
  esac
done
[ -n "$repo" ] || admin_usage_exit "Usage: $0 owner/repo [--days N] [--billing]"
printf '%s' "$days" | grep -Eq '^[1-9][0-9]*$' || admin_usage_exit "--days must be a positive whole number."
admin_need_tools
admin_check_repo "$repo"

since="$(admin_days_ago "$days")"
flags=0
echo "# Actions usage: $repo (since $since)"
echo

runs="$(gh api --paginate "repos/$repo/actions/runs?per_page=100&created=%3E%3D$since" 2>/dev/null \
  | jq -s 'map(.workflow_runs // []) | add // []' 2>/dev/null || echo '[]')"
[ -z "$runs" ] && runs='[]'
total="$(echo "$runs" | jq length)"
echo "## Workflows ($total runs)"
if [ "$total" -eq 0 ]; then
  echo "No runs in this window."
else
  echo "| Workflow | Runs | Failed | Fail % | Avg run (min) | Avg wait (min) |"
  echo "| --- | --- | --- | --- | --- | --- |"
  table="$(echo "$runs" | jq -r '
    def t: if . == null then null else (sub("\\.[0-9]+Z$";"Z") | fromdateiso8601) end;
    group_by(.name)[] as $g
    | ($g | length) as $n
    | ($g | map(select(.conclusion=="failure" or .conclusion=="timed_out")) | length) as $f
    | ($g | map(select(.run_started_at and .updated_at) | ((.updated_at|t) - (.run_started_at|t)) / 60) ) as $dur
    | ($g | map(select(.run_started_at and .created_at) | ((.run_started_at|t) - (.created_at|t)) / 60) ) as $wait
    | "| \($g[0].name) | \($n) | \($f) | \(($f * 100 / $n) | floor) | \(if ($dur|length)>0 then (($dur|add)/($dur|length)*10|round/10) else "n/a" end) | \(if ($wait|length)>0 then (($wait|add)/($wait|length)*10|round/10) else "n/a" end) |"')"
  echo "$table"
  noisy="$(echo "$runs" | jq '[group_by(.name)[] | select(length >= 5) | select(([.[] | select(.conclusion=="failure" or .conclusion=="timed_out")] | length) * 5 > length)] | length')"
  if [ "$noisy" -gt 0 ]; then echo; echo "- **Flag:** $noisy workflow(s) fail more than 20% of the time. Failed runs still bill minutes."; flags=$((flags+1)); fi
fi
echo

echo "## Cache"
cache="$(gh api "repos/$repo/actions/cache/usage" 2>/dev/null || true)"
if [ -n "$cache" ]; then
  bytes="$(echo "$cache" | jq '.active_caches_size_in_bytes // 0')"
  echo "Active caches: $(echo "$cache" | jq '.active_caches_count // 0'), $(jq -n --argjson b "$bytes" '($b/1048576*10|round/10)') MB."
  if [ "$bytes" -gt 8589934592 ]; then echo "- **Flag:** cache is near the 10 GB repo limit; old entries get evicted."; flags=$((flags+1)); fi
else echo "_Not available._"; fi
echo

echo "## Artifacts"
arts="$(gh api --paginate "repos/$repo/actions/artifacts?per_page=100" 2>/dev/null | jq -s 'map(.artifacts // []) | add // []' 2>/dev/null || true)"
if [ -n "$arts" ]; then
  live="$(echo "$arts" | jq '[.[] | select(.expired|not)]')"
  abytes="$(echo "$live" | jq 'map(.size_in_bytes) | add // 0')"
  echo "Unexpired: $(echo "$live" | jq length), $(jq -n --argjson b "$abytes" '($b/1048576*10|round/10)') MB."
  if [ "$abytes" -gt 1073741824 ]; then echo "- **Flag:** over 1 GB of artifacts. Lower retention with scripts/admin/actions-policy.sh --retention-days."; flags=$((flags+1)); fi
else echo "_Not available._"; fi
echo

if $billing; then
  echo "## Billing (best effort)"
  me="$(gh api user 2>/dev/null | jq -r '.login // empty')"
  bill="$(gh api "users/$me/settings/billing/usage" 2>/dev/null || true)"
  if [ -n "$bill" ] && echo "$bill" | jq -e '.usageItems' >/dev/null 2>&1; then
    echo "| Product | Quantity | Net amount (USD) |"; echo "| --- | --- | --- |"
    echo "$bill" | jq -r '.usageItems | group_by(.product)[] | "| \(.[0].product) | \(map(.quantity // 0) | add * 100 | round / 100) | \(map(.netAmount // 0) | add * 100 | round / 100) |"'
  else
    echo "_Billing usage API did not answer for this account. Use Settings > Billing and licensing > Usage._"
  fi
  echo
fi

echo "Flags: $flags. Rate limit left: $(gh api rate_limit 2>/dev/null | jq -r '.resources.core | "\(.remaining)/\(.limit)"' 2>/dev/null || echo unknown)."
exit 0

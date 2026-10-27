#!/usr/bin/env bash
# Claude Code PostToolUseFailure: bounded retries + escalation.
# Counts failures per (tool, target). After the 2nd failure of the same
# action, tells Claude to stop and escalate. Exit 2 shows stderr to Claude.
input="$(cat)"
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
mkdir -p "$root/.agent"
counts="$root/.agent/failures.json"
[[ -f "$counts" ]] || echo '{}' > "$counts"

key="$(jq -r '.tool_name + ":" + ((.tool_input.command // .tool_input.file_path // "") | tostring | .[0:120])' <<<"$input")"
n="$(jq -r --arg k "$key" '(.[$k] // 0) + 1' "$counts")"
jq --arg k "$key" --argjson n "$n" '.[$k] = $n' "$counts" > "$counts.tmp" && mv "$counts.tmp" "$counts"

agent="claude:$(jq -r '.agent_type // "main"' <<<"$input")"
jq -nc --arg a "$agent" --arg k "$key" --argjson n "$n" '{ts:(now|todate), agent:$a, event:"tool_failure", action:$k, count:$n}' >> "$root/.agent/audit.log"

if (( n >= 2 )); then
  cat >&2 <<EOF
ESCALATE: "$key" has failed $n times. Stop retrying.
Write an escalation note in .agent/state.md with:
  1. What failed (command/check and error)
  2. Root cause category: reasoning error | tool misuse | context/environment issue
  3. What you tried
  4. Evidence (logs, run links)
  5. Suggested next step for the human
Then stop and report to the user.
EOF
  exit 2
fi
echo "Failure 1 of 2 for \"$key\". Classify the root cause in .agent/state.md and change something before retrying." >&2
exit 2

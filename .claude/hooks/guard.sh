#!/usr/bin/env bash
# Claude Code PreToolUse adapter -> shared policy.
# Claude Code: exit 2 blocks the tool call and shows stderr to Claude.
input="$(cat)"
tool="$(jq -r '.tool_name // ""' <<<"$input")"
agent="claude:$(jq -r '.agent_type // "main"' <<<"$input")"
policy="${CLAUDE_PROJECT_DIR:-.}/.agent-policy/policy.sh"
export AGENT_REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

case "$tool" in
  Bash)
    exec "$policy" shell "$(jq -r '.tool_input.command // ""' <<<"$input")" "$agent" ;;
  Edit|Write|MultiEdit|NotebookEdit)
    exec "$policy" edit "$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")" "$agent" ;;
esac
exit 0

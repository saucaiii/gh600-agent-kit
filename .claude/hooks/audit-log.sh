#!/usr/bin/env bash
# Claude Code PostToolUse (async): audit trail.
# Logs who did what to which target, tied to the current commit.
# Tool output is never logged, so secrets in output stay out.
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
mkdir -p "$root/.agent"
sha="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo none)"
branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo none)"
jq -c --arg sha "$sha" --arg br "$branch" '{
  ts: (now | todate),
  agent: ("claude:" + (.agent_type // "main")),
  session: .session_id,
  event: "tool_use",
  tool: .tool_name,
  target: (.tool_input.command // .tool_input.file_path // .tool_input.pattern // .tool_input.url // null),
  branch: $br,
  commit: $sha
}' >> "$root/.agent/audit.log" 2>/dev/null
exit 0

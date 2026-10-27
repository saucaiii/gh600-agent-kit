#!/usr/bin/env bash
# Close a task: archive short-term memory, reset it, prune old audit entries.
# GH-600 Domain 3: memory expiration, pruning, and reset rules.
#
# Usage: scripts/agent/close-task.sh [--remove-worktree]
set -euo pipefail
root="$(git rev-parse --show-toplevel)"; cd "$root"
RETENTION_DAYS="${AUDIT_RETENTION_DAYS:-30}"
task="$(grep -iE '^task:' .agent/state.md 2>/dev/null | head -1 | sed -E 's/^[Tt]ask:\s*//')"
task="${task:-untitled}"
stamp="$(date +%Y-%m-%d)"
arch=".agent/archive/${stamp}-${task}"
mkdir -p "$arch"

# 1. Archive the task's short-term memory and plan (kept for audit, out of the agent's context).
for f in state.md plan.md scope.txt eval.md failures.json; do
  [[ -f ".agent/$f" ]] && mv ".agent/$f" "$arch/"
done

# 2. Reset short-term memory.
cat > .agent/state.md <<'EOF'
# Working memory (short-term). Keep under 60 lines. Prune when a task closes.
Branch: none
Task: none
Status: idle

## Progress
- (none)
EOF

# 3. Prune audit log entries older than the retention window into the archive.
if [[ -f .agent/audit.log ]]; then
  cutoff="$(date -u -d "-${RETENTION_DAYS} days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-"${RETENTION_DAYS}"d +%Y-%m-%dT%H:%M:%SZ)"
  jq -c --arg c "$cutoff" 'select(.ts < $c)' .agent/audit.log >> "$arch/audit-expired.log" 2>/dev/null || true
  jq -c --arg c "$cutoff" 'select(.ts >= $c)' .agent/audit.log > .agent/audit.tmp 2>/dev/null && mv .agent/audit.tmp .agent/audit.log
fi

echo "Closed task '$task'. Archived to $arch. Short-term memory reset."
echo "Long-term memory (.agent/decisions.md) was kept. Add 'review-by YYYY-MM-DD' to decisions that should expire."

if [[ "${1:-}" == "--remove-worktree" ]]; then
  main_wt="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
  if [[ "$main_wt" != "$root" ]]; then
    git -C "$main_wt" worktree remove "$root" && echo "Removed worktree $root"
  fi
fi

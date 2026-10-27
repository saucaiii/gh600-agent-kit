#!/usr/bin/env bash
# Shared agent policy. One rule set, enforced for every agent tool.
#   Claude Code -> .claude/hooks/guard.sh       -> this file
#   Copilot     -> .github/hooks/scripts/pre-tool.sh -> this file
#
# Usage: policy.sh <kind> <target> [agent-name]
#   kind:   shell | edit
#   target: the shell command, or the file path being edited
# Exit 0 = allow. Exit 2 = deny, reason on stderr.
#
# GH-600 skills: tool permissions, branch-based scope, scope to repo paths,
# environment constraints, least privilege, block policy violations,
# controlled paths for irreversible changes, traceability.

set -uo pipefail

kind="${1:-}"; target="${2:-}"; agent="${3:-unknown}"
root="${AGENT_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$root" 2>/dev/null || true

# ---- Policy configuration (edit these for your repo) ----
DEFAULT_BRANCHES_RE='^(main|master)$'
HIGH_RISK_RE='^(\.github/workflows/|\.github/agents/|\.github/hooks/|\.github/CODEOWNERS|CODEOWNERS|\.agent-policy/|infra/|deploy/|src/auth/)'
FORBIDDEN_RE='(^|/)(\.env($|\.)|secrets/)|\.(pem|key|p12)$|^\.claude/(settings\.json|hooks/)|^\.agent-policy/'
# Paths any agent may always write (its own working memory).
ALWAYS_WRITABLE_RE='^\.agent/'

log_block() {
  mkdir -p .agent
  jq -nc --arg a "$agent" --arg k "$kind" --arg t "$target" --arg r "$1" \
    '{ts:(now|todate), agent:$a, event:"blocked", kind:$k, target:$t, reason:$r}' \
    >> .agent/audit.log 2>/dev/null || true
}
deny() { log_block "$1"; echo "BLOCKED by agent policy: $1" >&2; exit 2; }

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
on_default=false; [[ "$branch" =~ $DEFAULT_BRANCHES_RE ]] && on_default=true

plan_approved() {
  [[ -f .agent/plan.md ]] && grep -qiE '^\s*\**approved\**\s*:\s*\**\s*yes' .agent/plan.md
}

case "$kind" in
  shell)
    c="$target"
    grep -qE 'git\s+push\b.*(\s--force(\s|$|-with-lease)|\s-f(\s|$))' <<<"$c" && deny "force push. Use git revert instead of rewriting history."
    grep -qE '\s--no-verify\b' <<<"$c" && deny "--no-verify skips safety checks."
    grep -qE 'gh\s+pr\s+merge\b' <<<"$c" && deny "agents propose, humans merge."
    grep -qE 'gh\s+pr\s+review\b.*--approve' <<<"$c" && deny "an agent cannot approve its own PR."
    grep -qE 'gh\s+(workflow\s+run|api\s.*dispatches)' <<<"$c" && grep -qiE 'deploy' <<<"$c" && deny "deploys are critical risk. Prepare the change; a human runs the deploy."
    grep -qE 'gh\s+(secret|variable)\s+set\b' <<<"$c" && deny "secrets and repo settings are critical risk."
    grep -qE '(curl|wget)[^|]*\|\s*(ba|z)?sh\b' <<<"$c" && deny "piping a download into a shell."
    grep -qE 'git\s+push\b.*\b(main|master)\b' <<<"$c" && deny "never push to the default branch. Push an agent branch and open a PR."
    grep -qE 'git\s+reset\s+--hard' <<<"$c" && deny "git reset --hard can destroy work. Use git revert."
    grep -qE 'git\s+(rebase|filter-branch|filter-repo)\b' <<<"$c" && deny "history rewrites are not allowed for agents."
    if $on_default && grep -qE 'git\s+(commit|push|merge)\b' <<<"$c"; then
      deny "on '$branch'. Create a branch first: git switch -c agent/<task>"
    fi
    grep -qE '(cat|less|more|head|tail|printenv|env|base64|xxd)\b.*(\.env|secrets/|\.pem|\.key)' <<<"$c" && deny "reading secrets."
    exit 0
    ;;
  edit)
    rel="${target#"$root"/}"; rel="${rel#./}"
    [[ "$rel" =~ $FORBIDDEN_RE ]] && deny "'$rel' is a secret or a guardrail file."
    [[ "$rel" =~ $ALWAYS_WRITABLE_RE ]] && exit 0
    $on_default && deny "on '$branch'. Create a branch before editing: git switch -c agent/<task>"
    if [[ -f .agent/scope.txt ]]; then
      ok=false
      while IFS= read -r p; do
        p="${p%%#*}"; p="$(xargs <<<"$p")"; [[ -z "$p" ]] && continue
        [[ "$rel" == "$p"* ]] && ok=true && break
      done < .agent/scope.txt
      $ok || deny "'$rel' is outside this task's scope (.agent/scope.txt). Update the plan, get approval."
    fi
    if [[ "$rel" =~ $HIGH_RISK_RE ]] && ! plan_approved; then
      deny "'$rel' is high risk (plan-first). A human must set 'Approved: yes' in .agent/plan.md."
    fi
    exit 0
    ;;
  *) exit 0 ;;
esac

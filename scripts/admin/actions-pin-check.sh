#!/usr/bin/env bash
# Offline check: every `uses:` in the workflows is pinned and allowed.
# - Local actions (./path) are fine.
# - Remote actions must pin a full 40-character commit SHA.
# - Docker actions must pin an @sha256: digest.
# - Owners other than actions/ and github/ must match github/actions-allowlist.txt.
# No network, no gh. Safe for agents and CI to run.
#
# Usage: scripts/admin/actions-pin-check.sh [--dir .github/workflows] [--allowlist github/actions-allowlist.txt]
# Exit codes: 0 clean, 1 violations found, 2 bad arguments.
# GH-100: organizational policies for GitHub Actions. macOS bash 3.2 compatible.
set -uo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
dir="$root/.github/workflows"
allowlist="$root/github/actions-allowlist.txt"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir) [ "$#" -ge 2 ] || { echo "--dir needs a path" >&2; exit 2; }; dir="$2"; shift 2 ;;
    --allowlist) [ "$#" -ge 2 ] || { echo "--allowlist needs a path" >&2; exit 2; }; allowlist="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -d "$dir" ] || { echo "No workflows directory at $dir" >&2; exit 2; }

patterns=""
if [ -f "$allowlist" ]; then
  patterns="$(sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' "$allowlist" | grep -v '^$' || true)"
fi

allowed_owner() { # $1 = owner/repo[/path]@ref
  case "$1" in actions/*|github/*) return 0 ;; esac
  [ -z "$patterns" ] && return 1
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    # shellcheck disable=SC2254
    case "$1" in $p) return 0 ;; esac
  done <<EOF
$patterns
EOF
  return 1
}

bad=0; total=0
for f in "$dir"/*.yml "$dir"/*.yaml; do
  [ -f "$f" ] || continue
  n=0
  while IFS= read -r line; do
    n=$((n+1))
    case "$line" in *uses:*) ;; *) continue ;; esac
    trimmed="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/^-[[:space:]]*//')"
    case "$trimmed" in uses:*) ;; *) continue ;; esac
    ref="$(printf '%s' "$trimmed" | sed -e 's/^uses:[[:space:]]*//' -e 's/[[:space:]]#.*$//' -e 's/[[:space:]]*$//' -e "s/^[\"']//" -e "s/[\"']$//")"
    [ -z "$ref" ] && continue
    total=$((total+1))
    where="${f#"$root"/}:$n"
    case "$ref" in
      ./*) continue ;;
      docker://*)
        case "$ref" in *@sha256:*) continue ;; esac
        echo "UNPINNED  $where  $ref  (pin the image by @sha256: digest)"; bad=$((bad+1)); continue ;;
    esac
    sha="${ref##*@}"
    if [ "$sha" = "$ref" ] || ! printf '%s' "$sha" | grep -Eq '^[0-9a-f]{40}$'; then
      echo "UNPINNED  $where  $ref  (pin a full 40-character commit SHA, keep the tag as a comment)"; bad=$((bad+1)); continue
    fi
    if ! allowed_owner "$ref"; then
      echo "NOT ALLOWED  $where  $ref  (add a pattern to github/actions-allowlist.txt in a reviewed PR)"; bad=$((bad+1))
    fi
  done < "$f"
done

if [ "$bad" -eq 0 ]; then
  echo "actions-pin-check: $total uses: checked, all pinned and allowed."
  exit 0
fi
echo "actions-pin-check: $bad of $total uses: need fixing."
exit 1

#!/usr/bin/env bash
# Claude Code status line: model · git branch · context% [bar] · session cost
# Reads session JSON from stdin (model, workspace, transcript_path, cost...).
set -uo pipefail

input=$(cat)

model=$(printf '%s' "$input" | jq -r '.model.display_name // .model.id // "?"')
model_id=$(printf '%s' "$input" | jq -r '.model.id // ""')
cwd=$(printf '%s' "$input"   | jq -r '.workspace.current_dir // .cwd // "."')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // ""')
cost=$(printf '%s' "$input"  | jq -r '.cost.total_cost_usd // 0')

branch=""
if [ -d "$cwd" ]; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
        || git -C "$cwd" rev-parse --short HEAD 2>/dev/null \
        || true)
fi

read_ctx_tokens() {
  local file="$1"
  [ -n "$file" ] && [ -f "$file" ] || { echo 0; return; }
  # Between /compact and the next reply the transcript ends with a RESET
  # marker; fall back to the pre-RESET value so the bar doesn't read 0%.
  tail -n 2000 "$file" 2>/dev/null \
    | jq -R -r '
        fromjson?
        | if (.isCompactSummary == true) then "RESET"
          elif (.message.usage) then
            ((.message.usage.input_tokens // 0)
             + (.message.usage.cache_read_input_tokens // 0)
             + (.message.usage.cache_creation_input_tokens // 0)
             | tostring)
          else empty end' 2>/dev/null \
    | awk '
        /^RESET$/ { pre = val; val = 0; next }
        { val = $0 }
        END { print ((val+0) > 0 ? val+0 : pre+0) }'
}

ctx_tokens=$(read_ctx_tokens "$transcript")
case "$ctx_tokens" in ""|"null") ctx_tokens=0 ;; esac

# Context window: 1M for [1m] variants, 200k otherwise
limit=200000
case "$model_id" in
  *"[1m]"*|*"-1m"*) limit=1000000 ;;
esac

if [ "${ctx_tokens:-0}" -gt 0 ] 2>/dev/null; then
  pct=$(( ctx_tokens * 100 / limit ))
else
  pct=0
fi
[ "$pct" -gt 100 ] && pct=100

filled=$(( pct / 10 ))
bar=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  if [ "$i" -le "$filled" ]; then bar="${bar}█"; else bar="${bar}░"; fi
done

cost_fmt=$(printf '%.2f' "$cost" 2>/dev/null || echo "0.00")

DIM=$'\033[2m'; RESET=$'\033[0m'
CYAN=$'\033[36m'; MAG=$'\033[35m'
GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'

if   [ "$pct" -ge 80 ]; then bar_color="$RED"
elif [ "$pct" -ge 60 ]; then bar_color="$YELLOW"
else                          bar_color="$GREEN"
fi

sep="${DIM}·${RESET}"
out="${CYAN}${model}${RESET}"
[ -n "$branch" ] && out="${out} ${sep} ${MAG}⎇ ${branch}${RESET}"
out="${out} ${sep} ${bar_color}${bar}${RESET} ${pct}%"
out="${out} ${sep} ${DIM}\$${cost_fmt}${RESET}"

printf '%s\n' "$out"

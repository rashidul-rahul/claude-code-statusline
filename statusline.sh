#!/usr/bin/env bash
# Claude Code status line:
#   model · effort · git branch[*][↑↓] · context bar + tokens · rate limit · cost
# Reads session JSON from stdin (model, effort, context_window, rate_limits...).
set -uo pipefail

input=$(cat)

# --- one jq pass for every field ------------------------------------------
{
  IFS= read -r model
  IFS= read -r model_id
  IFS= read -r cwd
  IFS= read -r transcript
  IFS= read -r cost
  IFS= read -r effort
  IFS= read -r ctx_used
  IFS= read -r ctx_size
  IFS= read -r used_pct
  IFS= read -r rl5_pct
  IFS= read -r rl5_reset
  IFS= read -r rl7_pct
} < <(printf '%s' "$input" | jq -r '
  (.model.display_name // .model.id // "?"),
  (.model.id // ""),
  (.workspace.current_dir // .cwd // "."),
  (.transcript_path // ""),
  (.cost.total_cost_usd // 0),
  (.effort.level // ""),
  (.context_window.current_usage as $u
   | if $u then (($u.input_tokens // 0) + ($u.output_tokens // 0)
       + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0))
     else "" end),
  (.context_window.context_window_size // ""),
  (.context_window.used_percentage // ""),
  (.rate_limits.five_hour.used_percentage // ""),
  (.rate_limits.five_hour.resets_at // ""),
  (.rate_limits.seven_day.used_percentage // "")
' 2>/dev/null)

model=${model:-?}; model_id=${model_id:-}; cwd=${cwd:-.}; transcript=${transcript:-}
cost=${cost:-0}; effort=${effort:-}; ctx_used=${ctx_used:-}; ctx_size=${ctx_size:-}
used_pct=${used_pct:-}; rl5_pct=${rl5_pct:-}; rl5_reset=${rl5_reset:-}; rl7_pct=${rl7_pct:-}

# --- git: branch, dirty marker, ahead/behind upstream -----------------------
branch=""; dirty=""; arrows=""
if [ -d "$cwd" ] && git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
        || git -C "$cwd" rev-parse --short HEAD 2>/dev/null \
        || true)
  if [ -n "$branch" ]; then
    git -C "$cwd" diff --quiet 2>/dev/null && git -C "$cwd" diff --cached --quiet 2>/dev/null \
      || dirty="*"
    [ -z "$dirty" ] \
      && [ -n "$(git -C "$cwd" ls-files --others --exclude-standard 2>/dev/null | head -1)" ] \
      && dirty="*"
    counts=$(git -C "$cwd" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null || true)
    if [ -n "$counts" ]; then
      behind=${counts%%[[:space:]]*}; ahead=${counts##*[[:space:]]}
      [ "${ahead:-0}" -gt 0 ] 2>/dev/null && arrows="↑${ahead}"
      [ "${behind:-0}" -gt 0 ] 2>/dev/null && arrows="${arrows}↓${behind}"
    fi
  fi
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

fmt_tokens() {
  awk -v n="$1" 'BEGIN {
    if (n >= 1000000)   { v = n/1000000; printf (v == int(v) ? "%dM" : "%.1fM"), v }
    else if (n >= 1000) printf "%dk", n/1000
    else                printf "%d", n
  }'
}

# --- context %: native token counts -> used_percentage -> transcript --------
# pct10 is tenths of a percent (0..1000) so the bar can render partial blocks.
tok_label=""
if [ "${ctx_used:-x}" -ge 0 ] 2>/dev/null && [ "${ctx_size:-0}" -gt 0 ] 2>/dev/null; then
  pct10=$(( ctx_used * 1000 / ctx_size ))
  tok_label="$(fmt_tokens "$ctx_used")/$(fmt_tokens "$ctx_size")"
elif [ "${used_pct:-x}" -ge 0 ] 2>/dev/null; then
  pct10=$(( used_pct * 10 ))
else
  ctx_tokens=$(read_ctx_tokens "$transcript")
  case "$ctx_tokens" in ""|"null") ctx_tokens=0 ;; esac

  # Context window: 1M for [1m] variants, 200k otherwise
  limit=200000
  case "$model_id" in
    *"[1m]"*|*"-1m"*) limit=1000000 ;;
  esac

  if [ "${ctx_tokens:-0}" -gt 0 ] 2>/dev/null; then
    pct10=$(( ctx_tokens * 1000 / limit ))
  else
    pct10=0
  fi
fi
[ "$pct10" -gt 1000 ] && pct10=1000
pct=$(( pct10 / 10 ))

# --- smooth 10-cell bar with 1/8-block resolution ---------------------------
partials=("" "▏" "▎" "▍" "▌" "▋" "▊" "▉")
filled=$(( pct10 / 100 ))
rem_idx=$(( pct10 % 100 * 8 / 100 ))
bar=""
for (( i = 0; i < 10; i++ )); do
  if   (( i < filled ));                    then bar+="█"
  elif (( i == filled && rem_idx > 0 ));    then bar+="${partials[rem_idx]}"
  else                                           bar+="░"
  fi
done

cost_fmt=$(printf '%.2f' "$cost" 2>/dev/null || echo "0.00")

# --- 256-color palette -------------------------------------------------------
ESC=$'\033'
RESET="${ESC}[0m"
GRAY="${ESC}[38;5;245m";  DGRAY="${ESC}[38;5;240m"
BLUE="${ESC}[38;5;81m";   MAGENTA="${ESC}[38;5;176m"
GREEN="${ESC}[38;5;114m"; AMBER="${ESC}[38;5;214m"; RED="${ESC}[38;5;203m"

if   [ "$pct" -ge 80 ]; then bar_color="$RED"
elif [ "$pct" -ge 60 ]; then bar_color="$AMBER"
else                          bar_color="$GREEN"
fi

case "$effort" in
  max|xhigh) effort_color="$RED" ;;
  high)      effort_color="$AMBER" ;;
  medium)    effort_color="$GREEN" ;;
  *)         effort_color="$GRAY" ;;
esac

cost_band=$(awk -v c="$cost" 'BEGIN { print (c >= 20) ? 2 : (c >= 5) ? 1 : 0 }')
case "$cost_band" in
  2) cost_color="$RED" ;;
  1) cost_color="$AMBER" ;;
  *) cost_color="$GRAY" ;;
esac

# --- rate limit segment: 5h always, reset time when hot, 7d when >= 50% -----
rate_seg=""
if [ "${rl5_pct:-x}" -ge 0 ] 2>/dev/null; then
  if   [ "$rl5_pct" -ge 85 ]; then rate_color="$RED"
  elif [ "$rl5_pct" -ge 60 ]; then rate_color="$AMBER"
  else                             rate_color="$GRAY"
  fi
  rate_seg="${rate_color}5h ${rl5_pct}%${RESET}"
  if [ "$rl5_pct" -ge 60 ] && [ "${rl5_reset:-x}" -ge 0 ] 2>/dev/null; then
    reset_hm=$(date -r "$rl5_reset" +%H:%M 2>/dev/null \
            || date -d "@$rl5_reset" +%H:%M 2>/dev/null || true)
    [ -n "$reset_hm" ] && rate_seg="${rate_seg} ${GRAY}↻${reset_hm}${RESET}"
  fi
  if [ "${rl7_pct:-x}" -ge 50 ] 2>/dev/null; then
    if   [ "$rl7_pct" -ge 85 ]; then rl7_color="$RED"
    elif [ "$rl7_pct" -ge 60 ]; then rl7_color="$AMBER"
    else                             rl7_color="$GRAY"
    fi
    rate_seg="${rate_seg} ${rl7_color}7d ${rl7_pct}%${RESET}"
  fi
fi

# --- assemble ----------------------------------------------------------------
sep="${DGRAY}·${RESET}"
out="${BLUE}${model}${RESET}"
[ -n "$effort" ] && out+=" ${sep} ${effort_color}◈ ${effort}${RESET}"
if [ -n "$branch" ]; then
  out+=" ${sep} ${MAGENTA}⎇ ${branch}${RESET}"
  [ -n "$dirty" ]  && out+="${AMBER}${dirty}${RESET}"
  [ -n "$arrows" ] && out+=" ${GRAY}${arrows}${RESET}"
fi
out+=" ${sep} ${bar_color}${bar} ${pct}%${RESET}"
[ -n "$tok_label" ] && out+=" ${GRAY}${tok_label}${RESET}"
[ -n "$rate_seg" ] && out+=" ${sep} ${rate_seg}"
out+=" ${sep} ${cost_color}\$${cost_fmt}${RESET}"

printf '%s\n' "$out"

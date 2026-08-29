#!/bin/bash
# Claude Code status line — 3 lines:
#   1) model·effort │ folder │ branch │ git
#   2) context bar │ cost │ cache hit │ token breakdown
#   3) 5h usage bar + reset │ 7d usage bar + reset
# All data comes from the status line JSON on stdin (no external services).

input=$(cat)

# ── Extract everything in one jq pass ─────────────────────────────────────────
# Fields are joined with the unit-separator (U+001F). Unlike tab it is not
# IFS-whitespace, so empty fields (e.g. an absent effort) are preserved rather
# than collapsed, keeping every column aligned with its variable.
IFS=$'\037' read -r \
  MODEL EFFORT DIR COST CTX_PCT CTX_IN CTX_OUT CTX_SIZE \
  U_CR U_CW U_IN U_OUT \
  H5_PCT H5_RESET D7_PCT D7_RESET \
  < <(printf '%s' "$input" | jq -j '[
    (.model.display_name // "?"),
    (.effort.level // ""),
    (.workspace.current_dir // .cwd // ""),
    (.cost.total_cost_usd // 0),
    (.context_window.used_percentage // 0),
    (.context_window.total_input_tokens // 0),
    (.context_window.total_output_tokens // 0),
    (.context_window.context_window_size // 200000),
    (.context_window.current_usage.cache_read_input_tokens // 0),
    (.context_window.current_usage.cache_creation_input_tokens // 0),
    (.context_window.current_usage.input_tokens // 0),
    (.context_window.current_usage.output_tokens // 0),
    (.rate_limits.five_hour.used_percentage // -1),
    (.rate_limits.five_hour.resets_at // 0),
    (.rate_limits.seven_day.used_percentage // -1),
    (.rate_limits.seven_day.resets_at // 0)
  ] | map(tostring) | join("\u001f")')

# ── Palette (256-color) ──────────────────────────────────────────────────────
R=$'\033[0m'; B=$'\033[1m'; DIM=$'\033[2m'
MODELC=$'\033[38;5;170m'   # magenta   model
DIRC=$'\033[38;5;39m'      # blue      folder
BRANCHC=$'\033[38;5;114m'  # green     branch
SEP=$'\033[38;5;240m'      # gray      separators
LABEL=$'\033[38;5;245m'    # light gray labels
GREEN=$'\033[38;5;35m'; YELLOW=$'\033[38;5;178m'; RED=$'\033[38;5;203m'
CYAN=$'\033[38;5;80m'; GOLD=$'\033[38;5;220m'

BULL=" ${SEP}│${R} "   # segment separator

# ── Helpers ───────────────────────────────────────────────────────────────────
# color by percentage (0-100 int)
pctcolor() { if [ "$1" -ge 90 ]; then printf '%s' "$RED"; elif [ "$1" -ge 70 ]; then printf '%s' "$YELLOW"; else printf '%s' "$GREEN"; fi; }

# bar <pct-int> <width>
bar() {
  local pct=$1 width=$2 filled empty f e
  ((pct<0)) && pct=0; ((pct>100)) && pct=100
  filled=$(( (pct*width + 50) / 100 )); empty=$(( width - filled ))
  printf -v f '%*s' "$filled" ''; printf -v e '%*s' "$empty" ''
  printf '%s%s' "${f// /█}" "${e// /░}"
}

# fmt <tokens> -> 1.5k / 2.3M / 812
fmt() {
  awk -v n="$1" 'BEGIN{
    if(n>=1e6){v=n/1e6;u="M"} else if(n>=1e3){v=n/1e3;u="k"} else {printf "%d",n; exit}
    s=sprintf("%.1f",v); sub(/\.0$/,"",s); printf "%s%s",s,u }'
}

# resetclock <epoch> -> "2h05m (14:30)" / "3m (09:12)" / "now" / "—"
resetclock() {
  local ep=$1 now d h m clk
  { [ -z "$ep" ] || [ "$ep" -le 0 ]; } 2>/dev/null && { printf '—'; return; }
  now=$(date +%s); d=$(( ep - now ))
  clk=$(date -d "@$ep" +%H:%M 2>/dev/null || date -r "$ep" +%H:%M 2>/dev/null)
  if ((d<=0)); then printf 'now'; return; fi
  h=$(( d/3600 )); m=$(( (d%3600)/60 ))
  if ((h>0)); then printf '%dh%02dm (%s)' "$h" "$m" "$clk"; else printf '%dm (%s)' "$m" "$clk"; fi
}

# resetdate <epoch> -> "3d14h (Jul 24)" / "1d2h (Jul 22)" / "now" / "—"
resetdate() {
  local ep=$1 now d days hrs dt
  { [ -z "$ep" ] || [ "$ep" -le 0 ]; } 2>/dev/null && { printf '—'; return; }
  now=$(date +%s); d=$(( ep - now ))
  dt=$(date -d "@$ep" "+%b %-d" 2>/dev/null || date -r "$ep" "+%b %-d" 2>/dev/null)
  if ((d<=0)); then printf 'now'; return; fi
  days=$(( d/86400 )); hrs=$(( (d%86400)/3600 ))
  if ((days>0)); then printf '%dd%dh (%s)' "$days" "$hrs" "$dt"; else printf '%dh (%s)' "$hrs" "$dt"; fi
}

# ── Line 1: identity ──────────────────────────────────────────────────────────
CTX_PCT_I=${CTX_PCT%.*}; CTX_PCT_I=${CTX_PCT_I:-0}
MODEL_SEG="${MODELC}${B}◆ ${MODEL}${R}"
[ -n "$EFFORT" ] && MODEL_SEG="${MODEL_SEG}${DIM}·${EFFORT}${R}"

L1="${MODEL_SEG}${BULL}${DIRC}${DIR##*/}${R}"

if git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  BR=$(git -C "$DIR" branch --show-current 2>/dev/null); [ -z "$BR" ] && BR="detached"
  CHANGED=$(git -C "$DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  read -r BEHIND AHEAD < <(git -C "$DIR" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null || echo "0 0")
  GIT_SEG="${BRANCHC}⎇ ${BR}${R}"
  if [ "${CHANGED:-0}" -gt 0 ]; then GIT_SEG="${GIT_SEG} ${YELLOW}●${CHANGED}${R}"; else GIT_SEG="${GIT_SEG} ${GREEN}✓${R}"; fi
  [ "${AHEAD:-0}" -gt 0 ] && GIT_SEG="${GIT_SEG} ${CYAN}↑${AHEAD}${R}"
  [ "${BEHIND:-0}" -gt 0 ] && GIT_SEG="${GIT_SEG} ${CYAN}↓${BEHIND}${R}"
  L1="${L1}${BULL}${GIT_SEG}"
fi

# ── Line 2: context · cost · cache · tokens ───────────────────────────────────
CC=$(pctcolor "$CTX_PCT_I")
CTX_USED=$(( CTX_IN + CTX_OUT ))
CTX_SEG="${LABEL}ctx${R} ${CC}[$(bar "$CTX_PCT_I" 12)]${R} ${CC}${CTX_PCT_I}%${R} ${DIM}$(fmt "$CTX_USED")/$(fmt "$CTX_SIZE")${R}"

COST_SEG="${GOLD}\$$(awk -v c="$COST" 'BEGIN{printf (c>=1?"%.2f":"%.3f"),c}')${R}"

# cache hit rate = cache_read / (cache_read + cache_write + fresh_input) on last call
HIT=$(awk -v cr="$U_CR" -v cw="$U_CW" -v fi="$U_IN" 'BEGIN{d=cr+cw+fi; printf "%.0f",(d>0?cr*100/d:0)}')
if [ "$HIT" -ge 70 ]; then HC=$GREEN; elif [ "$HIT" -ge 40 ]; then HC=$YELLOW; else HC=$RED; fi
CACHE_SEG="${LABEL}cache${R} ${HC}${HIT}%${R}"

TOK_SEG="${DIM}in ${R}$(fmt "$U_IN") ${DIM}out ${R}$(fmt "$U_OUT") ${DIM}r ${R}$(fmt "$U_CR") ${DIM}w ${R}$(fmt "$U_CW")"

L2="${CTX_SEG}${BULL}${COST_SEG}${BULL}${CACHE_SEG}${BULL}${TOK_SEG}"

# ── Line 3: 5h / 7d usage windows ─────────────────────────────────────────────
window() { # <label> <pct> <reset-epoch> [datefmt]
  local lbl=$1 pct=$2 reset=$3 datefmt=${4:-clock} pi c clkfn
  pi=${pct%.*}
  if [ -z "$pi" ] || [ "$pi" -lt 0 ] 2>/dev/null; then
    printf '%s%s %sn/a%s' "$LABEL" "$lbl" "$DIM" "$R"; return
  fi
  c=$(pctcolor "$pi")
  [ "$datefmt" = date ] && clkfn="resetdate" || clkfn="resetclock"
  printf '%s%s%s %s[%s]%s %s%s%%%s %s↻ %s%s' \
    "$LABEL" "$lbl" "$R" "$c" "$(bar "$pi" 10)" "$R" "$c" "$pi" "$R" "$DIM" "$($clkfn "$reset")" "$R"
}

L3="$(window 5h "$H5_PCT" "$H5_RESET")${BULL}$(window 7d "$D7_PCT" "$D7_RESET" date)"

printf '%s\n%s\n%s\n' "$L1" "$L2" "$L3"

#!/usr/bin/env bash
# Weekly digest for the auto PR reviewer: posts, per-stage drop rates, failure
# types, pause time, notional cost, and the harvested addressed/dismissed
# labels. Writes ~/.local/state/auto-pr-review/digest-<date>.txt, prints it,
# and shows a one-line macOS notification. Run by launchd every Monday 09:00
# (launchd/com.example.auto-pr-review-digest.plist) or by hand.

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PATH="/opt/homebrew/bin:${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin"

STATE_DIR="${HOME}/.local/state/auto-pr-review"
DB="${STATE_DIR}/usage.db"
LOG="${STATE_DIR}/run.log"
EVAL_DIR="${HOME}/.config/auto-pr-review/eval"
DAYS="${DAYS:-7}"
# DAYS ago in the given format. BSD date (macOS) first, GNU date (Linux) second.
days_ago() { local fmt="$1"; shift; date "$@" -v-"${DAYS}"d "+$fmt" 2>/dev/null || date "$@" -d "-${DAYS} days" "+$fmt"; }
SINCE=$(days_ago '%Y-%m-%dT%H:%M:%SZ' -u)
LOG_SINCE=$(days_ago '%Y-%m-%d %H:%M:%S')
OUT="${STATE_DIR}/digest-$(date +%Y-%m-%d).txt"

q() { sqlite3 -header -column "$DB" "$1"; }

{
  echo "Auto-PR-Review digest: last ${DAYS} days (since ${SINCE})"
  echo
  echo "## Posted reviews"
  q "SELECT COUNT(*) AS posts, COALESCE(SUM(findings_n),0) AS findings,
            SUM(CASE WHEN verdict='needs-changes' THEN 1 ELSE 0 END) AS needs_changes
     FROM posts WHERE posted_at >= '${SINCE}';"
  echo
  echo "## Pipeline stages (what each stage dropped)"
  q "SELECT COUNT(*) AS runs, SUM(findings_raw) AS raw, SUM(findings_filtered) AS filtered,
            SUM(findings_anchored) AS anchored, SUM(findings_verified) AS verified, SUM(findings_posted) AS posted,
            SUM(is_incremental) AS incremental, SUM(is_partial) AS partial
     FROM pipeline WHERE created_at >= '${SINCE}';"
  echo
  echo "## File coverage (files_reviewed contract)"
  q "SELECT COUNT(files_total) AS runs_reporting, SUM(files_total) AS files, SUM(files_covered) AS covered,
            SUM(coverage_followup) AS followups,
            SUM(CASE WHEN files_covered < files_total THEN 1 ELSE 0 END) AS runs_with_gaps
     FROM pipeline WHERE created_at >= '${SINCE}';"
  echo
  echo "## Dropped findings by stage and reason (details: dropped_findings table)"
  q "SELECT stage,
            CASE WHEN stage = 'filter' THEN substr(reason, 1, instr(reason || ':', ':') - 1)
                 WHEN stage IN ('verify', 'anchor') THEN substr(reason, 1, 40)
                 ELSE reason END AS reason,
            COUNT(*) AS n
     FROM dropped_findings WHERE created_at >= '${SINCE}'
     GROUP BY 1, 2 ORDER BY 1, n DESC;"
  echo
  echo "## Anchor methods (run.log)"
  if [[ -f "$LOG" ]]; then
    awk -v since="$LOG_SINCE" '$1" "$2 >= since && /  anchors: /' "$LOG" \
      | { grep -oE '(snippet|snippet-first-line|line|line-snap|file-level)=[0-9]+' || true; } \
      | awk -F= '{n[$1] += $2} END {for (k in n) printf "%s=%d\n", k, n[k]; if (!length(n)) print "(no anchored findings logged yet)"}' | sort
  fi
  echo
  echo "## Primary calls by outcome"
  q "SELECT phase, model, is_error, COALESCE(stop_reason,'-') AS stop, COUNT(*) AS n,
            ROUND(AVG(num_turns),1) AS turns, ROUND(SUM(total_cost_usd),2) AS notional_usd
     FROM reviews WHERE call_started_at >= '${SINCE}' AND phase IN ('primary','salvage','fallback')
     GROUP BY 1,2,3,4 ORDER BY n DESC;"
  echo
  echo "## Verify calls"
  q "SELECT is_error, COUNT(*) AS n, ROUND(AVG(num_turns),1) AS turns
     FROM reviews WHERE call_started_at >= '${SINCE}' AND phase LIKE 'verify%' GROUP BY 1;"
  echo
  echo "## Pauses (rate limit / auth) in run.log"
  if [[ -f "$LOG" ]]; then
    awk -v since="$LOG_SINCE" '$1" "$2 >= since && /PAUSED until/' "$LOG" | wc -l | sed 's/^ */pause events: /'
    awk -v since="$LOG_SINCE" '$1" "$2 >= since && /skipping tick/ && /paused/' "$LOG" | wc -l | sed 's/^ */ticks skipped while paused: /'
    awk -v since="$LOG_SINCE" '$1" "$2 >= since && /Argument list too long/' "$LOG" | wc -l | sed 's/^ */E2BIG errors: /'
  fi
  echo
  echo "## Notional spend, month to date"
  q "SELECT * FROM monthly_spend LIMIT 1;"
  echo
  echo "## Harvested labels (GitHub behavior)"
  if "${SCRIPT_DIR}/harvest-labels.sh" >/dev/null 2>&1 && [[ -f "${EVAL_DIR}/harvest-summary.txt" ]]; then
    cat "${EVAL_DIR}/harvest-summary.txt"
  else
    echo "(harvest failed or not run)"
  fi
} | tee "$OUT"

POSTS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM posts WHERE posted_at >= '${SINCE}';")
FAILS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM reviews WHERE call_started_at >= '${SINCE}' AND phase='primary' AND is_error=1;")
osascript -e "display notification \"${POSTS} reviews posted, ${FAILS} failed primary calls. Details: ${OUT}\" with title \"Auto-PR-Review weekly digest\"" 2>/dev/null || true

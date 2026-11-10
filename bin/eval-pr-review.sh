#!/usr/bin/env bash
# Eval harness for the PR reviewer.
# Replays labeled past PRs through the REAL review pipeline (checkout -> review ->
# filter -> verify) with posting DISABLED, then scores the surviving findings
# against known-good labels and prints precision / recall / F1.
#
# This sources auto-review-prs.sh as a function library (AUTOPR_LIB=1) so it
# exercises the exact same pipeline the live tick uses — no drift.
#
# Labels: ~/.config/auto-pr-review/eval/labels.tsv (a template is created on
# first run). Run `eval-pr-review.sh` to replay every labeled PR.
#
# NOTE: eval calls cost real API tokens and are logged to usage.db like any
# other call. The monthly budget guard does NOT apply here (this is a manual
# tool), so run it deliberately.

set -euo pipefail

AUTOPR_LIB=1 source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/auto-review-prs.sh"

EVAL_DIR="${HOME}/.config/auto-pr-review/eval"
LABELS="${EVAL_DIR}/labels.tsv"
LINE_TOLERANCE="${LINE_TOLERANCE:-3}"   # a finding matches a label within +/- N lines
mkdir -p "$EVAL_DIR"

if [[ ! -f "$LABELS" ]]; then
  cat > "$LABELS" <<'TEMPLATE'
# Eval labels for the auto PR reviewer. Tab-separated. Lines starting with '#'
# and blank lines are ignored.
#
# Columns:  repo <TAB> pr <TAB> sha <TAB> kind <TAB> path <TAB> line <TAB> note
#
#   repo   full name, e.g. your-org/your-repo
#   pr     PR number
#   sha    the head SHA to replay (full 40-char or the PR head; the diff is
#          taken as base..sha so the replay is reproducible)
#   kind   'bug' = a real defect the reviewer SHOULD flag (expected finding)
#          'fp'  = NOT a defect; the reviewer should NOT flag this location
#   path   file path as it appears in findings (repo-relative)
#   line   line number of the issue
#   note   free text (why it is / isn't a bug) — for humans only
#
# Aim for ~15 PRs mixing real bugs it must catch and tempting false positives it
# must not emit. Every (repo,pr,sha) listed here is replayed once; all its label
# rows are scored against that single review.
#
# Example (delete once you add real ones):
# your-org/your-repo	123	abc123def456...	bug	app/models/user.rb	42	nil deref when email missing
# your-org/your-repo	123	abc123def456...	fp	app/services/pdf.rb	88	fallback is intentional
TEMPLATE
  echo "Created labels template: $LABELS"
  echo "Fill it in with ~15 labeled PRs, then re-run this script."
  exit 0
fi

# Collect non-comment label rows.
mapfile -t LABEL_ROWS < <(grep -vE '^[[:space:]]*(#|$)' "$LABELS" || true)
if [[ "${#LABEL_ROWS[@]}" -eq 0 ]]; then
  echo "No labels found in $LABELS (only comments/blank lines)."
  echo "Add label rows (see the header in that file), then re-run."
  exit 0
fi

# Neutral cwd for claude (same protection the live tick uses).
NEUTRAL_CWD=$(mktemp -d -t pr-eval-cwd.XXXXXX)
export CLAUDE_CWD="$NEUTRAL_CWD"
trap 'rm -rf "$NEUTRAL_CWD" "${CHECKOUT_DIR:-}" "${TICK_TMP:-}" 2>/dev/null || true' EXIT

# A run row so usage logging (reviews.run_id) has a valid parent.
RUN_ID=$(db_exec "INSERT INTO runs (started_at, pid) VALUES ('$(date -u +%Y-%m-%dT%H:%M:%SZ)', $$); SELECT last_insert_rowid();")

# Unique (repo,pr,sha) keys, order-preserving.
declare -A SEEN_PR
KEYS=()
for row in "${LABEL_ROWS[@]}"; do
  IFS=$'\t' read -r repo pr sha _kind _path _line _note <<<"$row"
  key="${repo}"$'\t'"${pr}"$'\t'"${sha}"
  if [[ -z "${SEEN_PR[$key]:-}" ]]; then SEEN_PR[$key]=1; KEYS+=("$key"); fi
done

TOT_TP=0; TOT_FP=0; TOT_FN=0; TOT_UNLABELED=0

# Does any emitted finding match (path == and |line diff| <= tol)?
# Reads the FINDINGS array from the enclosing scope.
finding_matches() {
  local tpath="$1" tline="$2" f fpath fline d
  for f in "${FINDINGS[@]:-}"; do
    [[ -z "$f" ]] && continue
    IFS=$'\t' read -r fpath fline <<<"$f"
    [[ "$fpath" == "$tpath" ]] || continue
    if [[ "$fline" =~ ^[0-9]+$ && "$tline" =~ ^[0-9]+$ ]]; then
      d=$(( fline > tline ? fline - tline : tline - fline ))
      (( d <= LINE_TOLERANCE )) && return 0
    elif [[ "$fline" == "$tline" ]]; then
      return 0
    fi
  done
  return 1
}

for key in "${KEYS[@]}"; do
  IFS=$'\t' read -r REPO PR SHA <<<"$key"
  echo ""
  echo "=== ${REPO}#${PR} @ ${SHA:0:7} ==="

  PR_VIEW=$(gh pr view "$PR" --repo "$REPO" 2>/dev/null) || PR_VIEW="(failed to fetch PR overview)"
  EXISTING_COMMENTS=$(gh api --paginate "repos/${REPO}/pulls/${PR}/comments" \
    --jq '.[] | "- \(.path):\(.line) [\(.user.login)]: \((.body // "")[0:200])"' 2>/dev/null) \
    || EXISTING_COMMENTS=""

  BASE=$(gh pr view "$PR" --repo "$REPO" --json baseRefOid --jq '.baseRefOid' 2>/dev/null) || BASE=""
  DIFF_TEXT=""
  if [[ -n "$BASE" ]]; then
    DIFF_TEXT=$(gh api "repos/${REPO}/compare/${BASE}...${SHA}" \
      --jq '.files[]? | "diff --git a/" + .filename + " b/" + .filename + "\n" + (.patch // "(binary or empty patch)")' \
      2>/dev/null) || DIFF_TEXT=""
  fi
  [[ -z "$DIFF_TEXT" ]] && DIFF_TEXT=$(gh pr diff "$PR" --repo "$REPO" 2>/dev/null) || true
  if [[ -z "$DIFF_TEXT" ]]; then
    echo "  SKIP: could not fetch diff"
    continue
  fi
  DIFF_TEXT=$(printf '%s' "$DIFF_TEXT" | strip_noise_from_diff)
  CHANGES=$(printf '%s\n' "$DIFF_TEXT" | diff_change_count)

  FINAL=""
  if ! FINAL=$(review_pipeline "$REPO" "$PR" "$SHA" 1 0 "" "$CHANGES" "$PR_VIEW" "$DIFF_TEXT" "$EXISTING_COMMENTS" "") \
     || [[ -z "$FINAL" ]] || ! printf '%s' "$FINAL" | jq . >/dev/null 2>&1; then
    echo "  SKIP: review pipeline produced no usable findings JSON"
    continue
  fi

  # Findings for this PR as "path<TAB>line" lines.
  mapfile -t FINDINGS < <(printf '%s' "$FINAL" | jq -r '(.findings // [])[] | "\(.path)\t\(.line)"')
  echo "  findings emitted: ${#FINDINGS[@]}  (stages: $(printf '%s' "$FINAL" | jq -c '.stages // {}'))"

  # This PR's labels.
  declare -a BUG_LABELS=() FP_LABELS=()
  for row in "${LABEL_ROWS[@]}"; do
    IFS=$'\t' read -r lrepo lpr lsha lkind lpath lline _lnote <<<"$row"
    [[ "$lrepo" == "$REPO" && "$lpr" == "$PR" && "$lsha" == "$SHA" ]] || continue
    case "$lkind" in
      bug) BUG_LABELS+=("${lpath}"$'\t'"${lline}");;
      fp)  FP_LABELS+=("${lpath}"$'\t'"${lline}");;
    esac
  done

  pr_tp=0; pr_fn=0; pr_fp=0
  for lbl in "${BUG_LABELS[@]:-}"; do
    [[ -z "$lbl" ]] && continue
    IFS=$'\t' read -r lpath lline <<<"$lbl"
    if finding_matches "$lpath" "$lline"; then pr_tp=$((pr_tp+1)); echo "  TP  caught bug      ${lpath}:${lline}"
    else pr_fn=$((pr_fn+1)); echo "  FN  MISSED bug      ${lpath}:${lline}"; fi
  done
  for lbl in "${FP_LABELS[@]:-}"; do
    [[ -z "$lbl" ]] && continue
    IFS=$'\t' read -r lpath lline <<<"$lbl"
    if finding_matches "$lpath" "$lline"; then pr_fp=$((pr_fp+1)); echo "  FP  flagged non-bug ${lpath}:${lline}"; fi
  done

  # Findings not matching any label of this PR (unknown ground truth).
  pr_unl=0
  for f in "${FINDINGS[@]:-}"; do
    [[ -z "$f" ]] && continue
    IFS=$'\t' read -r fpath fline <<<"$f"
    matched=0
    for lbl in "${BUG_LABELS[@]:-}" "${FP_LABELS[@]:-}"; do
      [[ -z "$lbl" ]] && continue
      IFS=$'\t' read -r lpath lline <<<"$lbl"
      if [[ "$fpath" == "$lpath" ]]; then
        if [[ "$fline" =~ ^[0-9]+$ && "$lline" =~ ^[0-9]+$ ]]; then
          d=$(( fline > lline ? fline - lline : lline - fline ))
          (( d <= LINE_TOLERANCE )) && { matched=1; break; }
        elif [[ "$fline" == "$lline" ]]; then matched=1; break; fi
      fi
    done
    (( matched == 0 )) && { pr_unl=$((pr_unl+1)); echo "  ??  unlabeled        ${fpath}:${fline}"; }
  done

  echo "  -> TP=$pr_tp FN=$pr_fn FP=$pr_fp unlabeled=$pr_unl"
  TOT_TP=$((TOT_TP+pr_tp)); TOT_FN=$((TOT_FN+pr_fn)); TOT_FP=$((TOT_FP+pr_fp)); TOT_UNLABELED=$((TOT_UNLABELED+pr_unl))
  unset BUG_LABELS FP_LABELS
done

db_exec "UPDATE runs SET ended_at='$(date -u +%Y-%m-%dT%H:%M:%SZ)' WHERE id=$RUN_ID;" 2>/dev/null || true

echo ""
echo "=================== EVAL SUMMARY ==================="
echo "TP=$TOT_TP  FP=$TOT_FP  FN=$TOT_FN  unlabeled=$TOT_UNLABELED"
awk -v tp="$TOT_TP" -v fp="$TOT_FP" -v fn="$TOT_FN" 'BEGIN{
  p = (tp+fp>0) ? tp/(tp+fp) : 0;
  r = (tp+fn>0) ? tp/(tp+fn) : 0;
  f1 = (p+r>0) ? 2*p*r/(p+r) : 0;
  printf "precision=%.3f  recall=%.3f  F1=%.3f\n", p, r, f1;
}'
echo "(unlabeled = findings with no matching label; label them to improve signal)"

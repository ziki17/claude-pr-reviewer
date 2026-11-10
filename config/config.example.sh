# Config for auto-pr-review. Sourced by auto-review-prs.sh.
# Installed as ~/.config/auto-pr-review/config.sh.

# GitHub organization whose open PRs are reviewed.
ORG="your-org"

# Repos in this org to *skip* (space-separated). Empty = review all.
SKIP_REPOS=""

# Skip draft PRs.
SKIP_DRAFTS=1

# Skip PRs authored by these GitHub logins (in addition to your own).
# The org PR search reports GitHub App logins without the "[bot]" suffix.
SKIP_AUTHORS="dependabot renovate github-actions dependabot[bot] renovate[bot] github-actions[bot]"

# Working directory Claude runs from when CLAUDE_CWD is unset (the live tick
# always sets a neutral temp cwd; this is only a fallback).
CLAUDE_WORKDIR="${TMPDIR:-/tmp}"

# ----- models -----
# Auth: whatever the Claude Code CLI uses. With a subscription login (or
# CLAUDE_CODE_OAUTH_TOKEN) total_cost_usd in usage.db is notional and the real
# constraint is the session rate limit (see pauses below). With ANTHROPIC_API_KEY
# set (shell env, or ~/.config/auto-pr-review/env for launchd) it is real spend.
CLAUDE_MODEL="claude-sonnet-5"
FALLBACK_MODEL="claude-haiku-5-5"      # last-resort only, on the final attempt
FILTER_MODEL="claude-haiku-5-5"        # FP/threshold filter pass
# Pinned so the bot does not follow the interactive effortLevel in
# ~/.claude/settings.json. Opus/Haiku 5.5 default to medium otherwise.
CLAUDE_EFFORT="high"

# Escalate to a stronger model ONLY when the diff touches a critical path.
# The old size trigger (>800 lines) is gone: big diffs are what made Opus hit
# max-turns; size is now handled by MAX_TURNS + salvage instead.
ESCALATION_MODEL="claude-opus-5-5"
CRITICAL_PATHS_REGEX="auth|payment|billing|credit|token|secret|password|crypto|security|migrat|schema\.rb$|structure\.sql$"
ESCALATION_BUDGET_USD=15               # notional monthly sub-cap, whole escalation family (claude-opus-*)

# ----- turns -----
# Agentic review explores the checkout. 20 turns produced 46 max-turns
# failures in Aug-Sep; runs that still hit the cap are salvaged by resuming the
# session for one turn and asking for the JSON.
MAX_TURNS=30
VERIFY_MAX_TURNS=10                    # per-finding refutation call (was 6, failed 76%)

# ----- size -----
MAX_FILES=60                           # above this (after noise stripping) -> partial review
MAX_CHANGES=5000                       # changed lines kept in a (partial) review
PARTIAL_REVIEW=1                       # 0 = skip oversized PRs as before
PARTIAL_HARD_MAX_CHANGES=20000         # above this even a partial review is skipped
# Never included in a partial review (tests, fixtures, docs).
TEST_PATHS_REGEX='(^|/)(test|tests|spec|__tests__|__mocks__|fixtures|__snapshots__|docs?)/|\.(test|spec)\.[cm]?[jt]sx?$|_spec\.rb$|_test\.(go|py|rb|ts|js)$|\.(md|mdx|txt|csv|svg)$'

# Skip PRs <= TRIVIAL_FILES files AND <= TRIVIAL_LINES lines (typo fixes).
TRIVIAL_FILES=1
TRIVIAL_LINES=10

# ----- thresholds -----
# Findings below these are dropped by the filter pass.
SEVERITY_THRESHOLD=3
CONFIDENCE_THRESHOLD=4
# Re-review convergence: incremental reviews post only severity >= this.
INCREMENTAL_MIN_SEVERITY=4

# ----- reliability -----
MAX_ATTEMPTS=3                         # per (repo, PR, SHA); rate-limit/auth pauses do NOT count
RETRY_SLEEP=15                         # seconds before retrying a transient primary failure
RATE_LIMIT_PAUSE_MIN=60                # fallback pause when the reset time cannot be parsed
AUTH_PAUSE_MIN=10                      # pause after an authentication failure
MAX_REVIEWS_PER_PR=5                   # auto-pause long-lived PRs after this many reviews

# ----- spend guard (real spend under an API key; notional under a subscription) -----
MONTHLY_BUDGET_USD=100

# Set NO_POST=1 in the environment to run the full pipeline and write the
# would-be payload to ~/.local/state/auto-pr-review/last-payload.json instead
# of posting. DRY_RUN=1 lists candidates without calling claude at all.

# ----- coverage contract -----
# Every reviewable file (RIGHT-side lines, not TEST_PATHS_REGEX) must be listed in
# files_reviewed. Missing ones get ONE resumed follow-up call of this many turns;
# files still missing are named in the summary. 0 = log coverage only.
COVERAGE_FOLLOWUP=1
COVERAGE_MAX_TURNS=15
# Path-specific checklists live in ~/.config/auto-pr-review/rules/ (index.tsv).

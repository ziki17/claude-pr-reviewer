# Design notes

How the reviewer got to its current shape: what broke in production, what the
data said about why, and what changed. All numbers below are measurements of
this bot on one GitHub organization's repositories, taken from its own
`usage.db`, `reviewed.tsv`, `run.log`, the headless Claude Code session
transcripts, and GitHub's GraphQL API. They describe the bot, not the code it
reviewed.

## Starting point

The first version was a single bash script on a launchd timer: poll every repo
in the org with `gh pr list`, shallow-checkout each new PR head, run
`claude -p` with read-only tools from a neutral working directory, pass the
findings through a cheaper model as a false-positive filter, and post inline
comments with `gh api`.

It worked, and early numbers looked fine: about 11.5 turns per review. But the
primary model "failed" on 14 of 58 calls (24%) in the first 30-day window, and
the fallback model then failed on 11 of those 14. The first plan assumed
transient network errors and added a retry with backoff, a network/auth
preflight, log rotation, deduplication against existing PR comments, a
per-finding verification pass and an eval harness.

The first bug fixed was a sandbox escape: the filter call ran from the
configured project directory instead of the neutral one, so that project's
`CLAUDE.md` was loaded into the filter's context.

## Cost controls

One month hit the then $50 budget halfway through; escalations to the larger
model were 46% of that month's spend. Three controls came out of it: a
monthly sub-budget for the escalation model, a per-PR cap, and a once-per-month
budget notification instead of one every five minutes. The per-PR cap later
changed from dollars to a count of reviewed pushes (`MAX_REVIEWS_PER_PR=5`,
the default CodeRabbit uses), because under a subscription the dollar figure
is notional.

## The September review: what was actually failing

A full review of 744 calls, the bot's posted reviews and 207 session
transcripts showed the failures were not network errors.

| Cause | Count | Effect |
|---|---|---|
| `max_turns` reached | 61 (46 primary at 20 turns, 15 verify at 6 turns) | The whole exploration was discarded and recorded as cost 0, so the budget guard under-counted. The PR was retried up to 3 times, then skipped for good. |
| Subscription rate limit | 16 | A 15 s retry cannot outlast a session limit. Each tick burned an attempt, so after 15 minutes of limiting the PR was permanently skipped. |
| `authentication_failed` | 13 | OAuth token refresh hiccups, same attempt-burning effect. |
| `Argument list too long` (E2BIG) | 12 in `claude`, 6 in `python3` | The prompt, including the diff, was passed as a command-line argument and hit the macOS argv limit. |

Other findings from the same review:

- Primary-call error rate since July: 115 of 286 (40%) for the default model,
  18 of 54 (33%) for the escalation model. Full-diff reviews failed 47% of the
  time, incremental reviews 7%.
- The verify stage errored on 42 of 55 calls (max-turns at 6) and had refuted
  2 findings ever.
- The incremental diff was wrong. It used `compare/PRIOR...HEAD`, which
  includes everything merged in from the base branch. One PR's "delta" was 70
  files and 301 KB, while the whole PR diff was 56 KB.
- Polling every repo with `gh pr list` every 5 minutes cost one API call per
  repo per tick and logged 352 failures. One search query returns the same PRs.
- 18 of 68 posted reviews had no inline comment at all, only an "lgtm" or
  "minor" summary.
- A thumbs-up/down reaction footer produced no usable feedback signal.

### Judging quality from GitHub

Since reactions gave no signal, quality is judged from what happens on the
review threads: a reply confirming or dismissing a finding, or the flagged line
changing before the PR is merged (the thread goes "outdated"). CodeRabbit,
Cursor and Greptile define acceptance the same way. On that measure, security
findings were the category least often acted on.

### What changed

1. **No author-controlled text in argv.** Prompts go to `claude -p` on stdin;
   the rubric and repo guidance go through `--append-system-prompt-file`; all
   temp files live in a per-tick directory outside the model's working
   directory. This removed the E2BIG class of failures.
2. **Salvage instead of discard.** On `error_max_turns` the script resumes the
   same session with `--resume <session_id> --max-turns 1` and asks for the
   final JSON from what it has already verified. `MAX_TURNS` went from 20 to
   30, and errored calls are now costed whenever their output is valid JSON.
3. **Pauses that do not burn attempts.** Rate-limit and auth failures write a
   `paused-until` epoch (parsed from the "resets 3pm" message when present),
   abort the tick, and do not count as an attempt. Ticks are skipped until the
   pause expires.
4. **PR-relative incremental diffs.** The delta is now the set of files whose
   patch differs between `compare/BASE...PRIOR` and `compare/BASE...HEAD`. A
   merge from the base branch yields an empty delta and the push is skipped.
   The 70-file, 301 KB delta above became 2 files and 2 KB.
5. **One GraphQL search per tick** (`org:ORG is:pr is:open`) instead of one
   list call per repo.
6. **Verify reworked, not dropped.** Disprove-style verification is what
   Anthropic, Cursor and CodeRabbit all run, so the concept stayed and the
   implementation changed: the finding's diff hunk is inlined, the turn budget
   is 10, and max-turns is salvaged the same way as the primary call.
7. **Zero-finding reviews are not posted**, and every finding's anchor is
   validated against the diff before posting (GitHub rejects the whole review
   with a 422 on one bad line).
8. **Escalation only on critical paths.** The size trigger was removed: large
   diffs were what made the larger model run out of turns.
9. **Per-stage counts** (`pipeline` table) so each filter's drop rate is
   visible.
10. **Labels from behaviour, not reactions** (`harvest-labels.sh`): a reply
    like "fixed" or an outdated thread on a merged PR is a `bug` label, a reply
    like "false positive" or "intentional" is `fp`.
11. **Weekly digest** of posts, stage drops, failure types and pauses.
12. **Partial review for oversized PRs**: critical-path files first, then the
    largest source files, tests and docs excluded, with the summary saying so.
13. **Security tally**: findings in the `security` category at severity 4 or
    above get a line at the top of the review body, since they were the
    category least often acted on.

After these changes, replaying a PR that had died at max-turns twice finished
in 17 turns, and a replay of another PR produced 2 findings, both anchored and
verified.

## An experiment that showed no effect

A code-graph tool (code-review-graph) was piloted to give the reviewer a
"what to read first" summary: a Tree-sitter graph of the checkout,
risk-scored changed functions, test gaps and blast radius, injected as an
untrusted block into the prompt. The decision gate set in advance was "at least
30% cheaper per review". Measured on successful reviews before and after:
$0.72 to $0.71 notional per review, 14.0 to 13.0 turns, input tokens about
flat. It also wrote about 10k INFO lines into `run.log` and caused the
`python3` E2BIG errors. The gate was not met and the integration was removed.

## Ideas adopted from alibaba/open-code-review

[open-code-review](https://github.com/alibaba/open-code-review) (Apache-2.0)
keeps everything that must not go wrong in deterministic code and uses the
model only for judgement. Before adopting its ideas, the baseline over 27
pipeline runs was 19 raw findings, 10 after the filter, 10 anchored,
9 verified, 7 posted. The filter was the biggest drop (47%), and nothing
recorded what it dropped.

- **Secret paths.** `.env*` (except `.example`/`.sample`/`.template`),
  `.npmrc`, `.pypirc`, `.netrc`, `.dockercfg`, SSH keys and `.ssh/` are removed
  from the diff before the model sees it and deleted from the checkout so the
  Read tool cannot reach them. Generated-code patterns (`*.gen.*`, `*.pb.*`,
  `__snapshots__/`) are stripped as noise.
- **Snippet anchoring.** The rubric requires `existing_code`: 1 to 5 verbatim
  lines from the new side of the diff. The harness finds them in the diff's
  right-side lines (whitespace-insensitive, within one hunk, nearest to the
  model's line hint) and turns a multi-line match into a `start_line..line`
  range. Fallbacks in order: first quoted line, exact line hint, line hint
  within 3 lines, file-level; anything else is dropped. Each finding records
  which path anchored it.
- **Dropped-findings table and a fact-check filter.** Every stage (threshold,
  filter, incremental, anchor, verify) writes what it removed and why to
  `dropped_findings`. The model no longer re-scores confidence (self-rated
  confidence is close to random, as Greptile reported); thresholds are applied
  in `jq` to the reviewer's own scores. The filter model may only remove a
  finding as a duplicate, as pure style/lint, when the described code is not in
  the file's diff (ground A), or when one diff line literally contradicts it
  (ground B). A and B must quote that line. Protected subjects (null
  dereference, bounds, concurrency, behaviour/compatibility change, unused
  parameter) are never removed. The model returns ids; the harness applies
  them, so the filter cannot rewrite a finding. Any failure keeps everything.
- **Coverage contract.** The reviewer must list every file in
  `files_reviewed` as reviewed, or skipped with a concrete reason. Files
  missing from that list (or skipped for running out of turns) get one resumed
  follow-up call; files still missing are named in the review summary. A replay
  of a 13-file PR loaded 3 checklists and covered 10 of 10 reviewable files
  without needing the follow-up.
- **Path-scoped rule checklists.** `rules/index.tsv` maps a repo regex and a
  path regex to a checklist file. A checklist is added to the user prompt only
  when a non-test file in the diff matches, so the system prompt stays
  byte-stable per repo for prompt caching.

Not implemented so far: semantic bundling of large PRs into groups and a second
review round (both cost more calls on a rate-limited subscription and wait on
eval data showing recall gaps), GitHub suggestion blocks, and a separate
planning call (the reviewer already plans within its 30 turns).

## Model and effort pinning

Every call passes `--effort` explicitly so the bot does not inherit whatever
effort level the interactive CLI is configured with. The escalation budget sums
spend across the whole model family (`claude-opus-*`), so bumping the model
version mid-month does not reset the sub-budget.

## File-tool scope

Passing only `--allowed-tools "Read,Grep,Glob"` does not confine those tools
to the checkout. In a test with Claude Code 2.1.322, run from an empty
directory with the checkout as `--add-dir`, `Read` and `Grep` returned a marker
file that sat outside both. Every call now also passes
`--settings '{"permissions":{"blockReadsOutsideWorkingDirectories":true}}'`.
In the same test, `Read`, `Grep` and `Glob` on the outside file were then
refused (reported in `permission_denials`), and a file inside the checkout was
still readable.

## Still open

- The eval harness exists and the label set is growing, but no threshold has
  been tuned against it yet.
- Security findings are the category least often acted on. Whether that is
  because they are wrong or because they are out of scope has not been settled.

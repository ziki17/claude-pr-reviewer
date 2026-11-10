-- Auto-PR-Review usage log schema.
-- Applied idempotently on every script startup via `sqlite3 $USAGE_DB < schema.sql`.

CREATE TABLE IF NOT EXISTS runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  pid INTEGER,
  reviews_attempted INTEGER DEFAULT 0,
  reviews_posted INTEGER DEFAULT 0,
  reviews_failed INTEGER DEFAULT 0,
  skipped_already_reviewed INTEGER DEFAULT 0,
  skipped_trivial INTEGER DEFAULT 0,
  skipped_too_large INTEGER DEFAULT 0,
  skipped_exhausted INTEGER DEFAULT 0,
  budget_blocked INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS reviews (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id INTEGER,
  repo TEXT NOT NULL,
  pr INTEGER NOT NULL,
  head_sha TEXT NOT NULL,
  attempt INTEGER NOT NULL,
  model TEXT NOT NULL,
  phase TEXT NOT NULL,             -- 'primary' | 'salvage' | 'fallback' | 'filter' | 'verify' | 'verify-salvage'
  is_incremental INTEGER DEFAULT 0,
  delta_from_sha TEXT,
  call_started_at TEXT NOT NULL,
  duration_ms INTEGER,
  num_turns INTEGER,
  input_tokens INTEGER,
  output_tokens INTEGER,
  cache_read_input_tokens INTEGER,
  cache_creation_input_tokens INTEGER,
  cache_5m_input_tokens INTEGER,
  cache_1h_input_tokens INTEGER,
  total_cost_usd REAL,
  is_error INTEGER DEFAULT 0,
  stop_reason TEXT,
  session_id TEXT
);

CREATE TABLE IF NOT EXISTS posts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id INTEGER,
  repo TEXT NOT NULL,
  pr INTEGER NOT NULL,
  head_sha TEXT NOT NULL,
  github_review_id INTEGER,
  verdict TEXT,
  findings_n INTEGER,
  posted_at TEXT NOT NULL,
  is_fallback_body INTEGER DEFAULT 0
);

-- Per-stage finding counts for one pipeline run: what the filter, anchor
-- validation and verify stages actually drop.
CREATE TABLE IF NOT EXISTS pipeline (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id INTEGER,
  repo TEXT NOT NULL,
  pr INTEGER NOT NULL,
  head_sha TEXT NOT NULL,
  attempt INTEGER NOT NULL,
  model TEXT NOT NULL,
  is_incremental INTEGER DEFAULT 0,
  is_partial INTEGER DEFAULT 0,
  findings_raw INTEGER DEFAULT 0,
  findings_filtered INTEGER DEFAULT 0,
  findings_anchored INTEGER DEFAULT 0,
  findings_verified INTEGER DEFAULT 0,
  findings_posted INTEGER DEFAULT 0,
  verdict TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_pipeline_created ON pipeline(created_at);

-- Every finding a stage removed, with the stage's reason, so drops can be
-- checked against eval/labels.tsv. stage: threshold | filter |
-- incremental | anchor | verify.
CREATE TABLE IF NOT EXISTS dropped_findings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id INTEGER,
  repo TEXT NOT NULL,
  pr INTEGER NOT NULL,
  head_sha TEXT NOT NULL,
  attempt INTEGER NOT NULL,
  stage TEXT NOT NULL,
  reason TEXT,
  path TEXT,
  line INTEGER,
  severity INTEGER,
  confidence INTEGER,
  category TEXT,
  body TEXT,
  existing_code TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_dropped_repo_pr ON dropped_findings(repo, pr);

CREATE INDEX IF NOT EXISTS idx_reviews_started ON reviews(call_started_at);
CREATE INDEX IF NOT EXISTS idx_reviews_repo_pr ON reviews(repo, pr);
CREATE INDEX IF NOT EXISTS idx_runs_started  ON runs(started_at);
CREATE INDEX IF NOT EXISTS idx_posts_repo_pr ON posts(repo, pr);

-- Spend by month. Cache hit % is (cache_read / total_input_processed).
DROP VIEW IF EXISTS monthly_spend;
CREATE VIEW monthly_spend AS
SELECT
  strftime('%Y-%m', call_started_at) AS month,
  ROUND(SUM(total_cost_usd), 2)      AS cost_usd,
  COUNT(*)                            AS calls,
  SUM(input_tokens)                   AS input_tokens,
  SUM(output_tokens)                  AS output_tokens,
  SUM(cache_read_input_tokens)        AS cache_read_tokens,
  SUM(cache_creation_input_tokens)    AS cache_creation_tokens,
  ROUND(100.0 * SUM(cache_read_input_tokens)
              / NULLIF(SUM(input_tokens + cache_read_input_tokens + cache_creation_input_tokens), 0), 1) AS cache_hit_pct
FROM reviews
WHERE is_error = 0
GROUP BY month
ORDER BY month DESC;

-- Most expensive PRs (lifetime sum).
DROP VIEW IF EXISTS pr_cost;
CREATE VIEW pr_cost AS
SELECT
  repo, pr,
  COUNT(*)                       AS calls,
  ROUND(SUM(total_cost_usd), 4)  AS cost_usd,
  MIN(call_started_at)           AS first_call,
  MAX(call_started_at)           AS last_call
FROM reviews
WHERE is_error = 0
GROUP BY repo, pr
ORDER BY cost_usd DESC;

-- Daily roll-up for sparkline / weekly digest.
DROP VIEW IF EXISTS daily_spend;
CREATE VIEW daily_spend AS
SELECT
  date(call_started_at)          AS day,
  ROUND(SUM(total_cost_usd), 2)  AS cost_usd,
  COUNT(*)                       AS calls,
  SUM(CASE WHEN is_error = 1 THEN 1 ELSE 0 END) AS errors
FROM reviews
GROUP BY day
ORDER BY day DESC;

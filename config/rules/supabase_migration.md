Postgres/Supabase migration. Precision over recall: read earlier migrations (`supabase/migrations/`) and the calling code before claiming a table, policy or column is missing or unused. Assume rolling deploys: old app code runs against the new schema for a while.

- **RLS**: a new table in an exposed schema (`public`) without `ENABLE ROW LEVEL SECURITY`, or RLS enabled with no policy while app code reads it with the user client. Policies must scope rows to `auth.uid()` / membership, not `USING (true)` for writes; `WITH CHECK` missing on INSERT/UPDATE policies that should restrict the new row.
- **Security definer**: `SECURITY DEFINER` functions without `SET search_path = ''` (or a fixed schema list), or that expose other users' rows because they skip the caller's permission check. Prefer `SECURITY INVOKER` unless the function needs elevated rights.
- **Grants**: `GRANT ... TO anon` or `authenticated` broader than the feature needs; new function callable by `anon` that should not be.
- **Destructive or incompatible change**: `DROP COLUMN/TABLE`, `RENAME`, type narrowing, or new `NOT NULL` without a default/backfill on a table with existing rows, while code in this PR or the base branch still reads the old shape. Say which caller breaks.
- **Data backfill**: `UPDATE` without a `WHERE` that targets exactly the intended rows; backfill that can fail on existing data (unique or FK violations).
- **Balances** (billing, credits, tokens): any `UPDATE ... SET balance = balance ± x` or other in-place mutation of a derived value, when the project records them as events (severity 5).
- **Indexes**: missing index on a new foreign key or on a column the PR's queries filter by on a large table; `CREATE INDEX CONCURRENTLY` inside a migration that runs in a transaction (fails).
- **Triggers and cron**: trigger functions that can recurse or fire on every row of a bulk update unexpectedly; `cron.schedule` jobs without an idempotent body or with a name that collides with an existing job.
- **Migration file** looks hand-named (timestamp out of order with neighbours, or not 14 digits) instead of generated with `supabase migration new`.

Do not report: formatting, naming style, comment wording, or "consider an index" without a query in the code that needs it.

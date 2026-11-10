Supabase JS client usage in app code.

- **Large `.in()`**: `.in("col", ids)` where `ids` grows with users or content. PostgREST puts the filter in the URL, so behind a proxy with a URL length limit a large array fails with a 502 or a silent empty result that does not reproduce locally. Large or unbounded arrays must be chunked or moved into an RPC. Bounded-small arrays (static enums, one user's handful of memberships) are fine.
- **Ignored `error`**: code that reads only `data` from a Supabase call, so a failed query looks like "no rows" and the caller acts on it (e.g. treats the user as having no entitlement, or creates a duplicate).
- **Service-role client** in code reachable from a user request without an explicit authorization check for the specific rows (RLS is bypassed).
- **Balances** (billing, credits, tokens) mutated in place when the project records them as events (severity 5).

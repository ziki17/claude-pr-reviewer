# Per-repo review guidance: your-org/example-repo

Appended to the system prompt for PRs in this repo only. Copy this file to
`repos/<owner>/<repo>.md` and replace the content. Keep it short and concrete:
every line costs prompt tokens on every review of this repo.

Stack (illustrative): Next.js App Router, TypeScript, Postgres via Supabase,
Vitest for unit tests, Playwright for end-to-end tests.

## Always flag (severity 5)

- Server code that reads or writes another user's rows without checking the
  caller (missing ownership or membership check before a service-role query).
- Secrets, tokens or connection strings committed in code or logged.
- A migration that drops or renames a column the current app code still reads.

## Always flag (severity 4)

- A new route handler or server action without input validation.
- User-facing strings hard-coded in components instead of the message catalog.
- Queries inside a loop over request data (N+1) on pages that list records.
- Business logic changed without a matching test change.

## Usually ignore (Do NOT flag)

- Formatting, import order and naming: Prettier and ESLint run in CI.
- `any` in test files and fixtures.
- Generated files under `lib/database.types.ts`.
- Missing memoisation in components that render once per page load.

## Patterns the team has chosen, do not suggest changing

- Server actions return `{ error }` objects instead of throwing.
- Data fetching happens in server components, not in client `useEffect`.

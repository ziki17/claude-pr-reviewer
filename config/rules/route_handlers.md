Next.js Route Handler (`app/**/route.ts`).

- **Auth**: a new handler, or a new method in one, that reads or writes user data without authenticating the caller. Scheduled (cron) handlers must reject requests that do not carry the shared secret the platform sends (for example an `Authorization: Bearer` header checked against an env var, and rejecting when that env var is unset). Webhook handlers must verify the provider signature before acting.
- **Service-role access** driven by request input (ids, query params) without verifying the caller may touch those rows.
- **Input validation**: request body or params used without validation in queries, prompts or outbound calls; missing size limits on uploaded or streamed input.
- **Streaming**: a stream that is never closed on error, or errors swallowed after the response started so the client hangs.
- **Idempotency**: cron and webhook handlers that double-apply side effects (emails, credits, status changes) when retried or run concurrently.

Do not report: response shape style or status-code preferences without a caller that depends on them.

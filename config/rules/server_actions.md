Next.js Server Actions (`"use server"`). Every exported function is a public POST endpoint that any client can call with arbitrary arguments.

- **Authorization inside the action**: each exported action must check the caller itself (an auth helper, membership/ownership of the target row, or an RLS-scoped user client). A check only in the calling page or component does not count.
- **Service-role client** used after a check that does not cover the specific row being read or written, or with ids taken straight from arguments without an ownership check.
- **Input trust**: arguments used in queries, file paths, URLs or prompts without validation; a client-supplied price, credit amount, role or user id that the server should derive itself.
- **Errors**: the `{ error }` of a Supabase call ignored so the action reports success after a failed write; thrown errors that leak internal details to the client.
- **Cache**: a mutation that changes data shown on a page without `revalidatePath` / `revalidateTag` for that page (only if the page reads that data).

Do not report: "move this to a Route Handler" or vice versa (team choice).

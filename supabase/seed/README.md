# Demo seed

Creates a realistic contractor account in `pnchd-dev` and prints a working
sign-in link, so the app can be opened without waiting on a magic-link email.

```bash
cd supabase/seed
SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... deno task demo
```

Creates `demo@pnchd.test` (owner, "Ridgeline Construction") and
`client@pnchd.test` (their client), with 6 projects, 3 proposals, 3 invoices
with line items, and 3 active modules.

**Idempotent** — re-running wipes and recreates both accounts. Safe to run
repeatedly; the printed magic link is single-use, so re-run to get a fresh one.

Set `REDIRECT_TO` to point the link somewhere other than
`http://localhost:5183/dashboard`.

Never point this at production. It deletes accounts by email.

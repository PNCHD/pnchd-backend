# PNCHD — Session Hand-off (Phase 2, Block B)

## What this is
I'm building PNCHD ("Punched"), a modular contractor management SaaS —
Flutter mobile, React web dashboard, Supabase backend. Full architecture,
pricing model, schema, and RLS strategy live in `docs/ARCHITECTURE.md` in
this repo (pnchd-backend). Read that file first — it's the source of truth
for every decision below.

## Repo layout
- `pnchd-backend` — this repo. `docs/ARCHITECTURE.md`, `supabase/migrations/`,
  and (later) Edge Functions live here.
- `pnchd-mobile` — Flutter app (Pro contractor app + Client/Driver app).
- `pnchd-web` — React + TypeScript + Tailwind web dashboard and landing page.

## Supabase projects
- `pnchd-dev` — linked to this repo's CLI, all migrations pushed here so far.
- `pnchd-prod` — created, not yet linked or touched. Don't push here until
  Section 12.3 (Supabase Production checklist) in the architecture doc.

## What's done — Phase 2, Block A (database schema) — COMPLETE
All 11 migrations live in `supabase/migrations/` (timestamp-prefixed,
e.g. `20260808164940_organizations_profiles.sql`), pushed to `pnchd-dev` and
confirmed via `supabase migration list` (local == remote). Committed and
pushed to `origin/main` at `3b74da4`.

Note: migrations 001–008 were built and initially committed sitting at the
repo root with plain `001_`–`008_` numeric names, not inside
`supabase/migrations/` — meaning nothing had actually reached `pnchd-dev`
despite this doc previously claiming otherwise. Caught and fixed this
session: all files renamed to proper timestamp-prefixed names and moved
into `supabase/migrations/`, then pushed for real.

| File | Tables | Notes |
|---|---|---|
| 001 | organizations, profiles | Auto-create-profile trigger on `auth.users` insert (`organization_id` starts NULL, signup flow fills it in) |
| 002 | module_subscriptions | `has_active_module()` helper function for future module-gated RLS (Section 7.3 pattern) |
| 003 | projects | `set_updated_at()` reusable trigger function |
| 004 | project_assignments | Also adds the driver-read policy on `projects` that depends on this table |
| 005 | proposals | Client can only set `approved_at`, enforced by trigger, auto-flips `status` to `approved` |
| 006 | invoices | Client can only move `status` from `sent` → `approved`, enforced by trigger. Payment/`paid` status is webhook-only |
| 007 | line_items | Polymorphic (`parent_type`/`parent_id`) — no real FK possible, so a trigger validates the parent row exists |
| 008 | documents, document_signers | Signer can only set `signed_at` once, enforced by trigger, auto-flips `status` to `signed` |
| 009 | vehicles, vehicle_locations | Fleet module. `vehicle_locations` RLS ANDs `has_active_module('fleet_tracking')` into each policy directly (not a standalone policy — separate permissive policies OR together in Postgres RLS, which would've defeated the gating) |
| 010 | notifications | Scoped to `recipient_id = auth.uid()`, not org-wide like every other table — Section 7.2 gives owner/pro no special read access here. Inserts are Edge-Function-only via service role, same as `module_subscriptions` |
| 011 | vehicles index | Follow-up: added `idx_vehicles_organization_id`. Section 6 listed no index for `vehicles` at all (every other table gets one); flagged instead of guessing, added on explicit call once you confirmed it |

### Conventions established — follow these for new tables
- Every table: `alter table X enable row level security;`
- Every table gets an `admin_bypass_X` policy (`role = 'platform_admin'`) so the
  Section 15.3 admin dashboard works without special-casing.
- Standard org-isolation policy pattern (Section 7.1):
  `organization_id = (select organization_id from profiles where id = auth.uid())`
- Role checks inline via `(select role from profiles where id = auth.uid())`,
  not a separate helper — kept consistent across files rather than mixed.
- Where a role should only be able to write specific columns (client
  approving a proposal, a signer setting `signed_at`), that's enforced with a
  `before update` trigger, not the RLS policy itself — Postgres RLS can't do
  column-level restriction on its own.
- Indexes follow Section 6 exactly, composite where the doc lists two columns
  together (e.g. `organization_id, client_id`).
- Comments (`comment on table/column`) added wherever the doc gives useful
  context, so `\d+ tablename` in psql is self-documenting.

### Known gaps flagged during Block A (unresolved, need your call)
1. **Proposals have no rejection path.** Schema only has `approved_at`, no
   `rejected_at`. Client approval works; client rejection doesn't have a
   column to write to yet.
2. **Client document visibility is signer-only.** A client can only see a
   `document` if they appear in `document_signers` for it — there's no
   `client_id` on `documents` itself, so they can't browse "all documents on
   my project" before being added as a signer.

Neither was in scope to silently fix — surfacing them here instead of
guessing at schema additions that weren't spec'd.

## What's next
**Block B — Supabase client setup in both apps.** In progress, paused mid-way.

`pnchd-mobile` — DONE, committed and pushed (`5a8e89f`):
- `flutter create --org io.pnchd --project-name pnchd_mobile --platforms ios,android .`
- `supabase_flutter` added. `lib/core/supabase/supabase_client.dart` per the
  Section 9.1 folder structure — initializes from `SUPABASE_URL`/
  `SUPABASE_ANON_KEY` via `--dart-define` (Section 11.3). Uses the current
  `publishableKey` param, not the deprecated `anonKey` one, but kept the env
  var name matching the doc's Section 11.3 naming.
- `main.dart` replaced the counter demo with a placeholder screen showing
  the Supabase client connected. `test/widget_test.dart` updated to match,
  using `EmptyLocalStorage` so the test doesn't need platform plugins.
- `flutter analyze` clean.

`pnchd-web` — IN PROGRESS, NOT committed, NOT pushed. Left mid-edit:
- Scaffolded via `npm create vite@latest . -- --template react-ts --overwrite`,
  `npm install` done.
- `tailwindcss` + `@tailwindcss/vite` installed but **not yet wired in** —
  `vite.config.ts` still just has the React plugin, `src/index.css` still
  has Vite's demo styling, no `@import "tailwindcss";` added yet.
- Deleted the Vite demo assets (`src/assets/`, `src/App.css`,
  `public/icons.svg`, `public/vite.svg`) intending to replace `src/App.tsx`
  with a minimal placeholder (mirroring the mobile side), **but `App.tsx`
  still imports the deleted files — the app will not build right now.**
- Not started yet: `@supabase/supabase-js` install, `src/lib/supabase.ts`
  client, `.env.local`/`.env.example` for `VITE_SUPABASE_URL`/
  `VITE_SUPABASE_ANON_KEY` (Section 11.1).
- **Next session, start here:** rewrite `src/App.tsx` to drop the deleted
  imports (or restore them), finish the Tailwind wiring, then pick back up
  at the Supabase client install.
- Anon/publishable key for `pnchd-dev` already fetched this session via
  `supabase projects api-keys --project-ref jzmcgxugmeaebvxcrkjn` if needed
  again — publishable key starts `sb_publishable_Sgf-Mjng...`.

**After that** — rest of Block B–D: Flutter folder scaffolding per Section
9.1, React page scaffolding per Section 10.2. Then Phase 2's remaining
piece: Stripe Edge Functions (Section 8.2/8.3) — webhook handlers for
`customer.subscription.updated` and `payment_intent.succeeded`, plus the
Docuseal webhook (Section 8.1).

## How I like to work
Decision-already-made, execute-only-that, move-on. I don't need elaborate
planning restated back to me — pick the next unchecked item, build it
matching the established patterns, flag anything genuinely ambiguous, and
keep moving. If something in the architecture doc conflicts with what's
already built, tell me directly rather than picking a side quietly.

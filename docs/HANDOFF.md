# PNCHD — Session Hand-off (Phase 2, Block I)

## What this is
I'm building PNCHD ("Punched"), a modular contractor management SaaS —
Flutter mobile, React web dashboard, Supabase backend. Full architecture,
pricing model, schema, and RLS strategy live in **`docs/ARCHITECTURE.md`** in
this repo (pnchd-backend). Read that file first — it's the source of truth
for every decision below.

## Docs in this repo
- **`docs/ARCHITECTURE.md`** — the source of truth. v3.0, markdown. Contains
  everything from the original `.docx` plus every decision made since, with
  additions marked `[Added v3.0]`. **Edit this file**, not the `.docx`.
- `docs/ARCHITECTURE.docx` — superseded v2.0. Retained for reference only;
  no longer authoritative and intentionally not maintained.
- `docs/ENGINEERING_NOTES.md` — running explanation log. The *why* and the
  gotchas behind the architecture: RLS policy composition, auth/session
  mechanics, webhook correctness, framework-version traps, and bugs hit
  along the way with their root causes.
- `docs/ACCESS_MODEL.md` — **proposal, not built.** Subcontractor and
  multi-organization access, the permission model for money, and the
  security principles behind them (fail-closed, access-as-data, restrictive
  policies, column-level grants). Two decisions open at the bottom.
- `docs/HANDOFF.md` — this file. Session state, what's done, what's next.

## Repo layout
- `pnchd-backend` — this repo. `docs/`, `supabase/migrations/`,
  and `supabase/functions/` (Edge Functions) live here.
- `pnchd-mobile` — Flutter app (Pro contractor app + Client/Driver app).
- `pnchd-web` — React + TypeScript + Tailwind web dashboard and landing page.

## Engineering standards — read before writing any code
These are non-negotiable and apply to `pnchd-mobile` and `pnchd-web`
equally. The goal: if this software is ever sold, the buyer's dev team
should inherit a clean, scalable codebase and be productive immediately.
No technical debt is accepted as a tradeoff for shipping faster.

**Layering / decoupling**
- Data access lives in a dedicated repository layer. Never call
  `supabase.from(...)` (or `@supabase/supabase-js` equivalents) inline from
  a state provider, hook, widget, or component.
- Reference implementation: `pnchd-mobile/lib/core/data/*_repository.dart`,
  with Riverpod providers depending on repositories. Mirror this in
  `pnchd-web` — a repository/data module wrapping Supabase, not calls
  scattered through React components.
- Repositories take an injectable client (defaulting to the shared
  singleton) so they can be constructed with a fake in tests.

**Shared / injectable libraries**
- Styling and theming live in one centralized, swappable place
  (`core/theme/app_theme.dart` on mobile; the Tailwind `@theme` token block
  on web). Never hardcode brand colors per-screen.
- Shared UI (page shells, buttons, cards, empty/error states) gets
  extracted into a reusable component library. Rule of thumb: if 2+ screens
  repeat the same structural boilerplate, extract it rather than
  copy-pasting. Reference: `core/widgets/placeholder_screen.dart`.

**Testing**
- Write tests as the code lands, not in a deferred "testing pass."
  Untested logic counts as technical debt.
- Structure code to be testable. When meaningful logic is entangled with
  framework objects, extract it into a pure function. Reference:
  `core/router/redirect_logic.dart` — role-based routing pulled out of the
  GoRouter wiring into `resolveRedirect(profile, path)`, unit tested
  without needing a router or widget tree.

**Comments**
- Only where they earn their place, and concise. Skip comments that
  restate the code. Keep the ones carrying what code can't: why a
  non-obvious approach was chosen, a subtle framework behavior that would
  otherwise read as a bug, architecture-doc section references, and
  deliberately flagged gaps.

**Applying this**
- All of the above is part of the definition of done for every piece of
  work — including scaffolding, since scaffolding decisions calcify once
  real features build on top of them. It should not require a review pass
  or a prompt to get there.

## Product requirements
- **`pnchd-mobile` must support phone and tablet on both iOS and Android** —
  not just install/run, but adapt its layout to the larger canvas. Native
  project config already permits this on both platforms (iOS:
  `TARGETED_DEVICE_FAMILY = "1,2"` plus `UISupportedInterfaceOrientations~ipad`
  in `Info.plist`, both set by `flutter create` already; Android: no
  `<supports-screens>` restriction or `resizeableActivity="false"`, so
  nothing to change there either). What's NOT done yet: no screen exists
  yet to actually be responsive. Standing convention once `features/`
  screens get built (Section 9.1): use `LayoutBuilder`/breakpoints rather
  than fixed phone-width assumptions, same way the web dashboard should
  already be responsive by nature of being a browser app.

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
| 012 | client_feature_toggles | New table, not in ARCHITECTURE.docx yet. Owner-controlled on/off switch for client-facing capabilities (pay invoices, sign docs, messaging), independent of `module_subscriptions.is_active` (billing). Mirrors `has_active_module()` with a new `is_client_feature_enabled()` function. Not yet wired into the existing invoices/documents client RLS policies — see Block C gaps below |
| 013 | notifications type widening | Added `document_pending_signature`, `invoice_pending_payment`, `proposal_pending_approval` to the `type` check constraint — the original enum (010) only covered completion events, nothing for "something new landed in your queue" |

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

### Known gaps flagged during Block C (unresolved, need your call)
1. **`client_feature_toggles` isn't enforced at the RLS level yet.** A
   client can still approve/pay an invoice or sign a document via direct
   table access today regardless of the toggle — it only controls what the
   client app's UI chooses to show. Extending the existing client policies
   on `invoices`/`documents` (migrations 006/008) to also require
   `is_client_feature_enabled(...)` is real follow-up work, not done here.
2. **No push notification on assignment, only on completion.** Docuseal
   emails a client automatically when a document is assigned to them
   (Section 8.1 step 4), and `notifications.type` now has the enum values
   for pending-action rows (`document_pending_signature`,
   `invoice_pending_payment`, `proposal_pending_approval`), but nothing
   actually inserts those rows or sends an FCM push (Section 8.4) when a
   document/invoice/proposal gets assigned to a client — only Docuseal's
   own email exists today. The client-side to-do flow (in-app badge +
   push, not just email) needs an Edge Function or trigger that fires on
   assignment, not just on the existing completion webhooks. Not built —
   flagging so it's not lost before Edge Functions get built (Section
   8.2/8.3/8.4 is still queued in "What's next" below).

### Decisions confirmed this session
- **`client_feature_toggles` stays org-wide, no per-client override.** One
  set of switches per organization, applies to every client uniformly —
  matches how `module_subscriptions` already works (org-level, not
  per-user). Confirmed rather than assumed, since the schema as built
  (no `client_profile_id` column) only supports this and not per-client
  granularity. **You flagged wanting per-client override as a possible
  future change** — not built now, but when it comes up: add a nullable
  `client_profile_id` column (null row = org-wide default, a row with a
  specific `client_profile_id` overrides just that client), and
  `is_client_feature_enabled()` needs to check for a client-specific row
  before falling back to the org-wide one.

## What's next
**Block B — Supabase client setup in both apps — COMPLETE.**

`pnchd-mobile` — committed and pushed (`5a8e89f`, theming follow-up `daca3c3`):
- `flutter create --org io.pnchd --project-name pnchd_mobile --platforms ios,android .`
- `supabase_flutter` added. `lib/core/supabase/supabase_client.dart` per the
  Section 9.1 folder structure — initializes from `SUPABASE_URL`/
  `SUPABASE_ANON_KEY` via `--dart-define` (Section 11.3). Uses the current
  `publishableKey` param, not the deprecated `anonKey` one, but kept the env
  var name matching the doc's Section 11.3 naming.
- `main.dart` replaced the counter demo with a placeholder screen showing
  the Supabase client connected. `test/widget_test.dart` updated to match,
  using `EmptyLocalStorage` so the test doesn't need platform plugins.
- `flutter analyze` clean. Placeholder screen themed with Section 1.2 brand
  colors (navy/red/light-gray) — explicitly a placeholder, expect a real
  theming pass later.

`pnchd-web` — committed and pushed (`3e6b058`, theming follow-up `8bf3dc2`):
- Scaffolded via `npm create vite@latest . -- --template react-ts --overwrite`.
- Tailwind v4 wired in via the `@tailwindcss/vite` plugin (v4's model: no
  `tailwind.config.js`/PostCSS, just the Vite plugin plus
  `@import "tailwindcss";` in `src/index.css`). Brand colors registered as
  named tokens via Tailwind v4's CSS-based `@theme` block (`--color-navy`,
  `--color-brand-red`, `--color-app-bg`), same placeholder-only caveat as
  mobile.
- `@supabase/supabase-js` added. `src/lib/supabase.ts` reads
  `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY` from `.env.local` (gitignored
  via the default Vite `*.local` pattern; `.env.example` documents the shape,
  committed) per Section 11.1.
  Worth knowing: `createClient()`'s defaults persist the session
  (access + refresh token) in browser `localStorage` and silently
  auto-refresh the access token on a timer while the tab is open —
  `persistSession`/`autoRefreshToken` both default `true`. That's why a
  logged-in session survives a page reload with no extra code. It also means
  the token sits in `localStorage`, not an httpOnly cookie — acceptable here
  specifically because RLS is the real security boundary (Section 7), so a
  leaked token only grants what that user's own RLS policies already allow.
- `tsc -b && vite build` clean.
- Anon/publishable key for `pnchd-dev` fetched via
  `supabase projects api-keys --project-ref jzmcgxugmeaebvxcrkjn` if needed
  again — publishable key starts `sb_publishable_Sgf-Mjng...`.

## Block C — Flutter folder scaffolding (Section 9.1) — DONE for pnchd-mobile
Committed and pushed (`4c273fd`). React page scaffolding (Section 10.2)
still queued — see "What's next" below.

- `core/{auth,data,models,router,theme,supabase}` + `features/*` +
  `features/settings/*` all built out. Riverpod (`flutter_riverpod`) +
  GoRouter (`go_router`) added.
- **Repository layer**: `core/data/{profile,module,client_feature}_repository.dart`
  wrap all Supabase calls. Providers depend on repositories, not
  `supabase.from(...)` directly — decouples fetch logic from state/UI,
  makes it swappable/mockable. Established as the standing convention for
  new data access going forward.
- **Role-based routing**: `core/router/redirect_logic.dart` has a pure
  `resolveRedirect(profile, path)` function (owner/pro → contractor shell,
  client → `/client`, driver → `/driver`, signed out → `/onboarding`),
  unit tested (`test/core/router/redirect_logic_test.dart`, 11 cases).
  Pulled out of the GoRouter wiring specifically so it doesn't need a
  GoRouterState/widget tree to test.
- **Found and fixed a real race condition**: `refreshListenable` was
  originally built from the raw Supabase auth stream directly, which fires
  synchronously. `currentProfileProvider` does an async transform on top of
  that same event (even the signed-out fast path costs a microtask, since
  it's still an `async` function) — so the redirect re-check was firing
  before the profile provider had actually finished updating, read stale
  `AsyncLoading` state, and nothing ever triggered a second attempt. Fixed
  by deriving `refreshListenable` from `ref.listen(currentProfileProvider, ...)`
  instead of the raw stream — ties the refresh to the actual data changing,
  not the upstream trigger.
- **Module-gated bottom nav** (`core/router/contractor_shell.dart`): reads
  `activeModulesProvider`, only shows tabs for active modules.
  `dashboard`/`projects` are core and always visible. This is the concrete
  mechanism behind "contractors add/remove modules and the app adapts."
- Every `features/*` screen is a placeholder — `client_payments` and
  `messaging` have screen files but aren't wired into any route yet
  (`client_payments` needs `client_view` built out for real first;
  `messaging` is a roadmap module).
- **Shared component follow-up** (`83e42d3`): every placeholder screen was
  independently rebuilding the same Scaffold/AppBar/centered-text
  boilerplate — pulled into `core/widgets/placeholder_screen.dart`. Standing
  rule going forward: if 2+ screens repeat the same structural boilerplate,
  extract it instead of leaving it copy-pasted.
- `flutter analyze` clean, 12/12 tests passing.

## Block D — Edge Functions (Sections 8.1/8.2/8.3/8.5)

**Critical bug found and fixed first.** Migrations 001–014 enabled RLS and
wrote policies but never granted SQL table privileges. GRANT and RLS are
independent gates that must both pass, so **every table was unreachable by
every role**, service_role included — verified against dev, PostgREST
returned `42501 permission denied for table profiles`. This survived four
migrations' worth of work because neither client had ever issued a real
query; they were only ever constructed. Fixed in
`20260811192313_grant_table_privileges.sql`, which also sets default
privileges so future tables aren't dead on arrival. Full write-up in
`ENGINEERING_NOTES.md` §1.5.

**Built:**
- `webhook_events` ledger + `claim/complete/fail_webhook_event()`
  (`20260811192107`). The claim is a single atomic upsert, not
  SELECT-then-INSERT, so concurrent deliveries can't both proceed; a
  staleness window prevents a crashed run from stranding an event as
  permanently-skipped. State machine verified against dev, 5/5 cases.
- `supabase/functions/_shared/` — env accessor, service-role client,
  webhook response helpers (named for retry semantics, not status codes),
  idempotency wrapper, HMAC verification with constant-time compare, and
  the pure `subscription-state` / `docuseal-events` logic.
- `stripe-webhook` — `constructEventAsync` signature verification on the
  raw body, then `customer.subscription.updated` (module + seat reconcile,
  founding-member guard) and `payment_intent.succeeded` (invoice paid +
  notification).
- `docuseal-webhook` — HMAC verification, signer status update, document
  status rolled up from all signers.
- `config.toml`: `verify_jwt = false` for both webhook functions.

**The founding-member guard is load-bearing, not defensive.** Founding
members have no per-module subscription items (flat rate), so a naive
snapshot-reconcile computes an empty desired set and deactivates every
module they were promised for life — on any subscription update at all.
Handler skips module reconciliation for them entirely. `ENGINEERING_NOTES.md` §6.6.

**Not deployed yet.** Functions are written but not pushed to
`pnchd-dev` — deployment needs the Section 11.2 secrets set
(`supabase secrets set STRIPE_SECRET_KEY=... STRIPE_WEBHOOK_SECRET=...
DOCUSEAL_WEBHOOK_SECRET=...`) and Stripe/Docuseal dashboard endpoints
configured. Also needs Stripe Price metadata (`module_key` per module
price, `line_type=seats` on the seats price) — that's the join key the
reconcile depends on and it doesn't exist in Stripe yet.

## Block E — React page scaffolding (Section 10.2) — DONE
`pnchd-web` committed and pushed (`5264ad1`); mobile follow-up `a1ca289`.

- **Data layer** (`src/data/`): repositories with injectable Supabase clients,
  surfaced through a `Repositories` interface and a React context. Nothing
  outside `src/data/` calls supabase-js. Folder layout recorded in
  ARCHITECTURE.md §10.2.1.
- **`AuthRepository` added on both platforms.** Repositories were already
  injectable, but the auth stream was still reached through the global
  client on web (`useSession`) and mobile (`currentProfileProvider`),
  leaving the whole auth path untestable. Now behind a seam on both.
- **Routing**: pure `resolveAccess(profile, path)` with no React Router
  types. Web rules differ from mobile per §10.3 — contractors and platform
  admin only; clients/drivers get `/mobile-only` rather than being bounced
  somewhere they also can't use. The guard renders a loading state while the
  profile resolves instead of deciding on incomplete data (the mobile
  redirect-stall trap).
- **Module-gated nav** off `module_subscriptions`, mirroring
  `ContractorShell`. All §10.2 routes plus `/scheduling` and the §15.3 admin
  area. Shared `PageShell`/`EmptyState`/`LoadingScreen` + a placeholder page
  factory so 18 routes aren't 18 near-identical files.
- **29 tests** — access rules per role, module gating, and an integration
  pass driving `RequireAccess` entirely through injected fakes. `npm run
  verify` = lint + typecheck + tests. Mobile: 12 tests, `flutter analyze` clean.

## Block F — schema gap decisions + two critical RLS fixes

**Your decisions (ARCHITECTURE.md §5.2, all resolved):**
- No proposal rejection path — clients just don't approve, handled by conversation.
- Client document visibility stays signer-only.
- No `declined` document status — decline maps to `voided`.
- `client_feature_toggles` enforced in RLS, **hard block**, no grandfathering.

Three of four needed no schema change. Built: toggle enforcement
(`20260816000233`) and pending-action notification triggers
(`20260816000256`).

**CRITICAL: RLS infinite recursion (42P17) — fixed in `20260816000734`.**
Every policy resolved the user's org/role with an inline subquery on
`profiles`. On `profiles` itself that recurses through its own policy, and
because every table's policy reads `profiles`, the failure cascaded — **no
authenticated user could read any row from any table**. Fixed with
`SECURITY DEFINER` helpers (`current_user_organization_id()`,
`current_user_role()`, `current_user_is_admin()`,
`current_user_is_contractor()`) and all policies rewritten to use them.

This is the second total-outage bug with the same root cause as the missing
GRANTs: everything was verified with `service_role`, which bypasses RLS and
grants. Both were invisible to a fully green test suite.

**New verification infrastructure — this is what closes that class of bug:**
- `supabase/tests/rls.test.ts` — seeds real auth users of all five roles
  across two orgs, signs in as each, asserts reachability. 11 tests. First
  test is the recursion canary.
- `scripts/check-policies.sh` — static checks (inline `profiles` subqueries,
  missing RLS, standalone gate policies). Validated against planted bugs.
- `scripts/verify.sh [--with-rls]` — runs everything.

**A schema change is done when `./scripts/verify.sh --with-rls` passes, not
when `db push` succeeds.**

## Block G — magic-link auth (web) + a third RLS bug

Web committed (`4f63ac7`); backend fix pushed alongside.

- **Magic link chosen over password.** Login and signup are the same call
  (`signInWithOtp` + `shouldCreateUser`). No password reset flow to build.
- **Org setup** at `/welcome`: `handle_new_user` leaves `organization_id`
  NULL, so a new contractor names their business, which creates the org and
  attaches the profile. `resolveAccess` gained an org-setup state, tested
  across every role.
- **Sign out** clears the query cache so the next user can't briefly see the
  previous one's data.

**BUG FOUND — signup was impossible.** The `organizations` SELECT policy only
allowed `id = current_user_organization_id()`, which resolves through
`profiles.organization_id` — still NULL during signup, the very column signup
populates. A new owner couldn't read back the org they'd just created.
Compounded by a misleading error: `INSERT ... RETURNING` applies SELECT
policies, and PostgREST issues a RETURNING on every `.select()`, so it
surfaced as "new row violates row-level security policy" (reads like WITH
CHECK, wasn't). Fixed in `20260816002616`. Full write-up: ENGINEERING_NOTES.md
§1.7.

Third bug this session caught by exercising the authenticated path. The RLS
suite now walks the real signup flow (13 tests).

**Mobile auth done too** (`3c835f8`) — same flow, plus deep-link config.
`supabase_flutter` completes the callback itself through app_links and
`detectSessionInUri`, so no URL parsing in app code. Scheme
`io.pnchd.pnchd_mobile://login-callback` registered in `Info.plist`
(CFBundleURLTypes) and `AndroidManifest` (BROWSABLE intent-filter), both
validated. Sign-out is behind a confirmation dialog — with magic link,
getting back in means waiting on an email.

An unattached *client* on mobile goes to their own shell rather than org
setup, since clients are invited by a contractor and never create an
organization. 18 tests, analyze clean.

### Blocking before real users
- **Register the mobile redirect URL** `io.pnchd.pnchd_mobile://login-callback`
  in the Supabase Auth dashboard (Authentication → URL Configuration). Manual
  step; magic links to the app will fail without it.
- **Custom SMTP (Resend) in Supabase Auth.** With magic link, email IS the
  login path — Supabase's built-in sender is rate-limited to a handful per
  hour and not for production. No email means nobody can log in at all.
- **Org creation is not atomic** (two writes, ordering forced by RLS). Fails
  toward "user unattached, can retry" — the safe direction — but wants a
  SECURITY DEFINER function doing both in one transaction before launch.
- **No Stripe subscription on signup.** Section 10.2 says signup starts the
  30-day trial; without keys a new contractor gets an org and no subscription
  record. Seam is in `OnboardingPage`.

## Block H — the projects feature (first real screens)

Web `d9b89b9`, mobile `8097f0e`, backend tests pushed alongside.

- List with status filter chips (defaults to Open, hiding
  completed/archived), create form, and detail with status switching. Both
  platforms.
- **Generated database types on web** (`src/types/database.types.ts`), with
  the Supabase client typed against them. Makes a column rename a compile
  error. **Regenerate after every migration:**
  `supabase gen types typescript --project-id jzmcgxugmeaebvxcrkjn > pnchd-web/src/types/database.types.ts`
  Gotcha: the `.select()` string must be a single literal — supabase-js parses
  it at the type level, and concatenation widens it to `string` and silently
  drops row typing.
- Repositories deliberately **do not** filter by `organization_id`. RLS scopes
  the query; filtering in the app would imply isolation lives there.
- Project detail treats "not found" and "not yours" identically, because RLS
  returns null for both. Distinguishing them would leak that the row exists.
- Filtering is a pure module (web) / derived provider (mobile), tested
  separately rather than inlined in the view.
- **Riverpod 3.x**: `StateProvider` is removed (use a `Notifier`), and
  `AsyncValue.valueOrNull` is now `.value`. Most tutorials show both.

Counts: web 44, mobile 30, RLS 17, Edge Functions 32.

### Demo data
`supabase/../scratchpad/seed_demo.ts` (not committed) seeds
`demo@pnchd.test` / "Ridgeline Construction" with 6 projects and 3 active
modules, and prints a working magic link. Re-running wipes and recreates it.
Worth moving into the repo as a proper seed script.

### Design not yet reviewed
Screens were shown but theme decisions were deferred. Everything is
centralized (`@theme` tokens, `StatusBadge`/`StatusChip`, `PageShell`,
`AuthScaffold`) so restyling is a small diff. Status colours are generic
semantic green/amber and do not use the brand palette yet — the most obvious
thing to revisit.

### Flagged, not addressed
Web bundle is 497 kB (143 kB gzipped) in a single chunk with no route
splitting. Fine now; wants `React.lazy` on routes before launch.

## Block I — proposals & invoices, and a security bug that failed OPEN

Web `6943b88`, backend fix + tests pushed alongside. **Mobile not done yet.**

### SECURITY: three enforcement triggers never fired
The client-write triggers on `proposals` and `document_signers` declared a
PL/pgSQL variable named `current_role` — a **reserved SQL keyword** that
evaluates to the role name. The keyword wins over the variable, so
`if current_role = 'client'` compared `'authenticated' = 'client'` and the
whole enforcement body was dead code. No error, no warning.

Verified as a real client before the fix: approved a proposal that was never
sent, and **rewrote a $1,000.00 proposal to $0.01 while approving it**.

The invoices copy was incidentally rewritten during the RLS recursion fix, the
only reason it worked. Fixed in `20260819181016`.

**This one failed OPEN** — unlike §1.5/§1.6 which broke loudly, the app worked
perfectly with a security control silently absent. Only testing the
*adversarial* case finds that. Six new RLS tests now assert the controls
**deny**; a static check catches reserved-keyword variable names.
Write-up: ENGINEERING_NOTES.md §1.7a.

### Money handling
`lib/money.ts` is the only place cents become decimals. `quantity` is
`numeric(10,2)` so line totals involve decimal × integer in IEEE-754 — every
product is rounded to an integer immediately rather than accumulated and
rounded at the end, or the total stops matching the sum of visible rows. 32
tests. `parseCurrencyToCents` rejects >2 decimal places rather than rounding.

### Built
Proposals/invoices lists, detail with shared line-item editor, live totals,
send action. Records freeze once sent. `paid` is rejected client-side since
only the payment webhook sets it.

Counts: web 92, mobile 30, RLS 23, Edge Functions 32.

### Not done
- **Mobile proposals/invoices** — models, repositories, and screens.
- Invoices have `tax_cents` but no `tax_rate_percent` column, so the web
  editor can't compute invoice tax from a rate. Proposals can. Worth deciding
  whether invoices need the rate column too.
- `replaceLineItems` is delete-then-insert across three writes with no
  transaction (PostgREST can't). Recoverable by saving again, but wants a
  SECURITY DEFINER function.

**What's next, in rough order:**
1. **Deploy the Edge Functions** — blocked on secrets and provider config
   (see Block D above). Needs your Stripe/Docuseal accounts.
2. **Stripe Price metadata** — `module_key` on each module price,
   `line_type=seats` on the seats price. The subscription reconcile depends
   on this and it doesn't exist in Stripe yet.
3. **More real screens** — projects is done; proposals, invoices, documents,
   scheduling, and both client/driver shells are still placeholders.
4. **§5.2 schema gaps** — all resolved except #5 (Stripe module-removal API).

### Backlog (captured, not designed)
- **Referral rewards** — ARCHITECTURE.md §2.5a. Note the founding-member
  conflict: the Layer 3 webhook guard refuses subscription changes for them,
  so a referral *discount* would be blocked or require weakening the one
  mechanism protecting a lifetime price. Account credit avoids that.
- **Access model** — `ACCESS_MODEL.md`, decisions A and B still open.
- **Scheduling schema** — still owed. No events table exists; `scheduling` is
  a launch module with a nav entry and route but nothing behind it.

**Decision logged this session, not yet acted on:** Section 10.2's page
list is missing a `/scheduling` route — `scheduling` is one of the 4 launch
modules and has a Flutter feature folder (Section 9.1) but no web
counterpart as written. Confirmed: web should get scheduling too. Add a
`/scheduling` route when React page scaffolding actually happens — no rush
now.

## How I like to work
Decision-already-made, execute-only-that, move-on. I don't need elaborate
planning restated back to me — pick the next unchecked item, build it
matching the established patterns, flag anything genuinely ambiguous, and
keep moving. If something in the architecture doc conflicts with what's
already built, tell me directly rather than picking a side quietly.

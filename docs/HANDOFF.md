# PNCHD — Session Hand-off (Phase 2, Block C)

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

**What's next** — React page scaffolding per Section 10.2 (including the
`/scheduling` route decision below), matching the repository-layer pattern
established on mobile. Then Phase 2's remaining piece: Stripe Edge
Functions (Section 8.2/8.3) — webhook handlers for
`customer.subscription.updated` and `payment_intent.succeeded`, plus the
Docuseal webhook (Section 8.1).

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

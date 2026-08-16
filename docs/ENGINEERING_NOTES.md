# PNCHD — Engineering Notes

Running explanation log. Where `ARCHITECTURE.md` says *what* the system is, this
says *why it works that way* and *what's easy to get wrong*. Appended to as work
happens.

Focus is on mechanics that are easy to get subtly wrong and that generic docs don't
make obvious — especially anything where a mistake silently breaks security or data
isolation. Basics of Supabase/Flutter/React are assumed.

---

## 1. Row Level Security

### 1.1 What `auth.uid()` actually is

`auth.uid()` reads the `sub` claim out of the JWT attached to the current request.
It is not a database lookup — it's decoded from the token Supabase Auth issued.
Every policy in this system hinges on it.

The practical consequence: RLS is enforced **per request, inside Postgres**. The
client sends a token; Postgres decides what rows that token can touch. The client
cannot lie its way past this, which is what makes it safe to let a mobile app talk
to the database directly with no API server in between.

### 1.2 Policies combine with OR — this is the big one

Multiple *permissive* policies on the same table and command are combined with
**OR**, not AND. If any one policy grants access, access is granted.

This has bitten the project's design in two opposite directions:

**Where OR is what we want — `admin_bypass_*`.** Every table has an unconditional
policy granting everything to `platform_admin`. Because it ORs with the normal
org-isolation policy, the admin dashboard works without special-casing every table.

**Where OR would have been a security hole — module gating.** The original
architecture doc showed the fleet-tracking module check as its own standalone
policy:

```sql
-- WRONG — this does not gate anything
CREATE POLICY "fleet_module_required" ON vehicle_locations
  FOR ALL USING (EXISTS (SELECT 1 FROM module_subscriptions WHERE ...));
```

With the org-isolation policy also present, a user in an org **without**
`fleet_tracking` still passes — because the org-isolation policy alone satisfies the
OR. The gate does nothing.

The fix is to AND the check into each policy's own condition:

```sql
CREATE POLICY "vehicle_locations_owner_pro_read" ON vehicle_locations FOR SELECT
  USING (
    organization_id = (SELECT organization_id FROM profiles WHERE id = auth.uid())
    AND (SELECT role FROM profiles WHERE id = auth.uid()) IN ('owner','pro')
    AND has_active_module('fleet_tracking')
  );
```

Rule of thumb: **a policy can only ever grant. It can never take away.** If you want
a restriction to actually restrict, it has to live inside every policy that could
otherwise grant.

(Postgres does have `AS RESTRICTIVE` policies, which AND instead of OR. They're a
legitimate alternative here. We used inline ANDs for consistency with the existing
migrations, but restrictive policies would be worth considering if the number of
gated tables grows.)

### 1.3 `USING` vs `WITH CHECK`

Different gates, easy to conflate:

- `USING` — filters which **existing** rows you can see or touch (SELECT, UPDATE,
  DELETE). Rows failing it are invisible, not an error.
- `WITH CHECK` — validates what a row is **allowed to become** (INSERT, UPDATE).
  Violations raise an error.

An UPDATE runs both: `USING` decides if you may touch the row, `WITH CHECK` decides
if the resulting row is legal. Omitting `WITH CHECK` on an update policy is a common
way to accidentally let a user move a row *out of* their own org.

### 1.4 RLS cannot do column-level restriction

This is a hard limitation and shapes a lot of the schema. Section 7.2 of the
architecture doc says a client may "write `approved_at` only" on a proposal — RLS
cannot express that. A policy governs whole rows.

So the pattern used throughout is a `BEFORE UPDATE` trigger that inspects
`OLD` vs `NEW` and raises if any column other than the permitted one changed:

```sql
if new.organization_id != old.organization_id
  or new.total_cents != old.total_cents
  ... then raise exception '...';
```

The RLS policy gates *who may attempt* the update; the trigger gates *what they may
change*. Both are needed. This is why `proposals`, `invoices`, and
`document_signers` all have enforcement triggers.

### 1.5 GRANT and RLS are two separate gates — we shipped 14 migrations missing one

**This was a real bug, and it made every table in the project unreachable.**

A PostgREST request has to pass **two independent checks**:

1. **SQL table privileges** (`GRANT SELECT ON x TO authenticated`) — does this role
   have any right to touch this table at all?
2. **Row Level Security policies** — which rows within it?

Migrations 001–014 diligently did #2 and never did #1. Every table had RLS enabled
with carefully written policies, and every request failed before RLS was ever
consulted:

```
42501  permission denied for table profiles
hint:  Grant the required privileges to the current role with:
       GRANT SELECT ON public.profiles TO service_role;
```

Supabase normally papers over this with `ALTER DEFAULT PRIVILEGES` for tables
created by the `postgres` role, so hand-written migrations usually "just work." The
role `supabase db push` connects as didn't inherit those defaults, so nothing was
granted and nothing complained — DDL succeeded, policies were created, `supabase
migration list` showed everything applied.

**Why nobody noticed for four migrations' worth of work:** neither app had ever
issued an authenticated query. The Flutter and React clients were only ever
*constructed*, never used to fetch. Connectivity was "verified" by reading
`supabase.rest.url`, which is a local string, not a round trip. A build passing and
a client initializing prove nothing about whether the database will answer.

The fix (`20260811192313_grant_table_privileges.sql`) grants on existing objects
*and* sets default privileges so future tables aren't dead on arrival.

**Why granting `all` to `anon` is not a security hole:** this is the standard
Supabase model. Table privileges are deliberately broad; RLS is the enforcement
layer. A table with RLS enabled and no matching policy denies by default no matter
what it's granted. `webhook_events` is the exception — grants were explicitly
revoked from `anon`/`authenticated` as defense in depth, so that a policy added by
mistake later still can't expose operational plumbing.

**Generalizable lesson:** verify against the real thing. `supabase db push`
succeeding means the DDL ran, not that the API works. One `curl` against PostgREST
with a real key would have caught this on day one.

### 1.6 RLS policies that read `profiles` recurse — 42P17, and it broke everything

Second total-outage bug, same blind spot as §1.5.

The `profiles` SELECT policy resolved the user's org with an inline subquery:

```sql
create policy "profiles_read_within_org" on profiles for select
  using (organization_id = (select organization_id from profiles where id = auth.uid()));
```

That subquery reads `profiles`, which is itself subject to this policy, which
runs the subquery again. Postgres detects the cycle and aborts:

```
42P17  infinite recursion detected in policy for relation "profiles"
```

And because **every** table's policy resolved org and role the same way, the
recursion propagated to all of them. No authenticated user could read any row
from any table in the project.

**The fix** is a `SECURITY DEFINER` helper — running as the function owner, it
bypasses RLS for that one lookup, breaking the cycle:

```sql
create function current_user_organization_id() returns uuid
language sql stable security definer set search_path = public
as $$ select organization_id from profiles where id = auth.uid() $$;
```

`has_active_module()` was already written this way, which is exactly why it kept
working while everything around it failed — a useful tell in hindsight.

Note `set search_path = public` is not optional on a `SECURITY DEFINER`
function: without it a caller can put a malicious `profiles` in a schema earlier
in their search path and have it execute with the owner's privileges.

**Why it hid for so long:** identical to the missing GRANTs. Every check ran as
`service_role`, which bypasses RLS. `db push` succeeded, `migration list`
matched, 73 tests passed, both apps built — all green, while the database would
not answer a single authenticated query. It surfaced the moment a test signed in
as a real client for the first time.

### 1.7 The lesson both outages share, and what actually closes it

Two bugs, months of work apart, both capable of taking down the entire product,
both invisible to every check in place. The common cause is not carelessness:

> **`service_role` bypasses RLS and table grants. Verifying with it proves
> nothing about what real users can do.**

Being more careful does not fix this — neither bug was a lapse in care, and no
amount of re-reading the migrations would have surfaced either. What fixes it is
exercising the real path:

- **`supabase/tests/rls.test.ts`** seeds real auth users of every role across two
  organizations, signs in as each, and asserts what they can and cannot read and
  write. The first test is a bare "can this user read their own profile" — the
  canary for §1.6.
- **`scripts/check-policies.sh`** catches the shapes statically: inline
  `profiles` subqueries, tables missing `enable row level security`, and gates
  written as standalone policies (§1.2).
- **`scripts/verify.sh`** runs both.

A migration is not done when `db push` succeeds. It is done when the RLS suite
passes. Both of these bugs would have been caught on the day they were written
by a single authenticated `SELECT`.

### 1.8 The trust boundary

- **Anon / publishable key** — ships in the mobile binary and the web bundle. Safe,
  because it grants nothing on its own; RLS decides everything.
- **Service role key** — bypasses RLS completely. Only ever in Edge Function
  secrets. Never in a client bundle, never in a `VITE_*` or `--dart-define` variable.

This is why tables written exclusively by trusted server code
(`module_subscriptions`, `notifications`, `webhook_events`) have **no** client INSERT
policy at all. There's no gap to police — the only writer bypasses RLS by design.

### 1.9 Why `has_active_module()` is `SECURITY DEFINER`

The helper reads `module_subscriptions`. If it ran as the calling user
(`SECURITY INVOKER`), it would itself be subject to that table's RLS — and the RLS
on the table it's being used to protect. That's circular and fragile.

`SECURITY DEFINER` runs it as the function owner, bypassing RLS for that lookup.
`SET search_path = public` is attached for a reason: without a pinned search path, a
caller could create a malicious `module_subscriptions` in a schema earlier in their
path and hijack the definer's privileges. Pinning it is standard hardening for any
`SECURITY DEFINER` function.

---

## 2. Auth and session handling

### 2.1 Where the session lives

`supabase-js` `createClient()` defaults to `persistSession: true` and
`autoRefreshToken: true`. The access + refresh token pair goes into browser
`localStorage` and refreshes on a timer while the tab is open. That's why a session
survives a page reload with zero extra code.

`supabase_flutter` does the equivalent with `SharedPreferences` on mobile.

The tradeoff: the token sits in `localStorage`, not an httpOnly cookie, so it's
reachable by any JS running on the page (i.e. XSS gets you a token). That's
acceptable **here specifically because RLS is the real boundary** — a stolen token
grants exactly what that user could already do, nothing more. In an architecture
where the backend trusts the caller's identity and skips per-row checks, this would
be a much bigger problem.

### 2.2 The JWT proves *who*, not *what role*

The token carries the user id. It does **not** carry the PNCHD role
(owner/pro/client/driver/platform_admin) — that lives in `profiles.role`.

So every authorization decision needs a `profiles` lookup, which is exactly what the
policies do inline via `(SELECT role FROM profiles WHERE id = auth.uid())`, and what
`currentProfileProvider` does on the client. The client-side copy is for **routing
and UI only**; the authoritative check is the one Postgres does.

---

## 3. Flutter / Dart

### 3.1 Config via `--dart-define`

Flutter has no `.env` mechanism. Config comes in as compile-time constants:

```bash
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

read via `String.fromEnvironment('SUPABASE_URL')`. Because they're compile-time,
they must be `const` — `String.fromEnvironment` in a non-const context silently
returns the default. The `assert`s in `supabase_client.dart` catch a missing define
in debug builds, which is the common failure mode.

### 3.2 `anonKey` → `publishableKey`

The Supabase SDK deprecated the `anonKey` parameter in favor of `publishableKey`.
Same value, platform-wide rename. We use the new parameter but kept the env var name
`SUPABASE_ANON_KEY` to match the architecture doc.

### 3.3 Riverpod 3.x renamed `valueOrNull`

`AsyncValue.valueOrNull` is now just `.value` (nullable), with `.requireValue` as the
throwing variant. Most tutorials and Stack Overflow answers still show
`valueOrNull` — if you see that, it's Riverpod 2.x-era.

### 3.4 The GoRouter `refreshListenable` race — a real bug we hit

**Symptom:** signed-out users were never redirected to `/onboarding`. The redirect
ran, saw `AsyncLoading`, returned "no redirect," and never ran again. Permanently
stuck — not a flake, reproducible with a 2-second pump.

**Cause:** `refreshListenable` was wired directly to Supabase's raw auth stream:

```dart
refreshListenable: GoRouterRefreshStream(supabase.auth.onAuthStateChange)
```

That stream fires **synchronously**. But `currentProfileProvider` sits on top of it
doing an `asyncMap` — and even the signed-out fast path (`return null`) costs a
microtask, because it's inside an `async` function.

Order of events:
1. Auth stream emits → refresh listenable fires **immediately**
2. GoRouter re-runs `redirect`, reads `currentProfileProvider` → still `AsyncLoading`
3. Returns null (no redirect)
4. A microtask later, the provider resolves to `AsyncData(null)`
5. **Nothing fires again.** No second redirect attempt. Stuck forever.

**Fix:** drive the refresh from the *derived* state, not the upstream trigger:

```dart
final refresh = ValueNotifier(0);
ref.listen(currentProfileProvider, (_, _) => refresh.value++);
```

**Generalizable lesson:** when a router (or any consumer) reads value A but refreshes
on signal B, and A is derived asynchronously from B, you have a race. Always refresh
on changes to the thing you actually read.

### 3.5 Testing code that calls `Supabase.initialize`

Two separate storage concerns must both be stubbed in widget tests, or you get
`MissingPluginException`:

- `localStorage` — session persistence. Use the built-in `EmptyLocalStorage`.
- `pkceAsyncStorage` — PKCE flow state. **Has no built-in in-memory implementation**
  and defaults to a `SharedPreferences`-backed one regardless of what you pass for
  `localStorage`. Needs a hand-written in-memory `GotrueAsyncStorage`.

Missing the second one is the non-obvious failure — the error points at
`shared_preferences`, not at anything you wrote.

---

## 4. Web

### 4.1 Tailwind v4 setup differs from v3

v4 dropped `tailwind.config.js` and the PostCSS plugin for the common case. Setup is
now the Vite plugin plus one CSS import:

```ts
plugins: [react(), tailwindcss()]
```
```css
@import "tailwindcss";
@theme { --color-navy: #1b2f5e; }
```

Design tokens are declared in CSS via `@theme` rather than in a JS config object. A
token named `--color-navy` automatically generates `bg-navy`, `text-navy`,
`border-navy`, etc. Most v3-era tutorials will not match this.

Sanity check that it's actually wired: the built CSS should be several KB. A near-
empty CSS output means the plugin isn't generating utilities.

---

## 5. Database and migrations

### 5.1 Migrations are append-only once applied

A migration that has run against a real database is history — editing it desyncs
local files from the remote `schema_migrations` ledger, and the edit never runs
anywhere. This is why the `vehicles` index arrived as its own migration
(`..._vehicles_organization_id_index.sql`) rather than an edit to the file that
created the table.

### 5.2 Timestamped filenames, not sequential numbers

Supabase requires `<timestamp>_name.sql`. Files named `001_`, `002_` are ignored by
`supabase db push` entirely — which is exactly what happened early in this project:
eight migrations sat at the repo root with sequential names and **nothing had ever
reached the dev database**, despite the hand-off doc claiming otherwise. Worth
verifying with `supabase migration list` (local vs remote columns) rather than
trusting that a push happened.

### 5.3 Partial unique indexes for state invariants

```sql
create unique index ... on module_subscriptions (organization_id, module_key)
  where is_active = true;
```

The `WHERE` clause makes this enforce "at most one **active** subscription per
org+module" while still permitting historical inactive rows. Enforcing that
invariant in the database rather than application code means a webhook race or
retry cannot produce a duplicate — the database refuses it.

---

## 6. Webhooks and Edge Functions

### 6.1 `verify_jwt = false` is mandatory for webhook endpoints

Supabase Edge Functions require a valid Supabase JWT by default. Stripe and Docuseal
have no such token — every delivery would 401.

So webhook functions must be configured with `verify_jwt = false`. Which means
**signature verification is the only thing authenticating these endpoints.** It is
not optional hardening; it is the entire door lock.

### 6.2 Verify the signature on the raw body, before parsing

The signature is an HMAC over the exact bytes sent. `JSON.parse` followed by
`JSON.stringify` produces different bytes (key order, whitespace, number formatting)
and the signature will not match.

Always: read `await req.text()` → verify → *then* parse. Never verify against a
re-serialized object.

### 6.3 Stripe needs the async verification API in edge runtimes

`stripe.webhooks.constructEvent()` uses Node's synchronous crypto and fails on
Deno/Web Crypto. Use `constructEventAsync()`. The failure mode is confusing —
it looks like a signature mismatch rather than a runtime incompatibility.

### 6.4 Idempotency is not optional

Stripe retries failed deliveries with backoff for up to 3 days, and duplicate
deliveries happen even without failures. Processing an event twice is only harmless
if every side effect is idempotent — and inserting a `notifications` row is *not*.
Duplicate pings to a customer are a visible bug.

Hence the `webhook_events` ledger, keyed on `(provider, event_id)`. The claim is a
single atomic statement rather than SELECT-then-INSERT, because two concurrent
deliveries would both pass a separate SELECT:

```sql
insert into webhook_events (...) values (...)
on conflict (provider, event_id) do update set ...
  where webhook_events.status = 'failed'
     or (webhook_events.status = 'processing' and received_at < now() - stale_after)
returning true;
```

Returning no row means "already handled, skip." The `stale_after` clause matters:
without it, a function that crashes mid-processing leaves a row stuck in
`processing` forever, and every subsequent retry is skipped — silently losing the
event. That failure mode is worse than double-processing.

### 6.5 Delivery order is not guaranteed

Stripe explicitly does not promise ordered delivery. For `customer.subscription.updated`
this matters: an older event arriving late could overwrite newer state.

Mitigation used here: treat the payload as the **full current state** and reconcile
toward it (set exactly the modules present in the payload as active, deactivate the
rest) rather than applying deltas. Combined with recording the event's `created`
timestamp, a stale event can be detected and skipped.

### 6.6 The founding-member guard prevents a catastrophic bug, not a theoretical one

Section 2.3 describes the Layer 3 webhook guard defensively — "if a pricing update
accidentally targets a founding member subscription, the function refuses." Reading
it as belt-and-braces undersells it badly.

Founding members pay a **flat $39 rate with no per-module subscription items**
(migration 002 even notes `stripe_subscription_item_id` is NULL for them). The
sync handler reconciles module state from the subscription's items — treat the
payload as full current state, deactivate anything not in it.

Put those together for a founding member:

1. Subscription has a base item, no module items
2. `extractSubscriptionState` finds zero module keys
3. `diffModules([], ['scheduling', 'document_signing', ...])` → deactivate **all**
4. A customer promised all modules for life silently loses every one of them

And it would fire on *any* `customer.subscription.updated` — a card update, an
address change, a Stripe-side renewal. Not an edge case.

So the guard skips module reconciliation entirely for founding members and syncs
only `seat_count`. Their module access comes from the founding-member terms, not
from subscription items, so there is nothing to reconcile against.

**Generalizable lesson:** "reconcile toward the payload's full state" is the right
pattern for out-of-order delivery (6.5) but it assumes the payload actually
*represents* the full state. When a class of account is billed differently, that
assumption breaks and the reconcile quietly destroys data. Check whether a
snapshot-reconcile is valid for every account type it will run against.

### 6.7 Stripe has no `cancel_at_period_end` on subscription items

ARCHITECTURE.md Section 2.5 gives this as the module-removal implementation:

```js
await stripe.subscriptionItems.update(subscriptionItemId, {
  cancel_at_period_end: true,
});
```

**That field does not exist on `SubscriptionItem`.** `cancel_at_period_end` is a
property of the *Subscription*, which cancels the whole thing — not one module.
Removing a single item at period end requires either a Subscription Schedule, or
application-side logic that deletes the item when the period rolls over.

This doesn't affect the webhook handler — reconciling from the item list is correct
either way, since an item that goes away for any reason deactivates its module. But
the outbound "remove a module" code, when it gets written, cannot be written the way
the doc describes. Logged in Section 5.2 gaps.

### 6.8 HTTP status codes are control signals

The response code tells the provider what to do next:

- **2xx** — handled, don't retry
- **non-2xx** — retry later

Both directions have a failure mode. Returning 500 on a permanently malformed
payload causes a retry storm for days. Returning 200 on a transient database failure
silently drops the event forever. So: validate-and-accept bad payloads (log them,
return 200), and only return non-2xx for genuinely retryable failures.

---

*Appended to as work continues.*

# PROJECT ARCHITECTURE DOCUMENT
## PNCHD · Contractor Management Platform

**Version 3.0 · Living Document · Update as the project evolves**

This document is the single source of truth for the project. Keep it updated as
decisions change.

> **Provenance:** This markdown file supersedes `ARCHITECTURE.docx` (v2.0). It
> contains the full contents of that document plus every decision made since it
> was written. Additions not present in v2.0 are marked **[Added v3.0]**.
> `ARCHITECTURE.docx` is retained for reference but is no longer authoritative —
> edit this file instead.

---

## 1. Project Overview

### 1.1 Product Summary

A modular, cross-platform contractor management SaaS. Contractors subscribe to a
base plan and add only the feature modules they need. The platform has two app
surfaces: a full-featured Pro app for the contractor and a lightweight
Client/Driver app for their customers and field staff. Client and driver accounts
are always free.

### 1.2 App Name / Branding

App name confirmed: **PNCHD** (pronounced "Punched"). Domains purchased:
`pnchd.io` (primary marketing site) and `pnchd.app` (mobile app download links and
app store references). Logo designed and finalized.

| Element | Detail | Usage |
|---|---|---|
| App Name | PNCHD | All public-facing materials, App Store listings, Stripe account display name |
| Pronunciation | Punched | Use in any verbal or written description — "PNCHD (Punched)" |
| Primary Domain | pnchd.io | Main marketing website, landing page, web dashboard |
| App Domain | pnchd.app | Mobile app download links, App Store and Google Play references |
| Logo Mark | Shield with checkmark integrated into P letterform | App icon base — export at all required iOS and Android sizes |
| Primary Color — Navy | `#1B2F5E` | Primary text, headers, buttons, navigation backgrounds |
| Accent Color — Red | `#C0392B` | Accent lines, CTAs, highlights, status indicators |
| Background — Light Gray | `#F2F2F0` | App backgrounds, card surfaces, neutral sections |
| Typography Style | Bold condensed sans-serif | Match logo font weight in UI — use a heavy weight system font or similar |

Reference these brand colors explicitly for UI work. Consistent color usage from
the start saves a painful design cleanup pass later.

**[Added v3.0]** These colors are implemented as centralized tokens, never
hardcoded per-screen:
- Mobile: `pnchd-mobile/lib/core/theme/app_theme.dart` (`AppColors` + `appTheme`)
- Web: the Tailwind v4 `@theme` block in `pnchd-web/src/index.css`
  (`--color-navy`, `--color-brand-red`, `--color-app-bg`)

Both are currently placeholder-grade pending a real theming pass.

### 1.3 Target Market

- Primary vertical: Independent contractors and small contracting businesses (1–20 employees)
- Initial focus: General contractors, remodelers, specialty trades (HVAC, electrical, plumbing)
- Warm network entry point: Interior design architects and their contractor networks
- Geographic focus: United States, English-language first
- Expansion verticals post-launch: Fitness trainers, other field service businesses

### 1.4 Core Value Proposition

Contractors pay only for the features they actively use. Modules can be added or
removed at any time with automatic proration. No rigid tiers. No paying for unused
tools. Client and driver accounts are always free.

### 1.5 User Tiers

| Tier | Who | Access Level |
|---|---|---|
| Platform Admin | Developer (you) | Full platform, billing, all data, analytics |
| Pro User (Owner) | Contractor / business owner | All subscribed modules, org settings, billing, team management |
| Pro User (Seat) | Contractor's employees with full app access | All subscribed modules — cannot access billing or org settings |
| Client | Contractor's customer / homeowner | Project status, documents to sign, invoices to pay, proposal approval |
| Driver / Field Staff | Contractor's field employees or subcontractors | Assigned jobs, GPS location reporting, progress photo uploads |

---

## 2. Pricing Model

### 2.1 Base Fee + Seat Pricing

Every organization pays a base monthly fee that includes one Pro Owner seat.
Additional Pro seats are billed per seat per month with a team cap so growth is
never penalized. Client and driver accounts are always free and unlimited.

| Item | Previous Price | Revised Price | Notes |
|---|---|---|---|
| Base plan (includes 1 owner seat) | $15/month | **$10/month** | Lowered to reduce signup friction |
| Additional Pro seats (per seat/month) | $10/month each, no cap | **$10/month each, capped at $30/month total** | Cap prevents larger small teams from feeling penalized for growth |
| Client accounts | Free — unlimited | Free — unlimited | No change |
| Driver accounts | Free — unlimited | Free — unlimited | No change |
| Annual base plan discount | 20% off base only ($144/year) | **15% off base + all modules annually** | Extended discount to modules rewards full annual commitment |

### 2.2 Module Pricing

Modules are added or removed at any time. Stripe handles proration automatically.
Each module maps to a Stripe Product and Price ID. A **10% bundle discount** applies
automatically when 3 or more modules are active.

| Module Key | Module Name | Previous | Revised | Notes |
|---|---|---|---|---|
| `scheduling` | Scheduling & Timelines | $10/mo | $10/mo | Launch module |
| `document_signing` | Documents & E-Signing | $15/mo | $12/mo | Docuseal cost is low, value is high |
| `proposals_invoicing` | Proposals & Invoicing | $15/mo | $12/mo | Tied to revenue collection |
| `client_payments` | Client Payments | $20/mo + 1% per txn | $15/mo + 0.75% per txn | Launch module |
| `fleet_tracking` | Fleet GPS Tracking | $20/mo + $5/truck | $18/mo + $4/truck | Roadmap — after 50 subscribers |
| `messaging` | Client Messaging | $8/mo | $7/mo | Roadmap — after 50 subscribers |
| `budget_tracking` | Budget & Cost Tracking | $12/mo | $10/mo | Roadmap — after 100 subscribers |
| `file_storage` | Project File Storage | $8/mo | $7/mo | Roadmap — after 100 subscribers |
| `multi_contractor` | Multi-Contractor Coordination | $15/mo | $12/mo | Roadmap — after 200 subscribers |
| `client_portal` | Client Project Portal | $12/mo | $10/mo | Roadmap — after 200 subscribers |

Bundle discount: 10% off all active module costs when 3+ modules are active.
Applied in Stripe via a coupon attached to the subscription. Removed automatically
if the subscriber drops below 3 modules.

**Typical subscriber cost comparison**

| Subscriber Type | Previous Monthly | Revised Monthly | Savings |
|---|---|---|---|
| Solo contractor, all 4 launch modules | $75 | $59 (with bundle discount) | $16 — 21% less |
| Solo contractor, 2 modules only | $50 | $37 | $13 — 26% less |
| 3-person team, all 4 launch modules | $95 | $79 (bundle + seat cap) | $16 — 17% less |
| Annual solo, all 4 launch modules | ~$810/year | ~$601/year | ~$209/year saved |

### 2.3 Founding Member Offer

The first 50 subscribers get a Founding Member rate of **$39/month flat** with all
launch modules included, locked for life as long as they stay subscribed. At revised
pricing the regular all-modules cost is ~$59/month, so founding members save
~$20/month.

**What founding members get**
- All 4 launch modules at $39/month flat — never charged per module
- Any modules added to the platform within 12 months of their signup date included free
- Modules released after the 12-month window billed at standard per-module rate
- Price locked for life as long as the subscription remains active — canceling forfeits the rate

**4-layer overcharge protection**

| Layer | Mechanism |
|---|---|
| 1 — Database flag | `organizations.founding_member = true` gates all billing logic. `founding_member_price_cents` stores the exact promised price as an auditable record independent of Stripe. |
| 2 — Dedicated Stripe Price ID | Founding members attach to a separate Stripe Price object for the $39 rate. Even if standard pricing is restructured, their subscription stays on the founding Price ID. |
| 3 — Webhook guard | The `customer.subscription.updated` Edge Function checks `founding_member = true` before making subscription item changes. If a pricing update targets a founding member, the function refuses and logs a warning. |
| 4 — Billing UI | Founding members see a distinct billing screen with a badge, all modules active and non-removable. Standard module toggles hidden. |

### 2.4 Free Trial

30-day free trial, no credit card required, all modules unlocked. Contractor
projects don't move on a two-week cycle — 30 days gives a realistic chance to use
the product inside a real job before deciding to pay.

### 2.5 Module Removal Policy

**Decision:** Modules removed mid-cycle remain active until the end of the current
billing period, then do not renew. No immediate deactivation, no prorated refund.

- Contractor activates a module on the 1st — full month charged immediately
- Contractor removes the module on the 15th — access continues until period end
- Module does not renew next cycle — no further charges
- Stripe: set the subscription item to `cancel_at_period_end = true` rather than deleting it
- `module_subscriptions` row stays `is_active = true` until period end
- On period end: `customer.subscription.updated` fires → Edge Function sets `is_active = false` and `deactivated_at = now()`

**Why end-of-period over immediate proration:** simpler to explain, no confusing
prorated credits, removes anxiety around the remove button, eliminates partial-month
credit edge cases.

**UI treatment for pending removal:** show a "Cancels [date]" badge in billing
settings, a Reactivate button, and send an email 3 days before deactivation.

```js
// When contractor removes a module — cancel at period end, no proration:
await stripe.subscriptionItems.update(subscriptionItemId, {
  cancel_at_period_end: true,
});
```

### 2.6 Revenue Milestones

ARPU adjusted to ~$55/month reflecting lower base fee, reduced module prices, and
bundle discounts.

| Subscribers | Previous Est. Net | Revised Est. Net | Notes |
|---|---|---|---|
| 25 | ~$1,475 | ~$1,200 | Word of mouth |
| 50 | ~$2,930 | ~$2,450 | Consider part-time support help |
| 100 | ~$5,900 | ~$4,950 | Strong validation, Supabase Pro needed |
| 135 | ~$8,750 | ~$6,700 | Approaching meaningful side income |
| 160 | ~$10,400 | ~$8,750 | Day job replacement threshold |
| 200 | ~$14,800 | ~$11,000 | Full-time sustainable, begin hiring |
| 500 | ~$29,500 | ~$27,000 | Mature business |

Transaction fees from `client_payments` grow with subscriber count and are not
reflected in ARPU estimates above.

---

## 3. Tech Stack

### 3.1 Stack Overview

| Layer | Technology | Purpose |
|---|---|---|
| iOS + Android App | Flutter (Dart) | Single cross-platform mobile codebase |
| Web Dashboard | React + TypeScript + Tailwind CSS | Browser app for contractors doing heavy admin work on desktop |
| Landing Page + Signup | React + TypeScript + Tailwind CSS | Same codebase as web dashboard |
| Backend + Database | Supabase (PostgreSQL) | Auth, database, file storage, realtime, Edge Functions |
| Payments — Subscriptions | Stripe Billing | Monthly base + per-seat + per-module with automatic proration |
| Payments — Client Invoices | Stripe Connect | Contractors receive client payments through the platform |
| Document Signing | Docuseal API | Third-party e-signature — legally compliant, audit trail |
| Transactional Email | Resend + Supabase Auth Emails | Invitations, notifications, signing requests, receipts |
| Maps + Fleet Tracking | Google Maps Flutter Plugin | Wraps native Maps SDK |
| Push Notifications | Firebase Cloud Messaging (FCM) | Cross-platform push for iOS and Android |
| Frontend Hosting | Vercel | Auto-deploys from GitHub, CDN |
| Error Monitoring | Sentry (free tier) | Crash reporting for Flutter and React |

**[Added v3.0] Implementation libraries actually in use**

| Surface | Library | Purpose |
|---|---|---|
| Flutter | `flutter_riverpod` | State management (Section 9.2) |
| Flutter | `go_router` | Routing + role-based redirects (Section 9.3) |
| Flutter | `supabase_flutter` | Supabase client |
| Web | Vite | Build tool / dev server |
| Web | Tailwind CSS v4 (`@tailwindcss/vite`) | Styling — v4 uses the Vite plugin + `@import "tailwindcss"`, no `tailwind.config.js` |
| Web | `@supabase/supabase-js` | Supabase client |

### 3.2 Key Technical Decisions & Rationale

**Flutter over React Native** — Flutter compiles Dart to native ARM machine code via
AOT, no JavaScript bridge. Impeller renders directly to GPU. For a data-driven UI
(lists, forms, dashboards, maps), Flutter is more than sufficient and provides
better cross-platform consistency.

**Supabase over custom backend** — PostgreSQL, auth, file storage, realtime, and
Edge Functions in one managed service. Row Level Security enforces data access at
the database level. Scales from free tier through enterprise.

**React for web, not Flutter web** — Flutter web renders to canvas, giving poor SEO
and slow initial load. React produces standard HTML. Both surfaces share the same
Supabase backend.

**Docuseal for document signing, not custom-built** — Legally compliant e-signatures
require audit trails, tamper-evident sealing, signer identity verification, and
ongoing compliance maintenance. DocuSign was considered but is overpriced and
over-engineered for this stage.

**Stripe Connect for client payments** — Purpose-built for platforms facilitating
payments between two parties. Distinct from Stripe Billing, which handles contractor
subscriptions.

**Free client and driver accounts** — Charging per client creates friction and
discourages contractors from using the client-facing features that drive the most
platform value.

---

## 4. High-Level Architecture

### 4.1 System Components

All client surfaces (Flutter mobile, React web, Client/Driver app) connect to a
single Supabase backend. No data is duplicated across surfaces. Stripe webhooks
update subscription state. Docuseal webhooks update document signing state.

### 4.2 Data Flow Summary

- Contractor signs up → Stripe subscription created → Supabase user + organization record created with subscribed modules stored
- Contractor logs in → Supabase Auth validates session → RLS policies scope all queries to their `organization_id`
- Contractor adds a Pro seat → `profiles` record created with `role: pro` → Stripe subscription quantity updated → proration automatic
- Contractor invites a client → Supabase sends invite email via Resend → client downloads app → logs in with scoped client permissions
- Driver opens app with active job → app checks for active job → requests background location permission → GPS written to `vehicle_locations` every 30 seconds
- Contractor's fleet dashboard subscribes to `vehicle_locations` via Supabase Realtime → map polylines update live
- Contractor sends document for signing → Docuseal API creates submission → client receives signing email → signs in Docuseal hosted UI → webhook fires → status updated in Supabase
- Client approves proposal and pays → Stripe Connect processes payment → funds deposited to contractor's connected account → invoice status updated via webhook
- Contractor adds a module → Stripe subscription item added → webhook fires → `module_subscriptions` row activated → UI unlocks module immediately

### 4.3 Module Gating

**Two layers, and the distinction matters:**

- **Database level (the actual security boundary):** RLS policies check
  `module_subscriptions` before allowing reads/writes to module-specific tables. A
  user without `fleet_tracking` cannot query `vehicle_locations` regardless of what
  the client sends.
- **UI level (convenience only):** Flutter and React load the active module list on
  app start and conditionally render navigation and screens. Users never see
  features they have not subscribed to. **This is not security** — hiding a nav tab
  stops nothing on its own.

---

## 5. Database Schema (Supabase / PostgreSQL)

Living schema — update this section whenever tables or columns change.

### 5.1 Core Tables

#### organizations
Represents a contractor's business. All platform data is scoped to an organization.

| Column | Type / Notes |
|---|---|
| `id` | uuid, primary key, default `gen_random_uuid()` |
| `name` | text — business name |
| `owner_id` | uuid, references `auth.users` — the account that owns billing |
| `seat_count` | integer, default 1 — active Pro seats excluding owner |
| `stripe_customer_id` | text — Stripe Customer ID |
| `stripe_connect_account_id` | text, nullable — Stripe Connect ID |
| `stripe_connect_onboarded` | boolean, default false |
| `founding_member` | boolean, default false |
| `founding_member_price_cents` | integer, nullable — locked price (e.g. 3900 = $39.00) |
| `founding_member_modules_locked_at` | timestamptz, nullable — signup timestamp; modules added within 12 months are free |
| `created_at` | timestamptz, default `now()` |

#### profiles
Extends Supabase `auth.users`. Created automatically via database trigger on signup.

| Column | Type / Notes |
|---|---|
| `id` | uuid, primary key, references `auth.users` |
| `organization_id` | uuid, references `organizations` — NULL until signup flow attaches it |
| `role` | text — enum: `owner` \| `pro` \| `client` \| `driver` \| `platform_admin` |
| `full_name` | text |
| `avatar_url` | text, nullable — Supabase Storage path |
| `phone` | text, nullable |
| `push_token` | text, nullable — FCM device token |
| `is_active` | boolean, default true |
| `created_at` | timestamptz, default `now()` |

#### module_subscriptions
Tracks which modules an organization has active. Synced from Stripe via Edge Function webhook.

| Column | Type / Notes |
|---|---|
| `id` | uuid, primary key |
| `organization_id` | uuid, references `organizations` |
| `module_key` | text — matches module keys in Section 2.2 |
| `stripe_subscription_item_id` | text — NULL for founding members on the flat rate |
| `is_active` | boolean |
| `activated_at` | timestamptz |
| `deactivated_at` | timestamptz, nullable |

#### projects

| Column | Type / Notes |
|---|---|
| `id` | uuid, primary key |
| `organization_id` | uuid, references `organizations` |
| `title` | text |
| `description` | text, nullable |
| `status` | text — enum: `draft` \| `active` \| `on_hold` \| `completed` \| `archived` |
| `client_id` | uuid, references `profiles`, nullable |
| `address` | text, nullable — job site address |
| `start_date` | date, nullable |
| `end_date` | date, nullable |
| `created_by` | uuid, references `profiles` |
| `created_at` | timestamptz, default `now()` |
| `updated_at` | timestamptz — updated via trigger |

#### project_assignments
Links drivers/field staff to projects. Multiple drivers may be assigned to one project.

| Column | Type / Notes |
|---|---|
| `id` | uuid, primary key |
| `project_id` | uuid, references `projects` |
| `profile_id` | uuid, references `profiles` — the assigned driver/employee |
| `organization_id` | uuid, references `organizations` |
| `assigned_at` | timestamptz, default `now()` |
| `is_active` | boolean, default true |

#### proposals
A formal proposal sent to a client for approval before work begins.

| Column | Type / Notes |
|---|---|
| `id` | uuid, primary key |
| `organization_id` | uuid, references `organizations` |
| `project_id` | uuid, references `projects`, nullable |
| `client_id` | uuid, references `profiles` |
| `title` | text |
| `status` | text — enum: `draft` \| `sent` \| `approved` \| `rejected` \| `expired` |
| `subtotal_cents` | integer — always store money in cents |
| `tax_rate_percent` | numeric(5,2), nullable |
| `tax_cents` | integer, nullable |
| `total_cents` | integer |
| `notes` | text, nullable — contractor notes visible to client |
| `valid_until` | date, nullable |
| `approved_at` | timestamptz, nullable |
| `created_at` | timestamptz, default `now()` |

#### invoices

| Column | Type / Notes |
|---|---|
| `id` | uuid, primary key |
| `organization_id` | uuid, references `organizations` |
| `project_id` | uuid, references `projects`, nullable |
| `proposal_id` | uuid, references `proposals`, nullable |
| `client_id` | uuid, references `profiles` |
| `title` | text |
| `stripe_payment_intent_id` | text, nullable |
| `subtotal_cents` | integer — never floats |
| `tax_cents` | integer, nullable |
| `total_cents` | integer |
| `status` | text — enum: `draft` \| `sent` \| `approved` \| `paid` \| `voided` \| `refunded` |
| `due_date` | date, nullable |
| `paid_at` | timestamptz, nullable |
| `created_at` | timestamptz, default `now()` |

#### line_items
Shared by both proposals and invoices. Polymorphic via `parent_type` + `parent_id`.

| Column | Type / Notes |
|---|---|
| `id` | uuid, primary key |
| `organization_id` | uuid, references `organizations` |
| `parent_type` | text — enum: `proposal` \| `invoice` |
| `parent_id` | uuid — references `proposals.id` or `invoices.id` based on `parent_type` |
| `description` | text |
| `quantity` | numeric(10,2) |
| `unit_price_cents` | integer |
| `total_cents` | integer |
| `sort_order` | integer |

#### documents
Contracts and files requiring e-signature via Docuseal, or general project file storage.

| Column | Type / Notes |
|---|---|
| `id` | uuid, primary key |
| `organization_id` | uuid, references `organizations` |
| `project_id` | uuid, references `projects`, nullable |
| `title` | text |
| `storage_path` | text — Supabase Storage bucket path for the original file |
| `completed_storage_path` | text, nullable — path to the signed/completed document |
| `type` | text — enum: `contract` \| `change_order` \| `general` \| `other` |
| `status` | text — enum: `draft` \| `sent` \| `completed` \| `voided` |
| `docuseal_submission_id` | text, nullable |
| `created_by` | uuid, references `profiles` |
| `created_at` | timestamptz, default `now()` |

#### document_signers
Tracks each individual signer on a document.

| Column | Type / Notes |
|---|---|
| `id` | uuid, primary key |
| `document_id` | uuid, references `documents` |
| `organization_id` | uuid, references `organizations` |
| `profile_id` | uuid, references `profiles`, nullable — null if external signer |
| `signer_name` | text |
| `signer_email` | text |
| `docuseal_submitter_id` | text, nullable |
| `status` | text — enum: `pending` \| `sent` \| `opened` \| `signed` \| `declined` |
| `signed_at` | timestamptz, nullable |
| `signing_ip` | text, nullable — for audit trail |

#### vehicles (fleet module)

| Column | Type / Notes |
|---|---|
| `id` | uuid, primary key |
| `organization_id` | uuid, references `organizations` |
| `name` | text — e.g. "Truck 1", "Van - John" |
| `license_plate` | text, nullable |
| `assigned_driver_id` | uuid, references `profiles`, nullable |
| `is_active` | boolean, default true |
| `created_at` | timestamptz, default `now()` |

#### vehicle_locations (fleet module)
Append-only insert table. Driver app inserts rows on interval. Dashboard reads
latest per vehicle.

| Column | Type / Notes |
|---|---|
| `id` | uuid, primary key |
| `vehicle_id` | uuid, references `vehicles` |
| `organization_id` | uuid, references `organizations` |
| `driver_id` | uuid, references `profiles` |
| `latitude` | double precision |
| `longitude` | double precision |
| `accuracy_meters` | real, nullable |
| `recorded_at` | timestamptz, default `now()` |

#### notifications
In-app notifications for all user tiers. Push delivery handled separately via FCM.

| Column | Type / Notes |
|---|---|
| `id` | uuid, primary key |
| `organization_id` | uuid, references `organizations` |
| `recipient_id` | uuid, references `profiles` |
| `title` | text |
| `body` | text |
| `type` | text — see enum below |
| `reference_type` | text, nullable — e.g. `invoice`, `document` |
| `reference_id` | uuid, nullable — ID of the related record |
| `is_read` | boolean, default false |
| `created_at` | timestamptz, default `now()` |

`type` enum — completion events (original) plus **[Added v3.0]** pending-action events:

| Value | Fires when |
|---|---|
| `document_signed` | A document finished signing |
| `invoice_paid` | An invoice was paid |
| `proposal_approved` | A client approved a proposal |
| `job_assigned` | A driver was assigned to a job |
| `payment_received` | Payment landed |
| `general` | Catch-all |
| `document_pending_signature` **[Added v3.0]** | A document was assigned to a client to sign |
| `invoice_pending_payment` **[Added v3.0]** | An invoice was sent to a client to pay |
| `proposal_pending_approval` **[Added v3.0]** | A proposal was sent to a client to approve |

> The original enum only covered *completion* events. There was no "something new
> landed in your queue" type, so a client got Docuseal's email but no in-app
> notification for a pending to-do. See Section 5.2 for what still isn't wired up.

#### client_feature_toggles **[Added v3.0]**
Owner-controlled on/off switch for client-facing capabilities, **independent of**
`module_subscriptions.is_active` (which is a billing mirror synced from Stripe).

An org can be actively paying for `document_signing` — so the owner can use it —
while still choosing not to expose it to clients yet. `module_subscriptions` alone
cannot express that.

| Column | Type / Notes |
|---|---|
| `id` | uuid, primary key |
| `organization_id` | uuid, references `organizations` |
| `feature_key` | text — enum: `client_payments` \| `document_signing` \| `messaging` |
| `is_enabled` | boolean, default **false** (opt-in, not opt-out) |
| `updated_at` | timestamptz, default `now()`, maintained by trigger |

Unique on `(organization_id, feature_key)` — both the access pattern and the
"one row per feature per org" invariant.

**Granularity decision:** org-wide only. One setting applies to all of an org's
clients, matching how `module_subscriptions` works. Per-client override is a
possible future change — it would need a nullable `client_profile_id` column
(null = org-wide default, a specific value overrides just that client) and
`is_client_feature_enabled()` would check for a client-specific row before falling
back to the org-wide one.

#### webhook_events **[Added v3.0]**
Idempotency ledger for inbound third-party webhooks. See Section 8.5.

### 5.2 Known Schema Gaps **[Added v3.0]**

Surfaced during implementation, deliberately not "fixed" by guessing at unspec'd
schema. Each needs a decision.

1. **Proposals have no rejection path.** Schema has `approved_at` but no
   `rejected_at`. Client approval works; client rejection has no column to write to.
2. **Client document visibility is signer-only.** A client can only see a `document`
   if they appear in `document_signers` for it — there's no `client_id` on
   `documents` itself, so they can't browse "all documents on my project" before
   being added as a signer.
3. **`client_feature_toggles` is not enforced in RLS.** A client can still
   approve/pay an invoice or sign a document via direct table access regardless of
   the toggle — it currently only controls what the client app's UI shows.
   Extending the client policies on `invoices`/`documents` to also require
   `is_client_feature_enabled(...)` is outstanding work.
4. **No notification/push on assignment, only on completion.** The enum values now
   exist (`*_pending_*`), but nothing inserts those rows or sends an FCM push when
   a document/invoice/proposal is assigned to a client. Only Docuseal's own email
   exists today. Needs a trigger or Edge Function firing on assignment.
5. **Section 2.5's module-removal code doesn't match the Stripe API.**
   `cancel_at_period_end` is a property of a *Subscription*, not a
   `SubscriptionItem` — the snippet in 2.5 would not compile against the current
   API, and cancelling the subscription is not what's wanted. Removing one module
   at period end needs a Subscription Schedule or app-side deletion at rollover.
   Does not affect the inbound webhook (which reconciles from the item list
   regardless), but blocks the outbound "remove a module" flow.
6. **`documents.status` has no `declined` value.** Migration 008 allows
   `draft | sent | completed | voided`. A Docuseal decline currently maps to
   `voided`, which loses the distinction between "contractor cancelled it" and
   "client refused to sign." Fine if that distinction doesn't matter; needs an
   enum value if it does.

---

## 6. Database Indexes

Always index foreign key columns and any column used in `WHERE` or `ORDER BY`.

| Table / Column(s) | Reason |
|---|---|
| `profiles.organization_id` | Every query scopes to org — most frequent lookup |
| `profiles.role` | Frequent filter in RLS policies |
| `projects.organization_id` | Org scoping |
| `projects.client_id` | Lookup projects by client |
| `projects.status` | Filter by active/completed |
| `project_assignments.project_id` | Lookup assignments by project |
| `project_assignments.profile_id` | Lookup projects assigned to a driver |
| `module_subscriptions.organization_id + module_key` | Module gating check on every request |
| `proposals.organization_id, proposals.client_id` | Org scoping + client filter |
| `invoices.organization_id, invoices.client_id` | Org scoping + client filter |
| `invoices.status` | Filter unpaid/overdue |
| `line_items.parent_type + parent_id` | Lookup line items by parent |
| `documents.organization_id + project_id` | Document lookup by project |
| `document_signers.document_id` | Lookup signers by document |
| `vehicle_locations.vehicle_id + recorded_at DESC` | Latest location query for fleet map |
| `notifications.recipient_id + is_read` | Unread notification count badge |
| `vehicles.organization_id` **[Added v3.0]** | Org scoping — omitted from the original list; every other table has one |
| `client_feature_toggles.organization_id + feature_key` **[Added v3.0]** | Unique; access pattern + one-row-per-feature invariant |
| `webhook_events.provider + event_id` **[Added v3.0]** | Unique; idempotency lookup |

---

## 7. Row Level Security (RLS) Strategy

Every table must have RLS enabled. Never disable RLS in production, even
temporarily. Misconfigured RLS can expose one organization's data to another and is
difficult to detect.

### 7.1 Core Policy Pattern

```sql
-- Standard org isolation policy (apply to every table)
CREATE POLICY "org_isolation" ON [table_name]
  FOR ALL USING (
    organization_id = (
      SELECT organization_id FROM profiles
      WHERE id = auth.uid()
    )
  );
```

### 7.2 Role-Based Access Patterns

| Table | Owner / Pro User | Client / Driver |
|---|---|---|
| `projects` | Full CRUD on own org | Read only — own assigned projects |
| `project_assignments` | Full CRUD on own org | Read own assignments only |
| `proposals` | Full CRUD on own org | Read own proposals, write `approved_at` only |
| `invoices` | Full CRUD on own org | Read own invoices, write approval status only |
| `line_items` | Full CRUD on own org | Read on own proposals/invoices only |
| `documents` | Full CRUD on own org | Read assigned docs only |
| `document_signers` | Full CRUD on own org | Read own signer record, write `signed_at` only |
| `vehicles` | Full CRUD on own org | No access |
| `vehicle_locations` | Read all in own org | Insert only for own `driver_id` |
| `profiles` | Read all in own org, update own | Read and update own profile only |
| `module_subscriptions` | Read only | No access |
| `notifications` | Read and update own notifications | Read and update own notifications |
| `client_feature_toggles` **[v3.0]** | Full CRUD on own org | Client: read own org's toggles. Driver: no access |
| `webhook_events` **[v3.0]** | No access | No access — service-role only |

### 7.3 Module-Level RLS

For module-specific tables, the module check is combined with org isolation:

```sql
-- Reusable helper (migration 002)
CREATE FUNCTION has_active_module(check_module_key text) RETURNS boolean ...
```

> **[Added v3.0] Critical correctness note.** The original doc showed the module
> gate as its own separate policy. **That does not work.** Multiple permissive
> policies on the same command are combined with **OR** in Postgres, so a
> standalone module-gating policy would be satisfied by the org-isolation policy
> alone and silently grant access to unsubscribed orgs. The gate must be **ANDed
> into each policy's own condition**:
>
> ```sql
> CREATE POLICY "vehicle_locations_owner_pro_read" ON vehicle_locations FOR SELECT
>   USING (
>     organization_id = (SELECT organization_id FROM profiles WHERE id = auth.uid())
>     AND (SELECT role FROM profiles WHERE id = auth.uid()) IN ('owner','pro')
>     AND has_active_module('fleet_tracking')
>   );
> ```

### 7.4 Established Conventions **[Added v3.0]**

Follow these for every new table:

- `ALTER TABLE X ENABLE ROW LEVEL SECURITY;` — always.
- Every table gets an `admin_bypass_X` policy (`role = 'platform_admin'`) so the
  Section 15.3 admin dashboard works without special-casing. This one *is* correct
  as a standalone policy — unconditional bypass is exactly the OR semantics wanted.
- Role checks inline via `(SELECT role FROM profiles WHERE id = auth.uid())`.
- **RLS cannot restrict individual columns.** Where a role may only write specific
  columns (client setting `approved_at`, signer setting `signed_at`), enforce it
  with a `BEFORE UPDATE` trigger that raises on any other column change — not the
  policy.
- Tables written exclusively by Edge Functions using the service-role key
  (`module_subscriptions`, `notifications`, `webhook_events`) get **no** client
  INSERT policy — the service role bypasses RLS entirely.
- Add `COMMENT ON TABLE/COLUMN` wherever it gives useful context, so `\d+ tablename`
  is self-documenting.

---

## 8. Third-Party Integrations

### 8.1 Docuseal (Document Signing)

Do not build custom e-signature logic.

| Step | Implementation Detail |
|---|---|
| 1. Upload template | `POST /api/templates` — upload PDF, receive `template_id` |
| 2. Create submission | `POST /api/submissions` — pass `template_id` + signer names/emails, receive `submission_id` |
| 3. Store IDs | Save `docuseal_submission_id` to `documents`, submitter IDs to `document_signers` |
| 4. Signer receives email | Docuseal sends the signing invitation automatically — no custom email needed |
| 5. Signer signs | Docuseal hosted UI — no custom signing UI to build |
| 6. Webhook fires | Docuseal POSTs to a Supabase Edge Function URL on completion |
| 7. Update status | Edge Function updates `documents.status = completed` and `document_signers.signed_at` |
| 8. Store completed doc | `GET /api/submissions/:id/documents` — download signed PDF to Supabase Storage |

### 8.2 Stripe Billing (Subscriptions)

| Stripe Object | Maps To in Platform |
|---|---|
| Customer | One per organization — created on signup |
| Product | One per module + base plan + Pro seats + founding member flat rate |
| Price: standard | Monthly recurring price per product |
| Price: founding_member | Dedicated $39/month Price ID — never modified or reused |
| Subscription | One per organization — contains all active subscription items |
| Subscription Item: base | $10/month base plan, or founding member flat rate Price ID |
| Subscription Item: seats | `quantity` = additional seat count at $10/seat/month |
| Subscription Item: `[module_key]` | One item per active module (standard subscribers only) |
| Trial period | 30 days — set via `trial_period_days` on subscription creation |
| Webhook: `customer.subscription.updated` | Syncs `module_subscriptions` and `seat_count`. Guards founding member subscriptions. |
| Billing Portal | Hosted Stripe page for payment method management |

### 8.3 Stripe Connect (Client Payments)

| Step | Implementation Detail |
|---|---|
| 1. Contractor onboarding | Redirect to Stripe Connect hosted onboarding |
| 2. Store account ID | Store in `organizations.stripe_connect_account_id` |
| 3. Mark onboarded | Set `organizations.stripe_connect_onboarded = true` |
| 4. Client pays invoice | Create PaymentIntent with `on_behalf_of` = contractor's Connect account ID |
| 5. Platform fee (optional) | Pass `application_fee_amount` — evaluate after launch |
| 6. Payout | Stripe auto-pays contractor bank on standard schedule |
| 7. Webhook: `payment_intent.succeeded` | Update `invoices.status = paid`, `invoices.paid_at = timestamp` |

### 8.4 Firebase Cloud Messaging (Push Notifications)

| Step | Implementation Detail |
|---|---|
| 1. Flutter setup | Add `firebase_messaging`, configure `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) |
| 2. Capture token | On app open, get FCM device token and save to `profiles.push_token` |
| 3. Send notification | Supabase Edge Function calls FCM API with token + title + body + data payload |
| 4. Insert record | Edge Function also inserts a row into `notifications` for in-app display |
| 5. iOS requirement | APNs authentication key must be configured in Firebase console |

> **[Added v3.0]** `FCM_SERVER_KEY` (Section 11.2) refers to the **legacy** FCM API,
> which Google has deprecated. The current FCM HTTP v1 API requires a service
> account and OAuth2 bearer tokens instead. Revisit this secret before building
> push delivery.

### 8.5 Webhook Handling Conventions **[Added v3.0]**

Applies to every inbound third-party webhook (Stripe, Docuseal, and any future
provider). These are correctness- and security-critical.

- **Signature verification happens first, on the raw request body.** Read the body
  as text and verify before parsing. Never verify against a re-serialized object —
  `JSON.parse` → `JSON.stringify` changes bytes and invalidates the signature.
- **Stripe requires the async verification API in edge runtimes.**
  `constructEventAsync`, not `constructEvent` — the synchronous version depends on
  Node crypto and fails on Deno/Web Crypto.
- **Webhook functions must set `verify_jwt = false`.** Supabase Edge Functions
  require a valid Supabase JWT by default; third-party providers have no such
  token. Signature verification *is* the authentication for these endpoints — which
  is why it can never be skipped.
- **Every webhook is idempotent.** Providers retry on failure (Stripe for up to
  3 days) and may deliver duplicates. Events are claimed in the `webhook_events`
  table on `(provider, event_id)` before processing; an already-completed event
  short-circuits to `200`.
- **Delivery order is not guaranteed.** For state-syncing events, treat the payload
  as the full current state and reconcile toward it rather than applying deltas.
- **Return 2xx once handled, non-2xx to request a retry.** Returning an error for a
  permanently-bad payload causes retry storms; returning 200 for a transient
  failure silently drops the event.
- Edge Functions use `SUPABASE_SERVICE_ROLE_KEY`, deliberately bypassing RLS.
  That key must never reach a client bundle.

---

## 9. Flutter App Structure

### 9.1 Folder Architecture

Feature-first structure. Each module has its own folder mapping to the product's
modular concept.

```
lib/
  main.dart
  app.dart                    # Root widget, GoRouter setup
  core/
    auth/                     # Supabase auth logic, session management
    data/                     # [v3.0] Repository layer — all Supabase calls
    router/                   # GoRouter config, route guards by role
    theme/                    # Design tokens, colors, text styles
    supabase/                 # Supabase client singleton
    notifications/            # FCM setup, notification handling
    models/                   # Shared data models
    widgets/                  # [v3.0] Shared reusable widgets
    utils/                    # Formatters, validators, helpers
  features/
    onboarding/               # Signup, login, org setup, Stripe onboarding
    dashboard/                # Home screen, activity feed, module nav
    projects/                 # Project list, detail, creation
    scheduling/               # Scheduling module
    document_signing/         # Documents list, Docuseal integration
    proposals_invoicing/      # Proposals and invoices with line items
    client_payments/          # Stripe Connect payment flows
    fleet_tracking/           # GPS map, vehicle management (roadmap)
    messaging/                # Client messaging (roadmap)
    settings/
      account/                # Profile settings
      billing/                # Module management, seat management
      team/                   # Invite clients and drivers
      organization/           # Org settings
    client_view/              # Scoped UI shell for client role
    driver_view/              # Scoped UI shell for driver role
```

**[Added v3.0] `core/data/` — the repository layer.** Not in the original structure.
All Supabase access goes through repositories (`profile_repository.dart`,
`module_repository.dart`, `client_feature_repository.dart`); Riverpod providers
depend on repositories rather than calling `supabase.from(...)` inline. Repositories
accept an injectable client so they can be constructed with a fake in tests. See
Section 16.

### 9.2 State Management (Riverpod)

| Provider Type | Use Case |
|---|---|
| `AsyncNotifierProvider` | Data fetched from Supabase — project lists, documents, invoices |
| `StreamProvider` | Supabase Realtime subscriptions — live location updates, notifications |
| `NotifierProvider` | Complex local state with multiple actions — form state, multi-step flows |
| `StateProvider` | Simple local UI state — selected tab, filter values, toggles |
| `Provider` | Static dependencies — Supabase client, router, repositories |

> **[Added v3.0] Riverpod 3.x note:** `AsyncValue.valueOrNull` was renamed to
> `.value` (nullable), with `.requireValue` as the throwing variant. Most existing
> tutorials still show `valueOrNull`.

### 9.3 Role-Based Navigation

- `role: owner` or `pro` → Full contractor app shell with module-gated bottom navigation
- `role: client` → Client shell — projects view, documents to sign, invoices to pay, proposal approval
- `role: driver` → Driver shell — assigned jobs, active job detail, GPS status indicator, progress photo upload

**[Added v3.0] Implementation notes:**
- Redirect logic lives in `core/router/redirect_logic.dart` as a pure
  `resolveRedirect(profile, path)` function so it is unit-testable without a router
  or widget tree.
- `platform_admin` has no mobile home — that role's surface is the web admin
  dashboard (Section 15.3). It falls back to `/dashboard`.
- **GoRouter `refreshListenable` must be driven by the profile provider, not the
  raw Supabase auth stream.** The raw stream fires synchronously, while the profile
  provider does an async transform on top of it (even the signed-out path costs a
  microtask). Listening to the raw stream re-runs the redirect *before* the profile
  value updates, reads stale `AsyncLoading`, and never retries — the redirect
  stalls permanently.

### 9.4 Background Location Strategy (Driver App)

Only request background location permission when the driver has an active job
assigned for the current day.

- On driver login: check `project_assignments` for any active job today
- If active job exists: show clear explanation dialog, then request permission
- If no active job: do not request — request only when a job becomes active
- Location update interval: every 30 seconds while job is active
- On job completion or logout: stop background location updates
- Use `flutter_background_geolocation`

### 9.5 Device Support **[Added v3.0]**

The mobile app must support **phone and tablet on both iOS and Android** — not just
install and run, but adapt layout to the larger canvas.

Native config already permits this (set by `flutter create`, verified):
- iOS: `TARGETED_DEVICE_FAMILY = "1,2"` and `UISupportedInterfaceOrientations~ipad`
  in `Info.plist`
- Android: no `<supports-screens>` restriction and no `resizeableActivity="false"`

Outstanding: screens must actually be responsive. Use `LayoutBuilder`/breakpoints
rather than fixed phone-width assumptions.

---

## 10. React Web App Structure

### 10.1 Key Libraries

| Library | Purpose |
|---|---|
| React 18 + TypeScript | UI framework |
| Tailwind CSS | Utility-first styling |
| React Router v6 | Client-side routing with nested layouts |
| `@supabase/supabase-js` | Supabase client — auth, database, storage, realtime |
| `@stripe/stripe-js` + `@stripe/react-stripe-js` | Stripe Elements — no raw card data handling |
| TanStack Query | Server state — caching, background refresh, optimistic updates |
| React Hook Form + Zod | Form handling and schema validation |
| Recharts | Dashboard charts |
| date-fns | Date formatting |
| `@dnd-kit/core` | Drag-and-drop for scheduling and kanban views |

### 10.2 Page Structure

| Route | Description |
|---|---|
| `/` | Landing page — value prop, features, pricing, testimonials, signup CTA |
| `/pricing` | Interactive module picker + live pricing calculator |
| `/signup` | Account creation — org setup + Stripe subscription, 30-day trial |
| `/login` | Authentication |
| `/dashboard` | Contractor home — active projects, recent activity, unpaid invoices summary |
| `/projects` | Project list — filter by status, search, sort |
| `/projects/:id` | Project detail — timeline, documents, team, invoices |
| `/scheduling` **[Added v3.0]** | Scheduling module — missing from the original list |
| `/proposals` | Proposal list, creation, status tracking |
| `/proposals/:id` | Proposal detail with line items |
| `/invoices` | Invoice list — filter unpaid, overdue, paid |
| `/invoices/:id` | Invoice detail with payment status and pay button |
| `/documents` | Document library — upload, send for signing |
| `/documents/:id` | Document detail — signer status, download completed doc |
| `/fleet` | Fleet map with live truck positions |
| `/settings/account` | Profile and organization settings |
| `/settings/billing` | Module toggles, seat management, Stripe billing portal link |
| `/settings/team` | Invite clients, drivers, and additional Pro seats |

### 10.2.1 Folder Architecture **[Added v3.0]**

```
src/
  lib/supabase.ts       # client singleton
  data/                 # repository layer — the ONLY place supabase-js is called
    index.ts            #   Repositories interface + factory
    repositoryContext.ts, RepositoryProvider.tsx   # injection point
    authRepository.ts, profileRepository.ts, moduleRepository.ts
  auth/                 # useSession, useProfile, useActiveModules (TanStack Query)
  routing/
    access.ts           #   pure resolveAccess(profile, path) — no router types
    navigation.ts       #   pure module-gated nav derivation
    RequireAccess.tsx   #   guard component
    AppRoutes.tsx
  components/           # shared: AppLayout, PageShell, EmptyState, LoadingScreen
  pages/                # one export per Section 10.2 route
  types/                # shared domain types + row mappers
  test/setup.ts
```

Repositories take an injectable Supabase client and are resolved from React
context, never imported as singletons — so a test can supply fakes and never
touch the network. `AuthRepository` exists specifically so the auth stream isn't
reached through the global client, which would otherwise make the entire auth
path untestable. The mobile app has the same seam via Riverpod providers.

### 10.3 Scope Clarification **[Added v3.0]**

The web app is **not** a browser mirror of the whole mobile app. It is:
1. The **contractor** (owner/pro) dashboard — heavy admin work on desktop
2. The **platform admin** panel (Section 15.3), same codebase, gated on `platform_admin`
3. Marketing / signup

Clients and drivers use the **mobile app only**. No client- or driver-facing routes
exist in Section 10.2. A client web surface would arrive with the `client_portal`
roadmap module (Section 2.2, after 200 subscribers).

`client_payments` is asymmetric by design: the payment *action* belongs to the
client (mobile), so on web the contractor only sees status and history.

---

## 11. Environment Variables & Secrets

Never commit secrets to Git. Use `.env.local` for local development. Set production
values in the Vercel dashboard and Supabase Edge Function secrets. The anon /
publishable key is safe to expose in client code — it has no elevated permissions
and RLS enforces access.

### 11.1 React / Vercel (`.env.local`)

| Variable | Description |
|---|---|
| `VITE_SUPABASE_URL` | Supabase project URL — safe in frontend |
| `VITE_SUPABASE_ANON_KEY` | Supabase anon/publishable key — safe in frontend, RLS enforces access |
| `VITE_STRIPE_PUBLISHABLE_KEY` | Stripe publishable key — safe in frontend |
| `VITE_DOCUSEAL_API_URL` | Docuseal API base URL |

### 11.2 Supabase Edge Functions (Secrets)

| Variable | Description |
|---|---|
| `STRIPE_SECRET_KEY` | Stripe secret key — server side only |
| `STRIPE_WEBHOOK_SECRET` | Validates Stripe webhook signatures — prevents spoofed events |
| `SUPABASE_SERVICE_ROLE_KEY` | Bypasses RLS for admin operations — never expose to client |
| `DOCUSEAL_API_KEY` | Docuseal API key — server side only |
| `DOCUSEAL_WEBHOOK_SECRET` | Validates Docuseal webhook signatures |
| `FCM_SERVER_KEY` | Firebase server key — see the deprecation note in Section 8.4 |
| `RESEND_API_KEY` | Resend API key for transactional email |

> `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically into
> deployed Edge Functions by the platform — they do not need to be set manually.

### 11.3 Flutter (`--dart-define` at build time)

| Variable | Description |
|---|---|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_ANON_KEY` | Supabase anon/publishable key |
| `STRIPE_PUBLISHABLE_KEY` | Stripe publishable key |
| `GOOGLE_MAPS_API_KEY` | Set separately in `AndroidManifest.xml` and `AppDelegate.swift` |

> **[Added v3.0]** Flutter has no `.env` support; these are compile-time constants
> read via `String.fromEnvironment`. Note the Supabase SDK renamed the `anonKey`
> parameter to `publishableKey` — the env var name here is unchanged, only the SDK
> parameter differs.

### 11.4 Session Handling Note **[Added v3.0]**

`supabase-js` `createClient()` defaults to `persistSession: true` and
`autoRefreshToken: true` — the access + refresh token live in browser
`localStorage` and refresh silently on a timer. That's why a session survives a page
reload with no extra code.

It also means the token is in `localStorage`, not an httpOnly cookie. Acceptable
here **specifically because RLS is the real security boundary** — a leaked token
grants only what that user's own RLS policies already allow. This would not be
acceptable in an architecture where the API trusts the caller.

---

## 12. Deployment Checklist

### 12.1 Pre-Launch (All Platforms)
- [ ] Draft and publish Privacy Policy and Terms of Service
- [ ] Register business entity — required for Stripe verification
- [ ] Enroll in Apple Developer Program ($99/year) and Google Play Console ($25 one-time)
- [ ] Choose and register app name and domain
- [ ] Set up production Supabase project — separate from development
- [ ] Configure all environment variables for production
- [ ] Enable Sentry error monitoring in both Flutter and React

### 12.2 React (Vercel)
- [ ] Connect GitHub repo to Vercel — auto-deploys on push to main
- [ ] Set all environment variables in Vercel dashboard
- [ ] Configure custom domain — SSL automatic
- [ ] Verify Stripe webhook endpoint points to production URL
- [ ] Verify Docuseal webhook endpoint points to production Edge Function
- [ ] Test full signup → subscription → module activation flow end-to-end

### 12.3 Supabase Production
- [ ] Enable Point-in-Time Recovery (PITR)
- [ ] Run final review of all RLS policies before go-live
- [ ] Confirm all indexes from Section 6 are created
- [ ] Configure Stripe webhook → Supabase Edge Function URL
- [ ] Configure Docuseal webhook → Supabase Edge Function URL
- [ ] Enable email confirmations in Supabase Auth settings
- [ ] Test all Edge Functions end-to-end with Stripe test events
- [ ] **[v3.0]** Confirm webhook functions are deployed with `verify_jwt = false`
- [ ] **[v3.0]** Set all Section 11.2 secrets via `supabase secrets set`

### 12.4 Flutter App Stores
- [ ] Set up TestFlight (iOS) and Internal Testing track (Android)
- [ ] Test background location permission flow on real devices, both platforms
- [ ] Verify push notifications work end-to-end on real devices
- [ ] Confirm Google Maps API keys are set for both platforms
- [ ] **[v3.0]** Verify layouts on tablet form factors, both platforms (Section 9.5)
- [ ] Submit to App Store — budget 1–2 weeks for review
- [ ] Submit to Google Play — typically 1–3 days

### 12.5 Stripe Production Activation
- [ ] Complete Stripe business identity verification (1–3 days)
- [ ] Switch all environments from test mode to live mode keys
- [ ] Verify Stripe Connect onboarding works with a real bank account
- [ ] Test a real end-to-end payment from client to contractor
- [ ] Set up Stripe Radar rules for basic fraud prevention

---

## 13. Working with AI Coding Tools

### 13.1 Session Setup
At the start of each session provide:
- A one-paragraph summary of what you are building today
- The relevant sections of this document
- Any recent decisions not yet reflected here
- The specific file or feature to work on first

### 13.2 Effective Prompt Patterns

**For new Flutter screens:** "I'm building the [module] module. Schema: [paste]. The
user is a Pro contractor. Create a Flutter screen that [description]. Use Riverpod
with `AsyncNotifierProvider`. Go through the repository layer in `core/data/`, not
Supabase directly. Handle loading, error, and empty states. Follow Section 9.1."

**For RLS policies:** "Here is my table definition: [paste DDL]. Roles are owner,
pro, client, driver. Write RLS policies so owner and pro have full CRUD on their
org's rows, clients read only rows where their `profile_id` matches, drivers have no
access. Include the org isolation base policy. Remember permissive policies OR
together (Section 7.3)."

**For Supabase Edge Functions:** "I need an Edge Function handling the Stripe
webhook event [name]. When it fires, [behavior]. Tables: [paste]. Use
`SUPABASE_SERVICE_ROLE_KEY`. Validate the signature with `STRIPE_WEBHOOK_SECRET`
using `constructEventAsync` on the raw body. Follow the conventions in Section 8.5."

**For Docuseal:** "Integrate Docuseal for document signing. Tables: [paste]. When a
contractor sends a document, call the API to create a submission and store the IDs.
When the webhook fires on completion, update document and signer status. Reference
Section 8.1."

### 13.3 Code Review Checklist
- [ ] RLS enabled on any new table — verify: `SELECT tablename, rowsecurity FROM pg_tables`
- [ ] Supabase queries select specific columns — not `select('*')` in production code
- [ ] All money values are integers in cents — no floats in financial calculations
- [ ] Auth checks use `auth.uid()` — never a hardcoded user ID
- [ ] Error states handled — Supabase and API calls fail
- [ ] Sensitive actions (delete, payment, send document) have confirmation dialogs
- [ ] New tables have the indexes from Section 6
- [ ] Edge Functions validate webhook signatures before processing
- [ ] No secrets in Flutter or React code
- [ ] **[v3.0]** Data access goes through the repository layer, not inline in providers/components
- [ ] **[v3.0]** Meaningful logic has unit tests, and is structured to be testable
- [ ] **[v3.0]** Module-gating checks are ANDed into policies, not standalone policies

---

## 14. Architecture Decision Log

| Date | Decision | Rationale / Alternatives Considered |
|---|---|---|
| Project start | Flutter over React Native | AOT to native ARM, no JS bridge, better cross-platform UI consistency. RN rejected for bridge overhead. |
| Project start | Supabase over custom backend | Eliminates API server build/maintenance. Built-in auth, RLS, realtime, storage. Custom Node/Express rejected as too much overhead for a solo developer. |
| Project start | React for web, not Flutter web | Flutter web renders to canvas — poor SEO and load time. |
| Project start | Contractors vertical first | Higher willingness to pay than fitness trainers, richer module usage, underserved by mobile-first tools, warm intro channel available. |
| Project start | 4 launch modules only | Scheduling, document signing, proposals/invoicing, client payments cover the highest-value use cases and validate before over-building. |
| Project start | Docuseal for e-signatures | Legally compliant e-signatures are a significant ongoing engineering burden. DocuSign too expensive/complex for this stage. |
| Project start | Free client and driver accounts | Charging per client creates friction and discourages use of client-facing features that drive platform value. |
| Project start | Per-seat pricing for Pro users | Captures the value difference between solo and multi-employee contractors naturally. |
| Project start | Founding Member at $39/month | Still saves ~$20/month vs the ~$59 all-modules rate. 4-layer protection against overcharge. |
| Project start | Revised pricing — affordable with integrity | Lowered base to $10, reduced module prices, 10% bundle discount at 3+, annual discount extended to modules, seats capped at $30. Goal: genuine value, not extraction. |
| Project start | 30-day free trial (not 14) | Contractor projects don't move on a two-week cycle; a value moment may not occur for 1–2 weeks. |
| Project start | App named PNCHD (Punched) | Memorable, distinctive, doesn't sound like generic SaaS. |
| Project start | Module removal at end of billing period | Simpler UX, no confusing prorated credits, contractor gets what they paid for. |
| **v3.0** | **Module gate ANDed into policies, not standalone** | Permissive policies OR together in Postgres — a standalone gate policy would be bypassed by org isolation alone, silently exposing unsubscribed data. |
| **v3.0** | **`client_feature_toggles` separate from `module_subscriptions`** | Billing status and client exposure are different concerns. An org may pay for a module while not yet exposing it to clients. Rejected: reusing `module_subscriptions.is_active`, which is a Stripe mirror and can't express intent. |
| **v3.0** | **Client feature toggles are org-wide, not per-client** | Matches `module_subscriptions` granularity; simpler. Per-client override noted as a likely future change. |
| **v3.0** | **Repository layer for all data access** | Decouples fetch logic from state/UI, makes it mockable, keeps the codebase inheritable. Applies to both platforms. |
| **v3.0** | **Web gets a `/scheduling` route** | `scheduling` is a launch module with a Flutter feature folder but had no web counterpart in Section 10.2. |
| **v3.0** | **Webhook idempotency via a `webhook_events` ledger** | Providers retry and duplicate deliveries. Without dedup, replays double-apply side effects like notification inserts. |

---

## 15. Support Infrastructure

Set this up before the first subscriber. The stack costs ~$12/month and covers
everything through the first 100 subscribers.

### 15.1 Support Stack Overview

| Tool | Purpose | Cost | Priority |
|---|---|---|---|
| Google Workspace | Professional `support@pnchd.io` address | $6/month | Before launch |
| Crisp | Live chat widget + shared inbox + knowledge base | Free tier | Before launch |
| Sentry | Automatic crash and error capture | Free tier | Before launch |
| Instatus | Public status page at `status.pnchd.io` | Free tier | Before launch |
| Admin Dashboard | Internal org management view — built into pnchd.io | Build time | Before launch |
| `pnchd.io/changelog` | Public changelog — one sentence per fix or feature | Free | Before launch |
| Intercom | Upgrade path from Crisp if volume grows | $39+/month | When needed |

### 15.2 Crisp Setup
- Create account at crisp.chat — free tier covers early stage
- Add the widget script to the React app layout component
- Install the Crisp mobile app for support notifications
- Canned responses for: inviting a client, Stripe Connect setup, sending a document, adding a module, adding a Pro seat
- Auto-reply: "Thanks for reaching out. We respond within 24 hours on business days."
- Build 10–15 knowledge base articles before launch (Section 15.4)

### 15.3 Admin Dashboard (Built into pnchd.io)

A protected section of the React web app, not a separate app. Gated behind
`role: platform_admin` in `profiles`. Only your account sees it.

```sql
-- Add platform_admin bypass to all table policies
CREATE POLICY "admin_bypass" ON organizations
  FOR ALL TO authenticated
  USING (
    (SELECT role FROM profiles WHERE id = auth.uid()) = 'platform_admin'
  );
-- Repeat this pattern for every table
```

| Page / Route | What It Shows |
|---|---|
| `/admin` | Overview — total orgs, active subscribers, MRR estimate, recent signups, recent errors |
| `/admin/organizations` | All organizations — name, owner email, active modules, seat count, created date, subscription status |
| `/admin/organizations/:id` | Org detail — profile, modules, team members, activity, Stripe + Supabase links |
| `/admin/organizations/:id/impersonate` | Log in as this org's owner for debugging |
| `/admin/billing` | Revenue overview — subscribers by plan, MRR, churn, founding members |
| `/admin/errors` | Recent Sentry errors grouped by org |

**Account impersonation**
- Create an Edge Function: `impersonate-user`
- Accepts a target `user_id`, verifies the caller is `platform_admin` via service role
- Uses `supabase.auth.admin.generateLink()` to create a magic link for the target
- Admin UI opens the link in a new tab
- Show a visible "IMPERSONATING [name]" banner while active
- Provide an "End impersonation" button

### 15.4 Knowledge Base — Articles to Write Before Launch

| Article Title | Category |
|---|---|
| Getting started — setting up your PNCHD account | Onboarding |
| How to invite a client to your workspace | Team & Clients |
| How to invite a driver or field staff member | Team & Clients |
| How to add or remove a Pro seat | Billing |
| How to add or remove a module | Billing |
| How to set up Stripe Connect to receive client payments | Payments |
| How to create and send a proposal | Proposals |
| How to convert a proposal to an invoice | Invoices |
| How to send an invoice and collect payment | Payments |
| How to upload and send a document for signing | Documents |
| How to track document signing status | Documents |
| How to create a project and assign a client | Projects |
| How to assign drivers to a project | Projects |
| Understanding your billing and subscription | Billing |
| What to do if a client isn't receiving emails | Troubleshooting |

### 15.5 Status Page (Instatus)
- Create account at instatus.com — free tier
- Custom domain: `status.pnchd.io` via CNAME
- Components: PNCHD App, Web Dashboard, Authentication, Payments, Document Signing
- Connect Supabase and Stripe status feeds — auto-detects incidents
- Link in the landing page footer and app settings
- During any incident, post immediately even without a cause — reduces inbound volume ~80%

### 15.6 Domain and URL Structure

| URL | Purpose |
|---|---|
| `pnchd.io` | Main marketing and landing page |
| `app.pnchd.io` | Web dashboard |
| `pnchd.app` | App download page |
| `status.pnchd.io` | Public status page |
| `pnchd.io/changelog` | Public changelog |
| `pnchd.io/privacy` | Privacy Policy |
| `pnchd.io/terms` | Terms of Service |
| `pnchd.io/help` | Redirect to Crisp knowledge base |
| `support@pnchd.io` | Primary support email |

### 15.7 Changelog Habit
- Update every time you ship a fix or feature — one to three sentences
- Format: date, what changed, why it matters to the contractor
- Send a monthly "what's new" email summarizing the changelog
- Example: "Nov 15 — Document signing now sends an automatic reminder to clients after 48 hours if they haven't signed yet. No more chasing clients manually."

### 15.8 Support Response Commitment
- Post the response time commitment on the landing page
- Include it in the Crisp auto-reply and onboarding email sequence
- Never let a ticket go past 24 hours without at least an acknowledgment
- When you fix a reported bug, email the reporter directly

---

## 16. Engineering Standards **[Added v3.0]**

Non-negotiable, applying to `pnchd-mobile` and `pnchd-web` equally. The goal: if
this software is ever sold, the buyer's dev team inherits a clean, scalable codebase
and is productive immediately. **No technical debt is accepted as a tradeoff for
shipping faster.**

### 16.1 Layering and Decoupling
- Data access lives in a dedicated repository layer. Never call `supabase.from(...)`
  (or the JS equivalent) inline from a state provider, hook, widget, or component.
- Reference: `pnchd-mobile/lib/core/data/*_repository.dart`, with Riverpod providers
  depending on repositories. Mirror this on web.
- Repositories accept an injectable client (defaulting to the shared singleton) so
  they can be constructed with a fake in tests.

### 16.2 Shared and Injectable Libraries
- Styling and theming live in one centralized, swappable place
  (`core/theme/app_theme.dart`; the Tailwind `@theme` block). Never hardcode brand
  colors per-screen.
- Shared UI (page shells, buttons, cards, empty/error states) is extracted into a
  reusable component library. **Rule of thumb: if 2+ screens repeat the same
  structural boilerplate, extract it.** Reference:
  `core/widgets/placeholder_screen.dart`.

### 16.3 Testing
- Write tests as the code lands, not in a deferred testing pass. Untested logic is
  technical debt.
- Structure code to be testable. When meaningful logic is entangled with framework
  objects, extract it into a pure function. Reference:
  `core/router/redirect_logic.dart`.

### 16.4 Comments
- Only where they earn their place, and concise. Skip comments restating the code.
- Keep comments carrying what code cannot: why a non-obvious approach was chosen, a
  subtle framework behavior that would otherwise read as a bug, section references
  into this document, and deliberately flagged gaps.

### 16.5 Applying This
All of the above is part of the definition of done for every piece of work —
**including scaffolding**, since scaffolding decisions calcify once real features
build on top of them.

---

*End of Document*

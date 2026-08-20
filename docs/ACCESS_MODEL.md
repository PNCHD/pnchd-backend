# PNCHD — Access Model (Proposal)

**Status: proposal, not built.** Two decisions at the bottom are still open, and
§5b lists seven relationships this model does not yet cover — one of them
structural (subcontractors cannot bill general contractors).

**Decided so far:** collaboration is granted organization-to-organization, not
to individuals (§4); and a person belongs to exactly one organization — no
membership table, no active-organization concept (§4).

The requirement driving this: **no data should ever be reachable by the wrong
person.** Everything below is chosen for that first. Where a design is chosen
over an alternative, the reason given is correctness or security — not effort.

---

## 1. What the current model cannot express

`profiles` fuses two different things: *who someone is* and *which organization
they belong to*. `profiles.organization_id` is a single column, so a human can
belong to exactly one organization, permanently.

That breaks on four real cases:

1. **A subcontracted trade on someone else's job.** An electrical company works
   a GC's project for three weeks. Nobody there is an employee of that GC.
2. **A subcontractor who is themselves a PNCHD customer.** The plumbing company
   has its own owner account, its own crew, and its own jobs. None of them
   should need a second login to appear on a GC's project.
3. **A one-off trade.** On one job, once, never returns.
4. **A person who owns more than one business.** A GC running two LLCs, or a
   remodeling company plus a separate service outfit. **Decided: not
   supported** — two organizations means two accounts. See §4.

Cases 1–3 are *the same shape*: an organization outside this one needs access to
one job inside it. Note the actor is an organization, not a person — the GC
contracts with a company, and which of that company's people show up is not the
GC's concern. Case 4 is genuinely different and is treated separately.

There is also a permissions gap independent of the above: `owner` and `pro` have
**identical** database access today. A seat employee can read every invoice the
company has issued. Restricting that is a policy change, not a UI change.

---

## 2. Principles

These come directly from the bugs this project has already shipped and fixed.
Each one is a rule that would have prevented a real incident.

### 2.1 Fail closed, not open

A control that must be *remembered* will eventually be forgotten. Prefer designs
where the safe outcome is the default and access requires an explicit act.

This is the single reason for the recommendation in §3.

### 2.2 Access is data, not policy logic

Every serious defect here came from conditional logic inside policies:
recursion through a subquery, an `OR` that silently defeated a gate, a `for`
branch that never executed. Complex boolean conditions are hard to read, hard to
test, and fail quietly.

Policies should be **lookups against explicit grant rows**:

```sql
exists (select 1 from project_collaborations
        where project_id = projects.id
          and collaborator_org_id = current_user_organization_id())
```

The important property is not simplicity but **inspectability**. With logic-based
policies you can only ask *"can this one person see this?"*, one person at a
time. With grants as rows you can ask **"who can see this project?"** and get a
list. That is the question that actually gets asked — during an audit, during an
incident, or when a contractor asks whether the electrician saw their margins.

### 2.3 Hard boundaries are RESTRICTIVE policies

Permissive policies combine with `OR`. That is why a standalone module-gate
policy gated nothing. Restrictive policies combine with `AND`, so **no future
permissive policy can widen them by accident.**

Invariants that must never fail get restrictive policies:

- A row is never visible outside its organization unless an explicit grant says so.
- Money is never visible without a billing permission.

Permissive policies then grant within those bounds. A mistake in a permissive
policy becomes an over-grant *inside* a hard boundary rather than a breach of it.

### 2.4 Column-level privileges under RLS

Postgres supports `GRANT SELECT (columns)`. Money columns should be revoked from
roles that must not see them, so that even an incorrect row policy cannot leak a
dollar figure. This sits *beneath* RLS, not beside it.

### 2.5 Adversarial tests are written first

Every bug found so far was found by testing the *denial* case, always after the
fact. For this work the RLS suite gets the negative assertions **before** the
policies exist: a collaborator must not see other projects, must not see money,
must not see the org's other clients, must not see other collaborators.

A permission check that never runs is indistinguishable from one that passes.

---

## 3. Recommendation: project-scoped collaboration

**A subcontracting organization is granted access to a project. Nobody gains
membership in anybody else's organization.**

Membership and collaboration stay different things. Membership (§4) says which
organizations a person is *part of*. Collaboration says which single project of
*another* organization their organization may reach. A subcontractor never gains
membership in the hiring organization — only a grant on one job.

### Why this and not multi-organization membership

Not effort. Two reasons:

**It is fail-closed.** If a sub were a member of the GC's organization, then
"belongs to this org" is *true* for them, and every org-scoped policy in the
system grants access by default. Every table would need to actively remember to
exclude subs — including every table added in future. Under §2.1 that is the
wrong shape.

With collaboration, a sub is not a member, so every existing org-scoped policy
already excludes them, permanently, with nobody remembering anything. New tables
inherit safety rather than inheriting exposure.

**It is true.** A plumbing company is not part of the general contractor's
company. It is contracted onto a job. A data model that says otherwise is lying,
and models that lie produce features that surprise people.

Note that generality is not a virtue here. The most general access model is
"everyone can reach everything, with rules to restrict" — obviously wrong for a
security boundary. Narrowness is the point.

### What the plumbing company sees

Every `owner`/`pro` member of the plumbing company sees a project list that is
the union of their own organization's jobs and the jobs that organization has
been granted. One login each, one list, no switching, and no dependence on which
individual was named when the grant was made. When the GC's job ends the grant is
revoked and it disappears for all of them at once — nothing of theirs is
affected.

---

## 4. Proposed schema

### The grant is organization to organization

A general contractor does not hire a plumber. They hire **a plumbing company**.
Which technician turns up may change day to day, two may work at once, and the
one who was originally given access may leave.

So the grant is **org → project**, and the collaborating organization decides
which of its own people work the job using its own internal roles. The GC never
manages employees of a company it does not employ.

This unifies the cases rather than multiplying them: in PNCHD everyone with an
account already has an organization, because signup requires one. A solo plumber
is an organization of one; a forty-person plumbing company is an organization of
forty. Identical grant, no special case for either.

It also makes the policy check *simpler* than a per-person grant would: "does my
organization hold a grant on this project" resolves through
`current_user_organization_id()`, which every policy already calls, rather than
adding a separate per-person lookup alongside it.

```sql
-- Which organization may reach a project belonging to another, and as what.
create table project_collaborations (
  id                       uuid primary key default gen_random_uuid(),
  project_id               uuid not null references projects(id) on delete cascade,
  collaborator_org_id      uuid not null references organizations(id) on delete cascade,
  granting_organization_id uuid not null references organizations(id) on delete cascade,
  access_level             text not null check (access_level in ('view', 'contribute')),
  trade                    text,          -- see open decision B
  invited_by               uuid not null references profiles(id),
  invited_at               timestamptz not null default now(),
  accepted_at              timestamptz,
  revoked_at               timestamptz,

  -- A project cannot be shared with the organization that already owns it.
  constraint no_self_collaboration
    check (collaborator_org_id <> granting_organization_id)
);

create unique index on project_collaborations (project_id, collaborator_org_id)
  where revoked_at is null;
```

`revoked_at` rather than deletion: who had access to what, and when, is an audit
question that outlives the grant.

**Within the collaborating organization**, access follows that org's own rules —
its `owner` and `pro` members can reach the shared project, its clients and
drivers cannot. Their internal access control is their business, not the GC's.
The GC's security interest is "which *companies* can see my job," and that is
exactly what the grant expresses.

If a GC ever needs to narrow a grant to specific individuals at the sub, that is
an additive `project_collaboration_members` table later. Recommend not building
it until someone asks — the org-level grant is the honest default, and narrower
grants that nobody maintains drift into being wrong.

```sql
-- What a member of an organization may do beyond the default for their role.
create table profile_permissions (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null references profiles(id) on delete cascade,
  organization_id uuid not null references organizations(id) on delete cascade,
  permission      text not null check (permission in ('billing')),
  level           text not null check (level in ('read', 'write')),
  granted_by      uuid not null references profiles(id),
  granted_at      timestamptz not null default now(),
  revoked_at      timestamptz
);
```

A table rather than boolean columns because permissions multiply, and because
`granted_by`/`granted_at` is the audit trail for the question "who let them see
that."

**Money becomes invisible to seats by default** and is granted deliberately —
which is the behaviour described as wanted. `owner` always has it implicitly and
needs no row.

### A seat at a subcontracting company

Worth confirming, because it is the common case: a plumber who is a `pro` seat
at Ace Plumbing, where Ace is subcontracted onto a GC's project.

This needs nothing extra. The GC grants the project to **Ace Plumbing**, and the
plumber sees it through his existing membership. He needs no organization of his
own and no second login.

Granting to individuals would have broken precisely this. The GC would have had
to name the plumber personally — putting a seat, who has no authority to
contract anything, in possession of a business relationship belonging to his
employer. It would also survive his departure. With the org-to-org grant,
leaving Ace removes his membership and therefore his access, with nobody
revoking anything.

### DECIDED: one person, one organization

**A person belongs to exactly one organization. `profiles.organization_id` stays
a single column. There is no membership table and no active-organization
concept.**

Someone who is a seat at one company and wants to run side jobs creates a
separate owner account under a different email.

#### Why this is the more secure model, not merely the simpler one

With single-tenant identity, cross-tenant leakage is not something policies have
to prevent — it is structurally impossible. There is no membership set to
resolve, no active organization to select, and therefore none of the failure
mode described below.

> **The trap this avoids.** A user belonging to several organizations needs a
> notion of which one they are currently viewing. That selection is UI state and
> must never enter a security decision. Policies must check *set membership*
> resolved server-side; a policy that compares against the organization the
> *client says* it is viewing lets a lying client read another tenant's data.
> This is the standard way multi-tenant systems get breached, and it is a
> fail-open shape (§2.1).

Every multi-organization design is a bet that membership resolution is correct
everywhere, permanently, including in tables not yet written. Declining to make
that bet is stronger than winning it.

There is also an argument that single-tenant is simply *truer*: a side business
is a different legal entity, with its own licensing, insurance, and tax
treatment. One login spanning both models them as the same thing when they are
not.

#### What this preserves

Every subcontractor case still works, because collaboration is org-to-org and
does not require anyone to join anyone else's organization:

- a plumbing company subcontracted onto a GC's project
- that company's owner seeing the GC's job from their own login
- a seat at that company seeing the same job through their existing membership
- a solo trade — an organization of one — subcontracted on

#### What this costs

One human cannot be a seat at one organization and an owner of another under a
single login. They need two accounts with two email addresses.

#### What would reopen this

The moonlighting seat is the *occasional* case and two accounts is tolerable
there. The case that will press hardest is a contractor running **two LLCs they
own and operate daily** — switching by logging out is genuinely poor.

Reopen if that becomes a real, repeated complaint from actual customers rather
than a hypothetical. Adding membership later is a migration touching every
policy, and is worth doing properly at that point instead of carrying the risk
now for a case that may never arrive.

### Multi-business owners (case 4)

Handled by the decision above: two organizations, two accounts. Listed in §1 as
a case the current model cannot express, and it remains one — deliberately, per
the reasoning and reopen conditions above.

---

## 5. RLS shape

Illustrative, not final.

```sql
-- Hard boundary. Nothing widens this.
create policy "projects_boundary" on projects
  as restrictive for all to authenticated
  using (
    organization_id = current_user_organization_id()
    or exists (select 1 from project_collaborations
               where project_id = projects.id
                 and collaborator_org_id = current_user_organization_id()
                 and accepted_at is not null
                 and revoked_at is null)
  );

-- Grants operate only inside it.
create policy "projects_org_contractors" on projects
  for all to authenticated
  using (organization_id = current_user_organization_id()
         and current_user_is_contractor());
```

Money-bearing tables get a restrictive policy requiring either `owner`, or a
`billing` permission row — so a collaborator can never reach an invoice
regardless of any other policy, and neither can a seat without an explicit
grant.

---

## 5. Requirements from practice

From a design architect who works these relationships daily. These are
observations about how the industry actually behaves, not preferences.

### 5.1 Not every trade gets an account

Only the prominent subs — HVAC, plumbing, electrical — are typically given
access in software like this. Cabinet install, tile, painters usually are not.

So access is **selective and deliberate**, not something granted to everyone on a
job. This supports the fail-closed model: nobody is on a project until somebody
puts them there, and most trades never are.

### 5.2 Punchlist authority is asymmetric

**Only the GC or project manager can create, edit, or close punch items.**

Everyone else — subs, field staff — *submits* against an item: a comment with
photos or video showing the work is done. The PM or GC then signs off.

This is a permission split, not a role split. Two distinct capabilities:

- `punch:manage` — create, amend, accept, reject. GC/PM only.
- `punch:respond` — submit evidence against an assigned item. Subs and field staff.

A sub can never mark their own work accepted. That is the entire point of a
punchlist.

### 5.2a Punch requests

Working name for a sub's response to a punch item: a **punch request** —
deliberately echoing a pull request. Proposed by whoever did the work, approved
or sent back by someone with authority, and permanent either way.

**Not believed to be established industry vocabulary.** The adjacent standard
terms are *punch list* and *punch item* (universal), *submittal* (real, but means
shop drawings and product data approved before work), and *RFI*. The act of a sub
saying "I fixed it" appears to have no strong standard name. Confirm with someone
in the trade that "punch request" reads as natural rather than as software
jargon.

The analogy carries further than the name. A pull request cannot merge until its
required checks pass; a punch request cannot be submitted until the evidence the
GC demanded is attached.

**Required evidence is a setting.** The GC or PM can require a photo, a video,
or either, before a punch request may be submitted.

- Set at project level, overridable per item — some items genuinely need video
  (a running system, a drain test) where most need a photo.
- **Enforced server-side.** A disabled button is not enforcement. The insert must
  be rejected if the required media is absent, or the requirement is decorative.

**Assignment is to an organization; submission is by a person.** A punch item
assigned to a sub company is assigned to the *organization* — but the person who
submits is a profile in *their* org, not the GC's. Same shape as a ticket
assigned to a team and picked up by whoever is on shift. This is exactly gap G3,
and punch requests make it blocking rather than theoretical.

### 5.2b Field staff and sub companies are different entities

Stated plainly because the two are easy to conflate:

| | Field staff | Sub company |
|---|---|---|
| What it is | a **person** (`profiles` row) | an **organization** (`organizations` row) |
| Lives | inside the contractor's org | its own org |
| Connected via | `project_assignments` | `project_collaborations` |
| Account cost | free | pays its own subscription |
| Bills the contractor | privately, outside the app | through the app, org → org |
| Has its own crew | no — they *are* the crew | yes, its own profiles |

Two separate paths into a project, and the choice between them decides whether
any money touches the platform.

### 5.2c A sub company has its own field staff

Bolt Electric is an organization with an owner, possibly office seats, and its
own field techs. Those techs are profiles in **Bolt's** org. Getting one onto a
general contractor's job is a three-hop chain:

```
GC's project --collaboration--> Bolt Electric --assignment--> Bolt's tech
        (GC grants)                      (Bolt staffs it)
```

**The GC makes only the first hop.** The same reasoning that made the grant
org-to-org applies here: the GC hires the company, the company decides who shows
up, and swapping a tech must not require the GC to do anything.

This needs a second assignment table rather than an extension of the first:

```sql
create table collaboration_assignments (
  id            uuid primary key default gen_random_uuid(),
  collaboration_id uuid not null references project_collaborations(id) on delete cascade,
  profile_id    uuid not null references profiles(id) on delete cascade,
  assigned_by   uuid not null references profiles(id),
  assigned_at   timestamptz not null default now(),
  is_active     boolean not null default true
);
```

Separate rather than extending `project_assignments`, because extending it means
loosening a policy that currently carries a clean organization check — the
fail-open shape (§2.1) that has already produced three incidents here. A trigger
enforces that `profile_id` belongs to the collaboration's `collaborator_org_id`,
so a collaborating org can only assign its own people.

**Access within the collaborating organization then mirrors access within any
organization:**

- **owner / seats** at Bolt see the shared project, because Bolt holds the grant
- **field staff** at Bolt see it only if Bolt assigned them

Which preserves what "field staff" means on both sides of the relationship:
assigned-only, regardless of whose project it is.

Note the consequence: a Bolt tech has no relationship with the GC's organization
at all. They reach the job through Bolt's grant and Bolt's assignment, two hops
removed, and nothing else in the GC's org is reachable to them.

### 5.3 Visibility must be obvious, not buried

The controls for what clients and subs can see on a project must be **immediately
visible and easy to reach** — a single place showing who can see what, per
project.

This is from a real failure: in other software, a company **accidentally exposed
correspondence and payment information to clients** who should never have seen
it. That is a trust-destroying event, and it happened because the controls were
obscure enough that nobody realized what was on.

Design implications:

- A per-project visibility panel, reachable in one step, listing every party and
  what they can currently see.
- State shown affirmatively — "the client can see X" — not as unlabeled
  checkboxes whose meaning has to be inferred.
- Default to hidden. Sharing is an act; concealment is the resting state.

Note this is a *UI* requirement backed by an RLS requirement. The panel reflects
enforcement; it does not implement it. Anything the panel claims is hidden must
be unreachable at the database, or the panel is lying.

### 5.4 Append-only: the record is evidence

Nothing that establishes what happened may be destroyed.

- Items can be **unchecked**, and descriptions can be **struck through** — still
  visible, marked as withdrawn rather than removed.
- Edits are **appended**, not overwritten. The prior text remains legible.
- **Work submissions cannot be deleted, including by the owner.** If a sub
  submitted photos of completed work, that evidence survives — even if the GC
  later closes the item, disputes it, or would prefer it gone.

The stated purpose: *to keep everyone honest.* Both directions. A GC cannot erase
proof that a sub did the work; a sub cannot revise what they submitted after the
fact.

Practically this means punch items and submissions are **append-only tables with
soft state**, not mutable rows:

- no `DELETE` policy for any role, including `owner`
- `UPDATE` restricted to status transitions and withdrawal flags
- amendments stored as new rows referencing the original
- every row carries who and when

This is the one place where the platform genuinely is the legal record, so it
should be built to hold up as one.

---

## 5b. Relationship audit — what this model does NOT yet cover

Written by walking every pair of actors rather than only the ones that prompted
the design. Ordered by severity.

### G1. A subcontractor cannot bill the general contractor (structural)

Ace Plumbing does the work and invoices the GC. **The GC is Ace's customer.**

`invoices.client_id` references `profiles`, which assumes the client is a
*person* — a homeowner. To bill a company, Ace would have to fabricate a client
profile standing in for "GC Corp", and the GC would never see that invoice in
their own account or be able to pay it through the platform.

So the B2B leg of the money flow does not exist. `client_payments` currently
only models contractor → homeowner, and sub → GC is among the most common
transactions in construction.

Options, none chosen:

- Allow `invoices.client_organization_id` as an alternative to `client_id`,
  exactly one of the two set. Invoice becomes visible to the billed
  organization, payable through Connect, and the existing client-approval
  trigger needs a parallel path for an organization approving rather than a
  person.
- Model the GC as a client profile inside Ace's org and accept that the GC
  cannot see or pay it in-app. Loses the payments module for this case
  entirely.

The first is the honest one. It is a real schema change to `invoices`,
`proposals`, and their RLS.

### G2. Grant authority is unbounded (hole in §4)

`project_collaborations` constrains only that collaborator ≠ granter. It never
requires `granting_organization_id` to *own* the project. As written, a
collaborator could grant a project onward to a fourth organization.

Sub-subcontracting is real, but it must be the project owner's decision. Fix:
a check that the granting organization owns the project, enforced by trigger
since it spans tables — plus an explicit decision about whether a collaborator
may ever invite anyone (recommend: no, the owner invites everyone).

### G3. A subcontractor's crew cannot be assigned to the job

`project_assignments` is organization-scoped, so Ace's own crew and drivers
cannot be assigned to the GC's project. The sub can see the job but nobody at
the sub can be scheduled on it, which makes the collaboration close to useless
for field work — the thing it exists for.

Needs either assignments that permit a collaborating organization's members, or
a parallel per-collaboration assignment concept.

### G4. Does the subcontractor see the GC's client?

Projects carry `client_id`. If Ace can see the project, can Ace see the
homeowner's identity and contact details?

Arguments both ways: the plumber may genuinely need to reach the homeowner for
access to the property; equally, the homeowner is the GC's commercial
relationship and handing it to every trade invites disintermediation.

Folds into open decision B.

### G5. Do two subcontractors on one job see each other?

Ace Plumbing and Bolt Electric both collaborate on the same project. Do they see
each other's presence, line items, documents, or schedule entries?

Folds into open decision B, but note it is a distinct question from B — B is
about *pricing* visibility, this is about *existence*.

### G6. Cross-organization documents and notifications

- A subcontract agreement is signed *between* the GC and the sub.
  `document_signers.profile_id` is org-scoped, so a signer from another
  organization is not currently expressible.
- `notifications` carries `organization_id` and `recipient_id`. A notification
  to a sub about the GC's project has an ambiguous owner: the GC's org (where
  the work is) or the sub's (where the recipient is). Recommend the recipient's,
  so a sub's inbox never depends on retaining access to the GC's org.

### G7. A contractor who is also somebody's client

A plumber whose own house needs electrical work is a `client` of Bolt Electric
and an `owner` of Ace Plumbing. Under the one-person-one-organization decision
that is two accounts.

Called out because it is likely **more common than the moonlighting seat** —
trades hire each other constantly — and it is the same decision, not a new one.
It does not change the recommendation, but it does raise how often two accounts
will be felt.

---

## 6. Open decisions

**A. Does a one-off trade need an account?**

- *Real account* — they sign in, see the job, appear consistently everywhere.
  Consistent identity, works with everything above unchanged.
- *Link-scoped access without signup* — lower friction, but it means a
  credential that is not a user, which is a second authentication path and a
  second thing to get right. Given §2.1, a second auth path is a second place to
  fail open.

Leaning strongly toward a real account. Client and driver accounts are already
free and unlimited, so cost to the contractor is zero.

**B. Does a subcontractor see the whole project, or only their own scope?**

The concrete question: can the electrician see the mason's line items and
pricing?

- *Whole project* — simpler and more collaborative, but exposes other trades'
  pricing to competitors-in-adjacent-trades.
- *Scoped* — the `trade` column above, with line items and documents tagged by
  trade. More faithful to how the industry actually guards pricing, and more
  defensible. Requires tagging work, and a decision about what an untagged item
  means (recommend: visible only to the organization, never to collaborators).

This one materially changes the model, which is why it is called out rather than
assumed. Recommend scoped — a data model that lets one trade read another's
margins will eventually cause a real commercial problem for a customer.

---

## 7. Sequence

1. Settle A and B.
2. Write the adversarial RLS tests (§2.5) — they will fail.
3. Add restrictive boundary policies to existing tables. No behaviour change for
   current roles; verify the suite stays green.
4. Add `profile_permissions`; move money behind it. Seats lose default money
   access — a deliberate, breaking change.
5. Add `project_collaborations` and collaborator policies.
6. Column-level revokes on money columns.
7. UI: invite a collaborator, grant billing, revoke both.

Steps 3 and 4 are worth doing regardless of the subcontractor feature. They
close the "a seat can read every invoice" gap that exists today.

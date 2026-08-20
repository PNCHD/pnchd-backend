# PNCHD — Access Model (Proposal)

**Status: proposal, not built.** Supersedes nothing yet. Two decisions at the
bottom are still open.

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
   remodeling company plus a separate service outfit.

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

`profiles.organization_id` stays as it is — one person, one home organization.
Access to work elsewhere is a separate, explicit grant, made from one
organization to another, per project.

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
the union of their own organization's jobs and the jobs their organization has
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

It also makes the policy check *simpler* than a per-person grant would:
"does my organization hold a grant on this project" resolves through
`current_user_organization_id()`, which every policy already calls.

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

### One person, two organizations (identity vs membership)

The case one step further does *not* work today, and is common in the trades: a
plumber who is a seat at Ace Plumbing **and** runs his own side jobs. Employed by
one company, owner of another.

`profiles.organization_id` is a single column, so this is unrepresentable. That
is the same conflation described in §1 — `profiles` means both "who this person
is" and "which company they are in" — and it is the root of most of the questions
this document exists to answer.

Separating them is the correct model regardless of the subcontractor feature:

```sql
-- identity: one row per human, no organization
profiles(id, full_name, avatar_url, phone, push_token, is_active, …)

-- membership: many rows per human
organization_members(
  id, profile_id, organization_id,
  role,                 -- owner | pro | client | driver, within THIS org
  is_active, joined_at, …
)
```

Note that `role` becomes a property of the membership, not the person — which is
also more correct. Someone can be an `owner` of their own company and a `pro`
somewhere else, and today's schema cannot say that either.

#### The active organization is a filter, never a boundary

The single most dangerous mistake available here.

A user who belongs to several organizations needs a notion of which one they are
currently looking at. That selection is **UI state**. It must never appear in a
security decision.

- **Correct:** policies check *set membership* — "is this row's organization one
  I am a member of" — resolved server-side from `organization_members`.
- **Wrong:** policies check "equals the organization the client says it is
  viewing." A client that lies about its active organization then reads another
  tenant's data.

Concretely, `current_user_organization_id()` becomes
`current_user_organization_ids()` returning a set, and org-scoped policies move
from `organization_id = current_user_organization_id()` to
`organization_id = any(current_user_organization_ids())`. The active
organization narrows what is *displayed*; it never widens what is *reachable*.

This is a fail-open shape (§2.1) and belongs in the adversarial tests before any
of it is written: a member of orgs A and B, claiming to be viewing org C, must
read nothing from C.

### Multi-business owners (case 4)

Solved by the same `organization_members` separation above — a GC running two
LLCs holds an `owner` membership in each. No additional mechanism.

It is worth keeping distinct from subcontractor access conceptually, because
conflating "I own two companies" with "I'm working your job this month" is what
made this feel intractable. They are different relationships and stay different
rows: membership versus collaboration. But they share one prerequisite, which is
that identity stops being welded to a single organization.

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

0. Separate identity from membership (`organization_members`), including the
   set-membership policy change and the adversarial test that a user cannot
   read an organization they merely *claim* to be viewing. Everything else
   assumes this, and retrofitting it later means touching every policy a
   second time.
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

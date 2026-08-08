-- ============================================================================
-- PNCHD · Phase 2, Block A
-- Migration: documents + document_signers
-- Ref: Architecture Doc Section 5.1 (schema), Section 6 (indexes), Section 7.2 (RLS), Section 8.1 (Docuseal)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. documents
-- ----------------------------------------------------------------------------
create table if not exists documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  project_id uuid references projects(id),
  title text not null,
  storage_path text not null,
  completed_storage_path text,
  type text not null default 'general' check (type in (
    'contract', 'change_order', 'general', 'other'
  )),
  status text not null default 'draft' check (status in (
    'draft', 'sent', 'completed', 'voided'
  )),
  docuseal_submission_id text,
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now()
);

comment on column documents.storage_path is 'Supabase Storage bucket path for the original file.';
comment on column documents.completed_storage_path is 'Path to the signed/completed document, set once Docuseal reports completion.';
comment on column documents.docuseal_submission_id is 'Docuseal submission ID for status tracking (Section 8.1).';

-- ----------------------------------------------------------------------------
-- 2. document_signers
-- Tracks each individual signer on a document. A document may require
-- multiple signers.
-- ----------------------------------------------------------------------------
create table if not exists document_signers (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references documents(id),
  organization_id uuid not null references organizations(id),
  profile_id uuid references profiles(id),
  signer_name text not null,
  signer_email text not null,
  docuseal_submitter_id text,
  status text not null default 'pending' check (status in (
    'pending', 'sent', 'opened', 'signed', 'declined'
  )),
  signed_at timestamptz,
  signing_ip text
);

comment on column document_signers.profile_id is 'Null if the signer is external (not a platform user) — e.g. a client not yet invited, or a third party.';
comment on column document_signers.signing_ip is 'Captured for audit trail.';

-- ----------------------------------------------------------------------------
-- 3. Indexes (Section 6)
-- ----------------------------------------------------------------------------
create index if not exists idx_documents_org_project
  on documents (organization_id, project_id);

create index if not exists idx_document_signers_document_id
  on document_signers (document_id);

-- ----------------------------------------------------------------------------
-- 4. Client/signer write restriction on document_signers
--
-- Section 7.2: client "write signed_at only." In practice, actual signing
-- happens in Docuseal's hosted UI (Section 8.1) and the completion webhook
-- writes signed_at using the service role key — so this policy path is
-- more of a safety net than the primary write path. Still implementing it
-- per spec in case a platform user signs an in-app confirmation separate
-- from the Docuseal flow.
--
-- Restricted to the signer's own row, one-time set (can't un-sign or
-- re-sign), no other columns touchable.
-- ----------------------------------------------------------------------------
create or replace function public.enforce_document_signer_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  current_role text;
begin
  select role into current_role from profiles where id = auth.uid();

  if current_role in ('client', 'driver') then
    if new.signed_at is null or old.signed_at is not null then
      raise exception 'Signers may only set signed_at once';
    end if;

    if new.document_id != old.document_id
      or new.organization_id != old.organization_id
      or new.profile_id is distinct from old.profile_id
      or new.signer_name != old.signer_name
      or new.signer_email != old.signer_email
      or new.docuseal_submitter_id is distinct from old.docuseal_submitter_id
      or new.signing_ip is distinct from old.signing_ip
    then
      raise exception 'Signers may only update signed_at on their own record';
    end if;

    new.status = 'signed';
  end if;

  return new;
end;
$$;

create trigger enforce_document_signer_update_trigger
  before update on document_signers
  for each row execute function public.enforce_document_signer_update();

-- ----------------------------------------------------------------------------
-- 5. Row Level Security (Section 7.2)
-- ----------------------------------------------------------------------------
alter table documents enable row level security;
alter table document_signers enable row level security;

-- documents: owner/pro full CRUD on own org
create policy "documents_owner_pro_full_access"
  on documents for all
  to authenticated
  using (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) in ('owner', 'pro')
  )
  with check (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) in ('owner', 'pro')
  );

-- documents: client/driver read assigned docs only — "assigned" means
-- they appear as a signer on the document.
create policy "documents_signer_read_assigned"
  on documents for select
  to authenticated
  using (
    exists (
      select 1 from document_signers
      where document_signers.document_id = documents.id
      and document_signers.profile_id = auth.uid()
    )
  );

create policy "admin_bypass_documents"
  on documents for all
  to authenticated
  using (
    (select role from profiles where id = auth.uid()) = 'platform_admin'
  );

-- document_signers: owner/pro full CRUD on own org
create policy "document_signers_owner_pro_full_access"
  on document_signers for all
  to authenticated
  using (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) in ('owner', 'pro')
  )
  with check (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) in ('owner', 'pro')
  );

-- document_signers: read/write own signer record only
create policy "document_signers_own_record_read"
  on document_signers for select
  to authenticated
  using (profile_id = auth.uid());

create policy "document_signers_own_record_update"
  on document_signers for update
  to authenticated
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

create policy "admin_bypass_document_signers"
  on document_signers for all
  to authenticated
  using (
    (select role from profiles where id = auth.uid()) = 'platform_admin'
  );

-- ============================================================================
-- End of migration
-- ============================================================================

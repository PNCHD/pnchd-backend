-- ============================================================================
-- PNCHD · Phase 2, Block A
-- Migration: line_items
-- Ref: Architecture Doc Section 5.1 (schema), Section 6 (indexes), Section 7.2 (RLS)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. line_items
-- Shared by both proposals and invoices. Polymorphic via parent_type +
-- parent_id — a plain foreign key can't span two possible parent tables,
-- so referential integrity is enforced by the trigger below instead.
-- ----------------------------------------------------------------------------
create table if not exists line_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id),
  parent_type text not null check (parent_type in ('proposal', 'invoice')),
  parent_id uuid not null,
  description text not null,
  quantity numeric(10,2) not null default 1,
  unit_price_cents integer not null,
  total_cents integer not null,
  sort_order integer not null default 0
);

comment on column line_items.parent_id is 'References proposals.id or invoices.id depending on parent_type. Enforced by trigger, not a FK, since parent_type varies.';
comment on column line_items.total_cents is 'quantity * unit_price_cents. Money always stored in cents, never floats.';

-- ----------------------------------------------------------------------------
-- 2. Polymorphic parent existence check
-- Since parent_id can't be a real foreign key across two tables, this
-- trigger does the equivalent check manually on insert/update.
-- ----------------------------------------------------------------------------
create or replace function public.validate_line_item_parent()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.parent_type = 'proposal' then
    if not exists (select 1 from proposals where id = new.parent_id) then
      raise exception 'parent_id % does not reference an existing proposal', new.parent_id;
    end if;
  elsif new.parent_type = 'invoice' then
    if not exists (select 1 from invoices where id = new.parent_id) then
      raise exception 'parent_id % does not reference an existing invoice', new.parent_id;
    end if;
  end if;

  return new;
end;
$$;

create trigger validate_line_item_parent_trigger
  before insert or update on line_items
  for each row execute function public.validate_line_item_parent();

-- ----------------------------------------------------------------------------
-- 3. Indexes (Section 6)
-- ----------------------------------------------------------------------------
create index if not exists idx_line_items_parent
  on line_items (parent_type, parent_id);

-- ----------------------------------------------------------------------------
-- 4. Row Level Security (Section 7.2)
-- Owner/Pro: full CRUD on own org.
-- Client: read only, on line items belonging to their own proposals/invoices.
-- ----------------------------------------------------------------------------
alter table line_items enable row level security;

create policy "line_items_owner_pro_full_access"
  on line_items for all
  to authenticated
  using (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) in ('owner', 'pro')
  )
  with check (
    organization_id = (select organization_id from profiles where id = auth.uid())
    and (select role from profiles where id = auth.uid()) in ('owner', 'pro')
  );

create policy "line_items_client_read_own"
  on line_items for select
  to authenticated
  using (
    (parent_type = 'proposal' and exists (
      select 1 from proposals
      where proposals.id = line_items.parent_id
      and proposals.client_id = auth.uid()
    ))
    or
    (parent_type = 'invoice' and exists (
      select 1 from invoices
      where invoices.id = line_items.parent_id
      and invoices.client_id = auth.uid()
    ))
  );

create policy "admin_bypass_line_items"
  on line_items for all
  to authenticated
  using (
    (select role from profiles where id = auth.uid()) = 'platform_admin'
  );

-- ============================================================================
-- End of migration
-- ============================================================================

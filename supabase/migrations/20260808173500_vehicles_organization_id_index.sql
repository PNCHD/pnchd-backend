-- ============================================================================
-- PNCHD · Phase 2, Block A
-- Migration: vehicles organization_id index
-- Ref: Follow-up to 20260808172742_vehicles_vehicle_locations.sql — Section 6
-- lists no index for vehicles, but organization_id is checked on every RLS
-- lookup same as every other table. Added on explicit call rather than left
-- as a silent gap.
-- ============================================================================

create index if not exists idx_vehicles_organization_id
  on vehicles (organization_id);

-- ============================================================================
-- End of migration
-- ============================================================================

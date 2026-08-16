#!/usr/bin/env bash
# Static checks for RLS patterns that fail in ways migrations won't surface.
# `supabase db push` succeeding proves the DDL parsed, nothing more.
#
# Complements supabase/tests/rls.test.ts, which exercises the same concerns at
# runtime as real signed-in users. This catches the shapes; that catches the
# behavior.
set -uo pipefail

cd "$(dirname "$0")/.."
MIGRATIONS="supabase/migrations"
FINDINGS=$(mktemp)
trap 'rm -f "$FINDINGS"' EXIT

# The migration that replaced inline profiles subqueries with helper functions.
# Files at or before it are history; only later ones can reintroduce the bug.
FIX_MIGRATION="20260816000734"

report() {
  { printf '\n  %s\n' "$1"; shift; printf '    %s\n' "$@"; } >> "$FINDINGS"
}

# --- 1. Inline profiles subqueries inside policies ---------------------------
# On `profiles` this recurses through the table's own policy (42P17), which
# cascades to every table whose policy reads profiles — all of them.
for file in "$MIGRATIONS"/*.sql; do
  name=$(basename "$file")
  [[ "$name" < "$FIX_MIGRATION" || "$name" == "$FIX_MIGRATION"* ]] && continue
  if grep -q "from profiles where id = auth.uid()" "$file"; then
    report "Inline 'from profiles where id = auth.uid()' in $name" \
      "Causes 42P17 infinite recursion. Use current_user_organization_id()," \
      "current_user_role(), current_user_is_admin(), or current_user_is_contractor()."
  fi
done

# --- 2. Tables created without RLS enabled -----------------------------------
while read -r table; do
  [ -z "$table" ] && continue
  grep -qs "alter table $table enable row level security" "$MIGRATIONS"/*.sql \
    || report "Table '$table' never has RLS enabled" \
         "Every table must run: alter table $table enable row level security;"
done < <(grep -hoE "^create table if not exists [a-z_]+" "$MIGRATIONS"/*.sql \
  | awk '{print $NF}' | sort -u)

# --- 3. Module/feature gate written as a standalone policy -------------------
# Permissive policies OR together, so a gate with no ownership condition of its
# own is satisfied by a sibling policy and gates nothing. A gate is fine
# alongside either an org check or an auth.uid() ownership check.
while read -r finding; do
  [ -z "$finding" ] && continue
  report "Standalone gate policy: $finding" \
    "Permissive policies OR together, so this grants access on its own." \
    "AND the gate into each policy's ownership condition instead."
done < <(
  awk '
    /^create policy/ { body = ""; capturing = 1; name = $0 }
    capturing        { body = body " " $0 }
    /;[[:space:]]*$/ {
      if (capturing \
          && body ~ /has_active_module|is_client_feature_enabled/ \
          && body !~ /organization_id/ \
          && body !~ /auth\.uid\(\)/) {
        gsub(/^create policy |"/, "", name)
        print name " (" FILENAME ")"
      }
      capturing = 0
    }
  ' "$MIGRATIONS"/*.sql
)

# --- report ------------------------------------------------------------------
if [ ! -s "$FINDINGS" ]; then
  echo "policy checks: OK"
  exit 0
fi
cat "$FINDINGS"
printf '\n%d issue(s) found\n' "$(grep -c '^  [A-Z]' "$FINDINGS")"
exit 1

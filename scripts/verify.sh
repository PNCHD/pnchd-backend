#!/usr/bin/env bash
# One command to verify the backend. Run before considering schema work done.
#
#   ./scripts/verify.sh              # static checks + Edge Function tests
#   ./scripts/verify.sh --with-rls   # also run the RLS suite against pnchd-dev
#
# The RLS suite needs credentials and creates/destroys real users, so it is
# opt-in:
#   export SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... SUPABASE_ANON_KEY=...
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> policy static checks"
./scripts/check-policies.sh

echo
echo "==> Edge Function lint, typecheck, tests"
(cd supabase/functions && deno task verify)

if [ "${1:-}" = "--with-rls" ]; then
  echo
  echo "==> RLS suite (real signed-in users)"
  (cd supabase/tests && deno task rls)
else
  echo
  echo "(skipped RLS suite — pass --with-rls with credentials exported)"
fi

echo
echo "backend verify: OK"

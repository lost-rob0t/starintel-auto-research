#!/usr/bin/env sh
set -eu

A0_USR="${1:-/a0/usr}"
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

mkdir -p "$A0_USR/skills"
cp -R "$ROOT/skills/." "$A0_USR/skills/"

cat >&2 <<'EOF'
StarIntel autonomous Agent Zero worker profiles are retired.

Live Auto-RAGE development workers moved to lost-rob0t/hackmode:
  - hackmode-rage-database
  - hackmode-rage-hackpert

This installer copied the reusable skill pack only. It did NOT install a
StarIntel product worker. Migrated Hackmode workers may touch StarIntel only
for explicitly authorized cyber/BBP work or security finding/evidence projection.
EOF

printf 'Installed StarIntel reusable skills into %s/skills (no worker profile installed)\n' "$A0_USR"

#!/usr/bin/env sh
set -eu
A0_USR="${1:-/a0/usr}"
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$A0_USR/agents/starintel/prompts" "$A0_USR/skills"
cp -R "$ROOT/agent-zero/usr/agents/starintel/prompts/." "$A0_USR/agents/starintel/prompts/"
cp -R "$ROOT/skills/." "$A0_USR/skills/"
printf 'Installed Starintel Agent Zero profile and skills into %s\n' "$A0_USR"

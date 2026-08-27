#!/usr/bin/env bash
# Hook Stop (Claude) / stop (Cursor) — corre check-drift en modo DELTA y bloquea
# si el modelo introdujo errores NUEVOS respecto al baseline de inicio de sesión.
# La deuda preexistente NO bloquea (está en backlog/ledger). Re-basea al commitear.
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"
cd "$PROJECT_ROOT" || exit 0

drift="tools/check-drift.sh"; [ -x "$drift" ] || exit 0
state="$(hook_state_dir)"; mkdir -p "$state"
base="$state/drift-baseline.txt"; base_head="$state/drift-baseline.head"
cur_head="$(git rev-parse HEAD 2>/dev/null || echo no-git)"

# (Re)baseline si falta o si HEAD cambió (commit nuevo).
need=0
[ -f "$base" ] || need=1
[ -f "$base_head" ] || need=1
[ -f "$base_head" ] && [ "$(cat "$base_head" 2>/dev/null)" != "$cur_head" ] && need=1
if [ "$need" = "1" ]; then
  bash "$drift" > "$base" 2>&1 || true
  echo "$cur_head" > "$base_head"
  exit 0   # primer Stop tras baseline → permite.
fi

extract() { grep -E '^❌|^⚠️|:[0-9]+:|\([0-9]+ líneas\)' || true; }
new="$(comm -13 <(extract < "$base" | sort -u) <(bash "$drift" 2>&1 | extract | sort -u))"
[ -z "$new" ] && exit 0

hook_block "Drift detectó errores NUEVOS en esta sesión (no estaban al inicio):"$'\n\n'"$new"$'\n\n'"Repara antes de cerrar, o commitea (pasarán a baseline)."

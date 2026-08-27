#!/usr/bin/env bash
# Reúne el contexto para el sub-agente `process-judge`:
#   - la trayectoria capturada de la sesión (sin secretos)
#   - el diff del trabajo (staged + último commit)
#   - puntero a las reglas
# Uso:  bash scripts/process-judge-context.sh [session_id]
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1
SID="${1:-}"
TRAJ_DIR=".agents/state/trajectory"

echo "═══ REGLAS ═══"
echo "Lee: AGENTS.md, el tramo vivo de docs/process/lessons_learned.md (hasta el índice), y la skill del área tocada. El archivo histórico es bajo demanda."

# RC=3 cuando se pidió una sesión CONCRETA y su trayectoria no está.
#
# Antes salía 0 en ese caso, y eso convertía al juez en un lector de diffs que
# se cree lector de trayectorias: su encargo es juzgar CÓMO se trabajó, no solo
# qué salió, y sin el archivo solo puede hacer lo segundo — sin enterarse. Es
# justo el contrato de §14.3: 0 = limpio · 1 = hay un problema en lo tuyo ·
# 3 = EL DETECTOR NO PUDO MIRAR. Un gate que no corrió no puede parecer un gate
# que pasó. Lo destapó el propio process-judge: 4 de las 7 entradas que habia en
# la cola no tenian archivo (f-e416ab5e).
RC=0
echo ""; echo "═══ TRAYECTORIA ($SID) ═══"
if [ -n "$SID" ] && [ -f "$TRAJ_DIR/$SID.jsonl" ]; then
  cat "$TRAJ_DIR/$SID.jsonl"
elif [ -n "$SID" ]; then
  echo "⚠️  NO HAY TRAYECTORIA para «${SID}» — este contexto está INCOMPLETO."
  echo "   Lo que sigue es solo el diff. Si juzgas con esto, di explícitamente"
  echo "   que juzgaste el RESULTADO y no el PROCESO: no tienes con qué."
  echo "   Trayectorias disponibles:"
  ls -1 "$TRAJ_DIR" 2>/dev/null | sed 's/^/     /' || echo "     (ninguna)"
  RC=3
else
  echo "(sin session_id — modo listado; trayectorias disponibles:)"
  ls -1 "$TRAJ_DIR" 2>/dev/null | sed 's/^/  /' || echo "  (ninguna)"
fi

echo ""; echo "═══ DIFF (staged) ═══"
git diff --cached --stat 2>/dev/null || true
echo ""; echo "═══ DIFF (último commit) ═══"
git show --stat HEAD 2>/dev/null | head -40 || true

exit "$RC"

#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# session-end.sh — hook SessionEnd
# ════════════════════════════════════════════════════════════════════
# El process-judge existía desde el día 1 y NUNCA corría: nada lo invocaba ni
# recordaba invocarlo. Un juez al que nadie llama es un juez que no existe
# (la lección G5 aplicada a agentes en vez de gates).
#
# Esto NO lo invoca (lanzar un agente desde un hook = coste no consentido,
# PRD 0002 §8). Hace lo mecánico: si la sesión tocó código y no hubo juicio,
# la ENCOLA. inject-context muestra la cola cada turno; el veredicto real del
# juez (vía capture-review-verdict) la vacía. Visibilidad mecánica,
# invocación humana.
#
# Observe-only: jamás bloquea (SessionEnd ignora exit codes de todas formas).
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=lib/io.sh
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"
cd "$PROJECT_ROOT" || exit 0

hook_read_input

# ── El juicio de proceso es cosa de EQUIPO (preset full) ────────────
# En `lite` (una persona) la cola era ruido perpetuo: "N sesiones pendientes"
# que nadie iba a juzgar jamás, y una señal que siempre grita se deja de leer.
# El judge sigue disponible manualmente en lite; solo no se encola solo.
[ "$(hook_preset)" = "lite" ] && exit 0

SID="$(hook_session_id)"
[ -z "$SID" ] || [ "$SID" = "unknown" ] && SID="s-$(date +%s)"

QUEUE="$(hook_state_dir)/judge-queue.txt"

# ── ¿Tocó código esta sesión? ───────────────────────────────────────
# Señal: árbol sucio (fuera de .agents/state) o commits nuevos vs el inicio.
# Si la sesión fue solo lectura/conversación, no hay nada que juzgar.
# ⚠️ LA SEÑAL ERA "EL ÁRBOL QUEDÓ SUCIO", Y ESO PREMIABA DEJAR BASURA.
# La sesión que cierra BIEN —commitea su trabajo y deja el árbol limpio— salía
# por este `exit 0` y NUNCA se encolaba. El juez acababa auditando justo a
# quien no había trabajado: medido en un proyecto real, la cola apuntaba a una
# sesión con 7 tool-calls y CERO ediciones (leer el backlog y dos builds),
# mientras las dos sesiones que escribieron el adapter y el composition root
# no entraron. Una métrica de calidad sobre la muestra equivocada es peor que
# ninguna: da confianza sin cubrir nada.
#
# Ahora la señal primaria son los COMMITS producidos por la sesión, usando el
# HEAD de arranque que deja `session-start`. El árbol sucio sigue contando
# —trabajo a medias también merece juicio— pero ya no es la condición.
START_HEAD="$(grep -E '^head:' "$(hook_state_dir)/session-head.txt" 2>/dev/null | head -1 | sed -E 's/^head:[[:space:]]*//')"
COMMITS=0; RANGE=""
if [ -n "$START_HEAD" ] && git cat-file -e "${START_HEAD}^{commit}" 2>/dev/null; then
  COMMITS="$(git rev-list --count "${START_HEAD}..HEAD" 2>/dev/null || echo 0)"
  [ "${COMMITS:-0}" -gt 0 ] && RANGE="$(git rev-parse --short "$START_HEAD" 2>/dev/null)..$(git rev-parse --short HEAD 2>/dev/null)"
fi
DIRTY="$(git status --porcelain 2>/dev/null | grep -vE '^\?\? \.agents/state/' | wc -l | tr -d ' ')"
[ "${COMMITS:-0}" = "0" ] && [ "${DIRTY:-0}" = "0" ] && exit 0

# ── ¿Ya la juzgaron? ────────────────────────────────────────────────
# Match EXACTO sobre el campo `session:` que escribe capture-review-verdict.
# La primera versión grepeaba el SID "a pelo" contra un marker que nunca lo
# contenía — código muerto que solo pasaba el test porque el fixture metía el
# SID en el SCOPE (hallazgo del reviewer). Dedup best-effort: si falla, la
# cola tolera entradas de más (PRD 0002 §7); nunca bloquea nada.
JUDGE_MARKER="$(hook_state_dir)/markers/process-judge_run.txt"
# -F además de -x: sin él, el SID se interpreta como regex BRE y un `.` en el
# id actúa de comodín (reproducido por el reviewer: "s-a.c" matcheaba
# "s-aXc"). -x da match de línea completa; -F, match LITERAL. Los datos nunca
# son patrones.
if [ -f "$JUDGE_MARKER" ] && grep -qxF "session: ${SID}" "$JUDGE_MARKER" 2>/dev/null; then
  exit 0
fi

# ── Encolar (una línea por sesión, sin duplicar) ────────────────────
mkdir -p "$(dirname "$QUEUE")"
grep -q "· ${SID} ·" "$QUEUE" 2>/dev/null && exit 0
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
# El RANGO va en la línea a propósito: es el insumo que el juez debe mirar
# (`git diff <rango>`), y es mucho mejor que un id de sesión cuya trayectoria
# tiene huecos — en el caso real, 13 minutos sin cubrir, justo la ventana de
# los sub-agentes `reviewer` y los dos commits.
printf '%s · %s · %s · commits=%s%s · %s sin commitear\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SID" "$BRANCH" "${COMMITS:-0}" \
  "${RANGE:+ (}${RANGE}${RANGE:+)}" "$DIRTY" >> "$QUEUE"
exit 0

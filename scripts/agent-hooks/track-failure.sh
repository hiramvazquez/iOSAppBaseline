#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# track-failure.sh — hook PostToolUse (matcher Bash|Edit|Write|MultiEdit)
# ════════════════════════════════════════════════════════════════════
# Detecta al agente ATASCADO. Un agente que falla el mismo comando 4 veces
# seguidas no está progresando: está reintentando variaciones de una hipótesis
# equivocada, quemando contexto y consolidando el error en el historial.
#
# NOTA DE HISTORIA: esto vivió registrado en un evento "PostToolUseFailure"
# que NO EXISTE en Claude Code — jamás disparó (gate mudo). Ahora corre en
# PostToolUse (que dispara siempre) y deriva éxito/fallo del payload real.
# Ventaja inesperada del cambio: ahora también VE los éxitos, así que la racha
# se resetea sola cuando el agente desbloquea. Antes solo veía fallos y una
# racha vieja podía disparar un falso "atasco" días después.
# Fijado por tools/tests/test_hook_events.sh.
#
# No bloquea: informa. Pero informar en el momento correcto es la mitad
# del trabajo.
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=lib/io.sh
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"
cd "$PROJECT_ROOT" || exit 0

hook_read_input
STATE="$(hook_state_dir)"; mkdir -p "$STATE"
COUNTER="$STATE/failure-streak.txt"

TOOL="$(hook_tool)"
CMD="$(hook_command)"

# ── ¿La tool FALLÓ? Derivado del payload de PostToolUse ─────────────
# El shape del tool_response varía por tool y versión; probamos las señales
# conocidas en orden y, si ninguna aparece, asumimos ÉXITO (fail-open: un
# hook de aviso no debe inventar atascos).
FAILED=0
if command -v jq >/dev/null 2>&1; then
  _resp_success="$(_hook_jq '.tool_response.success // empty')"
  _resp_iserr="$(_hook_jq '.tool_response.is_error // empty')"
  _resp_exit="$(_hook_jq '.tool_response.exit_code // .tool_response.exitCode // empty')"
  if [ "$_resp_success" = "false" ] || [ "$_resp_iserr" = "true" ]; then
    FAILED=1
  elif [ -n "$_resp_exit" ] && [ "$_resp_exit" != "0" ] 2>/dev/null; then
    FAILED=1
  fi
fi

# Firma del fallo: la herramienta + los 2 primeros tokens del comando.
# Suficiente para agrupar reintentos de "lo mismo" sin ser sensible a flags.
SIG="$TOOL:$(printf '%s' "$CMD" | awk '{print $1, $2}')"

if [ "$FAILED" -eq 0 ]; then
  # Éxito → la racha muere. Solo tocamos disco si había racha (coste ~0).
  [ -f "$COUNTER" ] && rm -f "$COUNTER" 2>/dev/null
  hook_allow
fi

PREV_SIG=""; PREV_N=0
if [ -f "$COUNTER" ]; then
  PREV_SIG="$(head -1 "$COUNTER" 2>/dev/null)"
  PREV_N="$(sed -n 2p "$COUNTER" 2>/dev/null)"; : "${PREV_N:=0}"
fi

if [ "$SIG" = "$PREV_SIG" ]; then N=$((PREV_N + 1)); else N=1; fi
printf '%s\n%s\n' "$SIG" "$N" > "$COUNTER"

# Umbral: 3 es ruido normal de exploración; 4 ya es un bucle.
[ "$N" -lt 4 ] && hook_allow

# Registra el atasco para el process-judge (evidencia de trayectoria).
printf '[%s] atasco: %s × %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SIG" "$N" \
  >> "$STATE/stuck-log.txt" 2>/dev/null || true

hook_context "PostToolUse" "🔁 ATASCO DETECTADO: \`$SIG\` ha fallado $N veces seguidas.

Reintentar variaciones de la misma hipótesis es el modo de fallo más caro que existe:
quema contexto y consolida el error. Para y haz UNA de estas, en este orden:

1. **Lee el error completo otra vez.** ¿Estás arreglando el síntoma o la causa?
2. **Verifica tus supuestos contra el código/la DB**, no contra tu memoria
   (AGENTS.md §14.5). El supuesto equivocado suele ser el que ni cuestionaste.
3. **Si sigues sin saber: PREGUNTA al owner.** Open Question > suposición
   silenciosa (AGENTS.md §1.4). Preguntar ahora cuesta un mensaje; adivinar
   mal cuesta el resto de la sesión.

No intentes un cuarto enfoque sin haber hecho 1 y 2."

#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# run-hook.sh — un hook ROTO no puede dejar al agente sin herramientas
# ════════════════════════════════════════════════════════════════════
# Vivido en un proyecto real, y es el peor fallo que ha tenido este harness:
# un `upgrade.sh` dejó marcadores de conflicto dentro de `reviewer-gate.sh`,
# que es el hook `PreToolUse` de Bash. El archivo dejó de parsear, bash salió
# con error, y el cliente leyó ese error como DENY. A partir de ahí:
#
#     PreToolUse:Bash hook error: reviewer-gate.sh: line 158:
#     syntax error near unexpected token `<<<'
#
# …toda ejecución de Bash quedó bloqueada. El agente no podía listar los
# conflictos, ni correr `git status`, ni diagnosticar el problema que el propio
# upgrade acababa de crear. Salió solo porque tenía la tool `Edit`, que va por
# otro hook; un cliente que edite vía Bash, o un run headless, se queda muerto
# ahí — y el mensaje no dice ni la causa ni la salida.
#
# La raíz es que el modo de FALLO del hook colisiona con su señal de DENY:
# ambos son "exit distinto de 0". `AGENTS.md §14.3` ya decide qué hacer en ese
# empate —"un bug del hook nunca debe trabar al dev; un gate que no corrió
# nunca debe parecer un gate que pasó"— pero esa regla estaba implementada
# para los DETECTORES y no para los HOOKS que los invocan. Aquí lo está.
#
#   bash scripts/agent-hooks/run-hook.sh <hook.sh> [args…]
#
# Contrato: si el hook (o una de sus libs) no parsea, se AVISA por stderr con
# todas las letras y se sale 0 — el agente sigue trabajando SIN ese gate, que
# es infinitamente mejor que un agente que no puede ni mirar por qué. Si el
# hook parsea, se le cede el proceso con `exec` y su exit code manda: el gate
# funciona exactamente igual que antes.
set -uo pipefail

# PROJECT_ROOT derivado de $0, no del cwd: un hook lo invoca el CLIENTE desde
# donde le da la gana, y una ruta relativa aquí haría que este lanzador no
# encontrara ni el hook ni sus libs — y entonces "no parsea" y "no lo encuentro"
# se confundirían, que es el mismo colapso de significados que este archivo
# existe para deshacer. Lo fija test_shell_hygiene.sh::test_los_hooks_no_dependen_del_cwd,
# que me lo cazó en la primera pasada.
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)"
[ -n "$PROJECT_ROOT" ] || PROJECT_ROOT="$(pwd)"

HOOK="${1:-}"
[ -n "$HOOK" ] || { echo "uso: run-hook.sh <hook.sh> [args…]" >&2; exit 0; }
shift
case "$HOOK" in /*) : ;; *) [ -f "$HOOK" ] || HOOK="$PROJECT_ROOT/$HOOK" ;; esac

_avisar_y_pasar() {
  {
    echo "⚠️  HARNESS DEGRADADO: $1"
    echo "   Ese gate NO se está aplicando ahora mismo. Te dejo trabajar a"
    echo "   propósito (AGENTS.md §14.3: un hook roto no puede trabar al dev,"
    echo "   y menos impedirte diagnosticarlo), pero estás sin red."
    echo "   Causa típica: un upgrade dejó marcadores de conflicto sin resolver."
    echo "   Compruébalo:  bash -n $HOOK   ·   grep -rn '<<<<<<<' scripts/agent-hooks/"
  } >&2
  exit 0
}

[ -f "$HOOK" ] || _avisar_y_pasar "$HOOK no existe."

# El propio hook…
if ! _err="$(bash -n "$HOOK" 2>&1)"; then
  _avisar_y_pasar "$HOOK no parsea — $(printf '%s' "$_err" | head -1)"
fi

# …y las libs que va a cargar. `bash -n` NO sigue los `source`, así que una lib
# con conflictos pasaría este filtro y reventaría en runtime — el mismo brick
# por otra puerta. Son cuatro archivos: comprobarlos cuesta milisegundos.
_LIBDIR="$(dirname "$HOOK")/lib"
[ -d "$_LIBDIR" ] || _LIBDIR="$PROJECT_ROOT/scripts/agent-hooks/lib"
if [ -d "$_LIBDIR" ]; then
  for _lib in "$_LIBDIR"/*.sh; do
    [ -f "$_lib" ] || continue
    if ! _err="$(bash -n "$_lib" 2>&1)"; then
      _avisar_y_pasar "la librería $_lib no parsea — $(printf '%s' "$_err" | head -1)"
    fi
  done
fi

exec bash "$HOOK" "$@"

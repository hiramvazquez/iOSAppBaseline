#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# gate-adapter.sh — traduce el contrato de los gates compartidos al
#                   contrato de RESPUESTA de cada cliente
# ════════════════════════════════════════════════════════════════════
# Los gates de scripts/agent-hooks/ hablan UN solo contrato:
#   exit 0 = permitir · exit 2 + stderr = bloquear con razón
# Claude Code entiende ese contrato nativamente. Cursor y Codex esperan
# en cambio un JSON por stdout. Este adapter ejecuta el gate y traduce:
#
#   cursor →  {"permission":"deny","userMessage":…,"agentMessage":…}
#   codex  →  {"permissionDecision":"deny","permissionDecisionReason":…}
#
# Uso (desde .cursor/hooks.json / .codex/hooks.json):
#   bash scripts/agent-hooks/adapters/gate-adapter.sh <cursor|codex> <gate-rel>
#
# La lógica vive UNA vez en el gate; cada cliente solo aporta su sintaxis
# de respuesta — que es exactamente la promesa del harness.
#
# ⚠️ VALIDAR EN VIVO: los shapes de Cursor y Codex están tomados de su doc
# (ago-2026) y aún no se han visto disparar en este repo. `tools/validate-harness.sh`
# lista el checklist. Un wrapper sin validar es un gate PRESUNTO, no un gate.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CLIENT="${1:-}"; GATE="${2:-}"
[ -z "$CLIENT" ] || [ -z "$GATE" ] || [ ! -f "$ROOT/$GATE" ] && exit 0  # fail-open

INPUT="$(cat 2>/dev/null || true)"
ERR_FILE="$(mktemp 2>/dev/null || echo /tmp/.gate_adapter_$$)"
# Vía run-hook: si el gate (o una lib) no parsea, run-hook avisa y sale 0, y
# Cursor/Codex reciben "allow" en vez de un deny fantasma. Sin esto, un hook
# con marcadores de conflicto dejaba al agente sin poder ejecutar NADA —
# ni siquiera el `git status` con el que diagnosticarlo (§14.3).
_RUNNER="$ROOT/scripts/agent-hooks/run-hook.sh"
if [ -f "$_RUNNER" ]; then
  OUT="$(printf '%s' "$INPUT" | bash "$_RUNNER" "$ROOT/$GATE" 2>"$ERR_FILE")"
else
  OUT="$(printf '%s' "$INPUT" | bash "$ROOT/$GATE" 2>"$ERR_FILE")"
fi
RC=$?
REASON="$(cat "$ERR_FILE" 2>/dev/null || true)"; rm -f "$ERR_FILE" 2>/dev/null

if [ "$RC" = "2" ]; then
  if command -v jq >/dev/null 2>&1; then
    case "$CLIENT" in
      cursor)
        jq -nc --arg m "$REASON" \
          '{permission:"deny", userMessage:"Gate del harness: acción bloqueada", agentMessage:$m}' ;;
      codex)
        jq -nc --arg m "$REASON" \
          '{permissionDecision:"deny", permissionDecisionReason:$m}' ;;
      *)
        printf '%s\n' "$REASON" >&2; exit 2 ;;
    esac
  else
    # Sin jq no podemos emitir JSON seguro → degradamos al contrato universal.
    printf '%s\n' "$REASON" >&2; exit 2
  fi
  exit 0
fi

# Permitir. El stdout informativo del gate va a stderr (log del cliente);
# stdout queda limpio para el JSON de decisión.
[ -n "$OUT" ] && printf '%s\n' "$OUT" >&2
[ -n "$REASON" ] && printf '%s\n' "$REASON" >&2
case "$CLIENT" in
  cursor) printf '{"permission":"allow"}\n' ;;
  codex)  printf '{}\n' ;;
esac
exit 0

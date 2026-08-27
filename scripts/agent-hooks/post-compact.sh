#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# post-compact.sh — hook SessionStart con matcher `compact`
# ════════════════════════════════════════════════════════════════════
# NOTA DE HISTORIA: esto vivió registrado en un evento "PostCompact" que NO
# EXISTE en Claude Code — el hook jamás disparó y nadie lo notó (gate mudo).
# El patrón correcto es SessionStart con source=compact, que sí dispara tras
# cada compactación. Fijado por tools/tests/test_hook_events.sh.
#
# Claude Code re-inyecta solo el CLAUDE.md raíz tras compactar; lo que se
# pierde es el resto: estado vivo, findings, fase del proyecto. Eso es esto.
# Causa silenciosa nº1 de degradación en sesiones largas: tras compactar,
# el agente conserva un RESUMEN de la conversación pero pierde el detalle de
# las reglas. Sigue "recordando" que hay reglas, ya no cuáles. Y como no sabe
# que las perdió, no las relee — simplemente empieza a improvisar.
#
# Este hook reinyecta el mínimo irrenunciable justo después de compactar:
# las reglas duras, la fase actual y los findings abiertos. Es barato
# (unos cientos de tokens) y ocurre pocas veces por sesión.
#
# Deliberadamente NO reinyecta AGENTS.md entero: eso volvería a llenar lo
# que se acaba de vaciar. Solo el digest de lo irrompible.
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=lib/io.sh
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"
cd "$PROJECT_ROOT" || exit 0

hook_read_input

CTX="🔄 Contexto compactado — reinyectando lo irrenunciable (no lo vuelvas a perder):

## Reglas duras (AGENTS.md — la fuente canónica sigue ahí si necesitas el detalle)
1. **Scope = lo explícitamente pedido.** Nada de refactorizar lo de al lado (§8).
2. **TDD**: ninguna lógica nueva sin un test que FALLE primero (§5).
3. **Cero secretos** en código, logs o telemetría (§6).
4. **El dominio no importa UI ni infraestructura** (§3) — lo verifica \`tools/check-layers.sh\`.
5. **Open Question > suposición silenciosa** (§1.4). Si no sabes, pregunta.
6. Jamás \`--no-verify\`, \`--amend\` ni \`push\` sin orden explícita del owner (§7).
7. **El que toca, cierra**: findings preexistentes se arreglan o se registran (§10).
"

# ── Fase actual del proyecto ────────────────────────────────────────
MAP="docs/process/current_execution_map.md"
if [ -f "$MAP" ]; then
  EXTRACT="$(grep -E '^- (Fase|En curso|Último ship):' "$MAP" 2>/dev/null | head -5 || true)"
  [ -n "$EXTRACT" ] && CTX="$CTX
## Dónde estamos ($MAP)
$EXTRACT
"
fi

# ── Findings abiertos (lo que NO se puede volver a olvidar) ─────────
LEDGER="tools/findings/ledger.jsonl"
if [ -f "$LEDGER" ]; then
  # Tolerante a ambos espaciados JSON (lección L-json-espacios).
  OPEN="$(grep -E '"status": ?"open"' "$LEDGER" 2>/dev/null \
          | sed -E 's/.*"id": ?"([^"]+)".*"title": ?"([^"]+)".*"area": ?"([^"]+)".*/  - [\1] \2 (\3)/' \
          | head -8 || true)"
  N="$(grep -cE '"status": ?"open"' "$LEDGER" 2>/dev/null || true)"; : "${N:=0}"
  [ -n "$OPEN" ] && CTX="$CTX
## Findings ABIERTOS ($N) — si tocas su área, los cierras o los actualizas
$OPEN
"
fi

# ── Tarea en curso ──────────────────────────────────────────────────
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
DIRTY="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
CTX="$CTX
## Estado del árbol
branch=$BRANCH · archivos modificados=$DIRTY · preset=$(hook_preset)

Antes de seguir editando: si no recuerdas la skill del área que estás tocando
(AGENTS.md §11), reléela. El hook \`skill-reminder\` te la exigirá igualmente."

hook_context "SessionStart" "$CTX"

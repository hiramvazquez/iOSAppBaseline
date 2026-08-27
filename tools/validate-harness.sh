#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# validate-harness.sh — ¿los gates EXISTEN de verdad, o solo lo parecen?
# ════════════════════════════════════════════════════════════════════
# La lección más cara de este harness: sus peores fallos no fueron gates que
# bloquearon mal, sino gates que NUNCA DISPARARON — hooks sobre eventos
# inexistentes, patrones de permisos que no matchean, wrappers con el esquema
# equivocado. Todos fallan hacia el SILENCIO: un gate mudo y uno sano se ven
# igual desde fuera... hasta que corres esto.
#
# Regla operativa: NINGÚN gate cuenta como existente hasta que lo has visto
# bloquear algo una vez. Este script hace (A) todo lo verificable en estático,
# y (B) imprime el checklist EN VIVO de lo que solo una sesión real prueba.
#
#   bash tools/validate-harness.sh            # checks estáticos + checklist
#   bash tools/validate-harness.sh --selftest # además: cada detector DEMUESTRA
#                                             # que ve, contra un fixture mínimo
#   bash tools/validate-harness.sh --full     # estático + selftest + suite entera
#
# Salida: exit 1 si algún check falla. Correr tras CADA update de
# Claude Code / Cursor / Codex: sus contratos de hooks versionan rápido.
#
# ── Este archivo es el ORQUESTADOR ──────────────────────────────────
# Los checks viven en `tools/lib/validate-*.sh`, uno por CONTRATO, y se
# sourcean aquí. Aquí quedan solo: los helpers (ok/bad/warn/FAIL), el orden en
# que se pregunta y el veredicto. Si buscas un check concreto:
#
#   validate-hooks.sh     §1-§4  configs válidos, eventos que existen, scripts
#                                referenciados que parsean, symlinks
#   validate-matrix.sh    §5     skill-matrix.conf y sus referencias
#   validate-levels.sh    §6-§9  dependencias y probes, suite, compilador
#                                cableado, Anillo 3, bits de ejecución
#   validate-selftest.sh  --selftest / --full: cada detector demuestra que VE
#   validate-checklist.sh el checklist en vivo (lo no verificable en estático)
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

VH_MODE="${1:-}"

FAIL=0
ok()   { echo "  ✅ $1"; }
bad()  { echo "  ❌ $1"; FAIL=1; }
warn() { echo "  ⚠️  $1"; }

# ── Las libs, o exit 3 EN VOZ ALTA ──────────────────────────────────
# El contrato §14.3: `3` = el detector no pudo mirar. Sin este guard, un árbol
# con el orquestador nuevo y sin las libs (un `git checkout` a mano de UN solo
# archivo, un sync a medias) sourcearía la nada, fallaría cada llamada con
# "command not found" en stderr y **saldría 0 con FAIL=0** — cero checks
# corridos y un ✅ final. Es exactamente el gate mudo que este script existe
# para cazar, cometido por este script. Se resuelve por ruta del PROPIO archivo
# y no por cwd: la lib tiene que aparecer o no aparecer, nunca "según desde
# dónde me invocaron".
VH_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib"
for _vh_lib in validate-hooks validate-matrix validate-levels validate-selftest validate-checklist; do
  [ -f "$VH_LIB/$_vh_lib.sh" ] && continue
  echo "❌ validate-harness: NO PUDE MIRAR — falta tools/lib/$_vh_lib.sh"
  echo "   El orquestador está aquí y sus checks no. Un árbol así no está"
  echo "   'a medias': está SIN VERIFICAR, y un exit 0 lo haría parecer sano."
  echo "   Remedio:  git checkout <ref-del-template> -- tools/validate-harness.sh tools/lib"
  exit 3
done
# shellcheck source=tools/lib/validate-hooks.sh
. "$VH_LIB/validate-hooks.sh"
# shellcheck source=tools/lib/validate-matrix.sh
. "$VH_LIB/validate-matrix.sh"
# shellcheck source=tools/lib/validate-levels.sh
. "$VH_LIB/validate-levels.sh"
# shellcheck source=tools/lib/validate-selftest.sh
. "$VH_LIB/validate-selftest.sh"
# shellcheck source=tools/lib/validate-checklist.sh
. "$VH_LIB/validate-checklist.sh"

echo "━━━ validate-harness: checks estáticos ━━━"

vh_check_hooks
vh_check_matrix
vh_check_levels

case "$VH_MODE" in --selftest|--full) selftest ;; esac

# ── Veredicto estático + checklist en vivo ──────────────────────────
vh_print_checklist

echo ""
if [ "$FAIL" = "0" ]; then
  echo "✅ validate-harness: checks estáticos OK. Lo de arriba ↑ solo lo prueba una sesión real."
  exit 0
fi
echo "❌ validate-harness: hay checks estáticos FALLANDO — gates mudos o rotos. Arréglalos antes de confiar."
exit 1

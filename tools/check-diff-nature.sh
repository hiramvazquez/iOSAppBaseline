#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-diff-nature.sh — ¿este diff mezcla naturalezas? (AVISO, no gate)
# ════════════════════════════════════════════════════════════════════
# EL DATO QUE LO JUSTIFICA, medido en el primer proyecto real: un commit de
# adopción de 27 archivos y 5 naturalezas costó TRES reviews de ~150k tokens
# y 17 minutos cada una. Partido por naturaleza: 62k y 4,6 minutos, GREEN a
# la primera. Los tres RED eran correctos y distintos — el problema no era el
# reviewer, era el LOTE.
#
# Y nada en el harness empujaba a partir: el owner tuvo que decirlo a mano.
# Esto lo mecaniza, porque es lo único del flujo que escala mal: el coste de
# una review crece con TODO el diff, no con la parte dudosa.
#
# ⚠️  ES UN AVISO, NUNCA UN BLOQUEO, y la razón es de diseño: "cuántas
# naturalezas caben en un commit" es JUICIO, no una regla objetiva. Hay
# cambios legítimamente transversales (renombrar un símbolo público toca
# producto, tests y docs a la vez) y bloquearlos sería un falso positivo
# permanente — de los que acaban con el gate desactivado (§14.2). Un gate
# bloquea cuando la respuesta correcta es única; aquí no lo es.
#
# Dónde vale de verdad: ANTES de invocar al reviewer (paso 1b del runner).
# Después del commit ya solo sirve de aprendizaje para la próxima.
#
#   bash tools/check-diff-nature.sh            # sobre lo staged
#   bash tools/check-diff-nature.sh --range    # sobre un rango (CI)
#
# Contrato: exit 0 SIEMPRE (es informativo).
# Contrato de stdout:  NATURE_SUMMARY naturalezas=<N> archivos=<M>
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

MODE="${1:---staged}"
UMBRAL="${DIFF_NATURE_UMBRAL:-3}"

if [ "$MODE" = "--range" ]; then
  BASE="${GATES_BASE_REF:-origin/main}"
  CHANGED="$(git diff --name-only "$BASE"...HEAD 2>/dev/null || true)"
else
  CHANGED="$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)"
fi
[ -z "$CHANGED" ] && { echo "NATURE_SUMMARY naturalezas=0 archivos=0"; exit 0; }

# Las naturalezas son las mismas categorías que el harness ya usa para decidir
# qué exige review (check-review-marker) y cómo resolver un conflicto de
# upgrade. Reusarlas no es pereza: si un día divergen, el aviso hablaría de
# una taxonomía que no existe en ningún otro sitio.
_nature() {
  case "$1" in
    tools/tests/*|*Tests.swift|*_test.go|*.test.ts|*.spec.ts|test_*.py)  echo "tests" ;;
    tools/*|scripts/*|ci/*|lefthook.yml|.github/*)                       echo "maquinaria" ;;
    AGENTS.md|CLAUDE.md|GEMINI.md|.agents/skills/*|.claude/*|.cursor/*|.codex/*) echo "meta-doc" ;;
    docs/*|README*|*.md)                                                 echo "docs" ;;
    backlog/*)                                                           echo "backlog" ;;
    *.pbxproj|*.gradle|*.xcconfig|package.json|Package.swift|*.lock|*.toml|*.yaml|*.yml|*.json|*.conf) echo "config/build" ;;
    *)                                                                   echo "producto" ;;
  esac
}

NATS=""; N=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  N=$((N+1))
  NATS="${NATS}$(_nature "$f")"$'\n'
done <<< "$CHANGED"

UNIQ="$(printf '%s' "$NATS" | grep -v '^$' | sort -u)"
COUNT="$(printf '%s' "$UNIQ" | grep -c . || echo 0)"
echo "NATURE_SUMMARY naturalezas=$COUNT archivos=$N"

[ "${COUNT:-0}" -lt "$UMBRAL" ] && exit 0

{
  echo "⚠️  Este diff mezcla ${COUNT} naturalezas en ${N} archivo(s):"
  while IFS= read -r nat; do
    [ -z "$nat" ] && continue
    printf '     · %-14s' "$nat"
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      [ "$(_nature "$f")" = "$nat" ] && printf '%s ' "$(basename "$f")"
    done <<< "$CHANGED"
    echo ""
  done <<< "$UNIQ"
  echo ""
  echo "   El coste de una review crece con TODO el diff, no con la parte dudosa."
  echo "   Medido aquí: 27 archivos y 5 naturalezas = 3 vueltas de ~150k tokens y"
  echo "   17 min cada una. Partido por naturaleza: 62k, 4,6 min y GREEN a la"
  echo "   primera — y los tres RED del lote grande eran correctos y distintos."
  echo "   Si estas naturalezas no dependen entre sí, commitea y revisa por"
  echo "   separado. Si el cambio es legítimamente transversal, ignora esto:"
  echo "   es un aviso, no un gate (partir o no es juicio, no una regla)."
} >&2
exit 0

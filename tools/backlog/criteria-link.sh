#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# criteria-link.sh — cada criterio de aceptación cita el test que lo verifica
# ════════════════════════════════════════════════════════════════════
# Mismo mecanismo que `lesson-detector-link.sh`, aplicado un nivel más arriba.
# Allí: toda lección lleva su `Detector:` o es prosa. Aquí: todo criterio de
# aceptación lleva el test que lo fija, o es decoración.
#
# El caso real: el criterio 6 de una historia ("la lista NO construye su
# destino") se dio por verificado con un `grep` a mano pegado en el informe del
# run. Se cumplía ese día — lo comprobé — y nada impedía la regresión al día
# siguiente. Los criterios NEGATIVOS son los que más se quedan así: afirman lo
# que el código NO hace, y un grep parece suficiente porque encuentra cero.
#
# «Verificado» no es una frase en un informe: es un test que falla si dejas de
# cumplirlo. Un criterio sin test es una intención, y las intenciones no
# sobreviven al siguiente refactor.
#
#   bash tools/backlog/criteria-link.sh backlog/0007-algo.md
#
# Formato esperado en la historia (lo rellena el agente antes de cerrar):
#
#   ## Verificación de criterios
#   1. Tests/FooTests.swift::testCargaOk
#   2. Tests/FooTests.swift::testErrorDeRed
#   3. n/a-manual — es criterio visual, verificado en captura adjunta
#
# Contrato de stdout:  CRITERIA_SUMMARY total=<N> sin_test=<M>
# Exit: 0 todos cubiertos · 1 falta cobertura · 3 no pude mirar
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

STORY="${1:-}"
[ -n "$STORY" ] && [ -f "$STORY" ] || {
  echo "uso: bash tools/backlog/criteria-link.sh <historia.md>" >&2
  echo "CRITERIA_SUMMARY total=0 sin_test=0"; exit 3; }

# Los criterios son los items numerados bajo "## Criterios de aceptación".
# Se cuentan hasta el siguiente encabezado — ni una línea más, o cualquier
# lista posterior inflaría el total y el gate pediría cobertura de la nada.
_items_de() { # _items_de <encabezado>
  awk -v h="$1" '
    index($0, h) == 1 { dentro = 1; next }
    dentro && /^#/    { dentro = 0 }
    dentro && /^[[:space:]]*[0-9]+\./ { print }
  ' "$STORY"
}

CRITERIOS="$(_items_de '## Criterios de aceptación')"
TOTAL="$(printf '%s' "$CRITERIOS" | grep -c . || true)"
[ "${TOTAL:-0}" -eq 0 ] && { echo "CRITERIA_SUMMARY total=0 sin_test=0"; exit 0; }

VERIF="$(_items_de '## Verificación de criterios')"

SIN=""
i=0
while [ "$i" -lt "${TOTAL:-0}" ]; do
  i=$((i+1))
  linea="$(printf '%s\n' "$VERIF" | awk -v n="$i" '$0 ~ "^[[:space:]]*"n"\\." {print; exit}')"
  valor="$(printf '%s' "$linea" | sed -E 's/^[[:space:]]*[0-9]+\.[[:space:]]*//; s/[[:space:]]*$//')"
  case "$valor" in
    '') SIN="${SIN}  · criterio ${i}: sin línea en '## Verificación de criterios'"$'\n'; continue ;;
    'n/a-manual'*) continue ;;   # excepción legítima, y explícita
    'TODO'*|'pendiente'*|'manual'|'—'|'-')
      SIN="${SIN}  · criterio ${i}: '${valor}' no es un test"$'\n'; continue ;;
  esac
  # Si cita un archivo del repo, tiene que EXISTIR. Un test fantasma da el
  # mismo verde que uno real — la lección de los detectores citados que ya no
  # existían, cometida otra vez un nivel más arriba.
  archivo="$(printf '%s' "$valor" | grep -oE '[A-Za-z0-9_./-]+\.(swift|kt|ts|tsx|js|py|go|rb|sh)' | head -1 || true)"
  archivo="${archivo%%::*}"
  if [ -n "$archivo" ] && [ ! -e "$archivo" ]; then
    SIN="${SIN}  · criterio ${i}: cita '${archivo}', que NO existe"$'\n'
  fi
done

M="$(printf '%s' "$SIN" | grep -c . || true)"
echo "CRITERIA_SUMMARY total=${TOTAL:-0} sin_test=${M:-0}"
[ "${M:-0}" -eq 0 ] && exit 0

{
  echo "❌ criterios sin test que los fije, en ${STORY}:"
  printf '%s' "$SIN"
  echo ""
  echo "   Añade a la historia una sección así, una línea por criterio:"
  echo ""
  echo "     ## Verificación de criterios"
  echo "     1. <ruta/al/test>::<nombre del test>"
  echo "     2. n/a-manual — <por qué este criterio no es mecanizable>"
  echo ""
  echo "   «Verificado» no es una frase en el informe del run: es un test que falla"
  echo "   si dejas de cumplirlo. Ojo especialmente a los criterios NEGATIVOS ('X NO"
  echo "   ocurre'): un grep que encuentra cero parece suficiente y no impide nada."
} >&2
exit 1

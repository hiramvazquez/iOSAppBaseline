#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# secret-scan.sh — wrapper portable sobre gitleaks (Anillo 1 + Anillo 3)
# ════════════════════════════════════════════════════════════════════
# Modos:
#   --staged   solo lo staged (pre-commit, sub-segundo) ← default del hook
#   --range    commits del push actual (pre-push)
#   --history  TODO el historial (nocturno / adopción inicial)
#   --all      árbol de trabajo completo
#
# Usa .gitleaks.toml (config + allowlist) y .gitleaks-baseline.json si existe.
# Si gitleaks no está instalado: avisa cómo instalarlo y NO bloquea (failure-open
# en local; en CI deberías hacerlo obligatorio — ver ci/run-gates.sh).
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

MODE="${1:---staged}"

if ! command -v gitleaks >/dev/null 2>&1; then
  cat >&2 <<'EOF'
⚠️  gitleaks no está instalado — secret-scan OMITIDO en local.
   Instálalo:  brew install gitleaks   |   https://github.com/gitleaks/gitleaks
   (En CI el scan SÍ es obligatorio; ver ci/run-gates.sh.)
EOF
  exit 0
fi

BASE=""; [ -f .gitleaks-baseline.json ] && BASE="--baseline-path .gitleaks-baseline.json"

# ════════════════════════════════════════════════════════════════════
# `--range`: el fallback era un FAIL-OPEN, y del peor tipo
# ════════════════════════════════════════════════════════════════════
# La versión anterior era:
#
#   gitleaks git … --log-opts="${RANGE:-@{push}..HEAD}" 2>/dev/null \
#     || gitleaks git --staged …
#
# El `||` no distingue "el rango no se pudo resolver" de "gitleaks ENCONTRÓ un
# secreto" — las dos cosas son exit != 0. Así que ante un hallazgo REAL en el
# rango, el script se iba al fallback, escaneaba el índice (vacío en CI), salía
# 0, y el gate daba verde sobre una fuga. El `2>/dev/null` remataba la jugada
# borrando el motivo. Es exactamente el patrón que este harness persigue —
# la operación falla y reporta éxito— cometido dentro del gate de secretos.
#
# Ahora el rango se RESUELVE y se VALIDA antes de escanear, y si no se puede,
# se sale con 3: "no pude mirar" (§14.3), que en local avisa y en CI bloquea.
# Nunca se cae a escanear otra cosa.
#
# ÚLTIMO recurso, y no es un fallback laxo: `HEAD` a secas. Es el caso del
# PRIMER push de un repo —no hay upstream contra el que comparar y `@{push}`
# no existe— y ahí lo que este push trae es TODA su historia. Escanear `HEAD`
# es MÁS estricto que cualquier rango, no menos: cubre cada commit alcanzable
# desde la punta. Y no arrastra historia ajena: si el repo tiene un remote
# `template` con historia no relacionada (adopción por copia), esos commits no
# son ancestros de HEAD y quedan fuera — que es lo correcto, no son suyos.
# Sin esto, el primer push de todo adoptante moría con exit 3 y la única
# salida era un override o un RANGE a mano contra una ref que aún no existe.
_resolver_rango() {
  local r
  for r in "${RANGE:-}" "${GATES_BASE_REF:+$GATES_BASE_REF...HEAD}" '@{push}..HEAD'; do
    [ -z "$r" ] && continue
    git rev-list --count "$r" >/dev/null 2>&1 && { printf '%s' "$r"; return 0; }
  done
  # Último recurso SOLO si nadie pidió un rango concreto: es el PRIMER push de
  # un repo (sin upstream, `@{push}` no existe) y lo que ese push trae es toda
  # su historia. `HEAD` es MÁS estricto que cualquier rango —cubre cada commit
  # alcanzable desde la punta— y no arrastra historia ajena: los commits de un
  # remote `template` no son ancestros de HEAD.
  #
  # La condición importa y la fija `test_rango_irresoluble_devuelve_3_no_0`: si
  # ALGUIEN PIDIÓ un rango (RANGE o GATES_BASE_REF) y ese rango no resuelve,
  # caer aquí escanearía algo DISTINTO de lo que se pidió y lo reportaría como
  # limpio — el fail-open exacto que este script existe para no cometer. Ahí se
  # sale con 3. Sin pedido explícito no hay nada que traicionar.
  if [ -z "${RANGE:-}" ] && [ -z "${GATES_BASE_REF:-}" ] \
     && git rev-list --count HEAD >/dev/null 2>&1; then
    printf 'HEAD'; return 0
  fi
  return 1
}

case "$MODE" in
  --staged)  gitleaks git --staged --no-banner --redact $BASE ;;
  --range)
    if ! RANGO="$(_resolver_rango)"; then
      {
        echo "❌ secret-scan: no pude resolver el rango de commits a escanear."
        echo "   Probé: \$RANGE · \$GATES_BASE_REF...HEAD · @{push}..HEAD"
        echo "   Dilo explícito:  RANGE=origin/main...HEAD bash tools/secret-scan.sh --range"
        echo "   NO escaneo otra cosa en su lugar: un scan que no miró lo que"
        echo "   debía no puede parecerse a un scan limpio."
      } >&2
      exit 3
    fi
    gitleaks git --no-banner --redact $BASE --log-opts="$RANGO" ;;
  --history) gitleaks git --no-banner --redact $BASE ;;
  --all)     gitleaks dir . --no-banner --redact $BASE ;;
  *) echo "uso: secret-scan.sh [--staged|--range|--history|--all]" >&2; exit 2 ;;
esac
rc=$?
[ $rc -ne 0 ] && echo "❌ secret-scan: gitleaks encontró posibles secretos (ver arriba). Rota la credencial y quítala del diff." >&2
exit $rc

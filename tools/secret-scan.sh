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
_resolver_rango() {
  local r
  for r in "${RANGE:-}" "${GATES_BASE_REF:+$GATES_BASE_REF...HEAD}" '@{push}..HEAD'; do
    [ -z "$r" ] && continue
    git rev-list --count "$r" >/dev/null 2>&1 && { printf '%s' "$r"; return 0; }
  done
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

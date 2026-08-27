#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# drift-ratchet.sh — el conteo de deuda SOLO baja
# ════════════════════════════════════════════════════════════════════
# tools/drift-ratchet.json es el TECHO committeado (errors + warns de check-drift).
# Ningún commit puede subirlo (lo bloquea reviewer-gate + CI). Subirlo a mano =
# esconder deuda. Para bajarlo cuando mejoras: `--update` y commitea el JSON.
#
#   --check    falla (exit 1) si el conteo actual SUPERA el techo
#   --update   re-escribe el techo con el conteo actual — SOLO si no lo sube.
#
# LA DIRECCIÓN LA IMPONE ESTE SCRIPT (espejo de mutation-score.sh --update):
# un `--update` con el conteo por ENCIMA del techo se rehúsa. Antes no
# comparaba nada — el "trinquete" era una sugerencia: bastaba `--update` para
# legalizar la deuda nueva. Fijado por test_ratchets.sh::test_drift_update_nunca_sube.
# Primera vez (JSON ausente) sí se permite: fijar el techo inicial de un repo
# con deuda preexistente es el caso de adopción legítimo.
#
# Failure-open en parsing: si no puede leer counts, exit 0 (infra rota no traba).
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

JSON="tools/drift-ratchet.json"
MODE="${1:---check}"

read_counts() {
  local out; out="$(bash tools/check-drift.sh 2>/dev/null | grep '^DRIFT_SUMMARY' | tail -1)"
  CUR_E="$(echo "$out" | sed -nE 's/.*errors=([0-9]+).*/\1/p')"
  CUR_W="$(echo "$out" | sed -nE 's/.*warns=([0-9]+).*/\1/p')"
}
ceil() { sed -nE "s/.*\"$1\"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p" "$JSON" | head -1; }

read_counts
[ -z "${CUR_E:-}" ] || [ -z "${CUR_W:-}" ] && { echo "drift-ratchet: no pude leer counts (infra) — paso."; exit 0; }

if [ "$MODE" = "--update" ]; then
  if [ -f "$JSON" ]; then
    MAX_E="$(ceil errors)"; MAX_W="$(ceil warns)"
    : "${MAX_E:=0}"; : "${MAX_W:=0}"
    if [ "$CUR_E" -gt "$MAX_E" ] || [ "$CUR_W" -gt "$MAX_W" ]; then
      echo "❌ drift-ratchet --update REHUSADO: el conteo actual (errors=$CUR_E warns=$CUR_W)"
      echo "   SUPERA el techo (errors=$MAX_E warns=$MAX_W). El techo SOLO baja."
      echo "   Un trinquete que su propio script puede aflojar es una sugerencia."
      echo "   Baja la deuda que introdujiste; si de verdad quieres aceptar deuda nueva,"
      echo "   esa es una decisión del OWNER: edita el JSON a mano fuera del agente"
      echo "   (está en permissions.deny a propósito) y explica el porqué en el commit."
      exit 1
    fi
  fi
  cat > "$JSON" <<EOF
{
  "errors": $CUR_E,
  "warns": $CUR_W,
  "_note": "Techo del drift-ratchet. SOLO baja. Subirlo a mano = esconder deuda."
}
EOF
  echo "✅ techo actualizado: errors=$CUR_E warns=$CUR_W (commitea $JSON)."
  exit 0
fi

MAX_E="$(ceil errors)"; MAX_W="$(ceil warns)"
: "${MAX_E:=0}"; : "${MAX_W:=0}"
if [ "$CUR_E" -gt "$MAX_E" ] || [ "$CUR_W" -gt "$MAX_W" ]; then
  echo "❌ drift-ratchet: el conteo SUBIÓ (actual errors=$CUR_E warns=$CUR_W vs techo errors=$MAX_E warns=$MAX_W)."
  echo "   Baja la deuda que introdujiste, o compénsala en otro lado. El techo solo baja."
  exit 1
fi
echo "✅ drift-ratchet: dentro del techo (errors=$CUR_E/$MAX_E warns=$CUR_W/$MAX_W)."
exit 0

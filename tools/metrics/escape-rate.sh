#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# escape-rate.sh — ¿cuánto puedo confiar en la IA sin revisión humana?
# ════════════════════════════════════════════════════════════════════
# LA métrica del proyecto. "Detectar no basta — CERRAR" mide el destino de un
# hallazgo; esto mide EN QUÉ FASE se detectó, que es lo que responde a la
# pregunta real: ¿puedo bajar la revisión humana este trimestre?
#
# Es el equivalente al *phase containment* de la ingeniería clásica y primo del
# *change failure rate* de DORA (elite: 0-15%). El principio: un defecto cuesta
# ~10× más en cada fase que avanza sin ser detectado. Si tu escape rate baja,
# tus gates están funcionando. Si es plano, estás añadiendo ceremonia, no calidad.
#
# Fases, de más barata a más cara:
#   in-loop   → lo cazó post-edit-verify / linter / tipos       (coste ~0)
#   gate      → lo cazó canon-enforce / drift / capas / semgrep (coste bajo)
#   review    → lo cazó el reviewer o el security-reviewer      (coste medio)
#   ci        → lo cazó el Anillo 3                             (coste alto)
#   prod      → lo cazó un usuario                              (coste máximo)
#
# El dato sale SOLO del ledger: un ID durable cuenta una vez, aunque tenga
# varios source_event_ids o siga presente en la telemetría local. `source`
# identifica la primera fase reconocible. Unknown queda fuera del denominador,
# visible; imputarlo sería fabricar confianza.
#
#   bash tools/metrics/escape-rate.sh                         # últimos 30 días
#   bash tools/metrics/escape-rate.sh --days 90 --json
#   bash tools/metrics/escape-rate.sh --since 2026-01-01 --until 2026-03-31
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1
command -v python3 >/dev/null 2>&1 \
  || { echo "⚠️  escape-rate: python3 ausente — no pude leer JSONL con seguridad." >&2; exit 3; }
exec python3 tools/metrics/metrics-report.py escape-rate "$@"

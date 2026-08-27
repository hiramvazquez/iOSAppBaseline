#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# gate-value.sh — ¿qué gate sigue siendo LOAD-BEARING?
# ════════════════════════════════════════════════════════════════════
# El harness solo sabía CRECER. Cada error añadía un detector, cada lección
# un test, cada incidente un anillo — y no existía ningún momento en el que
# se preguntara si algo de eso ya sobra. Un sistema que solo acumula acaba
# cobrando su peaje (tiempo de gate, tokens de contexto, fricción) por
# defensas que quizá ya no defienden de nada.
#
# La idea es de la ingeniería de harnesses de Anthropic: revisar con
# regularidad si los componentes siguen siendo *load-bearing* a medida que
# los modelos mejoran. Un gate que existía para un error que el modelo ya no
# comete es ceremonia; y la ceremonia no es neutra — es justo lo que hace
# que un equipo termine desactivando el harness entero.
#
# ⚠️  EL MATIZ QUE HACE HONESTO ESTE INFORME, y que hay que leer SIEMPRE:
# un gate con CERO detecciones puede estar en dos estados opuestos, y los
# datos por sí solos no los distinguen:
#     (a) DISUASIÓN — funciona tan bien que nadie intenta ya lo que prohíbe.
#         Es el éxito perfecto y se ve idéntico al fracaso.
#     (b) MUDO o INÚTIL — nunca disparó porque no puede, o porque el riesgo
#         que cubría no existe en este proyecto.
# Para separarlos: (a) lo confirma `validate-harness --selftest`, donde el
# gate DEMUESTRA que ve. Cero detecciones + selftest verde = disuasión, se
# queda. Cero detecciones + sin selftest = candidato REAL a revisión.
# Por eso este informe no recomienda borrar nada: hace la pregunta
# respondible con datos en vez de con intuición. La decisión es del owner.
#
# El reporte cuenta eventos únicos (v2 por event_id; v1 por línea), suma `n`
# como actividad y usa duration_ms solo donde existe. Un event_id enlazado en
# el ledger está promovido; uno no enlazado sigue UNTRIAGED, nunca se llama FP.
# Sin estado durable negativo, FP rate se reporta n/a en vez de inventarlo.
#
#   bash tools/metrics/gate-value.sh                         # últimos 30 días
#   bash tools/metrics/gate-value.sh --days 90 --json
#   bash tools/metrics/gate-value.sh --since 2026-01-01 --until 2026-03-31
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1
command -v python3 >/dev/null 2>&1 \
  || { echo "⚠️  gate-value: python3 ausente — no pude leer JSONL con seguridad." >&2; exit 3; }
exec python3 tools/metrics/metrics-report.py gate-value "$@"

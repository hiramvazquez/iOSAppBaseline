#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# verdict.sh — el CONTRATO de veredicto de los sub-agentes de review
# ════════════════════════════════════════════════════════════════════
# El invariante nº1 del harness: **el veredicto no lo emite el modelo, lo
# deriva el sistema.** Un sub-agente de review termina su mensaje final con:
#
#     VERDICT: GREEN|AMBER|RED
#     FINDINGS: <n>
#     SCOPE: <descripción corta>
#
# El hook `SubagentStop` lee `last_assistant_message` del payload, lo pasa por
# aquí, y SOLO si el veredicto es markable escribe el marker que desbloquea el
# commit. El modelo no puede escribir el marker: puede escribir el TEXTO, pero
# el texto que reclama GREEN habiendo hallazgos graves es un problema de
# honestidad del reviewer — no de falsificación del gate. La diferencia importa:
# antes bastaba con ejecutar un script; ahora hay que emitir un veredicto
# explícito, atribuible y auditable.
#
# Reglas de parsing (deliberadamente estrictas):
#   - La línea debe ser `VERDICT:` al inicio de línea (tolera espacios).
#     Mencionar "verdict green" en prosa NO cuenta.
#   - Solo GREEN|AMBER|RED. Cualquier otro valor → sin veredicto.
#   - Si hay varias, gana la ÚLTIMA (el agente puede autocorregirse).
#   - Sin línea válida → sin veredicto → sin marker. Ausencia de evidencia
#     NO es evidencia de ausencia.
# ════════════════════════════════════════════════════════════════════

# verdict_parse <texto> → imprime GREEN|AMBER|RED, o vacío si no hay contrato.
verdict_parse() {
  printf '%s\n' "${1:-}" \
    | grep -iE '^[[:space:]]*VERDICT[[:space:]]*:[[:space:]]*(GREEN|AMBER|RED)[[:space:]]*$' \
    | tail -1 \
    | sed -E 's/^[[:space:]]*[Vv][Ee][Rr][Dd][Ii][Cc][Tt][[:space:]]*:[[:space:]]*//; s/[[:space:]]*$//' \
    | tr '[:lower:]' '[:upper:]'
}

# verdict_scope <texto> → imprime el SCOPE declarado (o vacío).
verdict_scope() {
  printf '%s\n' "${1:-}" \
    | grep -iE '^[[:space:]]*SCOPE[[:space:]]*:' \
    | tail -1 \
    | sed -E 's/^[[:space:]]*[Ss][Cc][Oo][Pp][Ee][[:space:]]*:[[:space:]]*//; s/[[:space:]]*$//'
}

# verdict_findings <texto> → imprime el nº de hallazgos declarado (o vacío).
verdict_findings() {
  printf '%s\n' "${1:-}" \
    | grep -iE '^[[:space:]]*FINDINGS[[:space:]]*:[[:space:]]*[0-9]+' \
    | tail -1 \
    | sed -E 's/[^0-9]*([0-9]+).*/\1/'
}

# ── MODO CONTRATO: el review que ocurre ANTES de que exista el código ──
# El coste de una review crece con TODO el diff y cada vuelta re-verifica
# desde cero: medido en el primer proyecto real, tres vueltas de ~150k tokens
# para un cambio que, partido, costó 62k. La causa no era el reviewer: era
# que llegaba a ciegas al final, sin saber qué importaba de antemano.
#
# El contrato invierte el orden (patrón de harness-design de Anthropic:
# generador y evaluador acuerdan qué significa "hecho" ANTES de escribir
# código). El reviewer lee la historia y el área, y declara por adelantado
# qué riesgos aplican y qué sería RED. La review final deja de ser
# exploratoria y pasa a ser dirigida.
#
# Es un contrato DISTINTO del veredicto y por eso tiene su propia línea: un
# contrato JAMÁS puede escribir el marker que desbloquea un commit — si
# compartieran línea, pedir el contrato desbloquearía el commit del código
# que aún no existe. Fijado por tools/tests/test_verdict.sh.
#
#     CONTRACT: READY
#
# contract_parse <texto> → imprime READY, o vacío.
contract_parse() {
  printf '%s\n' "${1:-}" \
    | grep -iE '^[[:space:]]*CONTRACT[[:space:]]*:[[:space:]]*READY[[:space:]]*$' \
    | tail -1 \
    | sed -E 's/.*:[[:space:]]*//; s/[[:space:]]*$//' \
    | tr '[:lower:]' '[:upper:]'
}

# verdict_is_markable <veredicto> → exit 0 si permite escribir marker.
# GREEN y AMBER marcan (AMBER = hallazgos menores, se atienden y se commitea).
# RED, valor inválido y vacío NO marcan.
verdict_is_markable() {
  case "${1:-}" in
    GREEN|AMBER) return 0 ;;
    *)           return 1 ;;
  esac
}

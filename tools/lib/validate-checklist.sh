#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# validate-checklist.sh — lo que NINGÚN check estático puede probar
# ════════════════════════════════════════════════════════════════════
# La regla operativa del validador: ningún gate cuenta como existente hasta
# que lo has visto bloquear algo una vez. Los checks estáticos y el selftest
# cubren todo lo verificable sin un cliente vivo; esto es la lista de lo que
# solo demuestra una sesión REAL de Claude Code / Cursor / Codex.
#
# Se imprime SIEMPRE (pase o falle lo demás): una lista que solo apareciera
# cuando todo va bien no es un aviso, es una felicitación.
#
# Se SOURCEA desde tools/validate-harness.sh. No se ejecuta suelta
# (tools/lib/ → sin bit +x, exento de check-exec-bits.sh).

vh_print_checklist() {
# CUERPO VERBATIM (sin re-indentar): el heredoc `<<'LIVE'` exige que su
# terminador siga en la columna 0.
echo ""
echo "━━━ checklist EN VIVO (esto NO se puede verificar en estático) ━━━"
cat <<'LIVE'
En una sesión REAL de Claude Code sobre este repo, verifica una vez por
versión del cliente (y anota la fecha en docs/process/lessons_learned.md):

  □ SessionStart: al abrir la sesión se imprime el health-check.
  □ git-guard: pide `git commit --no-verify -m x` → debe DENEGARSE por el
    reviewer-gate. (Las prohibiciones de FLAGS viven en el guard a propósito:
    permissions no soporta comodines intermedios — lección f-3c027a85.)
  □ skill-reminder: intenta editar un archivo que case la matriz sin haber
    leído las refs → debe bloquear (preset full).
  □ reviewer-gate: `git commit` sin marker → bloqueado (full) / aviso (lite).
  □ SubagentStop: invoca al sub-agente reviewer; al terminar debe existir
    .agents/state/markers/reviewer_run.txt con `source: hook`.
  □ Compactación: fuerza `/compact`; el turno siguiente debe traer el digest
    reinyectado (SessionStart matcher compact → post-compact.sh) y NO debe
    haberse borrado .agents/state/skills-read/.
  □ Telemetría: .agents/state/metrics/detections.jsonl crece cuando un gate
    detecta algo.

En Codex CLI (si lo usas):
  □ hooks habilitados ([features] codex_hooks) y `git commit --no-verify`
    denegado por el adapter. Si tu versión no soporta hooks de proyecto,
    muévelos a ~/.codex/hooks.json.

En Cursor (si lo usas):
  □ beforeShellExecution deniega `git commit` sin marker (respuesta JSON del
    gate-adapter). Recuerda: sin SubagentStop, el marker se genera con
    scripts/mark-reviewer-run.sh (auditado) o preset lite.
LIVE
}

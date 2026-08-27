#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# harness-report.sh — el estado del harness en UN informe pegable
# ════════════════════════════════════════════════════════════════════
# Para qué: el harness corre en TU máquina, pero quien ayuda a mejorarlo (un
# humano, otra IA, la conversación de Cowork donde se diseñó) no está ahí.
# Este comando empaqueta toda la evidencia dispersa — telemetría de gates,
# runs del backlog, atascos, overrides, findings, salud — en un solo markdown
# ACOTADO (pegable en un chat) y con REDACCIÓN de secretos por si acaso.
#
#   bash tools/harness-report.sh              # imprime + guarda copia
#   bash tools/harness-report.sh --since-days 7
#
# Contrato: SIEMPRE exit 0 (es observabilidad: un informe que falla cuando
# las cosas van mal es inútil justo cuando más se necesita). Lo que no pueda
# leer, lo declara como ausente. Cada sección va acotada (tail) a propósito:
# un informe de 5000 líneas no se pega en ningún sitio.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 0

STATE=".agents/state"
OUT_DIR="$STATE/report"; mkdir -p "$OUT_DIR" 2>/dev/null
OUT="$OUT_DIR/harness-report-$(date -u +%Y%m%dT%H%M%SZ).md"

# Redacción de secretos: mismos patrones que canon-enforce CHECK 2. La
# telemetría no debería contenerlos por diseño, pero un informe que viaja a
# un chat merece el cinturón además de los tirantes.
_redact() {
  sed -E 's/(sk-[A-Za-z0-9]{8})[A-Za-z0-9]{12,}/\1…REDACTED/g;
          s/AKIA[0-9A-Z]{16}/AKIA…REDACTED/g;
          s/ghp_[A-Za-z0-9]{10}[A-Za-z0-9]{26}/ghp_…REDACTED/g;
          s/xox[baprs]-[A-Za-z0-9-]{10,}/xox…REDACTED/g'
}
_section() { echo ""; echo "## $1"; echo ""; }
_ver() { # versión de un binario SIN riesgo de cuelgue: semgrep --version hace
  # un version-check contra su servidor y en redes restringidas espera para
  # siempre (cazado con timeout+trace, no en teoría). Env lo desactiva; y si
  # hay `timeout` (GNU), cinturón extra de 5s.
  command -v "$1" >/dev/null 2>&1 || { echo "AUSENTE"; return 0; }
  local T=""; command -v timeout >/dev/null 2>&1 && T="timeout 5"
  SEMGREP_ENABLE_VERSION_CHECK=0 SEMGREP_SEND_METRICS=off \
    $T "$1" --version 2>/dev/null </dev/null | head -1 || true
}
_tailf() { # _tailf <archivo> <n> [descripcion]
  if [ -f "$1" ]; then
    echo '```'
    tail -n "$2" "$1" | _redact
    echo '```'
    local total; total="$(wc -l < "$1" | tr -d ' ')"
    [ "$total" -gt "$2" ] && echo "_(…${total} líneas en total; mostrando las últimas $2 — archivo: \`$1\`)_"
  else
    echo "_(sin datos: \`$1\` no existe${3:+ — $3})_"
  fi
}
_runtime_inventory() {
  local tests=0 fills=0 commit="unknown"
  tests="$(git grep -hE '^test_[A-Za-z0-9_]+[[:space:]]*\(\)' HEAD -- 'tools/tests/test_*.sh' 2>/dev/null \
    | wc -l | tr -d ' ')"
  fills="$(git grep -I -h -E '^[[:space:]]*([#;]|//|--)?[[:space:]]*<!--[[:space:]]*FILL([[:space:]:>-]|$)' HEAD -- . 2>/dev/null \
    | wc -l | tr -d ' ')"
  commit="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo "tests_discovered=${tests:-0}"
  echo "fill_markers=${fills:-0}"
  echo "evidence_commit=$commit"
  echo "evidence_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

{
  echo "# Harness report — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  echo "> Generado por \`tools/harness-report.sh\`. Pega este archivo COMPLETO en la"
  echo "> conversación de mejora del harness. Secretos: redacción automática aplicada."

  _section "1. Entorno"
  echo '```'
  echo "repo:    $(basename "$(pwd)") @ $(git rev-parse --abbrev-ref HEAD 2>/dev/null)/$(git rev-parse --short HEAD 2>/dev/null)"
  echo "preset:  $(awk 'NR==1{print $1}' tools/preset 2>/dev/null || echo '?')"
  echo "os:      $(uname -sm) $(sw_vers -productVersion 2>/dev/null || true)"
  for b in claude git semgrep gitleaks lefthook jq python3; do
    printf '%-9s %s\n' "$b:" "$(_ver "$b")"
  done
  echo '```'

  _section "1b. Inventario calculado (no snapshots manuales)"
  echo '```'
  _runtime_inventory
  echo '```'

  _section "2. Salud (validate-harness, checks estáticos)"
  echo '```'
  bash tools/validate-harness.sh 2>&1 | sed -n '1,60p' || true
  echo '```'

  _section "3. Estado del proyecto (session-start --report)"
  echo '```'
  bash scripts/agent-hooks/session-start.sh --report 2>&1 | _redact || true
  echo '```'

  _section "4. Runs del backlog (los últimos 3, colas de 60 líneas)"
  if ls "$STATE/backlog/"*.log >/dev/null 2>&1; then
    # shellcheck disable=SC2012
    for f in $(ls -t "$STATE/backlog/"*.log | head -3); do
      echo "### $(basename "$f")"
      _tailf "$f" 60
    done
  else
    echo "_(aún no hay runs de backlog registrados)_"
  fi

  _section "5. Detecciones de los gates (telemetría, últimas 40)"
  _tailf "$STATE/metrics/detections.jsonl" 40 "ningún gate ha detectado nada aún, o la telemetría no corre"

  # LA métrica del proyecto (nivel 9) vivía como script HUÉRFANO: existía,
  # estaba bien escrito, se alimentaba solo... y no lo invocaba nadie — ni el
  # informe, ni run-gates, ni CI. Es decir, la tesis central del harness ("la
  # revisión humana decrece") era la única afirmación sin evidencia del
  # sistema que exige evidencia para todo. Aquí se cierra: si el número no
  # sale en el informe que el humano lee, el número no existe.
  _section "5b. Contención por fase (escape rate) — LA métrica del nivel 9"
  echo '```'
  if [ -f tools/metrics/escape-rate.sh ]; then
    bash tools/metrics/escape-rate.sh 2>&1 | head -30
  else
    echo "(tools/metrics/escape-rate.sh ausente — nivel 9 sin medir)"
  fi
  echo '```'
  echo "_Cuanto más ABAJO se detecta (in-loop, gate), más barato. Si el reparto no se_"
  echo "_mueve hacia abajo con el tiempo, estás añadiendo ceremonia, no calidad._"

  # La otra mitad de la misma pregunta: escape-rate dice DÓNDE se caza;
  # esto dice QUIÉN sigue cazando. Un harness que solo crece acaba cobrando
  # peaje por defensas que ya no defienden.
  _section "5c. Valor por gate (¿sigue siendo load-bearing?)"
  echo '```'
  if [ -f tools/metrics/gate-value.sh ]; then
    bash tools/metrics/gate-value.sh 2>&1 | head -28
  else
    echo "(tools/metrics/gate-value.sh ausente)"
  fi
  echo '```'

  _section "6. Atascos, overrides y cola de juicio"
  echo "**Atascos (4+ fallos seguidos):**"
  _tailf "$STATE/stuck-log.txt" 15
  echo ""
  echo "**Overrides del review-marker (cada uno merece explicación):**"
  _tailf "$STATE/markers/override_log.txt" 15
  echo ""
  echo "**Cola del process-judge:**"
  _tailf "$STATE/judge-queue.txt" 10

  _section "7. Findings abiertos"
  echo '```'
  bash tools/findings/findings.sh list --status open 2>/dev/null | head -20 || echo "(ledger no disponible)"
  echo '```'

  _section "8. Git: ramas de historias y últimos commits"
  echo '```'
  git branch --list 'story/*' 2>/dev/null | head -10
  echo "---"
  git log --oneline -15 2>/dev/null
  echo "---"
  git worktree list 2>/dev/null | head -5
  echo '```'

  _section "9. Suite del harness"
  echo "_(no se ejecuta aquí por tiempo — pega el final de \`bash tools/tests/run-tests.sh\` si es relevante)_"
} > "$OUT" 2>/dev/null </dev/null   # </dev/null: NINGÚN subcomando puede colgarse esperando stdin

cat "$OUT"
echo ""
echo "════════════════════════════════════════════════════════════"
echo "📋 Informe guardado en: $OUT"
echo "   Pega su contenido completo en la conversación de mejora del harness."
exit 0

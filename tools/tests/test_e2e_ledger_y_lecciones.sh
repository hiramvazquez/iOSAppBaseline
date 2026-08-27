#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# test_e2e_ledger_y_lecciones.sh — GOLDEN 6/7 del PRD 0004 (fase 10)
# ════════════════════════════════════════════════════════════════════
# Parte de la MATRIZ E2E del PRD 0004, dividida en fase 2a del PRD 0005
# (tools/tests/test_e2e_matrix.sh superaba el hard limit de 400 líneas,
# AGENTS.md §4) por FAMILIA de escenario, no por posición. Este archivo
# cubre el gobierno del CONTEXTO acumulado: el mismo defecto, detectado dos
# veces por el scanner, cuenta como un solo finding en el ledger y en las
# métricas derivadas (G6); y rotar lecciones reduce el contexto obligatorio
# SIN que ninguna lección mecanizada deje de estar verificada por su
# detector (G7). Las hermanas de esta matriz — capacidades declaradas,
# orquestador del backlog, gates del Anillo 3, plataformas — viven en los
# otros `test_e2e_*.sh`.
#
# QUÉ ES ESTO Y QUÉ NO ES. `test_findings_cli.sh`, `test_metrics.sh` y
# los `test_lessons_*.sh` cubren cada pieza por separado; esto cruza la FRONTERA
# evento→ledger→métrica y rotación→vínculo-lección-detector, que es donde
# un harness con todas sus piezas verdes puede seguir roto en la costura.
#
# HERMÉTICA POR CONSTRUCCIÓN: ni `claude` ni `semgrep` reales. Los proveedores
# entran por stubs en un `bin/` del sandbox y el PATH se fija a mano, así que
# el resultado no depende de lo que tenga instalado la máquina.

# ── Sandbox con la maquinaria real, no con recortes ──────────────────
# Un E2E que copia solo los tres scripts que va a llamar no prueba la
# integración: prueba el recorte que hizo quien escribió el test. Aquí va la
# maquinaria entera (tools sin su propia suite, scripts, ci, .github) sobre un
# repo git nuevo.
_e2e_repo() { # _e2e_repo <función>
  local d rc; d="$(mktemp -d)"
  cp -R "$PROJECT_ROOT/tools" "$d/tools" 2>/dev/null
  rm -rf "$d/tools/tests"
  cp -R "$PROJECT_ROOT/scripts" "$d/scripts" 2>/dev/null
  cp -R "$PROJECT_ROOT/ci" "$d/ci" 2>/dev/null
  mkdir -p "$d/.github/workflows" "$d/docs/process" "$d/backlog"
  cp "$PROJECT_ROOT/.github/workflows/harness-ci.yml" "$d/.github/workflows/" 2>/dev/null
  cp "$PROJECT_ROOT/AGENTS.md" "$d/AGENTS.md" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q -b develop . 2>/dev/null
    git config user.email t@t.t; git config user.name t
    echo seed > seed.txt
    git add -A >/dev/null 2>&1
    git commit -qm "seed: maquinaria del harness" >/dev/null 2>&1
    "$1"
  )
  rc=$?
  rm -rf "$d"
  return $rc
}

# Líneas de lectura OBLIGATORIA de un doc de lecciones: todo lo anterior al
# índice mecanizado (el índice es una vista generada; AGENTS.md manda parar
# ahí). Misma definición que usa el límite de 250 líneas en test_lessons.sh.
_e2e_contexto_obligatorio() { # _e2e_contexto_obligatorio <doc>
  local corte
  corte="$(grep -n '^## Lecciones mecanizadas (índice)$' "$1" | head -1 | cut -d: -f1)"
  if [ -n "$corte" ]; then
    printf '%s\n' "$((corte - 1))"
  else
    grep -c '' "$1"
  fi
}

# ════════════════════════════════════════════════════════════════════
# GOLDEN 6 — el mismo defecto, detectado dos veces, cuenta una
# ════════════════════════════════════════════════════════════════════
# La pata nueva: la promoción pasa por el CLI real del ledger (dos `add` con
# `--source-event` distintos) y las DOS métricas se leen sobre el resultado.
_case_g6_defecto_unico_en_dos_detecciones() {
  : > tools/findings/ledger.jsonl
  mkdir -p .agents/state/metrics docs/process
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  {
    printf '{"schema":2,"event_id":"ev-alpha","ts":"%s","phase":"gate","source":"semgrep","duration_ms":12,"commit":"abc1234","triage":"unknown"}\n' "$ts"
    printf '{"schema":2,"event_id":"ev-beta","ts":"%s","phase":"gate","source":"semgrep","duration_ms":18,"commit":"abc1234","triage":"unknown"}\n' "$ts"
  } > .agents/state/metrics/detections.jsonl

  bash tools/findings/findings.sh add --title "adapter sin timeout" --area data \
    --source semgrep --source-event ev-alpha >/dev/null 2>&1 \
    || { echo "    el ledger rechazó la primera detección"; return 1; }
  bash tools/findings/findings.sh add --title "adapter sin timeout" --area data \
    --source semgrep --source-event ev-beta >/dev/null 2>&1 \
    || { echo "    el ledger rechazó la segunda detección del mismo defecto"; return 1; }

  local n; n="$(grep -c . tools/findings/ledger.jsonl | tr -d ' ')"
  [ "$n" = 1 ] || { echo "    dos detecciones del mismo defecto crearon $n findings"; return 1; }

  local escape gate
  escape="$(bash tools/metrics/escape-rate.sh --days 1 --json 2>/dev/null)" \
    || { echo "    escape-rate no pudo leer el ledger"; return 1; }
  assert_contains "$escape" '"findings_total":1' || return 1
  assert_contains "$escape" '"gate":1' || return 1

  # Y los eventos siguen contando como ACTIVIDAD: dos eventos, un defecto.
  gate="$(bash tools/metrics/gate-value.sh --days 1 --json 2>/dev/null)" \
    || { echo "    gate-value no pudo leer la telemetría"; return 1; }
  assert_contains "$gate" '"events_total":2' || return 1
  assert_contains "$gate" '"promoted_events":2' || return 1
}
test_golden_06_mismo_defecto_se_cuenta_una_sola_vez() {
  _e2e_repo _case_g6_defecto_unico_en_dos_detecciones
}

# ════════════════════════════════════════════════════════════════════
# GOLDEN 7 — rotar reduce el contexto SIN perder la garantía
# ════════════════════════════════════════════════════════════════════
# El riesgo de la rotación no es archivar poco: es archivar y que la lección
# deje de estar verificada. Por eso el test encadena rotate y
# lesson-detector-link, que es quien responde "¿sigue garantizada?".
_case_g7_rotacion_conserva_la_garantia() {
  mkdir -p docs/process tools/tests
  stub tools/tests/test_ficticio.sh '#!/usr/bin/env bash\n: # detector citado por la lección mecanizada\n'
  cat > docs/process/lessons_learned.md <<'EOF'
# Lecciones aprendidas

## Lecciones del harness

### [2026-01-01] Una lección ya mecanizada
- **Qué pasó:** el gate no miraba el índice, solo el árbol.
- **Regla:** mira el índice también.
- **Detector:** `tools/tests/test_ficticio.sh`
- **Área:** tools/

### [2026-01-02] Una lección de juicio
- **Qué pasó:** el agente eligió un default en vez de preguntar.
- **Regla:** Open Question > suposición silenciosa.
- **Detector:** n/a-manual — es criterio, no patrón mecanizable
- **Área:** proceso
EOF
  bash tools/lesson-detector-link.sh >/dev/null 2>&1 \
    || { echo "    el corpus de partida ya no pasaba el vínculo lección→detector"; return 1; }

  # La medida es la del propio proyecto: el contexto OBLIGATORIO termina donde
  # empieza el índice (AGENTS.md manda leer solo hasta ahí). Contar el archivo
  # entero mediría otra cosa — el índice es una vista, no lectura obligatoria.
  local antes despues
  antes="$(_e2e_contexto_obligatorio docs/process/lessons_learned.md)"
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1 \
    || { echo "    la rotación falló"; return 1; }
  despues="$(_e2e_contexto_obligatorio docs/process/lessons_learned.md)"
  [ "$despues" -lt "$antes" ] \
    || { echo "    rotar no redujo el contexto obligatorio ($antes → $despues líneas)"; return 1; }

  grep -q 'Una lección de juicio' docs/process/lessons_learned.md \
    || { echo "    la rotación archivó una lección n/a-manual (juicio no mecanizado)"; return 1; }
  grep -q 'es criterio, no patrón mecanizable' docs/process/lessons_learned.md \
    || { echo "    la lección viva perdió su cuerpo"; return 1; }
  grep -q 'el gate no miraba el índice' docs/process/lessons_archive.md 2>/dev/null \
    || { echo "    la lección mecanizada no llegó al archivo"; return 1; }
  grep -q 'el gate no miraba el índice' docs/process/lessons_learned.md \
    && { echo "    la lección mecanizada sigue en el contexto obligatorio"; return 1; }

  bash tools/lesson-detector-link.sh >/dev/null 2>&1 \
    || { echo "    tras rotar, el vínculo lección→detector dejó de verificarse"; return 1; }
}
test_golden_07_rotacion_reduce_contexto_sin_perder_garantia() {
  _e2e_repo _case_g7_rotacion_conserva_la_garantia
}


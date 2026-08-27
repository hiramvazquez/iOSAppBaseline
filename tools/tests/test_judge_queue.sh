#!/usr/bin/env bash
# Cola del process-judge. El juez existía desde el día 1 y NUNCA corría solo:
# nada lo invocaba ni recordaba invocarlo. La cola hace el trabajo pendiente
# VISIBLE cada turno (inject-context) hasta que un veredicto real lo vacía.
#
# Deliberadamente NO auto-invoca al juez (PRD 0002 §8): lanzar un agente desde
# un hook es coste no consentido. Visibilidad mecánica, invocación humana.

_jq_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/.agents/state/trajectory" "$d/tools/findings" "$d/docs/process"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  cp "$PROJECT_ROOT/tools/preset" "$d/tools/preset" 2>/dev/null
  # El .gitignore REAL: sin él, `.agents/state/` no está ignorado y git reporta
  # `?? .agents/` colapsando el directorio — el filtro de session-end casa
  # `?? .agents/state/`, no el padre, y todo parecería árbol sucio. El sandbox
  # tiene que parecerse al repo también en esto.
  cp "$PROJECT_ROOT/.gitignore" "$d/.gitignore" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo seed > seed.txt
    # Se commitea TODO el andamiaje copiado: el caso "sesión sin cambios"
    # exige un árbol base LIMPIO, o el propio sandbox sería el falso positivo.
    git add -A 2>/dev/null; git commit -qm init 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_end_session() { # _end_session <session_id>
  printf '{"session_id":"%s","hook_event_name":"SessionEnd"}' "$1" \
    | bash scripts/agent-hooks/session-end.sh >/dev/null 2>&1
}
QUEUE=".agents/state/judge-queue.txt"

# ── encolar ─────────────────────────────────────────────────────────
_case_sesion_con_codigo_encola() {
  mkdir -p src; echo "x" > src/App.swift          # árbol tocado
  _end_session s-abc
  [ -f "$QUEUE" ] && grep -q "s-abc" "$QUEUE" || { echo "    la sesión con código no se encoló"; return 1; }
}
test_sesion_que_toco_codigo_se_encola() { _jq_sandbox _case_sesion_con_codigo_encola; }

# ── FALSO POSITIVO: sesión sin trabajo no encola ────────────────────
_case_sesion_limpia_no_encola() {
  _end_session s-clean
  [ -f "$QUEUE" ] && grep -q "s-clean" "$QUEUE" && { echo "    FALSO POSITIVO: una sesión sin cambios se encoló"; return 1; }
  return 0
}
test_sesion_sin_cambios_no_se_encola() { _jq_sandbox _case_sesion_limpia_no_encola; }

_case_no_duplica_sesion() {
  mkdir -p src; echo "x" > src/App.swift
  _end_session s-dup; _end_session s-dup
  local n; n="$(grep -c "s-dup" "$QUEUE" 2>/dev/null || echo 0)"
  [ "$n" = "1" ] || { echo "    la misma sesión se encoló $n veces"; return 1; }
}
test_la_misma_sesion_no_se_duplica() { _jq_sandbox _case_no_duplica_sesion; }

# ── visible cada turno ──────────────────────────────────────────────
_case_inject_muestra_cola() {
  mkdir -p src; echo "x" > src/App.swift
  _end_session s-vis
  local out; out="$(echo '{}' | bash scripts/agent-hooks/inject-context.sh 2>/dev/null)"
  case "$out" in *process-judge*) return 0 ;; esac
  echo "    inject-context no muestra la cola pendiente"; return 1
}
test_la_cola_es_visible_por_turno() { _jq_sandbox _case_inject_muestra_cola; }

# ── el veredicto REAL del juez vacía la cola ────────────────────────
_case_verdict_del_juez_vacia() {
  mkdir -p src; echo "x" > src/App.swift
  _end_session s-judged
  # printf '%s' para que el \n llegue ESCAPADO (como lo envía Claude Code):
  # un salto de línea real dentro de un string JSON es inválido y jq devuelve
  # vacío → el hook saldría por "sin mensaje" y el test pasaría por el motivo
  # equivocado.
  printf '%s' '{"agent_type":"process-judge","last_assistant_message":"Trayectoria revisada.\nVERDICT: AMBER\nFINDINGS: 2\nSCOPE: sesión s-judged"}' \
    | bash scripts/agent-hooks/capture-review-verdict.sh >/dev/null 2>&1
  [ -s "$QUEUE" ] && { echo "    el veredicto del juez NO vació la cola"; return 1; }
  [ -f ".agents/state/markers/process-judge_run.txt" ] || { echo "    no quedó marker del juicio"; return 1; }
  return 0
}
test_el_verdict_del_juez_vacia_la_cola() { _jq_sandbox _case_verdict_del_juez_vacia; }

# ── la sesión YA JUZGADA no se re-encola al terminar ────────────────
_case_sesion_juzgada_no_reencola() {
  mkdir -p src; echo "x" > src/App.swift
  # El juez corre DURANTE la sesión s-done (su payload trae el session_id):
  printf '%s' '{"session_id":"s-done","agent_type":"process-judge","last_assistant_message":"VERDICT: GREEN\nFINDINGS: 0\nSCOPE: lote"}' \
    | bash scripts/agent-hooks/capture-review-verdict.sh >/dev/null 2>&1
  # …y al cerrar ESA sesión (árbol aún sucio), no debe volver a la cola.
  # La primera versión de este dedup era código muerto: grepeaba el SID en un
  # marker que nunca lo contenía, y el test de arriba pasaba solo porque el
  # fixture metía el SID en el SCOPE. Este caso fija el contrato REAL
  # (campo `session:` con match exacto).
  _end_session s-done
  [ -f "$QUEUE" ] && grep -q "s-done" "$QUEUE" && { echo "    la sesión ya juzgada se re-encoló"; return 1; }
  return 0
}
test_sesion_ya_juzgada_no_se_reencola() { _jq_sandbox _case_sesion_juzgada_no_reencola; }

_case_otro_sid_si_encola() {
  # FALSO POSITIVO guard del dedup: que s-aaa esté juzgada no puede tragarse
  # a s-aaab (match EXACTO, no substring).
  mkdir -p src; echo "x" > src/App.swift
  printf '%s' '{"session_id":"s-aaa","agent_type":"process-judge","last_assistant_message":"VERDICT: GREEN\nFINDINGS: 0\nSCOPE: lote"}' \
    | bash scripts/agent-hooks/capture-review-verdict.sh >/dev/null 2>&1
  _end_session s-aaab
  grep -q "s-aaab" "$QUEUE" 2>/dev/null || { echo "    el dedup por substring se tragó una sesión distinta"; return 1; }
}
test_dedup_es_por_match_exacto() { _jq_sandbox _case_otro_sid_si_encola; }

_case_sid_con_metacaracteres() {
  # FALSO POSITIVO guard del dedup, capa 2: los DATOS no son PATRONES.
  # El grep usa como PATRÓN el SID de la sesión QUE CIERRA. Sin -F, un `.` en
  # ese SID actúa de comodín contra el guardado: con "s-aXc" juzgada, el
  # cierre de "s-a.c" (distinta, SIN juzgar) matcheaba y se saltaba el
  # encolado en silencio. Repro del reviewer, dirección exacta.
  mkdir -p src; echo "x" > src/App.swift
  printf '%s' '{"session_id":"s-aXc","agent_type":"process-judge","last_assistant_message":"VERDICT: GREEN\nFINDINGS: 0\nSCOPE: lote"}' \
    | bash scripts/agent-hooks/capture-review-verdict.sh >/dev/null 2>&1
  _end_session "s-a.c"
  grep -qF "s-a.c" "$QUEUE" 2>/dev/null || { echo "    el SID se interpretó como regex: una sesión sin juzgar se saltó el encolado"; return 1; }
}
test_el_sid_es_dato_no_patron() { _jq_sandbox _case_sid_con_metacaracteres; }

# ── el juez NO desbloquea el gate del reviewer ──────────────────────
_case_juez_no_escribe_marker_de_reviewer() {
  printf '%s' '{"agent_type":"process-judge","last_assistant_message":"VERDICT: GREEN\nFINDINGS: 0\nSCOPE: x"}' \
    | bash scripts/agent-hooks/capture-review-verdict.sh >/dev/null 2>&1
  [ -f ".agents/state/markers/reviewer_run.txt" ] && { echo "    el JUEZ escribió el marker canónico del reviewer"; return 1; }
  return 0
}
test_el_juez_no_desbloquea_commits() { _jq_sandbox _case_juez_no_escribe_marker_de_reviewer; }

# ════════════════════════════════════════════════════════════════════
# f-judge-cola-sesion-equivocada — la señal premiaba dejar basura
# ════════════════════════════════════════════════════════════════════
# Encolar según "el árbol quedó sucio" significa que la sesión que cierra BIEN
# —commitea y deja limpio— es exactamente la que nunca se encola. Medido en un
# proyecto real: la cola apuntaba a una sesión con 7 tool-calls y CERO
# ediciones, mientras las dos que escribieron el adapter y el composition root
# no entraron. Una métrica de calidad sobre la muestra equivocada es peor que
# ninguna: da confianza sin cubrir nada.
_case_sesion_que_commitea_si_se_encola() {
  printf 'sid: s-1\nhead: %s\n' "$(git rev-parse HEAD)" > .agents/state/session-head.txt
  echo "codigo" > app.txt; git add -A; git commit -qm "trabajo real" 2>/dev/null
  echo '{"session_id":"s-1"}' | bash scripts/agent-hooks/session-end.sh >/dev/null 2>&1
  local q=.agents/state/judge-queue.txt
  [ -s "$q" ] || { echo "    la sesión que COMMITEÓ y dejó el árbol limpio NO se encoló"; return 1; }
  grep -q 'commits=1' "$q" || { echo "    la cola no registra los commits producidos: $(cat "$q")"; return 1; }
  grep -qE '\.\.[0-9a-f]{7,}' "$q" \
    || { echo "    la cola no lleva el RANGO que el juez debe mirar: $(cat "$q")"; return 1; }
}
test_la_sesion_que_commitea_y_deja_limpio_SI_se_encola() {
  _jq_sandbox _case_sesion_que_commitea_si_se_encola
}

_case_sesion_que_solo_lee_no_se_encola() {
  # Guard de FALSO POSITIVO: sin commits y sin cambios, no hay nada que juzgar.
  # Si esto se encolara, la cola volvería a llenarse de sesiones vacías — el
  # mismo daño por el otro extremo.
  printf 'sid: s-2\nhead: %s\n' "$(git rev-parse HEAD)" > .agents/state/session-head.txt
  echo '{"session_id":"s-2"}' | bash scripts/agent-hooks/session-end.sh >/dev/null 2>&1
  [ -s .agents/state/judge-queue.txt ] \
    && { echo "    una sesión de solo lectura se encoló"; return 1; }
  return 0
}
test_una_sesion_sin_commits_ni_cambios_no_se_encola() {
  _jq_sandbox _case_sesion_que_solo_lee_no_se_encola
}

# ── El contexto del juez no puede fingir que miró la trayectoria ────
# El `process-judge` existe para juzgar CÓMO se trabajó, no solo qué salió. Su
# script de contexto salía 0 cuando le pedías una sesión cuya trayectoria no
# existe, así que el juez recibía solo el diff y no tenía forma de saber que le
# faltaba la mitad de su encargo. Lo destapó él mismo: de las 7 entradas que
# había en la cola, 4 no tenían archivo (`f-e416ab5e`).
#
# Contrato de §14.3: 0 = limpio · 1 = hay un problema en lo tuyo · 3 = el
# detector NO PUDO MIRAR. Un gate que no corrió no puede parecer uno que pasó.
_jc_sandbox() { # reusa el repo desechable de _jq_sandbox y añade el script
  _jq_sandbox "$1"
}

_case_sid_sin_trayectoria_es_exit3() {
  cp "$PROJECT_ROOT/scripts/process-judge-context.sh" scripts/
  local out rc
  out="$(bash scripts/process-judge-context.sh sid-que-no-existe 2>&1)"; rc=$?
  [ "$rc" = "3" ] || {
    echo "    pidió una sesión sin trayectoria y salió $rc (esperaba 3)."
    echo "    Con 0, el juez juzga solo el diff creyendo que vio el proceso."
    return 1; }
  printf '%s' "$out" | grep -q 'NO HAY TRAYECTORIA' || {
    echo "    salió 3 pero sin decirlo en la salida: el juez lee el texto,"
    echo "    no el exit code. Sin el aviso, el 3 no llega a quien decide."
    return 1; }
}
test_pedir_una_sesion_sin_trayectoria_devuelve_3_y_lo_dice() {
  _jc_sandbox _case_sid_sin_trayectoria_es_exit3; }

_case_sid_con_trayectoria_es_exit0() {
  cp "$PROJECT_ROOT/scripts/process-judge-context.sh" scripts/
  printf '{"tool":"Bash"}\n' > .agents/state/trajectory/sid-real.jsonl
  local out rc
  out="$(bash scripts/process-judge-context.sh sid-real 2>&1)"; rc=$?
  [ "$rc" = "0" ] || { echo "    con trayectoria presente salió $rc (esperaba 0)"; return 1; }
  printf '%s' "$out" | grep -q '"tool":"Bash"' || {
    echo "    salió 0 pero no volcó la trayectoria"; return 1; }
}
test_pedir_una_sesion_con_trayectoria_devuelve_0_y_la_vuelca() {
  _jc_sandbox _case_sid_con_trayectoria_es_exit0; }

_case_sin_sid_es_listado_y_no_falla() {
  # FALSO POSITIVO a evitar: invocarlo SIN argumento es el modo listado, para
  # ver qué trayectorias hay. Eso no es "no pude mirar" — no se pidió nada.
  cp "$PROJECT_ROOT/scripts/process-judge-context.sh" scripts/
  local rc
  bash scripts/process-judge-context.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || {
    echo "    el modo listado (sin sid) salió $rc; no se pidió ninguna sesión,"
    echo "    así que no hay nada que no se pudiera mirar."
    return 1; }
}
test_sin_session_id_es_modo_listado_y_sale_0() {
  _jc_sandbox _case_sin_sid_es_listado_y_no_falla; }

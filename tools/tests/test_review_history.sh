#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# review-history.jsonl — encoding, schema v2 y corrupción (WF-03 / PRD 0005 1a)
# ════════════════════════════════════════════════════════════════════
# El hallazgo (f-wf03-jsonl-sin-encoder): el hook construía las líneas del
# historial con `printf` y saneado parcial. Comillas, backslashes, tabs o
# CR/LF en agent_id, scope o nota invalidaban la línea — y los CONSUMIDORES
# hacían `grep` sobre texto (el dedupe `_hist_grep`, el puntero al reporte
# previo), así que una línea rota corrompía dedupe y auditoría EN SILENCIO.
#
# Lo que este archivo fija:
#   1. valores hostiles en agent_id/scope/nota ⇒ historial SIEMPRE `jq -e` válido
#   2. el dedupe y el peaje de la idempotencia sobreviven a esos valores
#   3. schema v2: se AÑADE "v":2; las líneas v1 (sin "v") se siguen leyendo
#   4. línea corrupta preexistente ⇒ estado explícito que la CITA, jamás
#      falso verde (sin marker) y jamás crash del hook (failure-open: exit 0)
#   5. el emisor único (lib/json.sh) degrada DECLARÁNDOLO sin runtime, y el
#      append es atómico bajo concurrencia
#
# Vive en archivo propio y NO en test_verdict.sh: ese ya está sobre el hard
# limit y su división es la fase 2a, no la 1a.

_RH_HIST=".agents/state/review-history.jsonl"

_rh_sandbox() { # mismo patrón que _crv_sandbox: repo git desechable con diff staged
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/.agents/state/markers"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo seed > seed.txt; git add -A; git commit -qm init 2>/dev/null
    echo 'let x = 1' > app.swift; git add app.swift
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_rh_json() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'; }
_rh_stop() { # _rh_stop <agente> <mensaje> [agent_id] — agent_id y mensaje van CODIFICADOS:
  # el payload de Claude Code llega como JSON válido; el bug a cazar está en lo
  # que el hook ESCRIBE, no en lo que recibe.
  printf '{"hook_event_name":"SubagentStop","agent_type":"%s","agent_id":%s,"last_assistant_message":%s}' \
    "$1" "$(_rh_json "${3:-}")" "$(_rh_json "$2")" \
    | bash scripts/agent-hooks/capture-review-verdict.sh 2>&1
}
_rh_n()     { grep -c . "$_RH_HIST" 2>/dev/null || echo 0; }
_rh_head()  { git rev-parse --short HEAD 2>/dev/null || echo no-repo; }
_rh_sha()   { git diff --cached 2>/dev/null | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | awk '{print $1}'; }

_RH_RED='Hay problemas.
VERDICT: RED
FINDINGS: 2
SCOPE: el adapter'

_RH_GREEN='Todo bien.
VERDICT: GREEN
FINDINGS: 0
SCOPE: el adapter'

# agent_id hostil: comillas, backslash, tab, CR y LF — todo junto.
_RH_EVIL=$'cli "uno"\\\ttab\r\nfin-de-run'

# ════════════════════════════════════════════════════════════════════
# 1) Valores hostiles ⇒ historial siempre válido
# ════════════════════════════════════════════════════════════════════
_rh_case_agent_id_hostil() {
  _rh_stop reviewer "$_RH_RED" "$_RH_EVIL" >/dev/null
  [ -f "$_RH_HIST" ] || { echo "    el veredicto no llegó al historial"; return 1; }
  jq -e . "$_RH_HIST" >/dev/null 2>&1 || {
    echo "    agent_id con comillas/backslash/tab/CR/LF dejó review-history.jsonl INVÁLIDO para jq -e:"
    sed 's/^/      /' "$_RH_HIST" | head -4
    return 1; }
  local n; n="$(_rh_n)"
  [ "$n" = "1" ] || { echo "    esperaba 1 entrada y hay $n: la línea se partió o se duplicó"; return 1; }
}
test_agent_id_hostil_deja_historial_jq_valido() { _rh_sandbox _rh_case_agent_id_hostil; }

_rh_case_scope_hostil_roundtrip() {
  local scope msg got
  scope=$'el "adapter"\tde C:\\temp y al final \\'
  msg="$(printf 'Revisado.\n\nVERDICT: RED\nFINDINGS: 1\nSCOPE: %s' "$scope")"
  _rh_stop reviewer "$msg" run-scope >/dev/null
  jq -e . "$_RH_HIST" >/dev/null 2>&1 || {
    echo "    scope con comillas/backslash/tab dejó el historial inválido:"
    sed 's/^/      /' "$_RH_HIST" | head -4
    return 1; }
  got="$(jq -r 'select(.scope != null) | .scope' "$_RH_HIST" 2>/dev/null | tail -1)"
  assert_eq "$scope" "$got" || {
    echo "    el scope no sobrevive el viaje historial→parser (saneado con pérdida)"; return 1; }
}
test_scope_hostil_sobrevive_el_roundtrip() { _rh_sandbox _rh_case_scope_hostil_roundtrip; }

# ════════════════════════════════════════════════════════════════════
# 2) El dedupe y el peaje sobreviven a los valores hostiles
# ════════════════════════════════════════════════════════════════════
_rh_case_dedupe_con_agent_id_hostil() {
  local i; for i in 1 2 3 4 5; do _rh_stop reviewer "$_RH_RED" "$_RH_EVIL" >/dev/null; done
  jq -e . "$_RH_HIST" >/dev/null 2>&1 || {
    echo "    5 vueltas con agent_id hostil dejaron el historial inválido"; return 1; }
  local n; n="$(_rh_n)"
  [ "$n" = "1" ] || { echo "    5 vueltas de la MISMA invocación dejaron $n entradas (esperaba 1): el encoding rompió el corte del bucle"; return 1; }
}
test_el_dedupe_sigue_cortando_el_bucle_con_agent_id_hostil() { _rh_sandbox _rh_case_dedupe_con_agent_id_hostil; }

_rh_case_dos_invocaciones_hostiles_distintas() {
  _rh_stop reviewer "$_RH_RED" "$_RH_EVIL" >/dev/null
  _rh_stop reviewer "$_RH_RED" $'otra "run"\r\ndistinta' >/dev/null
  jq -e . "$_RH_HIST" >/dev/null 2>&1 || {
    echo "    dos invocaciones con ids hostiles dejaron el historial inválido"; return 1; }
  local n; n="$(_rh_n)"
  [ "$n" = "2" ] || { echo "    dos invocaciones DELIBERADAS distintas dejaron $n entradas (esperaba 2): el peaje de la idempotencia se perdió"; return 1; }
}
test_dos_invocaciones_hostiles_distintas_se_registran() { _rh_sandbox _rh_case_dos_invocaciones_hostiles_distintas; }

# ════════════════════════════════════════════════════════════════════
# 3) Backward: las líneas v1 (sin "v") se siguen leyendo
# ════════════════════════════════════════════════════════════════════
_rh_case_linea_v1_se_sigue_leyendo() {
  mkdir -p .agents/state
  printf '{"ts":"2026-08-18T00:00:00Z","agent":"reviewer","run":"run-v1","verdict":"RED","findings":"2","scope":"x","head":"%s","staged_sha":"%s","report":"r.md","nota":"sin marker; commit sigue bloqueado"}\n' \
    "$(_rh_head)" "$(_rh_sha)" > "$_RH_HIST"
  _rh_stop reviewer "$_RH_RED" run-v1 >/dev/null
  local n; n="$(_rh_n)"
  [ "$n" = "1" ] || { echo "    una línea v1 VÁLIDA (sin campo \"v\") no se leyó: el mismo run/diff/veredicto se re-registró ($n entradas)"; return 1; }
  [ -f .agents/state/markers/history_corrupt.txt ] && { echo "    una línea v1 válida se marcó como corrupta (backward roto)"; return 1; }
  return 0
}
test_una_linea_v1_valida_se_sigue_leyendo() { _rh_sandbox _rh_case_linea_v1_se_sigue_leyendo; }

_rh_case_las_lineas_nuevas_llevan_v2() {
  _rh_stop reviewer "$_RH_RED" run-1 >/dev/null
  [ "$(jq -r '.v // "ausente"' "$_RH_HIST" 2>/dev/null | tail -1)" = "2" ] \
    || { echo "    la entrada nueva no lleva el campo \"v\":2 (schema versionado del PRD 0005 §NO-TOUCH)"; return 1; }
}
test_las_entradas_nuevas_declaran_schema_v2() { _rh_sandbox _rh_case_las_lineas_nuevas_llevan_v2; }

# ════════════════════════════════════════════════════════════════════
# 4) Corrupción preexistente ⇒ estado explícito, jamás falso verde
# ════════════════════════════════════════════════════════════════════
# Una línea que no parsea puede estar ocultando un RED o un RECHAZADO.
# Leer "lo que se pueda" con grep y seguir era el falso verde de WF-03.
_rh_case_corrupcion_preexistente_nunca_da_verde() {
  mkdir -p .agents/state
  printf '%s\n' '{"ts":"2026-08-18T00:00:00Z","agent":"reviewer","run":"run "roto","verdict":"RED","head":"x"' > "$_RH_HIST"
  printf '{"hook_event_name":"SubagentStop","agent_type":"reviewer","agent_id":"run-nuevo","last_assistant_message":%s}' \
    "$(_rh_json "$_RH_GREEN")" \
    | bash scripts/agent-hooks/capture-review-verdict.sh >/dev/null 2>&1
  local rc=$?
  [ "$rc" = "0" ] || { echo "    el hook REVENTÓ (exit $rc) ante una línea corrupta: failure-open roto"; return 1; }
  [ -f .agents/state/markers/reviewer_run.txt ] && \
    { echo "    FALSO VERDE: con el historial corrupto (que puede ocultar un RED) se escribió marker"; return 1; }
  grep -qF 'run "roto' .agents/state/markers/history_corrupt.txt 2>/dev/null \
    || { echo "    la corrupción no dejó estado explícito CITANDO la línea (markers/history_corrupt.txt)"; return 1; }
  return 0
}
test_una_linea_corrupta_preexistente_jamas_produce_marker() { _rh_sandbox _rh_case_corrupcion_preexistente_nunca_da_verde; }

# ── FALSO POSITIVO: un historial sano no puede disparar el estado de corrupción ──
# El caso más común de todos es el historial limpio: si el detector de
# corrupción disparara ahí, el hook dejaría de marcar TODOS los GREEN
# legítimos — el gate quedaría en deadlock permanente y acabaría desactivado.
_rh_case_historial_sano_no_es_corrupcion() {
  # Historial NO vacío y 100% sano: un RED real primero, remediación real
  # después. Si el detector disparara en falso, el GREEN legítimo del
  # segundo run se quedaría sin marker — el deadlock descrito arriba.
  _rh_stop reviewer "$_RH_RED" run-1 >/dev/null
  echo 'let x = 2 // arreglado' > app.swift; git add app.swift
  _rh_stop reviewer "$_RH_GREEN" run-2 >/dev/null
  [ -f .agents/state/markers/history_corrupt.txt ] && \
    { echo "    un historial SANO (2 entradas válidas) se marcó como corrupto (FP del detector)"; return 1; }
  [ -f .agents/state/markers/reviewer_run.txt ] \
    || { echo "    un GREEN legítimo con historial sano no escribió marker"; return 1; }
  return 0
}
test_falso_positivo_un_historial_sano_no_dispara_corrupcion() { _rh_sandbox _rh_case_historial_sano_no_es_corrupcion; }

# ════════════════════════════════════════════════════════════════════
# 5) Los consumidores PARSEAN: el puntero al previo con valores hostiles
# ════════════════════════════════════════════════════════════════════
_rh_case_puntero_previo_con_hostiles() {
  _rh_stop design-reviewer "$_RH_RED" "$_RH_EVIL" >/dev/null
  _rh_stop reviewer "$_RH_RED" run-2 >/dev/null
  jq -e . "$_RH_HIST" >/dev/null 2>&1 || {
    echo "    la primera entrada (id hostil) dejó el historial inválido"; return 1; }
  grep -rq '^previo: ' .agents/state/reviews/ \
    || { echo "    con valores hostiles en la historia, el segundo review perdió el puntero al previo"; return 1; }
}
test_el_puntero_al_previo_sobrevive_valores_hostiles() { _rh_sandbox _rh_case_puntero_previo_con_hostiles; }

# ════════════════════════════════════════════════════════════════════
# 6) El emisor único: lib/json.sh
# ════════════════════════════════════════════════════════════════════
_rh_case_emisor_codifica_nota_hostil() {
  . scripts/agent-hooks/lib/json.sh 2>/dev/null \
    || { echo "    falta scripts/agent-hooks/lib/json.sh (el emisor único de WF-03)"; return 1; }
  local nota linea
  nota=$'nota "x"\\\ttab\r\nfin'
  linea="$(json_hist_line 2026-08-19T00:00:00Z reviewer run-1 RED 2 "scope x" abc123 sha456 r.md "$nota")" \
    || { echo "    json_hist_line falló con una nota hostil"; return 1; }
  [ "$(printf '%s\n' "$linea" | wc -l | tr -d ' ')" = "1" ] \
    || { echo "    el emisor produjo más de una línea física (rompe el JSONL)"; return 1; }
  printf '%s\n' "$linea" | jq -e . >/dev/null 2>&1 \
    || { echo "    el emisor produjo JSON inválido: $linea"; return 1; }
  assert_eq "$nota" "$(printf '%s\n' "$linea" | jq -r '.nota')"
}
test_el_emisor_codifica_nota_hostil_en_una_sola_linea() { _rh_sandbox _rh_case_emisor_codifica_nota_hostil; }

_rh_case_append_concurrente() {
  . scripts/agent-hooks/lib/json.sh 2>/dev/null \
    || { echo "    falta scripts/agent-hooks/lib/json.sh"; return 1; }
  local w i
  for w in 1 2 3 4; do
    ( for i in $(seq 1 25); do
        json_append_line hist.jsonl "{\"w\":$w,\"i\":$i,\"v\":2}"
      done ) &
  done
  wait
  local n; n="$(grep -c . hist.jsonl 2>/dev/null || echo 0)"
  [ "$n" = "100" ] || { echo "    100 appends concurrentes dejaron $n líneas (se perdieron o partieron escrituras)"; return 1; }
  jq -e . hist.jsonl >/dev/null 2>&1 \
    || { echo "    los appends concurrentes se ENTRELAZARON: hay líneas inválidas"; return 1; }
}
test_los_appends_concurrentes_no_se_entrelazan() { _rh_sandbox _rh_case_append_concurrente; }

_rh_case_sin_runtime_degrada_declarandolo() {
  local out rc
  out="$(env PATH=/dev/null "${BASH:-/bin/bash}" -c '. scripts/agent-hooks/lib/json.sh 2>/dev/null; json_hist_line a b c d e f g h i j' 2>err.txt)"; rc=$?
  [ -z "$out" ] || { echo "    sin jq ni python3 el emisor AUN ASÍ emitió algo por stdout: [$out]"; return 1; }
  [ "$rc" != "0" ] || { echo "    sin runtime devolvió éxito: degradación silenciosa"; return 1; }
  grep -qi "jq" err.txt 2>/dev/null \
    || { echo "    la degradación no se DECLARA (stderr no menciona el runtime ausente)"; return 1; }
}
test_sin_runtime_el_emisor_degrada_declarandolo() { _rh_sandbox _rh_case_sin_runtime_degrada_declarandolo; }

# ── El gate de corrupción NO se traga al process-judge (AMBER-1) ────
# El camino del judge escribe process-judge_run.txt y vacía judge-queue sin
# tocar el historial de reviews jamás: una línea corrupta ahí no puede ocultar
# nada que afecte a su marker. Tragárselo significaba juicios descartados en
# silencio y session-end re-encolando la sesión para siempre.
_rh_case_judge_pasa_con_historial_corrupto() {
  mkdir -p .agents/state/markers
  printf '{"ts":"x","rota\n' > "$_RH_HIST"
  printf 'algo\n' > .agents/state/judge-queue.txt
  _rh_stop process-judge 'El proceso fue correcto.
VERDICT: GREEN
FINDINGS: 0
SCOPE: sesion abc' run-j >/dev/null
  [ -f .agents/state/markers/process-judge_run.txt ] \
    || { echo "    el historial corrupto se TRAGÓ el juicio: sin marker del judge"; return 1; }
  [ -s .agents/state/judge-queue.txt ] \
    && { echo "    la judge-queue no se vació: la sesión se re-encolará para siempre"; return 1; }
  # ...y el guard de FALSO POSITIVO del guard: un reviewer con ese mismo
  # historial corrupto SÍ sigue bloqueado sin marker.
  _rh_stop reviewer "$_RH_GREEN" run-r >/dev/null
  [ -f .agents/state/markers/reviewer_run.txt ] \
    && { echo "    FALSO POSITIVO invertido: eximir al judge eximió también al reviewer"; return 1; }
  return 0
}
test_el_historial_corrupto_no_se_traga_al_process_judge() {
  _rh_sandbox _rh_case_judge_pasa_con_historial_corrupto
}

#!/usr/bin/env bash
# Invariante nº1 del harness: EL VEREDICTO NO LO EMITE EL MODELO.
# El marker de review se deriva del mensaje final REAL del sub-agente.
# Si estos tests se relajan, el reviewer-gate vuelve a ser decorativo.
# shellcheck disable=SC1091
. "$PROJECT_ROOT/scripts/agent-hooks/lib/verdict.sh"

MSG_GREEN='Revisé el diff.

VERDICT: GREEN
FINDINGS: 0
SCOPE: gates de anillo 2'

MSG_AMBER='Hay cosas menores.
VERDICT: AMBER
FINDINGS: 3
SCOPE: refactor de io.sh'

MSG_RED='Esto no puede entrar.
VERDICT: RED
FINDINGS: 2
SCOPE: secretos en logs'

# ── happy path ──────────────────────────────────────────────────────
test_verdict_green() {
  assert_eq "GREEN" "$(verdict_parse "$MSG_GREEN")"
}

test_verdict_scope_extraido() {
  assert_eq "gates de anillo 2" "$(verdict_scope "$MSG_GREEN")"
}

test_verdict_findings_extraido() {
  assert_eq "3" "$(verdict_findings "$MSG_AMBER")"
}

# ── ramas de error / borde ──────────────────────────────────────────
test_verdict_amber_es_aceptable() {
  # AMBER permite commit (con findings atendidos); GREEN y AMBER son los únicos que marcan.
  assert_exit 0 verdict_is_markable "AMBER" || return 1
  assert_exit 0 verdict_is_markable "GREEN"
}

test_verdict_red_no_marca() {
  # RED NUNCA produce marker. Es la rama que impide que un review negativo se ignore.
  assert_exit 1 verdict_is_markable "RED"
}

test_verdict_ausente_no_marca() {
  # Sub-agente que muere o divaga sin emitir el contrato → NO hay marker.
  # Ausencia de evidencia no es evidencia de ausencia.
  assert_eq "" "$(verdict_parse 'terminé, todo bien, se ve correcto')" || return 1
  assert_exit 1 verdict_is_markable ""
}

test_verdict_texto_suelto_no_cuenta() {
  # Que el agente MENCIONE la palabra no basta: exige el contrato en su propia línea.
  assert_eq "" "$(verdict_parse 'yo diría que el verdict green estaría bien')"
}

test_verdict_ultima_linea_gana() {
  # Si el agente se autocorrige, vale el ÚLTIMO veredicto emitido, no el primero.
  local m='VERDICT: GREEN
me equivoqué, revisando de nuevo:
VERDICT: RED'
  assert_eq "RED" "$(verdict_parse "$m")"
}

test_verdict_valor_invalido_se_rechaza() {
  # Un valor fuera del enum no se interpreta como aprobación.
  assert_eq "" "$(verdict_parse 'VERDICT: PROBABLEMENTE_OK')" || return 1
  assert_exit 1 verdict_is_markable "PROBABLEMENTE_OK"
}

test_verdict_tolera_minusculas_y_espacios() {
  assert_eq "GREEN" "$(verdict_parse '   verdict:   green   ')"
}

# ════════════════════════════════════════════════════════════════════
# MODO CONTRATO — el review que ocurre ANTES de que exista el código
# ════════════════════════════════════════════════════════════════════
# Invierte el orden (patrón de harness-design de Anthropic): el evaluador
# acuerda qué es "hecho" antes de que se escriba nada, y la review final deja
# de ser exploratoria. El riesgo del mecanismo es UNO y es grave: si el
# contrato pudiera escribir marker, pedirlo desbloquearía el commit del
# código que aún no existe — el agujero exacto que el invariante nº1 tapa.
test_contrato_ready_se_reconoce() {
  local out; out="$(contract_parse 'Riesgos: capas, TDD.

CONTRACT: READY
SCOPE: historia 0005')"
  [ "$out" = "READY" ] || { echo "    CONTRACT: READY no se reconoció (obtuve '$out')"; return 1; }
}

test_contrato_no_es_veredicto() {
  # LO MÁS IMPORTANTE DE ESTE ARCHIVO: un contrato NO puede producir marker.
  local v; v="$(verdict_parse 'CONTRACT: READY
SCOPE: historia 0005')"
  [ -z "$v" ] || { echo "    un CONTRACT produjo veredicto '$v' — escribiría marker sin código"; return 1; }
  verdict_is_markable "$v" && { echo "    un contrato vacío resultó markable"; return 1; }
  return 0
}

test_veredicto_no_es_contrato() {
  # Y la simétrica: una review normal no debe leerse como contrato, o el
  # cierre saldría por la rama equivocada y no escribiría el marker legítimo.
  local c; c="$(contract_parse 'VERDICT: GREEN
FINDINGS: 0
SCOPE: x')"
  [ -z "$c" ] || { echo "    un VERDICT se leyó como contrato ('$c')"; return 1; }
}

test_contrato_mencionado_en_prosa_no_cuenta() {
  # Mismo rigor que el veredicto: solo la línea al inicio, nunca la prosa.
  local out; out="$(contract_parse 'te dejo el contract: ready cuando quieras')"
  [ -z "$out" ] || { echo "    una mención en prosa se leyó como contrato ('$out')"; return 1; }
}

# ════════════════════════════════════════════════════════════════════
# f-review-red-sin-huella — un RED tiene que dejar rastro
# ════════════════════════════════════════════════════════════════════
# Medido en un proyecto real: 36 RED, 9 AMBER y CERO GREEN en todo el
# historial, con secuencias RED→RED→GREEN sobre archivos cuyo mtime era
# ANTERIOR al primer RED — ni un byte cambió entre veredictos. La lectura
# benigna era la correcta ahí (los RED pedían registrar gaps en el ledger),
# y ese es justo el problema: el harness no podía distinguirla de un
# verdict-shopping. Con el sha del diff guardado también en RED, la diferencia
# pasa a ser mecánica.
_crv_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/.agents/state/markers"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  cp "$PROJECT_ROOT/.gitignore" "$d/.gitignore" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo seed > seed.txt; git add -A; git commit -qm init 2>/dev/null
    echo 'let x = 1' > app.swift; git add app.swift
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}
_crv() { # _crv <mensaje final del sub-agente>
  printf '{"agent_type":"reviewer","last_assistant_message":%s}' \
    "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    | bash scripts/agent-hooks/capture-review-verdict.sh >/dev/null 2>&1
}

_case_red_deja_huella() {
  _crv 'Hay problemas.
VERDICT: RED
FINDINGS: 3
SCOPE: el adapter'
  [ -f .agents/state/markers/last_red.txt ] \
    || { echo "    un RED no dejó huella del diff que juzgó"; return 1; }
  grep -q '^staged_sha: [0-9a-f]' .agents/state/markers/last_red.txt \
    || { echo "    la huella del RED no lleva el sha del diff"; return 1; }
  [ -f .agents/state/review-history.jsonl ] \
    || { echo "    el RED no entró en el historial de veredictos"; return 1; }
  [ -f .agents/state/markers/reviewer_run.txt ] \
    && { echo "    un RED escribió marker (desbloquearía el commit)"; return 1; }
  return 0
}
test_un_red_deja_huella_del_diff_juzgado() { _crv_sandbox _case_red_deja_huella; }

_case_green_sobre_el_mismo_diff_se_rechaza() {
  _crv 'VERDICT: RED
FINDINGS: 2
SCOPE: el adapter'
  _crv 'Ya está.
VERDICT: GREEN
FINDINGS: 0
SCOPE: el adapter'
  [ -f .agents/state/markers/reviewer_run.txt ] \
    && { echo "    un GREEN sobre EL MISMO diff que fue RED escribió marker (verdict-shopping)"; return 1; }
  grep -q 'RECHAZADO' .agents/state/review-history.jsonl 2>/dev/null \
    || { echo "    el rechazo no quedó registrado en el historial"; return 1; }
  return 0
}
test_green_sobre_el_mismo_diff_que_el_red_no_marca() {
  _crv_sandbox _case_green_sobre_el_mismo_diff_se_rechaza
}

_case_green_tras_arreglar_si_marca() {
  # EL GUARD QUE IMPORTA: una remediación de verdad tiene que pasar. Si esto
  # fallara habríamos cambiado un agujero por un deadlock — el reviewer no
  # podría aprobar nunca nada que hubiera sido RED alguna vez.
  _crv 'VERDICT: RED
FINDINGS: 2
SCOPE: el adapter'
  echo 'let x = 2 // arreglado' > app.swift; git add app.swift
  _crv 'Arreglado.
VERDICT: GREEN
FINDINGS: 0
SCOPE: el adapter'
  [ -f .agents/state/markers/reviewer_run.txt ] \
    || { echo "    una remediación REAL (diff distinto) no consiguió marker: deadlock"; return 1; }
}
test_green_tras_cambiar_el_codigo_si_marca() { _crv_sandbox _case_green_tras_arreglar_si_marca; }

_case_override_auditado() {
  # Para el RED que se resuelve con un argumento y no con código. Mismo patrón
  # que REVIEWER_OVERRIDE: existe, pero deja rastro.
  _crv 'VERDICT: RED
FINDINGS: 1
SCOPE: el adapter'
  printf '{"agent_type":"reviewer","last_assistant_message":"VERDICT: GREEN\\nFINDINGS: 0\\nSCOPE: el adapter"}' \
    | REVIEW_SAME_DIFF_OVERRIDE=1 REVIEW_SAME_DIFF_REASON="el RED era un malentendido" \
      bash scripts/agent-hooks/capture-review-verdict.sh >/dev/null 2>&1
  [ -f .agents/state/markers/reviewer_run.txt ] \
    || { echo "    el override no permitió marcar"; return 1; }
  grep -q 'same-diff-override' .agents/state/markers/override_log.txt 2>/dev/null \
    || { echo "    el override NO quedó auditado"; return 1; }
}
test_el_override_de_mismo_diff_queda_auditado() { _crv_sandbox _case_override_auditado; }

# ════════════════════════════════════════════════════════════════════
# EL REPORTE, no solo el veredicto (f-review-sin-reporte-persistido)
# ════════════════════════════════════════════════════════════════════
# El sistema guardaba QUÉ decidió el review y perdía QUÉ dijo. Medido en un
# adoptante: los hallazgos de un design-review y de tres pasadas del reviewer
# solo existían en el transcript del sub-agente, y hubo que parsearlo a mano
# cuatro veces. El propio design-reviewer, al re-revisar, tuvo que reconstruir
# sus 15 hallazgos por inferencia y avisó de que uno absorbido borrando la
# sección le sería invisible. El marker probaba QUE hubo review; nada probaba
# QUÉ dijo, ni permitía comprobar en la siguiente pasada si se atendió.
_REVIEW_RED='Encontré esto:
1. La precondición de `cargar()` no valida el id vacío.
2. El fake no pasa la suite de conformidad del adapter real.

VERDICT: RED
FINDINGS: 2
SCOPE: MovieRepository y su fake'

_case_el_red_guarda_su_reporte() {
  printf '{"hook_event_name":"SubagentStop","agent_type":"reviewer","last_assistant_message":%s}' \
    "$(printf '%s' "$_REVIEW_RED" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    | bash scripts/agent-hooks/capture-review-verdict.sh >/dev/null 2>&1
  local r; r="$(ls .agents/state/reviews/*-reviewer.md 2>/dev/null | head -1)"
  [ -n "$r" ] || { echo "    un RED no dejó reporte en .agents/state/reviews/"; return 1; }
  grep -q 'suite de conformidad' "$r" \
    || { echo "    el reporte no contiene el CUERPO del review, solo la cabecera"; return 1; }
  grep -q '^staged_sha: ' "$r" \
    || { echo "    el reporte no liga el diff que se juzgó"; return 1; }
  [ -f .agents/state/markers/reviewer_run.txt ] \
    && { echo "    ¡un RED escribió marker! guardar el reporte no puede desbloquear"; return 1; }
  return 0
}
test_un_red_persiste_el_cuerpo_del_review_no_solo_el_veredicto() {
  _crv_sandbox _case_el_red_guarda_su_reporte
}

_msg() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'; }
_stop() { # _stop <agente> <mensaje> [agent_id]
  printf '{"hook_event_name":"SubagentStop","agent_type":"%s","agent_id":"%s","last_assistant_message":%s}' \
    "$1" "${3:-}" "$(_msg "$2")" | bash scripts/agent-hooks/capture-review-verdict.sh 2>&1
}
_hist_n() { grep -c . .agents/state/review-history.jsonl 2>/dev/null || echo 0; }

# ════════════════════════════════════════════════════════════════════
# EL BUCLE (f-b3cf4f74) — un stop que reinyecta contexto se retroalimenta
# ════════════════════════════════════════════════════════════════════
# Este hook corre en SubagentStop y lo que emite VUELVE AL SUB-AGENTE, que
# responde; esa respuesta es otro SubagentStop. Medido en un adoptante sobre un
# diff de UNA línea: 11 disparos en una corrida y 12 en la siguiente, 35.256 y
# 67.427 tokens. Y el daño caro no era el coste: lo que recibe quien invoca al
# sub-agente es su ÚLTIMO mensaje, o sea la cola del bucle, nunca el review.
#
# ⚠️ El arreglo NO puede ser "escribe solo en el stop final": el hook no puede
# distinguir el final del intermedio, porque todos son SubagentStop. Es
# IDEMPOTENCIA. Este test es la prueba de bolsillo del §5: si se rompe el fix,
# vuelve a once.
_case_once_disparos_una_entrada() {
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11; do _stop reviewer "$_REVIEW_RED" >/dev/null; done
  local n; n="$(grep -c . .agents/state/review-history.jsonl 2>/dev/null || echo 0)"
  [ "$n" = "1" ] || {
    echo "    11 disparos del hook dejaron $n entradas en review-history.jsonl (esperaba 1)"
    echo "    Cada entrada de más es una vuelta de bucle: coste, y el retorno al"
    echo "    llamador sustituido por la cola del bucle en vez del review."
    return 1; }
}
test_once_disparos_del_mismo_veredicto_dejan_una_sola_entrada() {
  _crv_sandbox _case_once_disparos_una_entrada
}

_case_el_exito_no_reinyecta_contexto() {
  # La causa raíz: cualquier salida en el camino de éxito vuelve al sub-agente y
  # le hace responder. Sin `additionalContext` no hay a qué responder.
  local out; out="$(_stop reviewer 'Todo correcto.

VERDICT: GREEN
FINDINGS: 0
SCOPE: nada que objetar')"
  case "$out" in *additionalContext*)
    echo "    el camino de éxito reinyecta contexto: el sub-agente responderá y volverá a disparar"
    printf '%s\n' "$out" | head -3 | sed 's/^/      /'; return 1 ;; esac
  [ -f .agents/state/markers/reviewer_run.txt ] \
    || { echo "    dejó de reinyectar contexto pero también dejó de escribir el marker"; return 1; }
}
test_el_camino_de_exito_no_reinyecta_contexto_al_subagente() {
  _crv_sandbox _case_el_exito_no_reinyecta_contexto
}

_case_stop_sin_veredicto_tras_uno_con_veredicto_no_bloquea() {
  # Los mensajes [1]-[6] de la secuencia medida: el agente contestando al
  # recordatorio ("Confirmado", "No hay nada nuevo que revisar") y el hook
  # exigiéndole el contrato otra vez. Si ya emitió veredicto sobre este diff,
  # un stop posterior sin veredicto es el agente terminando de hablar.
  _stop reviewer "$_REVIEW_RED" >/dev/null
  local out; out="$(_stop reviewer 'Confirmado, sin cambios.')"
  case "$out" in *'"decision":"block"'*)
    echo "    volvió a exigir el contrato a un agente que YA emitió su veredicto"
    return 1 ;; esac
}
test_un_stop_sin_veredicto_no_reabre_la_jaula() {
  _crv_sandbox _case_stop_sin_veredicto_tras_uno_con_veredicto_no_bloquea
}

# ── El primer stop SIN veredicto sí tiene que exigir el contrato ────
# Guard de FP del arreglo de arriba: acotar la jaula no puede convertirse en
# borrarla. Un review que termina sin veredicto y nunca lo emitió sigue teniendo
# que oírlo — es el único mecanismo que hace que el contrato exista.
_case_el_primer_stop_sin_veredicto_si_bloquea() {
  local out; out="$(_stop reviewer 'He mirado el diff y me parece bien.')"
  case "$out" in *'"decision":"block"'*) return 0 ;; esac
  echo "    un review sin veredicto NO recibió la exigencia del contrato"
  return 1
}
test_el_primer_review_sin_veredicto_sigue_recibiendo_el_contrato() {
  _crv_sandbox _case_el_primer_stop_sin_veredicto_si_bloquea
}

# ── El reporte ANEXA: la última vuelta no puede pisar a la primera ──
# Medido: 3184 chars el primer mensaje, 165 los que quedaban en disco, y
# coincidían con el ÚLTIMO. El nombre del archivo no varía entre vueltas, así
# que `>` truncaba y los hallazgos se perdían enteros.
_case_el_reporte_no_pierde_el_primer_cuerpo() {
  # MISMO agente sobre el MISMO diff: es el único caso que comparte nombre de
  # archivo, y por tanto el único donde `>` destruye. Con dos agentes distintos
  # el truncado no se reproduce —cada uno escribe el suyo— y el test pasaría
  # contra la versión rota, que es un test que no prueba nada.
  _stop reviewer "$_REVIEW_RED" >/dev/null
  _stop reviewer 'Ya está atendido.

VERDICT: GREEN
FINDINGS: 0
SCOPE: MovieRepository y su fake' >/dev/null
  local r; r="$(ls .agents/state/reviews/*-reviewer.md 2>/dev/null | head -1)"
  [ -n "$r" ] || { echo "    no hay reporte"; return 1; }
  grep -q 'suite de conformidad' "$r" \
    || { echo "    el cuerpo del PRIMER review desapareció: la segunda vuelta lo pisó"; return 1; }
  grep -q 'Ya está atendido' "$r" \
    || { echo "    la segunda vuelta no quedó registrada"; return 1; }
}
test_una_segunda_vuelta_no_borra_los_hallazgos_de_la_primera() {
  _crv_sandbox _case_el_reporte_no_pierde_el_primer_cuerpo
}

_case_el_previo_se_encuentra_via_historia() {
  # El glob de `reviews/` NUNCA encontraba nada: el nombre del reporte no varía
  # entre vueltas del mismo agente sobre el mismo diff, y se excluía a sí mismo
  # por nombre exacto. La historia SÍ acumula, así que es la fuente correcta.
  _stop design-reviewer "$_REVIEW_RED" >/dev/null
  _stop reviewer "$_REVIEW_RED" >/dev/null
  grep -rq '^previo: ' .agents/state/reviews/ \
    || { echo "    el segundo review no apuntó al anterior sobre el mismo diff"; return 1; }
  grep -rq '^comparar: ' .agents/state/reviews/ \
    || { echo "    apuntó al previo pero no dijo qué hacer con él"; return 1; }
}
test_el_segundo_review_del_mismo_diff_apunta_al_anterior() {
  _crv_sandbox _case_el_previo_se_encuentra_via_historia
}

# ── FALSO POSITIVO: un reporte no puede anunciarse cuando no lo hay ──
# El aviso "ya hubo un review sobre este mismo diff" tiene que aparecer SOLO
# cuando existe. Anunciarlo siempre mandaría a leer un archivo inexistente en
# la primera review de cada diff — ruido en el caso más común de todos.
_case_la_primera_review_no_anuncia_un_previo() {
  _stop reviewer "$_REVIEW_RED" >/dev/null
  grep -rq '^previo: ' .agents/state/reviews/ 2>/dev/null \
    && { echo "    la PRIMERA review anunció un reporte anterior que no existe"; return 1; }
  return 0
}
test_la_primera_review_de_un_diff_no_inventa_un_previo() {
  _crv_sandbox _case_la_primera_review_no_anuncia_un_previo
}

# ════════════════════════════════════════════════════════════════════
# EL PEAJE DE LA IDEMPOTENCIA (f-a8bcb235)
# ════════════════════════════════════════════════════════════════════
# Deduplicar por (agente, diff, veredicto) corta el bucle, pero también descarta
# una segunda review DELIBERADA sobre el mismo diff. Medido en un adoptante: la
# re-review fue genuinamente distinta —8 tool_uses, y encontró algo que la
# primera no vio— y desapareció entera: Δ=0 en la historia, cero rastro.
# El discriminador es la IDENTIDAD DE LA INVOCACIÓN, no el tiempo: las vueltas de
# un bucle son el mismo sub-agente hablando y comparten `agent_id`.
_case_dos_invocaciones_distintas_se_registran() {
  _stop reviewer "$_REVIEW_RED" run-1 >/dev/null
  _stop reviewer "$_REVIEW_RED" run-2 >/dev/null
  local n; n="$(_hist_n)"
  [ "$n" = "2" ] || {
    echo "    dos invocaciones DELIBERADAS dejaron $n entradas (esperaba 2)"
    echo "    Una re-review sobre el mismo diff no es una vuelta de bucle: es"
    echo "    trabajo que alguien pidió, y descartarla la borra sin dejar rastro."
    return 1; }
}
test_una_re_review_deliberada_no_se_descarta_como_bucle() {
  _crv_sandbox _case_dos_invocaciones_distintas_se_registran
}

# ── …y dentro de UNA invocación se sigue deduplicando ───────────────
# El guard de FP del arreglo de arriba: distinguir invocaciones no puede
# convertirse en dejar de cortar el bucle, que era el problema caro.
_case_una_invocacion_en_bucle_sigue_deduplicando() {
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11; do _stop reviewer "$_REVIEW_RED" run-unico >/dev/null; done
  local n; n="$(_hist_n)"
  [ "$n" = "1" ] || { echo "    11 vueltas de la MISMA invocación dejaron $n entradas (esperaba 1)"; return 1; }
}
test_las_vueltas_de_una_misma_invocacion_siguen_colapsando() {
  _crv_sandbox _case_una_invocacion_en_bucle_sigue_deduplicando
}

# ── Sin `agent_id` se cae al criterio viejo, no al bucle ────────────
# Los adaptadores de Cursor/Codex pueden no mandarlo. Se falla hacia el lado en
# que el harness sigue siendo barato: se pierde el peaje, no el corte.
_case_sin_agent_id_sigue_cortando_el_bucle() {
  local i
  for i in 1 2 3 4 5; do _stop reviewer "$_REVIEW_RED" >/dev/null; done
  local n; n="$(_hist_n)"
  [ "$n" = "1" ] || { echo "    sin agent_id, 5 disparos dejaron $n entradas (esperaba 1)"; return 1; }
}
test_sin_agent_id_el_bucle_se_sigue_cortando() {
  _crv_sandbox _case_sin_agent_id_sigue_cortando_el_bucle
}

# ── Los dos casos que el adoptante no pudo verificar ────────────────
# Pidió explícitamente cubrirlos: agente DISTINTO sobre el mismo diff, y
# veredicto DISTINTO (GREEN tras RED, que además tiene su propio camino de
# rechazo). Si el puntero aparece ahí, el mecanismo está bien y el caso que él
# vio era el degenerado.
_case_puntero_con_agente_distinto() {
  _stop reviewer "$_REVIEW_RED" run-1 >/dev/null
  _stop security-reviewer "$_REVIEW_RED" run-2 >/dev/null
  grep -rq '^previo: ' .agents/state/reviews/ \
    || { echo "    un agente DISTINTO sobre el mismo diff no recibió el puntero al previo"; return 1; }
}
test_el_puntero_aparece_con_otro_agente_sobre_el_mismo_diff() {
  _crv_sandbox _case_puntero_con_agente_distinto
}

_case_puntero_con_veredicto_distinto() {
  _stop reviewer "$_REVIEW_RED" run-1 >/dev/null
  _stop reviewer 'Ya está.

VERDICT: GREEN
FINDINGS: 0
SCOPE: MovieRepository y su fake' run-2 >/dev/null
  grep -rq '^previo: ' .agents/state/reviews/ \
    || { echo "    un GREEN tras RED sobre el mismo diff no recibió el puntero al previo"; return 1; }
  [ -f .agents/state/markers/reviewer_run.txt ] \
    && { echo "    ¡el GREEN sobre el mismo diff que el RED escribió marker!"; return 1; }
  return 0
}
test_el_puntero_aparece_con_veredicto_distinto_y_el_rechazo_sigue_vivo() {
  _crv_sandbox _case_puntero_con_veredicto_distinto
}

# ── El último tramo: que alguien MIRE el reporte previo ─────────────
# El puntero al review anterior vive dentro del reporte, y a un sub-agente nuevo
# nadie se lo inyecta: el hook actúa al TERMINAR una ejecución, no al arrancar la
# siguiente. Inyectarlo al arrancar es justo lo que produjo el bucle de 11
# vueltas, así que la instrucción va donde no puede rebotar: el prompt del rol.
# Estático, no runtime. Este test existe porque una instrucción que se borra sin
# que nada falle vuelve a dejar el reporte escribiéndose para nadie.
test_el_prompt_del_reviewer_manda_leer_el_reporte_previo() {
  local f="$PROJECT_ROOT/tools/agent-prompts/review.md"
  [ -f "$f" ] || { echo "    falta tools/agent-prompts/review.md"; return 1; }
  grep -q '\.agents/state/reviews/' "$f" \
    || { echo "    el prompt del reviewer no le dice que mire .agents/state/reviews/"; return 1; }
  grep -qi 'hallazgo por hallazgo' "$f" \
    || { echo "    le dice dónde mirar pero no qué hacer con lo que encuentre"; return 1; }
}

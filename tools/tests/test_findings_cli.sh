#!/usr/bin/env bash
# CLI portable del ledger (findings.sh, shell+python3) + eventos de detección.
#
# Por qué existe: findings.ts exige Deno/Node y esta máquina no los tiene → el
# ledger era INOPERABLE localmente, y por eso 9 findings llevaban días en un
# pending-import.json. Un inventario al que no se puede escribir no es un
# inventario: es un archivo.
#
# Invariante heredado de findings.ts que estos tests fijan: add/import NUNCA
# resucitan un estado terminal (fixed/accepted/wontfix/duplicate).

_fcli_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/findings" "$d/docs/process" "$d/scripts/agent-hooks/lib"
  cp "$PROJECT_ROOT/tools/findings/findings.sh" "$d/tools/findings/" 2>/dev/null
  cp "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh" "$d/scripts/agent-hooks/lib/" 2>/dev/null
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}
_cli() { bash tools/findings/findings.sh "$@"; }

# ── add / list ──────────────────────────────────────────────────────
_case_add_y_list() {
  _cli add --id f-t1 --title "Algo roto" --area "src/x.sh" --severity low --tier auto-fix --source test >/dev/null 2>&1 \
    || { echo "    add falló"; return 1; }
  grep -q '"id": *"f-t1"' tools/findings/ledger.jsonl 2>/dev/null || grep -q '"id":"f-t1"' tools/findings/ledger.jsonl \
    || { echo "    el finding no quedó en el ledger"; return 1; }
  _cli list --status open 2>/dev/null | grep -q "f-t1" || { echo "    list --status open no lo muestra"; return 1; }
}
test_add_escribe_y_list_muestra() { _fcli_sandbox _case_add_y_list; }

_case_add_sin_id_genera_hash() {
  _cli add --title "Sin id" --area "a/b" --source test >/dev/null 2>&1
  grep -q '"id": *"f-' tools/findings/ledger.jsonl || grep -q '"id":"f-' tools/findings/ledger.jsonl \
    || { echo "    no generó id con prefijo f-"; return 1; }
}
test_add_sin_id_genera_uno() { _fcli_sandbox _case_add_sin_id_genera_hash; }

# ── close ───────────────────────────────────────────────────────────
_case_close() {
  _cli add --id f-t2 --title "Cerrable" --area x --source test >/dev/null 2>&1
  _cli close f-t2 --resolution "arreglado en test" >/dev/null 2>&1 || { echo "    close falló"; return 1; }
  grep -q '"status": *"fixed"' tools/findings/ledger.jsonl || grep -q '"status":"fixed"' tools/findings/ledger.jsonl \
    || { echo "    close no marcó fixed"; return 1; }
  _cli list --status open 2>/dev/null | grep -q "f-t2" && { echo "    sigue apareciendo como open"; return 1; }
  return 0
}
test_close_marca_fixed() { _fcli_sandbox _case_close; }

# ── EL INVARIANTE: un estado terminal no resucita ───────────────────
_case_terminal_no_resucita() {
  _cli add --id f-t3 --title "Ya resuelto" --area x --source test >/dev/null 2>&1
  _cli close f-t3 --resolution done >/dev/null 2>&1
  # Un gate lo re-detecta (o un import viejo vuelve a llegar):
  _cli add --id f-t3 --title "Ya resuelto" --area x --source otro-gate >/dev/null 2>&1
  local n_open; n_open="$(_cli list --status open 2>/dev/null | grep -c f-t3 || true)"
  [ "${n_open:-0}" = "0" ] || { echo "    un add RESUCITÓ un finding cerrado"; return 1; }
  grep -q '"status": *"fixed"' tools/findings/ledger.jsonl || grep -q '"status":"fixed"' tools/findings/ledger.jsonl \
    || { echo "    el estado terminal se perdió"; return 1; }
}
test_add_no_resucita_estado_terminal() { _fcli_sandbox _case_terminal_no_resucita; }

# ── import: idempotente ─────────────────────────────────────────────
_case_import_idempotente() {
  cat > batch.json <<'EOF'
[{"id":"f-i1","title":"Uno","area":"a","severity":"low","tier":"owner-decision","status":"open","source":"t","detail":"d","effort":"S","links":[]},
 {"id":"f-i2","title":"Dos","area":"b","severity":"high","tier":"auto-fix","status":"fixed","source":"t","detail":"d","resolution":"ya","effort":"S","links":[]}]
EOF
  _cli import batch.json >/dev/null 2>&1 || { echo "    import falló"; return 1; }
  _cli import batch.json >/dev/null 2>&1
  local total; total="$(wc -l < tools/findings/ledger.jsonl | tr -d ' ')"
  [ "$total" = "2" ] || { echo "    import repetido duplicó entradas (total=$total, esperaba 2)"; return 1; }
  # El que venía fixed se importa fixed (no se abre).
  _cli list --status open 2>/dev/null | grep -q f-i2 && { echo "    un import abrió un finding que venía fixed"; return 1; }
  return 0
}
test_import_es_idempotente_y_respeta_estados() { _fcli_sandbox _case_import_idempotente; }

# ── promoción explícita: evento local → finding durable ───────────
_case_add_promueve_evento_sin_reescribirlo() {
  # shellcheck disable=SC1091
  . scripts/agent-hooks/lib/io.sh
  DETECTION_DEDUP_WINDOW=0 PROJECT_ROOT="$(pwd)" \
    hook_log_detection "semgrep" "regla-x" "src/x.swift" 1
  local log=".agents/state/metrics/detections.jsonl" event_id before after
  event_id="$(python3 -c 'import json,sys; print(json.loads(open(sys.argv[1], encoding="utf-8").readline())["event_id"])' "$log")"
  before="$(cksum < "$log")"

  _cli add --id f-linked --title "Promovido" --area src/x.swift \
    --source semgrep --source-event "$event_id" --source-event "$event_id" >/dev/null 2>&1 \
    || { echo "    add --source-event falló"; return 1; }
  after="$(cksum < "$log")"

  [ "$before" = "$after" ] || { echo "    promover el evento reescribió detections.jsonl"; return 1; }
  python3 - <<'PY'
import json
item = json.loads(open("tools/findings/ledger.jsonl", encoding="utf-8").readline())
assert item["source_event_ids"] == [json.loads(open(".agents/state/metrics/detections.jsonl", encoding="utf-8").readline())["event_id"]]
assert "triage" not in item
PY
}
test_add_source_event_promueve_sin_reescribir_evento() {
  _fcli_sandbox _case_add_promueve_evento_sin_reescribirlo
}

_case_import_fusiona_source_events() {
  printf '%s\n' '[{"id":"f-i","title":"Importado","area":"a","source":"reviewer","source_event_ids":["evt-a"]}]' > batch.json
  _cli import batch.json --source-event evt-b --source-event evt-a >/dev/null 2>&1 \
    || { echo "    import --source-event falló"; return 1; }
  printf '%s\n' '[{"id":"f-i","title":"Importado","area":"a","source":"reviewer","source_event_ids":["evt-c"]}]' > batch.json
  _cli import batch.json --source-event evt-b >/dev/null 2>&1
  python3 - <<'PY'
import json
item = json.loads(open("tools/findings/ledger.jsonl", encoding="utf-8").readline())
assert item["source_event_ids"] == ["evt-a", "evt-b", "evt-c"]
PY
}
test_import_source_event_fusiona_ids_sin_duplicarlos() {
  _fcli_sandbox _case_import_fusiona_source_events
}

_case_source_event_sin_valor_falla() {
  bash tools/findings/findings.sh add --id f-bad --title Malo --area a \
    --source-event >/dev/null 2>&1
  [ "$?" = "2" ] || { echo "    add aceptó --source-event sin valor"; return 1; }
  [ ! -s tools/findings/ledger.jsonl ] \
    || { echo "    add inválido igualmente escribió el ledger"; return 1; }

  bash tools/findings/findings.sh add --id f-empty --title Vacío --area a \
    --source-event '' >/dev/null 2>&1
  [ "$?" = "2" ] || { echo "    add aceptó --source-event con valor vacío"; return 1; }
  [ ! -s tools/findings/ledger.jsonl ] \
    || { echo "    add con valor vacío igualmente escribió el ledger"; return 1; }

  printf '%s\n' '[{"id":"f-import","title":"Importado","area":"a"}]' > batch.json
  bash tools/findings/findings.sh import batch.json --source-event >/dev/null 2>&1
  [ "$?" = "2" ] || { echo "    import aceptó --source-event sin valor"; return 1; }
  [ ! -s tools/findings/ledger.jsonl ] \
    || { echo "    import inválido igualmente escribió el ledger"; return 1; }
  bash tools/findings/findings.sh import batch.json --source-event '' >/dev/null 2>&1
  [ "$?" = "2" ] || { echo "    import aceptó --source-event con valor vacío"; return 1; }
  [ ! -s tools/findings/ledger.jsonl ] \
    || { echo "    import con valor vacío igualmente escribió el ledger"; return 1; }
}
test_source_event_explicito_sin_valor_falla_sin_escribir() {
  _fcli_sandbox _case_source_event_sin_valor_falla
}

# ── render: la vista se regenera y avisa de no editarla ─────────────
_case_render() {
  _cli add --id f-t4 --title "Visible" --area x --severity high --tier owner-decision --source test >/dev/null 2>&1
  _cli render >/dev/null 2>&1 || { echo "    render falló"; return 1; }
  [ -f docs/process/findings-ledger.md ] || { echo "    no generó la vista"; return 1; }
  grep -q "f-t4" docs/process/findings-ledger.md || { echo "    la vista no incluye el finding"; return 1; }
  grep -qi "no editar" docs/process/findings-ledger.md || { echo "    la vista no avisa de que es generada"; return 1; }
}
test_render_genera_la_vista() { _fcli_sandbox _case_render; }

# ── eventos de detección (hook_log_detection) ───────────────────────
_case_evento_se_appendea() {
  # shellcheck disable=SC1091
  . scripts/agent-hooks/lib/io.sh
  PROJECT_ROOT="$(pwd)" hook_log_detection "canon-enforce" "secreto" "src/x.swift" 2 || { echo "    log_detection devolvió error"; return 1; }
  local f=".agents/state/metrics/detections.jsonl"
  [ -f "$f" ] || { echo "    no creó el archivo de eventos"; return 1; }
  grep -q '"source": *"canon-enforce"' "$f" || grep -q '"source":"canon-enforce"' "$f" \
    || { echo "    el evento no registró el source"; return 1; }
}
test_evento_de_deteccion_se_registra() { _fcli_sandbox _case_evento_se_appendea; }

_case_evento_v2_tiene_contrato_explicito() {
  # shellcheck disable=SC1091
  . scripts/agent-hooks/lib/io.sh
  DETECTION_DEDUP_WINDOW=0 PROJECT_ROOT="$(pwd)" \
    hook_log_detection "canon-enforce" "secreto" "src/x.swift" 2
  DETECTION_DEDUP_WINDOW=0 PROJECT_ROOT="$(pwd)" \
    hook_log_detection "reviewer" "verdict-AMBER" "src/y.swift" 1 37 review
  python3 - <<'PY'
import json
events = [json.loads(line) for line in open(".agents/state/metrics/detections.jsonl", encoding="utf-8")]
assert len(events) == 2
gate, review = events
assert gate["schema"] == 2
assert gate["event_id"].startswith("evt-")
assert gate["ts"] and gate["commit"]
assert gate["phase"] == "gate"
assert gate["duration_ms"] is None
assert gate["triage"] == "unknown"
assert gate["source"] == "canon-enforce" and gate["n"] == 2
assert review["phase"] == "review" and review["duration_ms"] == 37
assert review["event_id"] != gate["event_id"]
PY
}
test_evento_v2_declara_identidad_fase_duracion_commit_y_triage() {
  _fcli_sandbox _case_evento_v2_tiene_contrato_explicito
}

_case_evento_v2_numeros_son_json_canonico() {
  # shellcheck disable=SC1091
  . scripts/agent-hooks/lib/io.sh
  DETECTION_DEDUP_WINDOW=0 PROJECT_ROOT="$(pwd)" \
    hook_log_detection "semgrep" "x" "a" 01 08 gate
  python3 - <<'PY'
import json
event = json.loads(open(".agents/state/metrics/detections.jsonl", encoding="utf-8").readline())
assert event["n"] == 1
assert event["duration_ms"] == 8
PY
}
test_evento_v2_normaliza_ceros_iniciales_a_json_valido() {
  _fcli_sandbox _case_evento_v2_numeros_son_json_canonico
}

_case_evento_v2_escapa_controles_json() {
  # shellcheck disable=SC1091
  . scripts/agent-hooks/lib/io.sh
  DETECTION_DEDUP_WINDOW=0 PROJECT_ROOT="$(pwd)" \
    hook_log_detection $'sem\bgrep' $'control\fchar' $'src/vertical\vtab' 1
  python3 - <<'PY'
import json
event = json.loads(open(".agents/state/metrics/detections.jsonl", encoding="utf-8").readline())
assert event["source"] == "sem grep"
assert event["rule"] == "control char"
assert event["area"] == "src/vertical tab"
PY
}
test_evento_v2_reemplaza_todos_los_controles_que_invalidan_json() {
  _fcli_sandbox _case_evento_v2_escapa_controles_json
}

_case_evento_sin_head_declara_unknown() {
  # shellcheck disable=SC1091
  . scripts/agent-hooks/lib/io.sh
  PROJECT_ROOT="$(pwd)" hook_log_detection "semgrep" "x" "a" 1
  python3 - <<'PY'
import json
event = json.loads(open(".agents/state/metrics/detections.jsonl", encoding="utf-8").readline())
assert event["commit"] == "unknown", event["commit"]
PY
}
test_evento_v2_repo_sin_head_usa_unknown_sin_stdout_residual() {
  _fcli_sandbox _case_evento_sin_head_declara_unknown
}

_case_dedup_distingue_fase_y_commit() {
  # shellcheck disable=SC1091
  . scripts/agent-hooks/lib/io.sh
  git config user.email t@t.t; git config user.name t
  printf one > tracked; git add tracked; git commit -qm one
  PROJECT_ROOT="$(pwd)" hook_log_detection "semgrep" "x" "a" 1 "" gate
  PROJECT_ROOT="$(pwd)" hook_log_detection "semgrep" "x" "a" 1 "" ci
  printf two >> tracked; git add tracked; git commit -qm two
  PROJECT_ROOT="$(pwd)" hook_log_detection "semgrep" "x" "a" 1 "" gate
  python3 - <<'PY'
import json
events = [json.loads(line) for line in open(".agents/state/metrics/detections.jsonl", encoding="utf-8")]
assert len(events) == 3, events
assert [event["phase"] for event in events] == ["gate", "ci", "gate"]
assert events[0]["commit"] != events[2]["commit"]
PY
}
test_anti_rafaga_no_colapsa_fases_ni_commits_distintos() {
  _fcli_sandbox _case_dedup_distingue_fase_y_commit
}

_case_evento_jamas_rompe() {
  # FALSO POSITIVO del peor tipo posible: la TELEMETRÍA rompiendo un GATE.
  # Sin python3 en el PATH, log_detection debe seguir devolviendo 0.
  # shellcheck disable=SC1091
  . scripts/agent-hooks/lib/io.sh
  PATH="/nonexistent" PROJECT_ROOT="$(pwd)" hook_log_detection "x" "y" "z" 1
  [ "$?" = "0" ] || { echo "    la telemetría rota devolvió error (rompería el gate que la llama)"; return 1; }
}
test_telemetria_rota_jamas_rompe_al_gate() { _fcli_sandbox _case_evento_jamas_rompe; }

# ── Anti-ráfaga: 10 disparos del MISMO evento no son 10 detecciones ──
# Observado en vivo: SubagentStop se disparó 8-10 veces por el mismo
# veredicto y el log guardó diez líneas idénticas. escape-rate CUENTA estos
# eventos para medir contención por fase, así que una ráfaga le inventa
# nueve detecciones y sesga la única métrica que dice si el harness sirve.
_case_rafaga_se_deduplica() {
  # shellcheck disable=SC1091
  . scripts/agent-hooks/lib/io.sh
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    PROJECT_ROOT="$(pwd)" hook_log_detection "reviewer" "verdict-RED" "el mismo scope" 2
  done
  local c; c="$(grep -c 'verdict-RED' .agents/state/metrics/detections.jsonl 2>/dev/null || echo 0)"
  [ "$c" = "1" ] || { echo "    una ráfaga de 10 eventos idénticos registró $c líneas (esperaba 1)"; return 1; }
}
test_rafaga_del_mismo_evento_cuenta_una_vez() { _fcli_sandbox _case_rafaga_se_deduplica; }

_case_eventos_distintos_no_se_pisan() {
  # FALSO POSITIVO del dedup: si la ventana tragara eventos DISTINTOS,
  # apagaríamos la telemetría entera para "arreglar" el ruido. Dos
  # detecciones diferentes seguidas deben registrarse las dos.
  # shellcheck disable=SC1091
  . scripts/agent-hooks/lib/io.sh
  PROJECT_ROOT="$(pwd)" hook_log_detection "semgrep" "hallazgo" "a.swift" 1
  PROJECT_ROOT="$(pwd)" hook_log_detection "check-layers" "violacion" "b.swift" 3
  PROJECT_ROOT="$(pwd)" hook_log_detection "semgrep" "hallazgo" "a.swift" 2
  local c; c="$(grep -c . .agents/state/metrics/detections.jsonl 2>/dev/null || echo 0)"
  [ "$c" = "3" ] || { echo "    3 eventos DISTINTOS registraron $c líneas (el dedup se está comiendo señal)"; return 1; }
}
test_eventos_distintos_seguidos_se_registran_todos() { _fcli_sandbox _case_eventos_distintos_no_se_pisan; }

_case_repeticion_legitima_fuera_de_ventana() {
  # El mismo evento MÁS TARDE sí es una detección nueva (el agente volvió a
  # tropezar). Ventana configurable para poder probarlo sin dormir 2 min.
  # shellcheck disable=SC1091
  . scripts/agent-hooks/lib/io.sh
  DETECTION_DEDUP_WINDOW=0 PROJECT_ROOT="$(pwd)" hook_log_detection "drift" "sube" "x" 1
  DETECTION_DEDUP_WINDOW=0 PROJECT_ROOT="$(pwd)" hook_log_detection "drift" "sube" "x" 1
  local c; c="$(grep -c '"source":"drift"' .agents/state/metrics/detections.jsonl 2>/dev/null || echo 0)"
  [ "$c" = "2" ] || { echo "    con ventana 0 el evento repetido registró $c líneas (esperaba 2)"; return 1; }
}
test_repeticion_fuera_de_ventana_si_cuenta() { _fcli_sandbox _case_repeticion_legitima_fuera_de_ventana; }

# ── formato byte-idéntico entre emisores (L-json-espacios) ──────────
# El bug real: findings.sh (python, json.dumps con espacios) y los greps de
# los hooks ('"status":"open"', sin espacio) → "findings abiertos: 0" SIEMPRE,
# en silencio. Regla doble: el emisor escribe compacto Y los consumidores son
# tolerantes. Este test fija la mitad del emisor.
_case_formato_compacto() {
  _cli add --id f-fmt --title "Formato" --area x --source test >/dev/null 2>&1
  grep -q '"status":"open"' tools/findings/ledger.jsonl \
    || { echo "    el ledger no se escribe en formato compacto (sin espacios): $(head -1 tools/findings/ledger.jsonl)"; return 1; }
}
test_ledger_se_escribe_compacto() { _fcli_sandbox _case_formato_compacto; }

# …y la mitad de los consumidores: el grep tolerante de los hooks debe contar
# abiertos en AMBOS formatos (ledgers viejos con espacio incluidos).
_case_grep_tolerante() {
  mkdir -p tools/findings
  printf '{"id":"a","status":"open"}\n{"id": "b", "status": "open"}\n' > tools/findings/ledger.jsonl
  local n; n="$(grep -cE '"status": ?"open"' tools/findings/ledger.jsonl || true)"
  [ "$n" = "2" ] || { echo "    el grep tolerante contó $n de 2 abiertos"; return 1; }
}
test_grep_tolerante_cuenta_ambos_formatos() { _fcli_sandbox _case_grep_tolerante; }

# ════════════════════════════════════════════════════════════════════
# El CLI del ledger es la fuente de accountability: no puede ensuciarse
# ════════════════════════════════════════════════════════════════════
# Tres defectos que mordieron DOS VECES en el mismo proyecto real y que
# obligaron a editar el .jsonl a mano — justo lo que un archivo generado no
# debería necesitar nunca.
_case_help_no_ensucia() {
  # El peor de los tres: `add --help` interpretaba "--help" como flags de un
  # alta y escribía un hallazgo BASURA. Pedirle AYUDA al CLI corrompía la
  # fuente de verdad. Fail-open en su forma más traicionera: el daño lo hace
  # la operación que el humano creía inofensiva.
  bash tools/findings/findings.sh add --help >/dev/null 2>&1
  local n; n="$(grep -c . tools/findings/ledger.jsonl 2>/dev/null || echo 0)"
  [ "$n" = "0" ] || { echo "    'add --help' escribió $n entrada(s) en el ledger"; return 1; }
}
test_add_help_no_crea_hallazgo_basura() { _fcli_sandbox _case_help_no_ensucia; }

_case_add_exige_lo_minimo() {
  # Una entrada sin título ni área no es un hallazgo: es ruido que alguien
  # tendrá que limpiar. Mejor fallar que inventar defaults.
  bash tools/findings/findings.sh add --detail "algo" >/dev/null 2>&1
  [ "$?" = "2" ] || { echo "    un add sin --title/--area fue aceptado"; return 1; }
  local n; n="$(grep -c . tools/findings/ledger.jsonl 2>/dev/null || echo 0)"
  [ "$n" = "0" ] || { echo "    el add inválido igualmente escribió al ledger"; return 1; }
}
test_add_sin_titulo_ni_area_falla_ruidoso() { _fcli_sandbox _case_add_exige_lo_minimo; }

_case_add_duplicado_no_pisa_en_silencio() {
  # `add` con un id existente conservaba el title viejo: corregir un título
  # fallaba EN SILENCIO y el humano acababa editando el JSONL a mano.
  bash tools/findings/findings.sh add --id f-x --title "original" --area a >/dev/null 2>&1
  bash tools/findings/findings.sh add --id f-x --title "corregido" --area a >/dev/null 2>&1
  [ "$?" = "2" ] || { echo "    un add con id existente se aceptó (y pisa/ignora en silencio)"; return 1; }
  grep -q '"title":"original"' tools/findings/ledger.jsonl \
    || { echo "    el add duplicado modificó la entrada existente"; return 1; }
}
test_add_con_id_existente_falla_y_apunta_a_update() {
  _fcli_sandbox _case_add_duplicado_no_pisa_en_silencio
}

_case_update_corrige() {
  bash tools/findings/findings.sh add --id f-y --title "mal" --area a >/dev/null 2>&1
  bash tools/findings/findings.sh update f-y --title "bien" >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    update falló sobre un id existente"; return 1; }
  grep -q '"title":"bien"' tools/findings/ledger.jsonl \
    || { echo "    update no cambió el título"; return 1; }
}
test_update_corrige_un_hallazgo_existente() { _fcli_sandbox _case_update_corrige; }

_case_drop_exige_razon() {
  # Retirar del ledger sin explicar por qué es borrar evidencia. `drop` no es
  # `close`: cerrar afirma que hubo un problema y se resolvió; drop afirma
  # que nunca lo hubo.
  bash tools/findings/findings.sh add --id f-z --title "t" --area a >/dev/null 2>&1
  bash tools/findings/findings.sh drop f-z >/dev/null 2>&1
  [ "$?" = "2" ] || { echo "    drop sin --reason fue aceptado (borrar evidencia sin explicación)"; return 1; }
  grep -q 'f-z' tools/findings/ledger.jsonl \
    || { echo "    el drop sin razón igualmente retiró la entrada"; return 1; }
}
test_drop_sin_razon_se_rechaza() { _fcli_sandbox _case_drop_exige_razon; }

# ── close sobre un ya-cerrado NO sobrescribe la resolución ──────────
# El invariante «un estado terminal no resucita» cubría `add`/`import`, y
# dejaba fuera el camino contrario: `close` sobre algo YA cerrado reasignaba
# `status`/`resolution` sin mirar el estado previo.
#
# Pasó de verdad (2026-08-28): un `close --resolution "test"` lanzado para
# comprobar si el CLI admitía corregir una resolución machacó la resolución
# real de un finding `high` ya cerrado. La pérdida es silenciosa y del dato
# que justifica el cierre — justo lo que §10 dice que el ledger existe para
# no perder.
_case_close_no_pisa_resolucion_previa() {
  _cli add --id f-t9 --title "Cerrado con motivo" --area x --source test >/dev/null 2>&1
  _cli close f-t9 --resolution "la razón buena, con evidencia" >/dev/null 2>&1
  _cli close f-t9 --resolution "test" >/dev/null 2>&1
  grep -q "la razón buena" tools/findings/ledger.jsonl \
    || { echo "    un segundo close PISÓ la resolución original"; return 1; }
  grep -q '"resolution": *"test"' tools/findings/ledger.jsonl && { echo "    quedó la resolución basura"; return 1; }
  return 0
}
test_close_no_pisa_resolucion_previa() { _fcli_sandbox _case_close_no_pisa_resolucion_previa; }

_case_close_repetido_avisa_y_falla() {
  _cli add --id f-t10 --title "Cerrable" --area x --source test >/dev/null 2>&1
  _cli close f-t10 --resolution "primera" >/dev/null 2>&1
  local rc; _cli close f-t10 --resolution "segunda" >/dev/null 2>&1; rc=$?
  [ "$rc" != "0" ] || { echo "    cerrar dos veces salió 0: el aviso no bloquea nada"; return 1; }
}
test_close_repetido_avisa_y_falla() { _fcli_sandbox _case_close_repetido_avisa_y_falla; }

# …pero corregir a propósito SÍ debe ser posible, y explícito.
#
# Comprueba las DOS ramas en el mismo caso, y eso no es redundante: la primera
# versión de este test solo verificaba que `--force` funcionara, y con el código
# viejo —sin guard— también pasaba, porque cerrar dos veces «funcionaba»
# trivialmente. Un test que pasa igual con y sin la lógica que dice cubrir no
# distingue nada. Lo cazó la review.
_case_close_force_si_corrige() {
  _cli add --id f-t11 --title "Cerrable" --area x --source test >/dev/null 2>&1
  _cli close f-t11 --resolution "primera, incompleta" >/dev/null 2>&1
  # sin --force: rebota y NO toca la resolución
  _cli close f-t11 --resolution "la corregida" >/dev/null 2>&1 \
    && { echo "    sin --force debería haber rebotado"; return 1; }
  grep -q "primera, incompleta" tools/findings/ledger.jsonl \
    || { echo "    el intento sin --force alteró la resolución"; return 1; }
  # con --force: corrige
  _cli close f-t11 --resolution "la corregida" --force >/dev/null 2>&1 \
    || { echo "    --force no dejó corregir una resolución"; return 1; }
  grep -q "la corregida" tools/findings/ledger.jsonl || { echo "    --force no aplicó la corrección"; return 1; }
}
test_close_force_si_corrige() { _fcli_sandbox _case_close_force_si_corrige; }

# ── --force sin resolución nueva: la puerta que el propio guard abría ──
# Si `--force` salta el guard y no se da `--resolution`, el codigo caía al
# placeholder generico ("fixed") y machacaba la resolución real **en silencio**
# — la misma perdida que motivó el guard, por la puerta que el guard ofrece
# como via legitima de correccion. Lo cazó la review del propio fix.
_case_force_sin_resolucion_no_pisa() {
  _cli add --id f-t13 --title "Cerrable" --area x --source test >/dev/null 2>&1
  _cli close f-t13 --resolution "la razón real, con evidencia" >/dev/null 2>&1
  local rc; _cli close f-t13 --force >/dev/null 2>&1; rc=$?
  [ "$rc" != "0" ] || { echo "    --force sin --resolution salió 0"; return 1; }
  grep -q "la razón real" tools/findings/ledger.jsonl \
    || { echo "    --force sin --resolution PISÓ la resolución con el placeholder"; return 1; }
}
test_force_sin_resolucion_no_pisa() { _fcli_sandbox _case_force_sin_resolucion_no_pisa; }

# ── el guard vale para `accept`, no solo para `close` ───────────────
# Compartían rama de código, pero «está cubierto porque comparte código» no es
# un test: si mañana se separan, nadie se entera.
_case_accept_no_pisa_resolucion_previa() {
  _cli add --id f-t14 --title "Aceptable" --area x --source test >/dev/null 2>&1
  _cli close f-t14 --resolution "cerrado con su motivo" >/dev/null 2>&1
  local rc; _cli accept f-t14 --reason "test" >/dev/null 2>&1; rc=$?
  [ "$rc" != "0" ] || { echo "    accept sobre un terminal salió 0"; return 1; }
  grep -q "cerrado con su motivo" tools/findings/ledger.jsonl \
    || { echo "    accept PISÓ la resolución de un finding ya cerrado"; return 1; }
}
test_accept_no_pisa_resolucion_previa() { _fcli_sandbox _case_accept_no_pisa_resolucion_previa; }

# ── cerrar un id inexistente no puede pasar en silencio ─────────────
_case_close_id_inexistente_falla() {
  _cli add --id f-t12 --title "Existe" --area x --source test >/dev/null 2>&1
  local rc; _cli close f-NO-EXISTE --resolution "x" >/dev/null 2>&1; rc=$?
  [ "$rc" != "0" ] || { echo "    cerrar un id inexistente salió 0 — el usuario cree que cerró algo"; return 1; }
}
test_close_id_inexistente_falla() { _fcli_sandbox _case_close_id_inexistente_falla; }

# ── un flag no puede tragarse otro flag como valor ──────────────────
# `flags()` (plural) ya comprobaba que el token siguiente no empezara por `--`;
# `flag()` (singular) no, y devolvía el siguiente token fuera lo que fuera.
#
# Consecuencia real, cazada revisando el propio guard de terminalidad:
# `close ID --resolution --force` dejaba `nueva = "--force"` (truthy, salta el
# check de «force sin resolución») y a la vez `--force` seguía en la lista (así
# que el guard de terminalidad también se desactivaba). Resultado: la
# resolución real sobrescrita con la cadena literal "--force", exit 0, sin
# aviso. La misma pérdida silenciosa que el guard existe para evitar, por una
# tercera puerta.
_case_flag_no_se_traga_otro_flag() {
  _cli add --id f-t15 --title "Cerrable" --area x --source test >/dev/null 2>&1
  _cli close f-t15 --resolution "la razón real" >/dev/null 2>&1
  local rc; _cli close f-t15 --resolution --force >/dev/null 2>&1; rc=$?
  [ "$rc" != "0" ] || { echo "    '--resolution --force' salió 0"; return 1; }
  grep -q '"resolution": *"--force"' tools/findings/ledger.jsonl && { echo "    quedó el literal --force como resolución"; return 1; }
  grep -q "la razón real" tools/findings/ledger.jsonl \
    || { echo "    '--resolution --force' PISÓ la resolución original"; return 1; }
  return 0
}
test_flag_no_se_traga_otro_flag() { _fcli_sandbox _case_flag_no_se_traga_otro_flag; }

# ── un valor legítimo puede empezar por `--` ────────────────────────
# La regresión que introdujo el arreglo anterior: al rechazar como valor
# CUALQUIER token que empiece por `--`, un texto libre que arranca con guiones
# se perdía en silencio (exit 0, campo vacío o placeholder). Y en ESTE ledger es
# de lo más probable: su contenido describe bugs de flags de CLI, así que los
# títulos y detalles llevan `--algo` dentro constantemente.
#
# La distinción correcta no es «empieza por --» sino «ES un flag conocido»:
# `--force` era ambiguo porque existe como flag; «--force needs a reason» no.
_case_valor_legitimo_con_guiones_sobrevive() {
  _cli add --id f-t16 --title "Bug de CLI" --area x --source test \
      --detail "--force sin --resolution pisa el dato" >/dev/null 2>&1
  grep -q -- "--force sin --resolution pisa el dato" tools/findings/ledger.jsonl \
    || { echo "    un --detail que empieza por -- se perdió"; return 1; }
  _cli close f-t16 --resolution "--force ya exige motivo, arreglado" >/dev/null 2>&1 \
    || { echo "    close con --resolution que empieza por -- falló"; return 1; }
  grep -q -- "--force ya exige motivo" tools/findings/ledger.jsonl \
    || { echo "    la resolución que empieza por -- se perdió"; return 1; }
  grep -q '"resolution": *"fixed"' tools/findings/ledger.jsonl && { echo "    cayó al placeholder generico"; return 1; }
  return 0
}
test_valor_legitimo_con_guiones_sobrevive() { _fcli_sandbox _case_valor_legitimo_con_guiones_sobrevive; }

# ── un flag conocido en posición de valor no puede caer al placeholder ──
# La QUINTA puerta de la misma familia. `KNOWN_FLAGS` cerró el caso de
# `--force` porque hay un guard específico para ese literal; cualquier OTRO
# flag conocido en la posición del valor cae a `or "fixed"` / `or "aceptado"`
# en silencio, con exit 0. Nadie distinguía «no diste --resolution» (uso válido
# y documentado) de «diste --resolution y el valor se lo comió otro flag».
_case_flag_conocido_como_valor_no_cae_al_placeholder() {
  _cli add --id f-t17 --title "T" --area x --source test >/dev/null 2>&1
  local rc; _cli close f-t17 --resolution --tier >/dev/null 2>&1; rc=$?
  [ "$rc" != "0" ] || { echo "    'close --resolution --tier' salió 0"; return 1; }
  grep -q '"resolution": *"fixed"' tools/findings/ledger.jsonl && { echo "    cayó al placeholder en silencio"; return 1; }
  _cli add --id f-t18 --title "T" --area x --source test >/dev/null 2>&1
  _cli accept f-t18 --reason --severity >/dev/null 2>&1 && { echo "    'accept --reason --severity' salió 0"; return 1; }
  return 0
}
test_flag_conocido_como_valor_no_cae_al_placeholder() { _fcli_sandbox _case_flag_conocido_como_valor_no_cae_al_placeholder; }

# `--resolution ""` explícito tiene el mismo síntoma: vacío ≠ «no lo diste».
_case_resolucion_vacia_no_cae_al_placeholder() {
  _cli add --id f-t19 --title "T" --area x --source test >/dev/null 2>&1
  local rc; _cli close f-t19 --resolution "" >/dev/null 2>&1; rc=$?
  [ "$rc" != "0" ] || { echo "    'close --resolution \"\"' salió 0"; return 1; }
}
test_resolucion_vacia_no_cae_al_placeholder() { _fcli_sandbox _case_resolucion_vacia_no_cae_al_placeholder; }

# ── KNOWN_FLAGS es una lista a mano: que no se desincronice del USAGE ──
# Si alguien añade un flag al CLI y no lo mete en KNOWN_FLAGS, el siguiente
# valor que lo lleve delante se pierde sin avisar — la misma familia otra vez,
# y hoy NADA lo nota: quitar `--tier` de la lista deja los 40 tests en verde.
# Una lista a mano que debe seguir sincronizada con otra cosa necesita su
# detector (§10), o es la próxima gotera esperando.
_case_known_flags_cubre_el_usage() {
  python3 - <<'PY' || return 1
import re, sys
s = open('tools/findings/findings.sh').read()
kf = set(re.findall(r'"(--[a-z-]+)"', s.split('KNOWN_FLAGS = {')[1].split('}')[0]))
usage = s.split('USAGE = """')[1].split('"""')[0]
uf = set(re.findall(r'--[a-z-]+', usage))
faltan = uf - kf
if faltan:
    print(f"    flags en USAGE que faltan en KNOWN_FLAGS: {sorted(faltan)}")
    sys.exit(1)
PY
}
test_known_flags_cubre_el_usage() { _fcli_sandbox _case_known_flags_cubre_el_usage; }

# ── cerrar un id inexistente falla CON MENSAJE, no con un traceback ──
# El test anterior solo comprobaba `rc != 0`, y pasaba igual sin el guard:
# sin él, `match[0]` sobre una lista vacía revienta con IndexError y rc=1. No
# distinguía «falla explicando» de «crashea sin explicar» — decorativo (§5).
_case_close_id_inexistente_explica() {
  _cli add --id f-t20 --title "Existe" --area x --source test >/dev/null 2>&1
  local out; out="$(_cli close f-NO-EXISTE --resolution "x" 2>&1)"
  case "$out" in
    *"no existe el finding"*) : ;;
    *) echo "    no explicó el fallo (¿traceback?): $out"; return 1 ;;
  esac
  case "$out" in *Traceback*) echo "    reventó con traceback en vez de fallar limpio"; return 1 ;; esac
  return 0
}
test_close_id_inexistente_explica() { _fcli_sandbox _case_close_id_inexistente_explica; }

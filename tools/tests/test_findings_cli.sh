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

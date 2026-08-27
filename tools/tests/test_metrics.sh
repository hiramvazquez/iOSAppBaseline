#!/usr/bin/env bash
# Eventos son actividad/latencia; findings son defectos durables. Estos tests
# fijan que las dos poblaciones jamás vuelvan a compartir denominador.

_metrics_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/metrics" "$d/tools/findings" "$d/.agents/state/metrics"
  cp "$PROJECT_ROOT/tools/metrics/read-events.py" "$d/tools/metrics/"
  cp "$PROJECT_ROOT/tools/metrics/metrics-report.py" "$d/tools/metrics/"
  cp "$PROJECT_ROOT/tools/metrics/escape-rate.sh" "$d/tools/metrics/"
  cp "$PROJECT_ROOT/tools/metrics/gate-value.sh" "$d/tools/metrics/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

test_reviewer_gate_registra_una_deteccion_y_duracion_en_ms() {
  grep -Fq 'hook_log_detection "reviewer-gate" "budget-warning" "pre-commit" 1 "$(( (GATE_T1 - GATE_T0) * 1000 ))" gate' \
    "$PROJECT_ROOT/scripts/agent-hooks/reviewer-gate.sh" \
    || { echo "    reviewer-gate aún pasa segundos como n en vez de duration_ms"; return 1; }
}

_case_fuente_ausente_no_aprueba_en_vacio() {
  bash tools/metrics/escape-rate.sh --json >/dev/null 2>&1
  [ "$?" = "3" ] || { echo "    escape-rate sin ledger no devolvió exit 3"; return 1; }
  bash tools/metrics/gate-value.sh --json >/dev/null 2>&1
  [ "$?" = "3" ] || { echo "    gate-value sin fuentes no devolvió exit 3"; return 1; }
}
test_fuente_ausente_es_no_pude_medir_no_reporte_vacio() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/metrics"
  cp "$PROJECT_ROOT/tools/metrics/read-events.py" "$d/tools/metrics/"
  cp "$PROJECT_ROOT/tools/metrics/metrics-report.py" "$d/tools/metrics/"
  cp "$PROJECT_ROOT/tools/metrics/escape-rate.sh" "$d/tools/metrics/"
  cp "$PROJECT_ROOT/tools/metrics/gate-value.sh" "$d/tools/metrics/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; _case_fuente_ausente_no_aprueba_en_vacio )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_fuente_corrupta_no_aprueba_en_vacio() {
  printf '%s\n' \
    '{"id":"f-valido","status":"closed","severity":"high","source":"reviewer","createdAt":"2026-08-10T00:00:00Z"}' \
    'not json' > tools/findings/ledger.jsonl
  printf '%s\n' \
    '{"schema_version":2,"event_id":"evt-valido","ts":"2026-08-10T00:00:00Z","source":"reviewer","phase":"phase7","detections":[{"rule":"r1"}],"duration_ms":10}' \
    'not json' > .agents/state/metrics/detections.jsonl
  local out
  out="$(bash tools/metrics/escape-rate.sh --json 2>/dev/null)"; local escape_rc=$?
  [ "$escape_rc" = "3" ] || { echo "    escape-rate corrupto devolvió $escape_rc"; return 1; }
  [ -z "$out" ] || { echo "    escape-rate corrupto emitió JSON de éxito: $out"; return 1; }

  out="$(python3 tools/metrics/read-events.py .agents/state/metrics/detections.jsonl 2>/dev/null)"
  local reader_rc=$?
  [ "$reader_rc" = "3" ] || { echo "    read-events corrupto devolvió $reader_rc"; return 1; }
  [ -z "$out" ] || { echo "    read-events corrupto emitió stream parcial: $out"; return 1; }

  # gate-value debe fallar por cualquiera de sus dos fuentes corruptas.
  : > tools/findings/ledger.jsonl
  out="$(bash tools/metrics/gate-value.sh --json 2>/dev/null)"; local gate_rc=$?
  [ "$gate_rc" = "3" ] || { echo "    gate-value corrupto devolvió $gate_rc"; return 1; }
  [ -z "$out" ] || { echo "    gate-value corrupto emitió JSON de éxito: $out"; return 1; }
}
test_jsonl_corrupto_es_exit3_no_poblacion_cero() {
  _metrics_sandbox _case_fuente_corrupta_no_aprueba_en_vacio
}

_case_lector_normaliza_v1_y_preserva_v2() {
  printf '%s\n' \
    '{"ts":"2026-08-01T00:00:00Z", "source": "semgrep", "rule":"x", "area":"a", "n":2}' \
    '{"schema":2,"event_id":"evt-real","ts":"2026-08-02T00:00:00Z","phase":"review","source":"reviewer","duration_ms":41,"commit":"abc","triage":"unknown","n":1}' \
    > .agents/state/metrics/detections.jsonl
  python3 tools/metrics/read-events.py .agents/state/metrics/detections.jsonl > normalized.jsonl || return 1
  python3 - <<'PY'
import json
legacy, current = [json.loads(line) for line in open("normalized.jsonl", encoding="utf-8")]
assert legacy["schema"] == 1 and legacy["event_id"] is None
assert legacy["triage"] == "unknown" and legacy["phase"] == "gate"
assert legacy["duration_ms"] is None and legacy["commit"] is None
assert current["schema"] == 2 and current["event_id"] == "evt-real"
assert current["phase"] == "review" and current["duration_ms"] == 41
PY
}
test_lector_acepta_jsonl_v1_y_v2_y_v1_queda_unknown() {
  _metrics_sandbox _case_lector_normaliza_v1_y_preserva_v2
}

_case_metricas_consumen_stream_mixto() {
  : > tools/findings/ledger.jsonl
  printf '%s\n' \
    '{"ts":"2026-08-01T00:00:00Z", "source": "semgrep", "rule":"x", "area":"a", "n":2}' \
    '{"schema":2,"event_id":"evt-real","ts":"2026-08-02T00:00:00Z","phase":"review","source":"reviewer","duration_ms":41,"commit":"abc","triage":"unknown","n":3}' \
    > .agents/state/metrics/detections.jsonl
  local escape gate
  escape="$(bash tools/metrics/escape-rate.sh --since 2026-08-01 --until 2026-08-31 --json)" || return 1
  gate="$(bash tools/metrics/gate-value.sh --since 2026-08-01 --until 2026-08-31 --json)" || return 1
  python3 - "$escape" "$gate" <<'PY'
import json, sys
escape, gate = json.loads(sys.argv[1]), json.loads(sys.argv[2])
assert escape["total"] == 0 and escape["findings_total"] == 0
assert gate["events_total"] == 2 and gate["detections_total"] == 5
assert gate["legacy_events"] == 1
assert gate["gates"]["semgrep"]["events"] == 1
assert gate["gates"]["reviewer"]["events"] == 1
PY
}
test_escape_rate_y_gate_value_aceptan_stream_mixto_v1_v2() {
  _metrics_sandbox _case_metricas_consumen_stream_mixto
}

_case_gate_value_stream_vacio() {
  : > .agents/state/metrics/detections.jsonl
  : > tools/findings/ledger.jsonl
  local out
  out="$(METRICS_TODAY=2026-08-12 bash tools/metrics/gate-value.sh --json)" || return 1
  python3 - "$out" <<'PY'
import json, sys
report = json.loads(sys.argv[1])
assert report["events_total"] == 0 and report["detections_total"] == 0
assert report["window"] == {"since":"2026-07-14", "until":"2026-08-12"}
assert report["latency_coverage_pct"] is None
assert report["false_positives"] is None
PY
}
test_gate_value_reporta_cero_una_sola_vez_con_stream_vacio() {
  _metrics_sandbox _case_gate_value_stream_vacio
}

_case_ventana_default_es_utc_no_timezone_del_host() {
  : > .agents/state/metrics/detections.jsonl
  : > tools/findings/ledger.jsonl
  local east west
  east="$(TZ=Pacific/Kiritimati bash tools/metrics/gate-value.sh --json)" || return 1
  west="$(TZ=Etc/GMT+12 bash tools/metrics/gate-value.sh --json)" || return 1
  python3 - "$east" "$west" <<'PY'
import json, sys
east, west = json.loads(sys.argv[1]), json.loads(sys.argv[2])
assert east["window"] == west["window"]
PY
}
test_ventana_default_usa_dia_utc_en_cualquier_timezone_del_host() {
  _metrics_sandbox _case_ventana_default_es_utc_no_timezone_del_host
}

_case_escape_rate_cuenta_findings_unicos_en_ventana() {
  printf '%s\n' \
    '{"id":"f-gate","createdAt":"2026-08-10","status":"fixed","source":"semgrep","source_event_ids":["evt-1"]}' \
    '{"id":"f-gate","createdAt":"2026-08-10","status":"fixed","source":"semgrep","source_event_ids":["evt-1"]}' \
    '{"id":"f-human","createdAt":"2026-08-11","status":"open","source":"human-review, semgrep","source_event_ids":[]}' \
    '{"id":"f-unknown","createdAt":"2026-08-12","status":"open","source":"herramienta-propia, semgrep","source_event_ids":[]}' \
    '{"id":"f-old","createdAt":"2026-07-01","status":"fixed","source":"prod","source_event_ids":[]}' \
    > tools/findings/ledger.jsonl
  printf '%s\n' \
    '{"schema":2,"event_id":"evt-1","ts":"2026-08-10T00:00:00Z","phase":"gate","source":"semgrep","duration_ms":10,"commit":"a","triage":"unknown","n":1}' \
    '{"schema":2,"event_id":"evt-untriaged","ts":"2026-08-10T00:00:00Z","phase":"gate","source":"semgrep","duration_ms":20,"commit":"a","triage":"unknown","n":9}' \
    > .agents/state/metrics/detections.jsonl
  local report
  report="$(bash tools/metrics/escape-rate.sh --since 2026-08-01 --until 2026-08-31 --json)" || return 1
  python3 - "$report" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
assert r["window"] == {"since":"2026-08-01", "until":"2026-08-31"}
assert r["findings_total"] == 3 and r["classified"] == 2 and r["unknown"] == 1
assert r["total"] == 2 and r["gate"] == 1 and r["human"] == 1
assert r["escaped"] == 1 and r["escape_rate_pct"] == 50 and r["automated_pct"] == 50
PY
}
test_escape_rate_no_suma_eventos_y_cuenta_ids_unicos_en_ventana() {
  _metrics_sandbox _case_escape_rate_cuenta_findings_unicos_en_ventana
}

_case_gate_value_mide_eventos_con_denominadores_honestos() {
  printf '%s\n' \
    '{"id":"f-gate","createdAt":"2026-08-10","status":"fixed","source":"semgrep","source_event_ids":["evt-1"]}' \
    > tools/findings/ledger.jsonl
  printf '%s\n' \
    '{"ts":"2026-08-05T00:00:00Z","source":"semgrep","rule":"legacy","area":"a","n":2}' \
    '{"schema":2,"event_id":"evt-1","ts":"2026-08-10T00:00:00Z","phase":"gate","source":"semgrep","duration_ms":100,"commit":"a","triage":"unknown","n":1}' \
    '{"schema":2,"event_id":"evt-1","ts":"2026-08-10T00:00:01Z","phase":"gate","source":"semgrep","duration_ms":999,"commit":"a","triage":"unknown","n":1}' \
    '{"schema":2,"event_id":"evt-2","ts":"2026-08-11T00:00:00Z","phase":"gate","source":"semgrep","duration_ms":300,"commit":"b","triage":"unknown","n":1}' \
    '{"schema":2,"event_id":"evt-3","ts":"2026-08-12T00:00:00Z","phase":"review","source":"reviewer","duration_ms":null,"commit":"c","triage":"unknown","n":1}' \
    '{"schema":2,"event_id":"evt-old","ts":"2026-07-01T00:00:00Z","phase":"prod","source":"prod","duration_ms":500,"commit":"d","triage":"unknown","n":1}' \
    > .agents/state/metrics/detections.jsonl
  local report
  report="$(bash tools/metrics/gate-value.sh --since 2026-08-01 --until 2026-08-31 --json)" || return 1
  python3 - "$report" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
assert r["events_total"] == 4 and r["detections_total"] == 5
assert r["legacy_events"] == 1
assert r["promoted_events"] == 1 and r["untriaged_events"] == 3
assert r["false_positives"] is None and r["fp_rate_pct"] is None
assert r["latency_samples"] == 2 and r["latency_coverage_pct"] == 50
s = r["gates"]["semgrep"]
assert s["events"] == 3 and s["detections"] == 4
assert s["promoted"] == 1 and s["untriaged"] == 2
assert s["latency_samples"] == 2 and s["avg_duration_ms"] == 200
assert s["p95_duration_ms"] == 300
review = r["gates"]["reviewer"]
assert review["events"] == 1 and review["latency_samples"] == 0
assert review["avg_duration_ms"] is None
PY
}
test_gate_value_deduplica_event_id_y_no_llama_fp_a_unknown() {
  _metrics_sandbox _case_gate_value_mide_eventos_con_denominadores_honestos
}

_case_gate_value_valida_timestamp_completo() {
  : > tools/findings/ledger.jsonl
  printf '%s\n' \
    '{"schema":2,"event_id":"evt-offset","ts":"2026-08-10T23:30:00-05:00","phase":"gate","source":"semgrep","duration_ms":10,"commit":"a","triage":"unknown","n":1}' \
    '{"schema":2,"event_id":"evt-utc","ts":"2026-08-11T04:30:00Z","phase":"gate","source":"semgrep","duration_ms":10,"commit":"a","triage":"unknown","n":1}' \
    '{"schema":2,"event_id":"evt-invalid","ts":"2026-08-10NOT-A-TIME","phase":"gate","source":"semgrep","duration_ms":20,"commit":"b","triage":"unknown","n":1}' \
    '{"schema":2,"event_id":"evt-number","ts":123,"phase":"gate","source":"semgrep","duration_ms":20,"commit":"b","triage":"unknown","n":1}' \
    '{"schema":2,"event_id":"evt-date-only","ts":"2026-08-10","phase":"gate","source":"semgrep","duration_ms":20,"commit":"b","triage":"unknown","n":1}' \
    '{"schema":2,"event_id":"evt-naive","ts":"2026-08-10T12:00:00","phase":"gate","source":"semgrep","duration_ms":20,"commit":"b","triage":"unknown","n":1}' \
    > .agents/state/metrics/detections.jsonl
  local report
  report="$(bash tools/metrics/gate-value.sh --since 2026-08-11 --until 2026-08-11 --json 2>warnings.log)" || return 1
  local warnings
  warnings="$(grep -Fc 'timestamp inválido; se excluye de la métrica' warnings.log || true)"
  [ "$warnings" = "4" ] \
    || { echo "    se esperaban 4 señales de timestamp inválido y hubo $warnings"; return 1; }
  python3 - "$report" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
assert r["events_total"] == 2 and r["detections_total"] == 2
assert r["invalid_dates"] == 4
assert r["gates"]["semgrep"]["events"] == 2
PY
}
test_gate_value_valida_timestamp_completo_no_solo_prefijo_fecha() {
  _metrics_sandbox _case_gate_value_valida_timestamp_completo
}

# ════════════════════════════════════════════════════════════════════
# Un gate que BLOQUEA deja rastro. Si no, la fase 3 mide el instrumento
# ════════════════════════════════════════════════════════════════════
# Hallazgo de la fase 3 de PRD 0005: el informe de valor por gate daba CERO
# eventos para casi todos, y el propio gate-value avisa de que un cero es
# ambiguo entre disuasión (funciona tan bien que nadie lo intenta) y mudo.
# Pero había un TERCER estado que la herramienta no contemplaba: el gate
# disparó, bloqueó, hizo su trabajo — y no registró nada. En la sesión que lo
# descubrió, el git-guard del reviewer-gate y el skill-reminder bloquearon dos
# veces cada uno y los dos figuraban con cero.
#
# La instrumentación va en las PRIMITIVAS de bloqueo de `lib/io.sh` y NO en cada
# call-site: enumerar sitios es exactamente el error que costó ocho rondas en el
# bypass de scope. La fuente se DERIVA del script que llama, así que un hook
# nuevo queda instrumentado el día que se escribe.
#
# PRIMITIVAS, en plural, y eso es la corrección de f-2bd11525: la primera
# versión instrumentó SOLO `hook_block_or_warn` y escribió encima que era "por
# donde pasan TODOS los bloqueos". Eran tres —`hook_block`, `hook_json_block` y
# `hook_block_or_warn`— y la que quedó fuera es la que usa el git-guard, o sea
# la que bloquea `--no-verify`, `push --force` y `reset --hard`. Que sean tres y
# que las tres estén cubiertas ya no lo dice un comentario: lo enumera
# `test_toda_primitiva_de_bloqueo_esta_instrumentada`, más abajo.
_bw_sandbox() { # repo desechable con la lib y un hook de mentira
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/.agents/state/metrics"
  cp "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh" "$d/scripts/agent-hooks/lib/"
  ( cd "$d" || exit 1; PROJECT_ROOT="$d" "$1" "$d" )
  local rc=$?; rm -rf "$d"; return $rc
}
_bw_hook() { # _bw_hook <dir> <nombre> — un hook que solo bloquea
  printf '#!/usr/bin/env bash\n. scripts/agent-hooks/lib/io.sh\nhook_block_or_warn "🛑 prueba"\n' \
    > "$1/$2.sh"
}

_case_un_bloqueo_deja_rastro() {
  local d="$1"
  _bw_hook "$d" "gate-de-prueba"
  ( cd "$d" && bash gate-de-prueba.sh >/dev/null 2>&1 )
  local rc=$?
  [ "$rc" = "2" ] || { echo "    el hook debía bloquear con exit 2 y salió $rc"; return 1; }
  local ev="$d/.agents/state/metrics/detections.jsonl"
  [ -s "$ev" ] || {
    echo "    BLOQUEÓ Y NO REGISTRÓ: sin evento, la fase 3 mide el instrumento"
    echo "    y no las defensas — un gate que bloquea a diario figura con cero."
    return 1; }
  grep -q 'gate-de-prueba' "$ev" || {
    echo "    registró el evento pero no de quién: sin fuente no es medible"
    sed 's/^/      /' "$ev"; return 1; }
}
test_un_gate_que_bloquea_deja_rastro_en_la_telemetria() {
  _bw_sandbox _case_un_bloqueo_deja_rastro; }

# La otra mitad: en preset lite el gate AVISA en vez de bloquear, y ese aviso
# también es actividad. Un gate que avisa mucho es un candidato a revisión igual
# que uno que bloquea mucho — pero solo si queda constancia de que avisó.
_case_un_aviso_de_lite_tambien_deja_rastro() {
  local d="$1"
  printf 'lite\n' > "$d/tools/preset" 2>/dev/null || { mkdir -p "$d/tools"; printf 'lite\n' > "$d/tools/preset"; }
  _bw_hook "$d" "gate-en-lite"
  ( cd "$d" && bash gate-en-lite.sh >/dev/null 2>&1 )
  local rc=$?
  [ "$rc" = "0" ] || { echo "    en lite debía avisar y salir 0, salió $rc"; return 1; }
  grep -q 'gate-en-lite' "$d/.agents/state/metrics/detections.jsonl" 2>/dev/null || {
    echo "    avisó en lite y no dejó rastro: la actividad en lite es invisible"; return 1; }
}
test_un_aviso_en_preset_lite_tambien_deja_rastro() {
  _bw_sandbox _case_un_aviso_de_lite_tambien_deja_rastro; }

# CONTRATO DURO que no se puede romper al instrumentar: la telemetría JAMÁS
# rompe al gate que la llama. Si el disco falla, si no hay python3, si el
# directorio no se puede crear — el bloqueo tiene que seguir bloqueando.
_case_telemetria_rota_no_rompe_el_bloqueo() {
  local d="$1"
  _bw_hook "$d" "gate-sin-disco"
  # .agents/state/metrics como FICHERO: mkdir -p falla y el log no puede escribir.
  rm -rf "$d/.agents/state/metrics"; printf 'no soy un directorio\n' > "$d/.agents/state/metrics"
  ( cd "$d" && bash gate-sin-disco.sh >/dev/null 2>&1 )
  local rc=$?
  [ "$rc" = "2" ] || {
    echo "    con la telemetría rota el gate dejó de bloquear (exit $rc)."
    echo "    Instrumentar un gate no puede convertirlo en fail-open."
    return 1; }
}
test_telemetria_rota_no_impide_que_el_gate_bloquee() {
  _bw_sandbox _case_telemetria_rota_no_rompe_el_bloqueo; }

# ── La afirmación de cobertura ES el test (f-20ed9b44) ──────────────
# Tres rondas de review en RED, las tres por lo mismo: una afirmación de
# cobertura más fuerte que lo verificado. La tercera fue literalmente un
# comentario que decía "por aquí pasan TODOS los bloqueos" sobre una de tres
# primitivas. La regla que sale de ahí: si una afirmación de cobertura no puede
# ser un test, no puede ser una afirmación.
#
# Esto es ese test. NO enumera las primitivas a mano —una lista escrita a mano
# es la misma clase de bug— sino que relee `lib/io.sh`, DERIVA cuáles son las
# funciones que deniegan (las que salen con exit 2 o emiten un deny/block por
# JSON) y exige que cada una registre. Una primitiva nueva sin instrumentar
# falla el día que se escribe, no el día que alguien mida y vea ceros.
_PRIMITIVAS='tools/tests/lib/primitivas-de-bloqueo.sh'
_primitivas() { bash "$PROJECT_ROOT/$_PRIMITIVAS" "$1"; }

_case_toda_primitiva_de_bloqueo_esta_instrumentada() {
  local salida
  salida="$(_primitivas "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh")" || {
    echo "    el inventario de primitivas no pudo analizar io.sh"; return 1; }

  # Un meta-test que no ve NINGUNA primitiva pasa siempre: eso es un gate mudo,
  # no un gate verde. Es la misma clase de fallo que persigue.
  local deniegan; deniegan="$(printf '%s\n' "$salida" | awk '$2==1' | wc -l | tr -d ' ')"
  [ "$deniegan" -gt 0 ] || {
    echo "    no se encontró NINGUNA primitiva de bloqueo en io.sh."
    echo "    Un meta-test ciego se lee exactamente igual que uno que pasa."
    return 1; }

  local sin; sin="$(printf '%s\n' "$salida" | awk '$2==1 && $3==0 {print $1}')"
  [ -z "$sin" ] || {
    echo "    primitivas que DENIEGAN sin registrar: $(printf '%s' "$sin" | tr '\n' ' ')"
    echo "    Un gate que bloquea y no deja rastro figura con cero eventos, y"
    echo "    un cero se lee como 'nadie lo intentó'. Es el bug f-2bd11525:"
    echo "    el git-guard bloqueaba --no-verify sin aparecer en la telemetría."
    echo "    Llama a \`_hook_log_block\` en la primitiva, no en los call-sites."
    return 1; }
  echo "    $deniegan primitivas de bloqueo, todas instrumentadas"
}
test_toda_primitiva_de_bloqueo_esta_instrumentada() {
  _case_toda_primitiva_de_bloqueo_esta_instrumentada; }

# ── Y el meta-test se testea a sí mismo ─────────────────────────────
# Porque las dos primeras versiones NO lo hacían y acumularon CUATRO puntos
# ciegos, encontrados de uno en uno por rondas sucesivas de review: la keyword
# `function`, el `}` de cierre indentado, las definiciones de una línea, la
# llave en la línea siguiente, y un conteo de llaves que se desincronizaba con
# `${1}` sin comillas y hacía desaparecer el `exit 2` de después.
#
# Arreglar formas de una en una era perder la carrera —la lista de shapes
# válidos la decide bash—, así que ahora **el parser es bash** (`declare -f`).
# Estas fixtures son la prueba de que ya no hay forma que se escape, y siguen
# aquí precisamente porque un inventario ciego a una primitiva es el bug que
# dice prevenir, con una capa más de indirección.
_case_el_inventario_caza_una_primitiva_no_instrumentada() {
  local d; d="$(mktemp -d)"; local rc=0
  local -a formas=(
    'clasica|deny_clasica() {\n  exit 2\n}\n'
    'keyword_function_con_parens|function deny_kw_parens() {\n  exit 2\n}\n'
    'keyword_function_sin_parens|function deny_kw_solo {\n  exit 2\n}\n'
    'cierre_indentado|deny_indentada() {\n  exit 2\n  }\n'
    'una_sola_linea|deny_oneliner() { exit 2; }\n'
    'llave_en_la_linea_siguiente|deny_llave_abajo()\n{\n  exit 2\n}\n'
    'expansion_sin_comillas|deny_expansion() {\n  echo ${1}\n  exit 2\n}\n'
    'exit_tras_bloque_anidado|deny_anidada() {\n  if [ -n "${1:-}" ]; then\n    printf x\n  fi\n  case "${1:-}" in a) printf y ;; esac\n  exit 2\n}\n'
    'json_deny|deny_json() {\n  printf %s "{\\"permissionDecision\\":\\"deny\\"}"\n}\n'
  )
  local forma nombre codigo out
  for forma in "${formas[@]}"; do
    nombre="${forma%%|*}"; codigo="${forma#*|}"
    printf '%b' "$codigo" > "$d/f.sh"
    out="$(_primitivas "$d/f.sh" 2>&1)"
    if ! printf '%s\n' "$out" | awk '$2==1 && $3==0' | grep -q .; then
      echo "    NO se vio la primitiva en la forma '$nombre':"
      printf '%b' "$codigo" | sed 's/^/        /'
      echo "      inventario: ${out:-<vacío>}"
      rc=1
    fi
  done
  rm -rf "$d"; return $rc
}
test_el_inventario_caza_una_primitiva_no_instrumentada_en_toda_forma() {
  _case_el_inventario_caza_una_primitiva_no_instrumentada; }

# La otra mitad, o el test de arriba se satisface con un inventario que diga que
# TODO deniega: una función inocente no puede contarse como primitiva, y una
# instrumentada no puede contarse como sin instrumentar. Sin esto, un fallo en
# la dirección contraria bloquearía el commit sin motivo (ley del 10%, §14.2).
_case_el_inventario_no_inventa_primitivas() {
  local d; d="$(mktemp -d)"; local rc=0 out
  printf 'inocente() {\n  # aquí hay un exit 2 mencionado en prosa\n  printf ok\n  exit 0\n}\n' > "$d/f.sh"
  out="$(_primitivas "$d/f.sh" 2>&1)"
  printf '%s\n' "$out" | awk '$2==1' | grep -q . && {
    echo "    se llamó primitiva de bloqueo a una función que no lo es:"
    echo "      $out"; rc=1; }
  printf 'con_registro() {\n  _hook_log_block block\n  exit 2\n}\n' > "$d/f.sh"
  out="$(_primitivas "$d/f.sh" 2>&1)"
  printf '%s\n' "$out" | awk '$2==1 && $3==0' | grep -q . && {
    echo "    se dio por NO instrumentada una función que sí registra:"
    echo "      $out"; rc=1; }
  rm -rf "$d"; return $rc
}
test_el_inventario_no_inventa_primitivas_ni_falsos_incumplimientos() {
  _case_el_inventario_no_inventa_primitivas; }

# El inventario tiene que contener TODO lo que encuentra hasta un grep ingenuo.
#
# La versión anterior de este test comparaba el conteo del parser contra un
# `grep -cE` con LA MISMA regex de cabecera — o sea, una tautología: los dos
# compartían el punto ciego y `vistas == reales` daba verde con una función
# entera invisible para ambos. Lo cazó el reviewer. Ahora la relación no es de
# igualdad sino de INCLUSIÓN, y en la dirección que sí dice algo: bash ve más
# formas que un grep, así que lo que el grep encuentra tiene que estar sí o sí
# en el inventario. Si falta un nombre, el inventario está roto.
_case_el_inventario_contiene_lo_que_encuentra_un_grep_ingenuo() {
  local io="$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh" faltan="" fn
  local inventario; inventario="$(_primitivas "$io" | awk '{print $1}')"
  for fn in $(grep -oE '^[A-Za-z_][A-Za-z0-9_]*\(\)' "$io" | tr -d '()'); do
    printf '%s\n' "$inventario" | grep -qx "$fn" || faltan="$faltan $fn"
  done
  [ -z "$faltan" ] || {
    echo "    el inventario NO contiene funciones que hasta un grep ve:$faltan"
    echo "    Una definición invisible para el inventario es una primitiva"
    echo "    que alguien puede escribir ahí mañana sin disparar el gate."
    return 1; }
}
test_el_inventario_contiene_lo_que_encuentra_un_grep_ingenuo() {
  _case_el_inventario_contiene_lo_que_encuentra_un_grep_ingenuo; }

# El meta-test de arriba lee el código. Estos dos lo EJECUTAN: hook_block y
# hook_json_block son las dos que quedaron fuera de la primera versión, y las
# dos tenían un test que las cubría — ninguno.
_bw_hook_con() { # _bw_hook_con <dir> <nombre> <línea que bloquea>
  printf '#!/usr/bin/env bash\n. scripts/agent-hooks/lib/io.sh\n%s\n' "$3" > "$1/$2.sh"
}

_case_hook_block_deja_rastro() {
  local d="$1"
  _bw_hook_con "$d" "gate-directo" 'hook_block "🛑 prueba"'
  ( cd "$d" && bash gate-directo.sh >/dev/null 2>&1 )
  local rc=$?
  [ "$rc" = "2" ] || { echo "    hook_block debía salir 2 y salió $rc"; return 1; }
  grep -q 'gate-directo' "$d/.agents/state/metrics/detections.jsonl" 2>/dev/null || {
    echo "    hook_block bloqueó sin registrar. Es la primitiva del git-guard:"
    echo "    con esto, --no-verify / push --force / reset --hard figuran con cero."
    return 1; }
}
test_hook_block_directo_deja_rastro() {
  _bw_sandbox _case_hook_block_deja_rastro; }

_case_hook_json_block_deja_rastro() {
  local d="$1"
  _bw_hook_con "$d" "gate-json" 'hook_json_block SubagentStop "🛑 prueba"'
  ( cd "$d" && bash gate-json.sh >/dev/null 2>&1 )
  # Por JSON el bloqueo va en stdout con exit 0 — el rastro es lo que se mide.
  grep -q 'gate-json' "$d/.agents/state/metrics/detections.jsonl" 2>/dev/null || {
    echo "    hook_json_block bloqueó sin registrar. Es la primitiva con la que"
    echo "    capture-review-verdict deniega el cierre de un sub-agente sin VERDICT."
    return 1; }
}
test_hook_json_block_deja_rastro() {
  _bw_sandbox _case_hook_json_block_deja_rastro; }

# Delegación sin doble conteo: hook_json_block con un evento sin shape JSON
# conocido cae a hook_block. Si ambas registraran, UN bloqueo saldría como DOS
# — y gate-value cuenta eventos para decidir keep/tune/retire sobre ese gate.
#
# `DETECTION_DEDUP_WINDOW=0` NO es cosmética: sin ella este test estaba VERDE
# incluso quitando entero el guard `_HOOK_BLOCK_LOGGED` que dice cubrir, porque
# el dedup anti-ráfaga preexistente (misma key `src|rule|area|n|phase|commit`,
# ventana 120s) se tragaba el segundo evento. Un test que pasa con la lógica que
# cubre rota no es un test (§5). La versión anterior afirmaba justo lo contrario
# —"no lo cubre el dedup anti-ráfaga"— y era falso: lo cubría, por accidente de
# que las dos llamadas comparten key y segundo. El guard sigue haciendo falta
# porque esa coincidencia es un accidente, no una propiedad diseñada: basta que
# una de las dos primitivas pase rule/area distintos para que el dedup deje de
# taparlo. Poniendo la ventana a 0 el test aísla el guard y mata su mutante.
_case_delegacion_no_cuenta_dos_veces() {
  local d="$1"
  _bw_hook_con "$d" "gate-delegado" 'hook_json_block PostToolUse "🛑 prueba"'
  ( cd "$d" && DETECTION_DEDUP_WINDOW=0 bash gate-delegado.sh >/dev/null 2>&1 )
  local rc=$?
  [ "$rc" = "2" ] || { echo "    la delegación debía acabar en exit 2 y salió $rc"; return 1; }
  local n; n="$(grep -c 'gate-delegado' "$d/.agents/state/metrics/detections.jsonl" 2>/dev/null || echo 0)"
  [ "$n" = "1" ] || {
    echo "    un bloqueo delegado registró $n eventos (esperaba 1): gate-value"
    echo "    inventaría actividad que no ocurrió."
    return 1; }
}
test_un_bloqueo_delegado_no_cuenta_dos_veces() {
  _bw_sandbox _case_delegacion_no_cuenta_dos_veces; }

# El contrato de fail-open, para la primitiva nueva: con la telemetría rota,
# hook_block tiene que seguir bloqueando.
_case_telemetria_rota_no_rompe_hook_block() {
  local d="$1"
  _bw_hook_con "$d" "gate-directo-sin-disco" 'hook_block "🛑 prueba"'
  rm -rf "$d/.agents/state/metrics"; printf 'no soy un directorio\n' > "$d/.agents/state/metrics"
  ( cd "$d" && bash gate-directo-sin-disco.sh >/dev/null 2>&1 )
  local rc=$?
  [ "$rc" = "2" ] || {
    echo "    con la telemetría rota hook_block dejó de bloquear (exit $rc)."
    return 1; }
}
test_telemetria_rota_no_impide_que_hook_block_bloquee() {
  _bw_sandbox _case_telemetria_rota_no_rompe_hook_block; }

# Un `read` de nivel superior en el archivo analizado NO puede colgar el
# análisis. Sourcear ejecuta ese nivel superior —es la contrapartida declarada
# de usar bash como parser— y sin `< /dev/null` el proceso se queda esperando
# una entrada que nadie va a escribir. Un test que se CUELGA es peor que uno que
# falla: bloquea la suite entera y, en CI, el job completo.
#
# La señal es LA SALIDA, no el exit code, y esa distinción costó un intento:
# la primera versión conectaba stdin a un FIFO y miraba el rc. Abrir un FIFO
# para lectura bloquea hasta que alguien lo abre para escribir, así que el test
# se colgaba ANTES de ejecutar el script y fallaba por su propio montaje —
# habría dado rojo también con el arreglo puesto. Con un pipe vivo sin datos la
# diferencia es limpia: con `< /dev/null` la línea aparece; sin él, no aparece
# nada.
_case_analizar_un_archivo_que_lee_stdin_no_cuelga() {
  local d; d="$(mktemp -d)"; local rc=0 i=0
  printf 'read -r _x\ndeny_tras_read() { exit 2; }\n' > "$d/lee.sh"
  : > "$d/out"
  # `sleep 30 |` mantiene stdin ABIERTO y sin datos, que es el caso real: un
  # descriptor vivo del que nunca llega nada.
  ( sleep 30 | _primitivas "$d/lee.sh" > "$d/out" 2>&1 ) >/dev/null 2>&1 &
  local pid=$!
  while [ "$i" -lt 60 ]; do
    grep -q 'deny_tras_read 1 0' "$d/out" 2>/dev/null && break
    sleep 0.25; i=$((i + 1))
  done
  pkill -P "$pid" -x sleep 2>/dev/null; kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  grep -q 'deny_tras_read 1 0' "$d/out" 2>/dev/null || {
    echo "    el análisis no produjo salida en 15s: se colgó leyendo el stdin"
    echo "    del archivo sourceado. Falta \`< /dev/null\` en la invocación."
    rc=1; }
  rm -rf "$d"; return $rc
}
test_analizar_un_archivo_que_lee_stdin_no_cuelga() {
  _case_analizar_un_archivo_que_lee_stdin_no_cuelga; }

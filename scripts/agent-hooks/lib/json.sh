#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# json.sh — emisor y lector JSON ÚNICO de review-history.jsonl (WF-03)
# ════════════════════════════════════════════════════════════════════
# Por qué existe (f-wf03-jsonl-sin-encoder, PRD 0005 fase 1a): el historial
# se construía con `printf` y saneado parcial. Comillas, backslashes, tabs o
# CR/LF en agent_id/scope invalidaban la línea — y los consumidores hacían
# `grep` sobre texto, así que una línea rota corrompía dedupe y auditoría en
# silencio. Aquí TODO se codifica con un runtime JSON real y TODO se lee
# parseando campos, nunca grepeando el texto.
#
# Contrato:
#   · runtime: jq si está; si no, python3; sin ninguno DEGRADA DECLARÁNDOLO
#     (stderr + exit≠0) — jamás se emite JSON malformado en silencio.
#   · schema v2: los campos v1 NO se renombran (contrato congelado, PRD 0005
#     §NO-TOUCH); se AÑADE "v":2. Las líneas v1 (sin "v") se siguen leyendo.
#   · append atómico por línea. MEDIDO sobre el FS del puente (fuseblk):
#     flock(1) funciona, pero unlink NO ("Operation not permitted") — un
#     write-temp+cat dejaría temporales imposibles de retirar. Se usa flock
#     sobre el fd del PROPIO archivo (sin lockfile auxiliar, sin basura) y,
#     donde no hay flock (macOS no lo trae), un único `printf` sobre un fd
#     O_APPEND: un solo write() para líneas cortas (probado en el puente:
#     200/200 líneas válidas con 4 escritores concurrentes).
#
# Lib SOURCEADA: sin `set -u` propio y sin +x — lo impone el llamador
# (misma regla que io.sh/verdict.sh; test_shell_hygiene la fija).

json_runtime() {
  if command -v jq >/dev/null 2>&1; then echo jq
  elif command -v python3 >/dev/null 2>&1; then echo python3
  else echo none; fi
}

_json_degradado() {
  printf 'json.sh DEGRADADO: sin jq ni python3 no se emite/parsea JSON. Se declara en vez de emitir una linea malformada en silencio.\n' >&2
}

# json_hist_line <ts> <agent> <run> <verdict> <findings> <scope> <head>
#                <staged_sha> <report> <nota>
#   → UNA línea JSON v2 por stdout (los escapes absorben CR/LF/tab/comillas).
#   Los 10 campos v1 conservan nombre y orden; "v":2 va al final.
json_hist_line() {
  # scope y nota llegan del mensaje del sub-agente sin limite. La atomicidad
  # del camino sin flock (macOS) descansa en "un solo write()", y eso solo es
  # verdad para lineas cortas: se recortan a 2000 chars (AMBER-5). El dedupe
  # usa run/agent/head/staged_sha/verdict — nada de lo recortado.
  local _scope _nota
  _scope="$(printf '%s' "${6:-}" | cut -c1-2000)"
  _nota="$(printf '%s' "${10:-}" | cut -c1-2000)"
  set -- "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-}" "$_scope" "${7:-}" "${8:-}" "${9:-}" "$_nota"
  case "$(json_runtime)" in
    jq)
      jq -nc --arg ts "${1:-}" --arg agent "${2:-}" --arg run "${3:-}" \
        --arg verdict "${4:-}" --arg findings "${5:-}" --arg scope "${6:-}" \
        --arg head "${7:-}" --arg staged_sha "${8:-}" --arg report "${9:-}" \
        --arg nota "${10:-}" \
        '{ts:$ts,agent:$agent,run:$run,verdict:$verdict,findings:$findings,scope:$scope,head:$head,staged_sha:$staged_sha,report:$report,nota:$nota,v:2}'
      ;;
    python3)
      python3 - "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" \
        "${7:-}" "${8:-}" "${9:-}" "${10:-}" <<'PY'
import json, sys
k = ["ts","agent","run","verdict","findings","scope","head","staged_sha","report","nota"]
o = dict(zip(k, (sys.argv[1:11] + [""] * 10)[:10]))
o["v"] = 2
print(json.dumps(o, ensure_ascii=False, separators=(",", ":")))
PY
      ;;
    *) _json_degradado; return 1 ;;
  esac
}

# json_append_line <archivo> <línea> — append atómico de UNA línea física.
json_append_line() {
  local file="${1:-}" line="${2:-}"
  [ -n "$file" ] && [ -n "$line" ] || return 1
  case "$line" in *$'\n'*)
    printf 'json.sh: linea con salto de linea crudo RECHAZADA (romperia el JSONL)\n' >&2
    return 1 ;;
  esac
  if command -v flock >/dev/null 2>&1; then
    { flock 9 2>/dev/null || true; printf '%s\n' "$line" >&9; } 9>>"$file"
  else
    printf '%s\n' "$line" >> "$file"
  fi
}

# json_hist_first_corrupt <archivo>
#   → imprime la PRIMERA línea que NO parsea como objeto JSON y sale 0.
#     1 = limpio (o sin archivo); 2 = sin runtime (declarado, no verificable).
#   Las líneas en blanco no cuentan como corrupción; una línea v1 válida
#   tampoco (backward). "No pude mirar" ≠ "está limpio": el llamador decide.
json_hist_first_corrupt() {
  local file="${1:-}" bad=""
  [ -f "$file" ] || return 1
  case "$(json_runtime)" in
    jq)
      # Se consulta el rc de jq: un jq ABORTADO (UTF-8 invalido en jq viejo,
      # bytes NUL) con 2>/dev/null mapeaba a bad="" = "limpio" — la clase
      # exacta de falso verde que este modulo existe para impedir (AMBER-4).
      local _out _rc
      _out="$(jq -rR '. as $l
        | if ($l | test("^\\s*$")) then empty
          elif (($l | fromjson? | type == "object") // false) then empty
          else $l end' "$file" 2>/dev/null)"; _rc=$?
      if [ "$_rc" -ne 0 ]; then
        printf '(jq no pudo procesar el archivo: rc=%s — tratado como corrupcion)\n' "$_rc"
        return 0
      fi
      bad="$(printf '%s\n' "$_out" | head -1)"
      ;;
    python3)
      bad="$(python3 - "$file" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as fh:
    for raw in fh:
        line = raw.rstrip("\n")
        if not line.strip():
            continue
        try:
            ok = isinstance(json.loads(line), dict)
        except Exception:
            ok = False
        if not ok:
            print(line)
            break
PY
)"
      ;;
    *) _json_degradado; return 2 ;;
  esac
  [ -n "$bad" ] || return 1
  printf '%s\n' "$bad"
  return 0
}

# json_hist_match <archivo> <agent> <run> <head> <staged_sha> [verdict]
#   → 0 si alguna entrada PARSEADA casa. Semántica EXACTA del _hist_grep
#     histórico (la fijan test_verdict.sh y test_review_history.sh):
#     run≠"" casa por run (identidad de la invocación); run="" cae al
#     criterio por agent; siempre head+staged_sha; verdict opcional.
#     Las líneas v1 (sin "v") casan igual: campo ausente = "".
json_hist_match() {
  local file="${1:-}" agent="${2:-}" run="${3:-}" head="${4:-}" sha="${5:-}" v="${6:-}"
  [ -f "$file" ] || return 1
  case "$(json_runtime)" in
    jq)
      jq -e --arg agent "$agent" --arg run "$run" --arg head "$head" \
        --arg sha "$sha" --arg v "$v" '
        select(type == "object")
        | select(if $run != "" then (.run // "") == $run else (.agent // "") == $agent end)
        | select((.head // "") == $head and (.staged_sha // "") == $sha)
        | select($v == "" or (.verdict // "") == $v)' "$file" >/dev/null 2>&1
      ;;
    python3)
      python3 - "$file" "$agent" "$run" "$head" "$sha" "$v" <<'PY'
import json, sys
path, agent, run, head, sha, v = (sys.argv[1:7] + [""] * 6)[:6]
with open(path, "r", encoding="utf-8", errors="replace") as fh:
    for raw in fh:
        try:
            o = json.loads(raw)
        except Exception:
            continue
        if not isinstance(o, dict):
            continue
        if run:
            if o.get("run", "") != run:
                continue
        elif o.get("agent", "") != agent:
            continue
        if o.get("head", "") != head or o.get("staged_sha", "") != sha:
            continue
        if v and o.get("verdict", "") != v:
            continue
        sys.exit(0)
sys.exit(1)
PY
      ;;
    *) _json_degradado; return 2 ;;
  esac
}

# json_hist_last_report <archivo> <head> <staged_sha>
#   → imprime .report de la ÚLTIMA entrada sobre ese diff (vacío si no hay).
#     Sustituye al sed sobre texto del puntero al reporte previo.
json_hist_last_report() {
  local file="${1:-}" head="${2:-}" sha="${3:-}"
  [ -f "$file" ] || return 0
  case "$(json_runtime)" in
    jq)
      jq -r --arg head "$head" --arg sha "$sha" '
        select(type == "object")
        | select((.head // "") == $head and (.staged_sha // "") == $sha)
        | .report // ""' "$file" 2>/dev/null | tail -1
      ;;
    python3)
      python3 - "$file" "$head" "$sha" <<'PY'
import json, sys
path, head, sha = (sys.argv[1:4] + [""] * 3)[:3]
last = None
with open(path, "r", encoding="utf-8", errors="replace") as fh:
    for raw in fh:
        try:
            o = json.loads(raw)
        except Exception:
            continue
        if not isinstance(o, dict):
            continue
        if o.get("head", "") == head and o.get("staged_sha", "") == sha:
            last = o.get("report", "")
if last is not None:
    print(last)
PY
      ;;
    *) _json_degradado; return 1 ;;
  esac
}

#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# io.sh — capa de I/O NORMALIZADA para hooks de IA (Claude Code + Cursor)
# ════════════════════════════════════════════════════════════════════
# Problema: Claude Code y Cursor pasan JSON por stdin con shapes distintos
# y esperan respuestas distintas. Esta librería abstrae ambas para que los
# gates (skill-reminder, reviewer-gate, …) se escriban UNA sola vez.
#
# Diferencias clave que abstraemos:
#   - Claude:  {tool_name, tool_input:{file_path,command}, session_id}
#   - Cursor:  {hook_event_name, conversation_id, generation_id,
#               tool_name?, tool_input:{...}, command?, file_path?}
#   - Bloqueo: AMBOS soportan `exit 2 + stderr` para bloquear la acción.
#              (En Cursor, exit 2 == permission:"deny"; en Claude, exit 2
#               bloquea y reinyecta stderr al modelo.) → usamos exit 2.
#
# Filosofía: FAILURE-OPEN. Si algo del hook revienta (jq falta, JSON raro),
# permitimos (exit 0). Un bug del hook NO debe trabar al dev. El backstop
# de lo que se cuele es el Anillo 3 (CI).
# ════════════════════════════════════════════════════════════════════

HOOK_INPUT=""

hook_read_input() { HOOK_INPUT="$(cat)"; }

# ¿qué cliente nos invocó? (heurística por keys propias de cada uno)
hook_client() {
  command -v jq >/dev/null 2>&1 || { echo "unknown"; return; }
  local cid
  cid="$(printf '%s' "$HOOK_INPUT" | jq -r '.conversation_id // .generation_id // empty' 2>/dev/null)"
  if [ -n "$cid" ]; then echo "cursor"; else echo "claude"; fi
}

# Extrae un campo con fallbacks, agnóstico al cliente.
_hook_jq() { printf '%s' "$HOOK_INPUT" | jq -r "$1" 2>/dev/null || true; }

hook_tool()       { command -v jq >/dev/null 2>&1 && _hook_jq '.tool_name // empty'; }
hook_file_path()  { command -v jq >/dev/null 2>&1 && _hook_jq '.tool_input.file_path // .file_path // empty'; }
hook_command()    { command -v jq >/dev/null 2>&1 && _hook_jq '.tool_input.command // .command // empty'; }
hook_session_id() { command -v jq >/dev/null 2>&1 && _hook_jq '.session_id // .conversation_id // .generation_id // "unknown"'; }
hook_event()      { command -v jq >/dev/null 2>&1 && _hook_jq '.hook_event_name // empty'; }

# ── Campos de sub-agente (SubagentStart / SubagentStop) ─────────────
hook_agent_type() { command -v jq >/dev/null 2>&1 && _hook_jq '.agent_type // empty'; }
hook_agent_id()   { command -v jq >/dev/null 2>&1 && _hook_jq '.agent_id // empty'; }
# El mensaje final del sub-agente: de aquí se DERIVA el veredicto (lib/verdict.sh).
hook_last_message() { command -v jq >/dev/null 2>&1 && _hook_jq '.last_assistant_message // empty'; }

# Ruta relativa al repo (los hooks razonan en rutas relativas).
hook_rel_path() {
  local abs="$1" root="${PROJECT_ROOT:-$(pwd)}"
  printf '%s' "${abs#${root}/}"
}

# ── Decisiones (universales vía exit code) ──────────────────────────
# _hook_log_block <fase> [rule] [area] — instrumenta UN bloqueo, UNA vez.
#
# Va en las PRIMITIVAS, no en cada call-site: enumerar sitios es exactamente el
# error que costó ocho rondas en el bypass de scope. La fuente se DERIVA del
# script que llama, así que un hook nuevo queda instrumentado el día que se
# escribe y no el día que alguien se acuerda de añadirlo a una lista.
#
# "Todas las primitivas de bloqueo pasan por aquí" NO es una afirmación de este
# comentario: lo enumera `test_toda_primitiva_de_bloqueo_esta_instrumentada`
# (tools/tests/test_metrics.sh), que relee ESTE archivo con
# `tools/tests/lib/primitivas-de-bloqueo.sh`, DERIVA qué funciones deniegan y
# falla si alguna no registra. La versión anterior sí era solo un comentario
# —decía "por aquí pasan TODOS los bloqueos" escrito sobre `hook_block_or_warn`,
# que es UNA de tres— y con ella el git-guard bloqueaba `--no-verify`,
# `push --force` y `reset --hard` sin dejar rastro (f-2bd11525).
#
# ALCANCE EXACTO, porque prometer de más aquí es el bug que este comentario
# arrastra. Ese inventario NO reconoce formas de bash con regex —dos versiones
# lo intentaron y acumularon cinco puntos ciegos, cazados de uno en uno—: lo
# hace **bash**, sourceando este archivo en un subshell y preguntando a
# `declare -f`. Por eso no hay shape que se le escape: no hay shape que
# reconocer. Sus propios límites los fijan
# `test_el_inventario_caza_una_primitiva_no_instrumentada_en_toda_forma` y
# `test_el_inventario_no_inventa_primitivas_ni_falsos_incumplimientos` — un
# meta-test sin tests es la misma sobre-afirmación una capa más adentro.
# Lo que NO cubre y conviene saber: una denegación escrita FUERA de cualquier
# función (nivel superior del archivo), o en otro archivo.
#
# `fase` (block|warn) viaja en rule/area, no en el campo `phase`: el bucket de
# phase lo deriva `hook_log_detection` por `source`, que es lo que quiere
# gate-value. Aquí se pasa igualmente para no cambiar esa derivación.
#
# El guard evita el doble conteo cuando una primitiva delega en otra
# (`hook_json_block` → `hook_block` para eventos sin shape JSON conocido).
_HOOK_BLOCK_LOGGED=""
_hook_log_block() {
  [ -n "$_HOOK_BLOCK_LOGGED" ] && return 0
  _HOOK_BLOCK_LOGGED=1
  local _lb_fase="${1:-block}" _lb_src
  _lb_src="$(basename "${0:-hook}" .sh)"
  # Best-effort TOTAL: hook_log_detection ya corre en subshell con `set +e` y
  # devuelve 0 pase lo que pase, pero el `|| true` deja el contrato explícito.
  # Instrumentar un gate no puede convertirlo en fail-open — lo fijan los
  # tests `*_no_impide_que_el_gate_bloquee`.
  hook_log_detection "$_lb_src" "${2:-$_lb_fase}" "${3:-$_lb_fase}" 1 "" "$_lb_fase" || true
  return 0
}

# BLOQUEAR: imprime razón a stderr + exit 2. Funciona en Claude y Cursor.
hook_block() {
  _hook_log_block block
  printf '%s\n' "$1" >&2
  exit 2
}

# PERMITIR: exit 0 silencioso.
hook_allow() { exit 0; }

# ── Salida JSON estructurada (solo Claude Code) ─────────────────────
# Claude Code parsea stdout como JSON en exit 0. Cursor lo ignora sin romperse,
# así que es seguro emitirlo siempre. Nos da dos cosas que `exit 2` no puede:
#
#   1. `additionalContext` — INYECTAR texto en el contexto del agente sin
#      bloquearlo. Es el mecanismo del bucle de verificación in-loop: el
#      linter falla → el agente lo lee en el mismo turno → lo corrige.
#   2. `decision: block` con razón, sin depender del exit code.
#
# hook_context <evento> <texto>   → informa (no bloquea)
hook_context() {
  local ev="$1" ctx="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg e "$ev" --arg c "$ctx" \
      '{hookSpecificOutput:{hookEventName:$e, additionalContext:$c}}'
  else
    # Sin jq: degradamos a stderr, que el agente también ve.
    printf '%s\n' "$ctx" >&2
  fi
  exit 0
}

# hook_json_block <evento> <razón>  → bloquea vía JSON (equivalente a exit 2)
#
# EL SHAPE DEPENDE DEL EVENTO (contrato documentado de Claude Code):
#   Stop|SubagentStop → top-level  {"decision":"block","reason":"…"}
#   PreToolUse        → {"hookSpecificOutput":{"permissionDecision":"deny",…}}
# La versión anterior emitía `hookSpecificOutput.decision` para TODOS los
# eventos — un shape que Stop/SubagentStop ignoran: el "bloqueo" del cierre
# del sub-agente sin contrato VERDICT no bloqueaba nada (gate mudo).
# Fijado por tools/tests/test_hook_json_shapes.sh.
hook_json_block() {
  local ev="$1" why="$2"
  _hook_log_block block
  if command -v jq >/dev/null 2>&1; then
    case "$ev" in
      Stop|SubagentStop|stop)
        jq -nc --arg r "$why" '{decision:"block", reason:$r}' ;;
      PreToolUse|preToolUse)
        jq -nc --arg e "PreToolUse" --arg r "$why" \
          '{hookSpecificOutput:{hookEventName:$e, permissionDecision:"deny", permissionDecisionReason:$r}}' ;;
      *)
        # Evento sin shape de bloqueo JSON conocido → exit 2 universal.
        hook_block "$why" ;;
    esac
    exit 0
  fi
  hook_block "$why"
}

# ── Marcadores de estado compartidos (ambos clientes) ───────────────
# Viven en .agents/state/ (gitignored) para que Claude y Cursor compartan.
hook_state_dir() { echo "${PROJECT_ROOT:-$(pwd)}/.agents/state"; }

# ── Preset: full (default, equipo) | lite (personal) ────────────────
# Lite degrada los gates "blandos" (skill-read, reviewer-marker) de BLOQUEAR a AVISAR.
# El drift-ratchet y canon/drift-stop siguen DUROS en ambos presets.
# Fuente: env WORKFLOW_PRESET, o la primera palabra de tools/preset.
hook_preset() {
  local p="${WORKFLOW_PRESET:-}" root="${PROJECT_ROOT:-$(pwd)}"
  [ -z "$p" ] && [ -f "$root/tools/preset" ] && p="$(awk 'NR==1{print $1; exit}' "$root/tools/preset" 2>/dev/null)"
  case "$p" in lite) echo lite ;; *) echo full ;; esac
}

# Bloquea (exit 2) en full; avisa a stderr y permite (exit 0) en lite.
# hook_block_or_warn <mensaje> [rule] [area]
#
# La fase 3 de PRD 0005 destapó por qué el registro importa: el informe de valor
# por gate daba CERO eventos para casi todos, y `gate-value.sh` avisa de que un
# cero es ambiguo entre disuasión y mudo. Había un TERCER estado que nadie
# contemplaba — el gate disparó, bloqueó, hizo su trabajo, y no dejó rastro. En
# la sesión que lo descubrió, el git-guard y el `skill-reminder` bloquearon dos
# veces cada uno y los dos figuraban con cero.
#
# Esta primitiva es la ÚNICA que distingue `block` de `warn`: un gate que avisa
# mucho en `lite` es candidato a revisión igual que uno que bloquea, pero solo
# si queda constancia de que avisó. El registro en sí lo hace `_hook_log_block`,
# común a las tres primitivas.
hook_block_or_warn() {
  local _bw_preset _bw_fase
  _bw_preset="$(hook_preset)"
  [ "$_bw_preset" = "lite" ] && _bw_fase="warn" || _bw_fase="block"
  _hook_log_block "$_bw_fase" "${2:-}" "${3:-}"
  if [ "$_bw_preset" = "lite" ]; then printf '⚠️  [lite] %s\n' "$1" >&2; exit 0; fi
  printf '%s\n' "$1" >&2; exit 2
}

# ── Telemetría de detecciones (alimenta gate-value) ─────────────────
# hook_log_detection <source> <rule> <area> [n] [duration_ms] [phase]
#
# El eslabón que faltaba en el bucle de aprendizaje: los gates DETECTABAN y
# todo se descartaba. Desde el schema v2, los eventos miden actividad/latencia
# en gate-value; solo su promoción durable al ledger alimenta escape-rate.
#
# Es un EVENTO de métrica, no un finding curado: va a un canal local separado
# (.agents/state/, gitignored, como la trayectoria) para no ahogar el ledger.
#
# CONTRATO DURO: best-effort TOTAL. La telemetría JAMÁS puede romper al gate
# que la llama — siempre devuelve 0, pase lo que pase (sin python3, sin disco,
# sin git). Fijado por test_telemetria_rota_jamas_rompe_al_gate.
_hook_json_string() {
  local value="${1:-}" oct ch
  # JSON prohíbe U+0000–U+001F crudos. Bash no puede transportar NUL, pero sí
  # los otros 31; se reemplazan por espacio para conservar una sola línea y
  # no depender de python/jq en el emisor best-effort.
  for oct in 001 002 003 004 005 006 007 010 011 012 013 014 015 016 017 \
             020 021 022 023 024 025 026 027 030 031 032 033 034 035 036 037; do
    printf -v ch '%b' "\\$oct"
    value="${value//$ch/ }"
  done
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

hook_log_detection() {
  (
    set +e
    local src="${1:-?}" rule="${2:-?}" area="${3:-?}" n="${4:-1}"
    local duration="${5:-}" phase="${6:-}" duration_json="null"
    local dir="${PROJECT_ROOT:-$(pwd)}/.agents/state/metrics"
    mkdir -p "$dir" 2>/dev/null || exit 0
    case "$n" in
      ''|*[!0-9]*) n=1 ;;
      *) while [ "$n" != "0" ] && [ "${n#0}" != "$n" ]; do n="${n#0}"; done ;;
    esac
    case "$duration" in
      ''|*[!0-9]*) : ;;
      *)
        while [ "$duration" != "0" ] && [ "${duration#0}" != "$duration" ]; do
          duration="${duration#0}"
        done
        duration_json="$duration" ;;
    esac

    # La fase no se infiere después desde prosa ni desde `rule`: se fija al
    # emitir. Los callers viejos no la pasaban, así que el fallback explícito
    # conserva su bucket histórico por source durante la transición v1→v2.
    case "$phase" in
      in-loop|gate|review|ci|human|prod) : ;;
      *)
        case "$src" in
          post-edit-verify|linter|typecheck) phase="in-loop" ;;
          reviewer|security-reviewer|design-reviewer|process-judge) phase="review" ;;
          ci) phase="ci" ;;
          human-review) phase="human" ;;
          prod|user-report|incident) phase="prod" ;;
          *) phase="gate" ;;
        esac ;;
    esac

    # JSON a mano, sin dependencia de python3/jq a propósito: una máquina sin
    # runtime puede perder telemetría, pero jamás romper el gate que la llama.
    # Se eliminan todos los controles que harían inválida una línea JSONL.
    src="$(_hook_json_string "$src")"
    rule="$(_hook_json_string "$rule")"
    area="$(_hook_json_string "$area")"

    # ── Anti-ráfaga: el MISMO evento repetido no son N detecciones ─────
    # Observado en vivo: un SubagentStop puede dispararse 8-10 veces para el
    # mismo veredicto, y el log acababa con diez líneas idénticas separadas
    # por segundos. Eso no es ruido cosmético: gate-value mide actividad y
    # latencia contando estos eventos, así que una ráfaga inventa nueve
    # detecciones que nunca ocurrieron. Ventana corta y caché de una ranura (las ráfagas son
    # contiguas): barato, sin parsear el JSONL y sin tocar su esquema.
    # Un evento legítimamente repetido más tarde SÍ se registra.
    local win="${DETECTION_DEDUP_WINDOW:-120}" now prev commit
    now="$(date +%s 2>/dev/null || echo 0)"
    if ! commit="$(git -C "${PROJECT_ROOT:-$(pwd)}" rev-parse HEAD 2>/dev/null)"; then
      commit="unknown"
    fi
    [ -n "$commit" ] || commit="unknown"
    commit="$(_hook_json_string "$commit")"
    local key="$src|$rule|$area|$n|$phase|$commit"
    local cache="$dir/.last-detection"
    if [ "$now" != "0" ] && [ -f "$cache" ]; then
      prev="$(cat "$cache" 2>/dev/null)"
      case "$prev" in
        *"|$key")
          local pts="${prev%%|*}"
          case "$pts" in
            ''|*[!0-9]*) : ;;
            *) [ "$((now - pts))" -lt "$win" ] && exit 0 ;;
          esac ;;
      esac
    fi
    printf '%s|%s' "$now" "$key" > "$cache" 2>/dev/null

    # `mktemp` presta unicidad local/concurrente sin depender de uuidgen. El
    # archivo solo reserva el sufijo y se retira antes de appendear el evento.
    local token_file token event_id ts
    token_file="$(mktemp "$dir/.event-id.XXXXXX" 2>/dev/null)"
    if [ -n "$token_file" ]; then
      token="${token_file##*.event-id.}"
      rm -f "$token_file" 2>/dev/null
    else
      token="$$-${RANDOM:-0}"
    fi
    event_id="evt-${now}-${token}"
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"
    printf '{"schema":2,"event_id":"%s","ts":"%s","phase":"%s","source":"%s","duration_ms":%s,"commit":"%s","triage":"unknown","rule":"%s","area":"%s","n":%s}\n' \
      "$event_id" "$ts" "$phase" "$src" "$duration_json" "$commit" \
      "$rule" "$area" "$n" >> "$dir/detections.jsonl" 2>/dev/null
    exit 0
  ) 2>/dev/null
  return 0
}

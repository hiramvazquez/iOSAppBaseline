#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# post-edit-verify.sh — hook PostToolUse Edit|Write|MultiEdit|Bash
# ════════════════════════════════════════════════════════════════════
# EL BUCLE DE VERIFICACIÓN IN-LOOP. Es el gate de mayor ROI del harness.
#
# Sin él, el agente no recibe señal mecánica hasta el `Stop` o el commit: un
# error de tipos del turno 3 se descubre en el turno 40, con 37 turnos de
# trabajo construidos encima y el contexto ya contaminado. Con él, el linter
# corre sobre EL ARCHIVO QUE ACABA DE TOCAR y el resultado vuelve al agente
# vía `additionalContext` en el mismo turno.
#
# Reglas de diseño (importan tanto como el script):
#   - NUNCA bloquea. Solo informa. Un formateador con una opinión no debe
#     poder trabar el trabajo; para lo que sí debe bloquear están canon-enforce
#     (Stop) y los anillos 1 y 3.
#   - Solo los archivos tocados, jamás el repo. Debe costar < 2s (tope de 5).
#   - Silencioso cuando todo está bien: ruido constante = ruido ignorado.
#   - Sin linter configurado → no-op silencioso (lo reporta el health-check
#     del SessionStart, no cada edición).
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=lib/io.sh
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"
cd "$PROJECT_ROOT" || exit 0

hook_read_input
EV="PostToolUse"

# ── QUÉ ARCHIVOS MIRAR ──────────────────────────────────────────────
# Antes solo `Edit|Write`, y ahí estaba el agujero: en una sesión medida, 589
# de 609 tool-calls fueron Bash y ninguna Edit, así que 533 líneas de shell
# nuevo no recibieron NI UNA pasada del nivel 1 — el gate de mayor ROI del
# harness, mudo por el matcher (f-ee9787d9). Escribir con `sed -i`, un heredoc
# o `python3 -c` es escribir igual.
#
# Para Bash no se parsea el comando —esa carrera se pierde— sino que se
# OBSERVA el efecto: `lib/writes.sh` compara contra una marca temporal.
FILES=""
case "$(hook_tool)" in
  Edit|Write|MultiEdit|create_file|edit_file|search_replace|str_replace*)
    FILES="$(hook_file_path)" ;;
  Bash|run_terminal_cmd|shell)
    # shellcheck source=lib/writes.sh
    . "$PROJECT_ROOT/scripts/agent-hooks/lib/writes.sh"
    FILES="$(writes_since_mark)" ;;
  *) hook_allow ;;
esac
[ -z "$FILES" ] && hook_allow

OUT=""
add() { [ -n "$1" ] && OUT="${OUT}$1"$'\n'; }
# Corre un comando con timeout suave y captura solo si falla.
try() { # try <etiqueta> <comando...>
  local label="$1"; shift
  command -v "$1" >/dev/null 2>&1 || return 0
  local o; o="$("$@" 2>&1)"; local rc=$?
  [ $rc -eq 0 ] && return 0
  add "── $label ──"
  add "$(printf '%s' "$o" | head -25)"
}

# verify_one <ruta-absoluta> — acumula en OUT lo que encuentre de ESE archivo.
# Antes esto era el cuerpo del script y solo podia mirar uno; ahora hay que
# poder recorrer los N que escribio un comando de Bash.
verify_one() {
  local FILE="$1" REL o n dq legacy
  [ -f "$FILE" ] || return 0
  REL="$(hook_rel_path "$FILE")"

case "$REL" in
  # ── Shell: el harness es shell, así que esto SÍ está cableado ─────
  *.sh)
    try "shellcheck $REL" shellcheck -S warning "$FILE"
    try "bash -n $REL"    bash -n "$FILE"
    ;;

  # ── JSON / YAML: errores de sintaxis que rompen configs silenciosamente ─
  *.json)
    if command -v jq >/dev/null 2>&1; then
      o="$(jq empty "$FILE" 2>&1)" || { add "── JSON inválido en $REL ──"; add "$o"; }
    fi
    ;;
  *.yaml|*.yml)
    if command -v yq >/dev/null 2>&1; then
      o="$(yq e '.' "$FILE" 2>&1 >/dev/null)" || { add "── YAML inválido en $REL ──"; add "$o"; }
    fi
    ;;

  # ── Swift (referencia iOS, ACTIVA — se auto-desactiva sin toolchain) ─
  # Cableado nacido en el primer proyecto real y promovido al template.
  # swift-format viene con Xcode: cero instalación. Calibra `.swift-format`
  # al estilo de TU editor (la referencia: 4 espacios/120 cols) — con defaults
  # ajenos grita en TODOS los archivos y un linter así se desactiva entero
  # (ley del 10%, AGENTS.md §14). Sin `--strict`: ahogaría la señal real.
  # El typecheck completo es caro (simulador) → va en el commit, no aquí.
  *.swift)
    try "swift-format lint $REL" swift-format lint "$FILE"
    # Anti-patrones Swift 6.2 que el compilador NO caza pero la skill
    # `swift-estado-del-arte.md` prohíbe. Solo patrones EXACTOS (ley del 10%).
    legacy=""
    dq="$(grep -nE '^[^/]*DispatchQueue\.(main|global)' "$FILE" 2>/dev/null | head -3)"
    [ -n "$dq" ] && legacy="${legacy}GCD en código nuevo → usa async/await o @MainActor:
$dq
"
    grep -qE '^[^/]*: *ObservableObject' "$FILE" 2>/dev/null \
      && legacy="${legacy}ObservableObject → usa @Observable (Swift 6.2 / iOS 17+).
"
    grep -qE '@unchecked +Sendable' "$FILE" 2>/dev/null \
      && legacy="${legacy}@unchecked Sendable requiere justificación escrita del invariante (AGENTS.md §3).
"
    [ -n "$legacy" ] && { add "── Swift 6.2: estado del arte ──"; add "$legacy"; }
    ;;
  # <!-- FILL: cablea el lint/typecheck del RESTO de tu stack. Regla: solo el
  #      archivo tocado, < 2s, y texto accionable. Ejemplos:
  #  *.kt|*.kts)  try "ktlint"  ktlint "$FILE" ;;
  #  *.ts|*.tsx)  try "eslint"  npx --no-install eslint --format unix "$FILE" ;;
  #  *.py)        try "ruff"    ruff check "$FILE" ;;
  # -->
  *) : ;;
esac

# ── Señales universales, independientes del stack ───────────────────
# Tamaño de archivo (AGENTS.md §4): avisar en el momento en que se cruza el
# límite, no en el review, cuando dividirlo ya cuesta 10× más.
HARD=${DRIFT_FILE_HARD:-400}; SOFT=${DRIFT_FILE_SOFT:-200}
case "$REL" in
  *.swift|*.kt|*.kts|*.ts|*.tsx|*.js|*.jsx|*.py|*.java|*.go|*.rb|*.rs)
    n=$(wc -l < "$FILE" 2>/dev/null | tr -d ' ')
    if [ "${n:-0}" -gt "$HARD" ]; then
      add "── tamaño ──"
      add "$REL tiene $n líneas (hard limit $HARD, AGENTS.md §4). Divídelo en ESTE mismo cambio."
    elif [ "${n:-0}" -gt "$SOFT" ]; then
      add "── tamaño ──"
      add "$REL tiene $n líneas (soft limit $SOFT). Vale la pena revisar si ya son dos responsabilidades."
    fi
    ;;
esac
  REVISADOS="${REVISADOS} ${REL}"
}

# Tope de 5 archivos: el contrato de este hook es "< 2s, jamás bloquea". Un
# comando que toca 40 archivos no puede convertir el bucle in-loop en una
# espera. Cuando se recorta se DICE — un gate que mira menos de lo que parece
# es exactamente lo que este cambio viene a arreglar.
REVISADOS=""; VISTOS=0; OMITIDOS=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  # Formato `<estado><TAB><ruta>`: `?` = no se pudo comparar contenido. Aquí se
  # lintá igual, porque para "¿qué reviso?" mirar de más es barato. Se corta por
  # el TABULADOR y no por un prefijo pegado: un archivo puede llamarse `?x.sh`.
  f="${f#*"$(printf '\t')"}"
  case "$f" in /*) : ;; *) f="$PROJECT_ROOT/$f" ;; esac
  if [ "$VISTOS" -ge 5 ]; then OMITIDOS=$((OMITIDOS + 1)); continue; fi
  VISTOS=$((VISTOS + 1))
  verify_one "$f"
done <<EOF_FILES
$FILES
EOF_FILES
[ "$OMITIDOS" -gt 0 ] && add "(y $OMITIDOS archivo(s) más sin revisar: el hook mira 5 por turno)"

[ -z "$OUT" ] && hook_allow   # todo limpio → silencio

# Telemetría (nivel 9): la señal in-loop encontró algo — es el bucket más
# barato de gate-value; si se promueve a finding, el ledger alimenta escape-rate.
# Best-effort, jamás afecta al flujo.
hook_log_detection "post-edit-verify" "in-loop" "${REVISADOS# }" 1

hook_context "$EV" "🔧 Verificación automática de \`${REVISADOS# }\` (no bloquea, pero arréglalo AHORA — cuesta 10× menos que en el review):

$OUT"

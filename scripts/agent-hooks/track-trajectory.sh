#!/usr/bin/env bash
# Hook PostToolUse * (Claude) / postToolUse (Cursor) — observe-only.
# Registra una TRAYECTORIA compacta y SIN SECRETOS/PII de las tool-calls,
# para que el sub-agente `process-judge` juzgue *cómo* se construyó un trabajo.
#
# PHI/secret-safety (crítico): SOLO metadata. NUNCA contenido de archivos,
# argumentos de comandos, prompts ni patrones de búsqueda. Del comando solo
# tomamos el PRIMER token (el binario) y lo descartamos si es `VAR=valor`
# (un secreto puede preceder al binario: `SERVICE_ROLE_KEY=… deno run`).
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"
command -v jq >/dev/null 2>&1 || exit 0

hook_read_input
tool="$(hook_tool)"; [ -z "$tool" ] && exit 0
sid="$(hook_session_id)"; sid="$(printf '%s' "$sid" | tr -cd 'A-Za-z0-9._-')"; [ -z "$sid" ] && sid="unknown"

# path seguro: file_path | primer token del command (descartando VAR=...)
path="$(printf '%s' "$HOOK_INPUT" | jq -rc '
  (.tool_input // {}) as $i
  | ( $i.file_path // .file_path
      // (($i.command // .command // "") | split(" ") | (.[0] // "") | if test("=") then "" else . end)
      // "" )' 2>/dev/null || true)"
case "$path" in "$PROJECT_ROOT"/*) path="${path#${PROJECT_ROOT}/}" ;; esac

# Para Bash, el primer token es el BINARIO, no el archivo: la trayectoria de una
# sesión entera quedaba en `python3`, `sed`, `cat` y cadenas vacías, y con eso el
# `process-judge` no puede responder su pregunta nº1 —¿leyó la skill requerida
# ANTES de editar?— porque no sabe qué se editó (f-153aef5b). `lib/writes.sh`
# observa qué archivos cambiaron de verdad. Se registran en `writes`, aparte de
# `path`, para no romper a quien ya lee el esquema viejo.
writes=""; inciertos=0
case "$tool" in
  Bash|run_terminal_cmd|shell)
    # shellcheck source=lib/writes.sh
    if . "$PROJECT_ROOT/scripts/agent-hooks/lib/writes.sh" 2>/dev/null; then
      # Las rutas marcadas con `?` son "no lo sé", no "cambió": el detector pasó
      # de su tope y no pudo comparar contenido. Aquí NO se registran como
      # escrituras — la trayectoria es EVIDENCIA de qué tocó este comando, y
      # afirmar de más aquí es peor que no saber: una vez cruzado el tope,
      # hasta un `ls` arrastraría los mismos archivos como si los hubiera
      # escrito. Se cuenta cuántas eran, para que el juez sepa que la lista
      # está incompleta en vez de creerla completa.
      # `awk` y no `grep -c`: con cero coincidencias `grep -c` imprime 0 pero
      # SALE 1, así que el `|| echo 0` de rigor añadía un segundo 0 y la
      # variable acababa con dos líneas. Hoy lo tapaba el saneo de más abajo;
      # `awk` da un número y sale 0 siempre, sin tapadera.
      _wsm="$(writes_since_mark)"
      inciertos="$(printf '%s\n' "$_wsm" | awk -F'\t' '$1=="?"{n++} END{print n+0}')"
      # Las rutas viajan separadas por SALTO DE LÍNEA, no por espacio. Unirlas
      # con espacios y volver a partirlas por espacio usaba el mismo carácter
      # como separador y como contenido: `con espacios.txt` se convertía en dos
      # rutas fantasma (`con` y `espacios.txt`) que nunca existieron, mientras
      # la real desaparecía. Evidencia activamente falsa para el juez, que es
      # peor que no tener ninguna — y justo lo que f-153aef5b viene a arreglar.
      # `sub` y no `$2`: la ruta PUEDE contener tabuladores —porcelain `-z` no
      # los escapa— y quedarse con "el campo 2" la TRUNCA, registrando como
      # escritura confirmada una ruta que no existe. Se corta por el PRIMER
      # tabulador y se conserva todo el resto.
      writes="$(printf '%s\n' "$_wsm" \
        | awk -F'\t' '$1=="ok"{sub(/^[^\t]*\t/, ""); print}' | head -20)"
    fi ;;
esac
case "$inciertos" in ''|*[!0-9]*) inciertos=0 ;; esac

dir="$(hook_state_dir)/trajectory"; mkdir -p "$dir" 2>/dev/null || exit 0
line="$(jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg sid "$sid" --arg tool "$tool" \
  --arg path "$path" --arg writes "$writes" --argjson inciertos "${inciertos:-0}" \
  '{ts:$ts, sid:$sid, tool:$tool, path:$path}
   + (if $writes == "" then {} else {writes:($writes|split("\n")|map(select(length>0)))} end)
   + (if $inciertos == 0 then {} else {writes_inciertos:$inciertos} end)' \
  2>/dev/null || true)"
[ -n "$line" ] && printf '%s\n' "$line" >> "$dir/${sid}.jsonl" 2>/dev/null || true
exit 0

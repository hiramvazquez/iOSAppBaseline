#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# skill-matrix.sh — la matriz path→refs, en UN solo sitio
# ════════════════════════════════════════════════════════════════════
# Antes esta lógica vivía dentro de `skill-reminder.sh`, y eso bastaba
# mientras el único camino para escribir un archivo fuera la tool Edit. No lo
# es: `sed -i`, `tee`, una redirección o un `python3 -c` escriben igual y
# pasan por Bash, donde la matriz no miraba. Por ahí se coló una decisión de
# arquitectura real en el primer proyecto.
#
# Al necesitarla DOS llamadores (el hook de Edit y el guard de Bash), la
# lógica se extrae aquí: duplicarla habría sido reproducir exactamente el
# problema que la propia matriz resolvió cuando vivía en cinco sitios y
# divergía. Una regla implementada dos veces diverge; es cuestión de tiempo.
#
# API:
#   matrix_refs_for <ruta-relativa>      → imprime las refs requeridas (una por línea)
#   matrix_is_exempt <ruta-relativa>     → exit 0 si es doc/tooling (no código de producto)
#   matrix_missing_refs <ruta-relativa>  → imprime solo las refs NO leídas en esta sesión

# Rutas que NUNCA son código de producto. Editar la documentación de un área
# no es editar el código de esa área — era un falso positivo real (editar la
# skill de dominio exigía leer la skill de dominio) y un gate con falsos
# positivos se acaba desactivando entero (ley del 10%).
matrix_is_exempt() {
  case "$1" in
    .agents/*|.claude/*|.cursor/*|docs/*|tools/*|scripts/*|ci/*|enterprise/*|*.md)
      case "$1" in
        docs/process/prds/[0-9]*.md) return 1 ;;   # los PRDs numerados SÍ tienen regla
        *) return 0 ;;
      esac ;;
  esac
  return 1
}

matrix_refs_for() {
  local rel="$1" glob refs r
  local matrix="${PROJECT_ROOT:-$(pwd)}/tools/skill-matrix.conf"
  [ -f "$matrix" ] || return 0
  while IFS='|' read -r glob refs; do
    case "$glob" in ''|'#'*) continue ;; esac
    glob="$(printf '%s' "$glob" | sed -E 's/[[:space:]]+$//')"
    # shellcheck disable=SC2254  # el glob DEBE expandirse como patrón
    case "$rel" in
      $glob)
        local _oldIFS="$IFS"; IFS=','
        for r in $refs; do
          r="$(printf '%s' "$r" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
          [ -n "$r" ] && printf '%s\n' "$r"
        done
        IFS="$_oldIFS" ;;
    esac
  done < "$matrix"
}

matrix_missing_refs() {
  local rel="$1" ref flat
  local dir="${SKILLS_READ_DIR:-$(hook_state_dir)/skills-read}"
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    flat="${ref//\//__}"
    [ -f "$dir/${flat}.read" ] || printf '%s\n' "$ref"
  done < <(matrix_refs_for "$rel" | sort -u)
}

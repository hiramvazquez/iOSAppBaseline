#!/usr/bin/env bash
# Hook PreToolUse Edit|Write (Claude) / preToolUse (Cursor) — BLOQUEANTE.
# Si el path a editar requiere leer ciertas skill references y NO hay marker
# de lectura en esta sesión → bloquea (exit 2). El modelo lee los refs
# (track-reads.sh los marca) y reintenta.
#
# Failure-open: cualquier glitch → exit 0 (permite). Backstop = CI.
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=lib/io.sh
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"

hook_read_input

tool="$(hook_tool)"
# Solo nos importan herramientas de edición/escritura.
case "$tool" in
  Edit|Write|MultiEdit|create_file|edit_file|search_replace|str_replace*) : ;;
  *) hook_allow ;;
esac

file_path="$(hook_file_path)"
[ -z "$file_path" ] && hook_allow
rel="$(hook_rel_path "$file_path")"

# ── Exclusiones: DOCUMENTACIÓN no es CÓDIGO ─────────────────────────
# Sin esto, editar `.agents/skills/domain/SKILL.md` casa con el glob `*/domain/*`
# y exige leer las skills de dominio para editar… la propia skill de dominio.
# Es un falso positivo, y un gate con falsos positivos se acaba desactivando
# entero (ley del 10%, ver verification-loop.md nivel 2). La matriz de §11 habla
# de código de producto; estas rutas nunca lo son.
case "$rel" in
  .agents/*|.claude/*|.cursor/*|docs/*|tools/*|scripts/*|ci/*|enterprise/*|*.md)
      # Excepción: los PRDs numerados SÍ tienen su propia regla más abajo.
      case "$rel" in
        docs/process/prds/[0-9]*.md) : ;;
        *) hook_allow ;;
      esac
      ;;
esac

# ── Matriz path → lectura obligatoria ───────────────────────────────
# FUENTE ÚNICA: tools/skill-matrix.conf (formato `glob|ref1,ref2`).
# Antes esta matriz vivía en CINCO sitios (aquí, AGENTS.md §11, frontmatter
# de las skills, .claude/rules/, .cursor/rules/) y "Nada se duplica" era
# mentira: cambiar una carpeta exigía tocar cinco archivos, y el primero en
# divergir era justo este — el que bloquea. Ahora este hook LEE el conf en
# runtime; AGENTS.md §11 es la vista humana del mismo conf.
declare -a required=()
MATRIX="$PROJECT_ROOT/tools/skill-matrix.conf"
if [ -f "$MATRIX" ]; then
  while IFS='|' read -r glob refs; do
    # comentarios y vacías fuera
    case "$glob" in ''|'#'*) continue ;; esac
    glob="$(printf '%s' "$glob" | sed -E 's/[[:space:]]+$//')"
    # shellcheck disable=SC2254  # el glob DEBE expandirse como patrón
    case "$rel" in
      $glob)
        _oldIFS="$IFS"; IFS=','
        for r in $refs; do
          r="$(printf '%s' "$r" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
          [ -n "$r" ] && required+=("$r")
        done
        IFS="$_oldIFS" ;;
    esac
  done < "$MATRIX"
else
  # Fallback de fábrica si el conf no existe (repo recién clonado a medias).
  case "$rel" in
    *View*.swift|*.tsx|*Screen*.kt|*/ui/*)
        required+=(".agents/skills/architecture/SKILL.md") ;;
  esac
  case "$rel" in
    *Logic*.swift|*UseCase*.swift|*UseCase*.kt|*/services/*.ts|*/domain/*|*/Domain/*)
        required+=(".agents/skills/architecture/SKILL.md" ".agents/skills/domain/SKILL.md" \
                   ".agents/skills/process/references/tdd-workflow.md") ;;
  esac
  case "$rel" in
    docs/process/prds/[0-9]*.md)
        required+=(".agents/skills/process/references/prd-lifecycle.md" \
                   ".agents/skills/process/references/feature-workflow.md") ;;
  esac
fi

[ ${#required[@]} -eq 0 ] && hook_allow

# ── Verificación de markers ─────────────────────────────────────────
marker_dir="$(hook_state_dir)/skills-read"
declare -a missing=()
for ref in "${required[@]}"; do
  flat="${ref//\//__}"
  [ -f "$marker_dir/${flat}.read" ] || missing+=("$ref")
done
[ ${#missing[@]} -eq 0 ] && hook_allow

reason="🛑 Antes de editar \`$rel\` debes LEER (con la tool Read) en esta sesión:"$'\n'
for m in "${missing[@]}"; do reason+="  • $m"$'\n'; done
reason+="Tras leerlas, reintenta el Edit/Write. El sistema registra los Reads solo."
hook_block_or_warn "$reason"

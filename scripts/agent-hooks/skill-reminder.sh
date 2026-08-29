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

# ── AVISO (NUNCA bloquea): la skill exigida tiene FILLs sin rellenar ─
# Este es el instante EXACTO en que un agente va a escribir código guiado por
# esta skill. Si la skill todavía dice `<!-- FILL: tu patrón de navegación -->`,
# el agente no está siguiendo la convención del proyecto: está a punto de
# inventarse una y dejarla escrita en el código, que es peor que no tener guía
# —una convención inventada se parece a una decidida—. Enterarse aquí cuesta
# una línea; enterarse en el review cuesta el rediseño (§14.1, cázalo barato).
#
# AVISA Y NO BLOQUEA, a propósito: un FILL sin rellenar es deuda del ADOPTANTE,
# no un error del cambio que se está haciendo. Bloquear aquí dejaría a todo
# adoptante recién clonado sin poder escribir su primera línea de producto
# hasta completar el template entero — el día 1 en rojo que este repo ya
# aprendió a no provocar. Y un gate que impide el trabajo legítimo se desactiva
# entero (§14.2).
#
# ⚠️ EL DELIMITADOR NO PUEDE SER UNA CLASE CON `-` SUELTO. Un `-` al final de
# una clase es un guion LITERAL, así que `[[:space:]:>-]` casa también
# `FILL-HECHO` —el marcador de los ya RESUELTOS— y los cuenta como pendientes.
# Ese bug estaba VIVO en tools/harness-report.sh y se arregló en este mismo
# commit; aquí se nace con la forma correcta en vez de heredarla. La forma
# `<!-- FILL-->` (guion pegado) SÍ cuenta: por eso `-->` va como alternativa
# explícita en vez de borrar el guion sin más.
FILL_ERE='<!--[[:space:]]*FILL([[:space:]:>]|-->|$)'

# ── NARRAR UN FILL NO ES TENER UN FILL ──────────────────────────────
# Las propias skills EXPLICAN el mecanismo: «Rellena los `<!-- FILL -->` con TU
# negocio». Contar esa frase como hueco pendiente es el falso positivo de
# "narrar vs prescribir" que este repo ya ha pisado varias veces (está fijado
# para el patrón de `git add -A` en test_execution_map.sh). Lo cazó la prueba
# de bolsillo de este mismo cambio: el aviso señalaba la línea de prosa de
# `domain/SKILL.md` como si fuera un FILL sin rellenar.
#
# El discriminador es la comilla invertida, y no es una heurística feliz: un
# marcador REAL nunca va en backticks (sería literal, no marcador), y una
# mención SIEMPRE los lleva porque es markdown citando código. Medido contra
# las skills reales del repo: 5 menciones, las 5 en backticks, 0 marcadores
# reales perdidos. Se BORRAN los tramos entre backticks antes de mirar —así una
# línea que tenga mención Y marcador se juzga por el marcador— y `sed` emite una
# línea por línea de entrada, de modo que los números de `grep -n` siguen siendo
# los del archivo original.
_fill_nums() { # _fill_nums <archivo> → números de línea con FILL real
  sed 's/`[^`]*`//g' "$1" 2>/dev/null | grep -nE "$FILL_ERE" 2>/dev/null | cut -d: -f1
}

aviso_fill=""
for ref in "${required[@]}"; do
  _ruta="$PROJECT_ROOT/$ref"
  # Un ref inexistente NO es asunto de este hook (lo fija test_skill_matrix.sh)
  # y sobre todo no puede romperlo: esto avisa, nunca estorba.
  [ -f "$_ruta" ] || continue
  _nums="$(_fill_nums "$_ruta")" || true
  [ -z "$_nums" ] && continue
  _n="$(printf '%s\n' "$_nums" | grep -c . || true)"
  aviso_fill+="  • $ref — $_n sin rellenar"$'\n'
  # Solo una MUESTRA: el objetivo es que el agente sepa qué le falta, no
  # inundarle el contexto. El recuento completo va en la línea de arriba.
  while IFS= read -r _num; do
    [ -z "$_num" ] && continue
    aviso_fill+="      L${_num}: $(sed -n "${_num}p" "$_ruta" | sed 's/^[[:space:]]*//' | cut -c1-72)"$'\n'
  done <<< "$(printf '%s\n' "$_nums" | head -3)"
  [ "$_n" -gt 3 ] 2>/dev/null && aviso_fill+="      … y $((_n - 3)) más"$'\n'
done

_aviso_texto() {
  printf '%s' "⚠️  La guía que estás obligado a seguir está INCOMPLETA:"$'\n'"$aviso_fill"
  printf '%s' "Esos FILL son huecos del template que nadie ha rellenado todavía. Donde haya
uno, la skill NO decide por ti: no te inventes la convención y la dejes escrita
en el código como si fuera del proyecto. Pregunta al owner (AGENTS.md §0.4) o
abre una Open Question (§1.4) — una suposición silenciosa aquí se convierte en
el patrón que copiarán los siguientes cambios.
Si ya sabes la respuesta, rellenar el FILL es parte del trabajo: \`/adoptar\`."
}

# ── Verificación de markers ─────────────────────────────────────────
marker_dir="$(hook_state_dir)/skills-read"
declare -a missing=()
for ref in "${required[@]}"; do
  flat="${ref//\//__}"
  [ -f "$marker_dir/${flat}.read" ] || missing+=("$ref")
done

if [ ${#missing[@]} -eq 0 ]; then
  # Camino feliz: leíste todo lo exigido. Si además hay FILLs, el aviso viaja
  # por `additionalContext` — informa SIN tocar la decisión (sigue exit 0).
  [ -n "$aviso_fill" ] && hook_context "PreToolUse" "$(_aviso_texto)"
  hook_allow
fi

reason="🛑 Antes de editar \`$rel\` debes LEER (con la tool Read) en esta sesión:"$'\n'
for m in "${missing[@]}"; do reason+="  • $m"$'\n'; done
reason+="Tras leerlas, reintenta el Edit/Write. El sistema registra los Reads solo."
# El aviso se ADJUNTA al bloqueo en vez de perderse: si se emitiera solo en el
# camino feliz, el agente lo vería justo DESPUÉS de haber leído la skill, que es
# cuando ya se formó su modelo mental de ella. Aquí llega en el mismo mensaje
# que le manda leerla — sabe qué va a encontrar incompleto ANTES de leerlo.
[ -n "$aviso_fill" ] && reason+=$'\n'"$(_aviso_texto)"
hook_block_or_warn "$reason"

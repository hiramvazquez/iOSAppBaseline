#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# backlog/next.sh — ¿cuál es la SIGUIENTE historia trabajable?
# ════════════════════════════════════════════════════════════════════
# Imprime la ruta de la primera historia `status: ready` cuyas dependencias
# están TODAS en `done` — y done significa "mergeada a la rama base", porque
# el estado se lee del checkout actual: una dependencia solo desbloquea
# cuando el humano la revisó y mergeó. Eso ordena el grafo sin coordinación.
#
# Sin candidatas (o sin backlog/): imprime nada y sale 0 — apto para cron.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

[ -d backlog ] || exit 0

_field() { # _field <archivo> <campo>  → valor del frontmatter
  awk -v k="$2" '
    /^---[[:space:]]*$/ { n++; next }
    n==1 && $1 == k":" { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }
  ' "$1" 2>/dev/null
}

# ════════════════════════════════════════════════════════════════════
# EL ESTADO REAL DE UNA HISTORIA NO ESTÁ SOLO EN LA RAMA BASE
# ════════════════════════════════════════════════════════════════════
# Este selector decidía mirando ÚNICAMENTE el `status` del frontmatter en el
# checkout actual (la base). Pero el `in-review` lo escribe el runner DENTRO de
# la rama `story/NNNN`: desde `develop`, una historia terminada y esperando
# merge sigue diciendo `ready`. `backlog/README` promete que una rama en
# `in-review` no se re-trabaja, y el selector no podía cumplirlo porque el
# marcador vive donde no miraba.
#
# Consecuencia real, cazada con `story/0005` terminada: el selector la devolvía
# otra vez. Con el humano tardando en mergear —justo el escenario para el que
# existe un runner desatendido— el riesgo es rehacer desde cero trabajo ya
# verificado, y mientras tanto el backlog no avanza a la siguiente historia.
#
# La corrección: el hecho observable desde la base es LA RAMA. Y hay que
# distinguir dos situaciones que se parecen y piden lo contrario:
#
#   · rama con la historia en `in-review` → TERMINADA, esperando tu merge.
#     Se SALTA y se sigue con la siguiente. (Antes: se re-ofrecía.)
#   · rama con cualquier otro estado      → trabajo A MEDIAS (un run que se
#     cortó). Se DEVUELVE, porque `run.sh` sabe retomar el worktree donde
#     quedó. Saltarla aquí dejaría la historia huérfana para siempre.
#
# Ante la duda (no se puede leer el estado de la rama), se DEVUELVE: `run.sh`
# tiene su propio guard y retomar es reversible; olvidar una historia, no.
_rama_de() { # _rama_de <id> → nombre de la rama story/<id>… si existe
  git for-each-ref --format='%(refname:short)' \
      'refs/heads/story/*' 'refs/remotes/*/story/*' 2>/dev/null \
    | while IFS= read -r r; do
        # `##*story/` y no `##*/story/`: una rama local se imprime como
        # `story/0005-x` (sin barra delante), y con el patrón de la barra el
        # strip no casaba, la comparación fallaba siempre y el guard entero
        # quedaba inerte — un gate escrito, testeado en la cabeza, y mudo.
        case "${r##*story/}" in
          "$1"|"$1"-*) printf '%s\n' "$r"; break ;;
        esac
      done
}
_estado_en_rama() { # _estado_en_rama <rama> <archivo>
  git show "$1:$2" 2>/dev/null \
    | awk '/^---[[:space:]]*$/{n++;next} n==1 && $1=="status:" {sub(/^[^:]*:[[:space:]]*/,""); print; exit}'
}
_avisar() { printf '%s\n' "$1" >&2; }

# ── Paso 4.3 con rastro mecánico, no con buena voluntad ─────────────
# `feature-workflow.md` Fase 4 exige actualizar el mapa de ejecución al cerrar
# una historia. Durante cinco historias seguidas no lo hizo nadie, y no por
# descuido: NINGÚN mecanismo lo pedía (f-1eeba642). El selector del backlog es
# el sitio natural para que se note, porque es lo que se corre al terminar una
# y buscar la siguiente. Va a stderr — stdout es SOLO la ruta de la historia y
# hay quien lo parsea.
_avisar_mapa_stale() {
  [ -x tools/check-execution-map.sh ] || [ -f tools/check-execution-map.sh ] || return 0
  local out rc
  out="$(bash tools/check-execution-map.sh 2>&1)"; rc=$?
  # 3 = el detector no pudo mirar. Aquí no se convierte en ruido: quien
  # bloquea por eso es el Anillo 3 (§14.3), este es un aviso de conveniencia.
  [ "$rc" = "1" ] || return 0
  _avisar ""
  _avisar "⚠️  backlog: el mapa de ejecución está DESACTUALIZADO respecto al árbol."
  printf '%s\n' "$out" | sed 's/^/   /' >&2
}


for story in backlog/[0-9]*.md; do
  [ -f "$story" ] || continue
  status="$(_field "$story" status)"
  id="$(_field "$story" id)"; : "${id:=$(basename "$story" | cut -d- -f1)}"
  rama="$(_rama_de "$id")"

  # Mergeada y sin marcar: el backlog se para en silencio. `done` en la base es
  # parte del acto de mergear (el merge es SIEMPRE humano), y si se olvida, las
  # historias que dependen de esta no se desbloquean nunca y nadie ve por qué.
  if [ "$status" = "in-review" ] && [ -z "$rama" ]; then
    _avisar "ℹ️  backlog: ${story} está en 'in-review' y ya no existe su rama — parece MERGEADA."
    _avisar "   Ponle 'status: done' en la base o las historias que dependen de ella nunca se desbloquean."
    _avisar "   Y con ella, el paso 4.3 de feature-workflow.md: actualiza"
    _avisar "   docs/process/current_execution_map.md EN EL MISMO COMMIT (lo verifica"
    _avisar "   tools/check-execution-map.sh — antes era prosa que no ejecutaba nadie)."
  fi

  [ "$status" = "ready" ] || continue

  if [ -n "$rama" ]; then
    if [ "$(_estado_en_rama "$rama" "$story")" = "in-review" ]; then
      _avisar "⏭  backlog: ${story} salta — ya está TERMINADA en ${rama}, esperando tu merge."
      _avisar "   Revísala:  git diff HEAD...${rama}   ·  al mergear, pon 'status: done' aquí."
      continue
    fi
    _avisar "↩️  backlog: ${story} tiene la rama ${rama} a medias — se retoma donde quedó."
  fi

  # Dependencias: `depends_on: [0001, 0002]` → cada una debe estar en done.
  deps="$(_field "$story" depends_on | sed -E 's/[][]//g; s/,/ /g')"
  ok=1
  for dep in $deps; do
    dep="${dep// /}"; [ -z "$dep" ] && continue
    dep_done=0
    for df in backlog/${dep}*.md; do
      [ -f "$df" ] || continue
      [ "$(_field "$df" status)" = "done" ] && dep_done=1
    done
    [ "$dep_done" = "1" ] || { ok=0; break; }
  done
  [ "$ok" = "1" ] || continue

  _avisar_mapa_stale
  printf '%s\n' "$story"
  exit 0
done
_avisar_mapa_stale
exit 0

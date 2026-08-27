#!/usr/bin/env bash
# Hook PostToolUse Read (Claude) / postToolUse (Cursor) — observe-only.
# Cuando el modelo lee una skill reference (o AGENTS.md / execution map),
# crea un marker. skill-reminder.sh los consulta para permitir ediciones.
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"

hook_read_input
# Solo nos interesan los Read.
tool="$(hook_tool)"
case "$tool" in Read|read_file|view|cat) : ;; *) exit 0 ;; esac

file_path="$(hook_file_path)"
[ -z "$file_path" ] && exit 0
rel="$(hook_rel_path "$file_path")"

# ¿Es un path registrable? DOS fuentes, en este orden:
#   (a) cualquier REF que aparezca en tools/skill-matrix.conf — la fuente única.
#       Este es el fix ESTRUCTURAL de un bug cazado en vivo por el agente del
#       primer proyecto real: la matriz exigía leer platforms/*.md pero el
#       filtro estático de aquí no los registraba → el agente leía la skill,
#       el marker jamás aparecía, y skill-reminder bloqueaba PARA SIEMPRE.
#       Leyendo la matriz, filtro y gate no pueden divergir nunca más
#       (test_skill_matrix.sh::test_toda_ref_es_registrable_por_track_reads).
#   (b) allowlist estático de meta-docs + fallback sin conf.
REGISTRABLE=0
case "$rel" in
  .agents/skills/*/SKILL.md|.agents/skills/*/references/*.md|.agents/skills/*/platforms/*.md) REGISTRABLE=1 ;;
  AGENTS.md|CLAUDE.md|docs/process/current_execution_map.md) REGISTRABLE=1 ;;
esac
if [ "$REGISTRABLE" -eq 0 ] && [ -f "$PROJECT_ROOT/tools/skill-matrix.conf" ]; then
  grep -v '^[[:space:]]*#' "$PROJECT_ROOT/tools/skill-matrix.conf" 2>/dev/null \
    | cut -d'|' -f2- | tr ',' '\n' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | grep -qxF "$rel" && REGISTRABLE=1
fi
[ "$REGISTRABLE" -eq 1 ] || exit 0

marker_dir="$(hook_state_dir)/skills-read"
mkdir -p "$marker_dir"
touch "$marker_dir/${rel//\//__}.read"
exit 0

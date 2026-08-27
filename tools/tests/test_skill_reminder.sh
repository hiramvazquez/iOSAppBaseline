#!/usr/bin/env bash
# skill-reminder BLOQUEA ediciones si no leíste la skill del área (AGENTS.md §11).
# Es un gate duro, así que sus falsos positivos son caros: si bloquea trabajo
# legítimo, el equipo lo desactiva y se pierde el gate entero (ley del 10%).

_sr_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/tools" "$d/.agents/state/skills-read"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  cp "$PROJECT_ROOT/tools/preset" "$d/tools/preset" 2>/dev/null
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

# Simula un Edit sobre <path> y devuelve el exit code del hook.
_edit() {
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/%s"}}' "$(pwd)" "$1" \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/skill-reminder.sh >/dev/null 2>&1
  echo $?
}

# ── happy path: código de producto sin skill leída → BLOQUEA ────────
_case_bloquea_codigo_sin_skill() {
  local rc; rc="$(_edit "src/Domain/User.swift")"
  [ "$rc" = "2" ] || { echo "    no bloqueó código de dominio sin skill leída (exit=$rc)"; return 1; }
}
test_bloquea_codigo_de_dominio_sin_skill() { _sr_sandbox _case_bloquea_codigo_sin_skill; }

_case_permite_con_markers() {
  for m in .agents__skills__architecture__SKILL.md \
           .agents__skills__domain__SKILL.md \
           .agents__skills__process__references__tdd-workflow.md; do
    touch ".agents/state/skills-read/${m}.read"
  done
  local rc; rc="$(_edit "src/Domain/User.swift")"
  [ "$rc" = "0" ] || { echo "    bloqueó pese a tener los markers de lectura (exit=$rc)"; return 1; }
}
test_permite_cuando_las_skills_estan_leidas() { _sr_sandbox _case_permite_con_markers; }

# ── LOS FALSOS POSITIVOS (el motivo de estos tests) ─────────────────
_case_editar_la_propia_skill() {
  # Editar `.agents/skills/domain/SKILL.md` casaba con el glob `*/domain/*`
  # y exigía leer la skill de dominio… para poder editar la skill de dominio.
  local rc; rc="$(_edit ".agents/skills/domain/SKILL.md")"
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: bloqueó editar la propia skill (exit=$rc)"; return 1; }
}
test_editar_una_skill_no_requiere_leerla() { _sr_sandbox _case_editar_la_propia_skill; }

_case_editar_doc() {
  local rc; rc="$(_edit "docs/process/lessons_learned.md")"
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: bloqueó editar documentación (exit=$rc)"; return 1; }
}
test_editar_documentacion_no_bloquea() { _sr_sandbox _case_editar_doc; }

_case_editar_tooling() {
  local rc; rc="$(_edit "tools/check-layers.sh")"
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: bloqueó editar tooling (exit=$rc)"; return 1; }
}
test_editar_tooling_no_bloquea() { _sr_sandbox _case_editar_tooling; }

_case_prd_sigue_gateado() {
  # La excepción a la excepción: los PRDs numerados SÍ exigen leer su lifecycle,
  # aunque sean .md dentro de docs/.
  local rc; rc="$(_edit "docs/process/prds/0002-algo.md")"
  [ "$rc" = "2" ] || { echo "    un PRD numerado dejó de estar gateado (exit=$rc)"; return 1; }
}
test_prd_numerado_sigue_requiriendo_lifecycle() { _sr_sandbox _case_prd_sigue_gateado; }

_case_archivo_sin_regla() {
  local rc; rc="$(_edit "src/README.txt")"
  [ "$rc" = "0" ] || { echo "    bloqueó un archivo sin regla asociada (exit=$rc)"; return 1; }
}
test_archivo_sin_regla_pasa() { _sr_sandbox _case_archivo_sin_regla; }

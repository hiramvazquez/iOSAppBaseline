#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# META-DETECTOR: todo detector tiene tests de FALSO POSITIVO
# ════════════════════════════════════════════════════════════════════
# La lección más repetida del PRD 0001, ahora mecanizada. Tres detectores se
# auto-detectaron nada más nacer (skill-reminder bloqueó editar su propia doc;
# canon-enforce marcó como secreto al archivo que define qué es un secreto;
# shell-hygiene matcheó sus propios comentarios). El patrón fue tan
# consistente que quedó como regla:
#
#   **El primer falso positivo de un detector casi siempre aparece en el
#     repo del propio detector. Escribe sus tests de FP el mismo día.**
#
# Como toda lección, o tiene detector o es prosa (AGENTS.md §10). Este es su
# detector: un MANIFIESTO explícito detector→archivo de tests, exigiendo que
# el archivo exista y contenga al menos un caso marcado "FALSO POSITIVO".
#
# Manifiesto explícito y no heurística de nombres: un meta-detector con
# falsos positivos sería una ironía demasiado cara.

# detector :: archivo de tests que cubre sus FALSOS POSITIVOS
# <!-- FILL: al añadir un detector nuevo, añade su línea AQUÍ y sus tests de
#      FP en el archivo — en el MISMO cambio. Si este test te trajo hasta
#      este comentario, ese es exactamente el momento. -->
MANIFEST="
scripts/agent-hooks/skill-reminder.sh        :: test_skill_reminder.sh
scripts/agent-hooks/canon-enforce.sh         :: test_canon_enforce.sh
scripts/agent-hooks/reviewer-gate.sh         :: test_ratchets.sh
scripts/agent-hooks/session-end.sh           :: test_judge_queue.sh
scripts/agent-hooks/post-edit-verify.sh      :: test_post_edit_verify.sh
scripts/agent-hooks/drift-stop.sh            :: test_drift_stop.sh
scripts/agent-hooks/session-start.sh         :: test_session_start.sh
tools/check-layers.sh                        :: test_layers.sh
tools/check-conflict-markers.sh              :: test_conflict_markers.sh
tools/check-exec-bits.sh                     :: test_exec_bits.sh
tools/check-diff-nature.sh                   :: test_diff_nature.sh
tools/check-ring3.sh                         :: test_ring3.sh
tools/check-skill-matrix-doc.sh              :: test_skill_matrix.sh
tools/check-execution-map.sh                 :: test_execution_map.sh
tools/check-verify-marker.sh                 :: test_verify_marker.sh
scripts/agent-hooks/run-hook.sh              :: test_run_hook.sh
tools/backlog/next.sh                        :: test_backlog_selection.sh
tools/backlog/criteria-link.sh               :: test_backlog_criteria.sh
tools/backlog/scope-check.sh                 :: test_backlog_scope.sh
tools/architecture-check.sh                  :: test_architecture_capabilities.sh
tools/agent-runner.sh                        :: test_agent_runner.sh
tools/semgrep/rules/swift.yaml               :: test_semgrep_rules.sh
tools/check-drift.sh                         :: test_drift_aggregation.sh
tools/check-review-marker.sh                 :: test_review_marker_preset.sh
tools/lib/scope.sh                           :: test_scope_kind.sh
tools/drift-ratchet.sh                       :: test_ratchets.sh
tools/secret-scan.sh                         :: test_secret_scan.sh
tools/semgrep-scan.sh                        :: test_fail_closed.sh
tools/mutation-score.sh                      :: test_fail_closed.sh
tools/lesson-detector-link.sh                :: test_lessons_detector_link.sh
tools/findings/findings.sh                   :: test_findings_cli.sh
tools/check-source-sets.sh                   :: test_source_sets.sh
tools/check-finding-refs.sh                  :: test_finding_refs.sh
tools/check-version-claims.sh                :: test_finding_refs.sh
tools/render-capabilities.sh                 :: test_capabilities.sh
tools/probe-capability.sh                    :: test_capability_probe.sh
"

test_todo_detector_tiene_tests_de_falso_positivo() {
  local bad=""
  while IFS= read -r line; do
    line="$(printf '%s' "$line" | sed 's/#.*//')"
    [ -z "${line// /}" ] && continue
    local det tf
    det="$(printf '%s' "$line" | awk -F' *:: *' '{print $1}' | sed 's/ *$//')"
    tf="$(printf '%s' "$line"  | awk -F' *:: *' '{print $2}' | sed 's/ *$//')"
    [ -z "$det" ] || [ -z "$tf" ] && continue

    if [ ! -f "$PROJECT_ROOT/$det" ]; then
      bad="${bad}      $det: el detector del manifiesto ya no existe (limpia la línea)"$'\n'
      continue
    fi
    if [ ! -f "$PROJECT_ROOT/tools/tests/$tf" ]; then
      bad="${bad}      $det → tools/tests/$tf NO EXISTE"$'\n'
      continue
    fi
    if ! grep -qi "falso positivo" "$PROJECT_ROOT/tools/tests/$tf" 2>/dev/null; then
      bad="${bad}      $det → $tf no contiene ningún caso marcado 'FALSO POSITIVO'"$'\n'
    fi
  done <<< "$MANIFEST"

  [ -z "$bad" ] && return 0
  echo "    Detectores sin tests de falso positivo verificables:"
  printf '%s' "$bad"
  echo "    Regla (PRD 0001, repetida 3 veces en carne propia): el primer FP de un"
  echo "    detector aparece en el repo del propio detector. Los tests de FP se"
  echo "    escriben el MISMO día que el detector, no cuando alguien se queje."
  return 1
}

# El propio manifiesto no puede quedarse vacío por un error de formato.
test_el_manifiesto_no_esta_vacio() {
  local n
  n="$(printf '%s\n' "$MANIFEST" | grep -c '::' || true)"
  [ "${n:-0}" -ge 29 ] || { echo "    el manifiesto tiene $n entradas (esperaba ≥29) — ¿se rompió el formato?"; return 1; }
}

# ── El manifiesto tampoco puede quedarse ATRÁS (f-meta-fp-manifiesto) ──
# Un manifiesto que se mantiene a mano es una lista que alguien tiene que
# acordarse de actualizar — y este test solo mira lo que hay EN la lista, así
# que un detector ausente es invisible para el meta-detector. Se comprobó y
# había cinco fuera (conflict-markers, exec-bits, diff-nature, ring3 y el
# propio skill-matrix-doc): todos con tests de FP escritos, ninguno declarado.
# Es el modo de fallo de siempre — la cobertura parecía completa porque lo que
# faltaba no se contaba a sí mismo.
test_ningun_detector_se_queda_fuera_del_manifiesto() {
  local f fuera=""
  for f in "$PROJECT_ROOT"/tools/check-*.sh; do
    [ -f "$f" ] || continue
    local rel="tools/$(basename "$f")"
    printf '%s' "$MANIFEST" | grep -q "^${rel} " || fuera="${fuera}      $rel"$'\n'
  done
  [ -z "$fuera" ] && return 0
  echo "    Detectores que existen pero NO están en el manifiesto:"
  printf '%s' "$fuera"
  echo "    Añádelos arriba con su archivo de tests de FP. Un detector fuera del"
  echo "    manifiesto es invisible para este meta-test: la cobertura parece"
  echo "    completa justo porque lo que falta no se cuenta a sí mismo."
  return 1
}

# ── FALSO POSITIVO guard del propio meta-detector (f-meta-fp-self) ──
# El parser hace strip de comentarios y líneas vacías. Si ese strip se rompe,
# hay dos modos de fallo: contar un comentario como entrada (FP: exigiría un
# test a un detector inexistente) o tragarse entradas reales (FN silencioso).
# Ambos se fijan aquí contra un manifiesto de fixture.
test_el_parser_del_manifiesto_ignora_comentarios() {
  local fixture="
# comentario a línea completa :: no-es-entrada.sh
tools/check-layers.sh :: test_layers.sh   # comentario al final
"
  local n=0
  while IFS= read -r line; do
    line="$(printf '%s' "$line" | sed 's/#.*//')"
    [ -z "${line// /}" ] && continue
    printf '%s' "$line" | grep -q '::' && n=$((n+1))
  done <<< "$fixture"
  [ "$n" = "1" ] || { echo "    el parser contó $n entradas en el fixture (esperaba 1: los comentarios no son entradas)"; return 1; }
}

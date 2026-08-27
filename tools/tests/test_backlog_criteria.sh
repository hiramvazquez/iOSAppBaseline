#!/usr/bin/env bash
# Backlog runner (PRD 0003) — `tools/backlog/criteria-link.sh`:
# f-criterio6-sin-test, "un criterio de aceptación «verificado con un grep»
# es decoración". Cada criterio de aceptación tiene que enlazar a un test
# REAL (o declarar `n/a-manual` explícito) — validar solo que el campo esté
# relleno deja pasar tests fantasma que no existen.
#
# Split de tools/tests/test_backlog.sh (hard limit de 400 líneas, AGENTS.md
# §4) — parte 4/4. Hermanos: test_backlog_selection.sh,
# test_backlog_run_isolation.sh, test_backlog_run_completion.sh,
# test_backlog_scope.sh (aparte, prueba solo el checker de scope).

_bl_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/backlog" "$d/tools/agent-backends" "$d/tools/agent-prompts" \
    "$d/scripts/agent-hooks/lib" "$d/backlog"
  cp "$PROJECT_ROOT/tools/backlog/next.sh" "$d/tools/backlog/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/backlog/run.sh" "$d/tools/backlog/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/backlog/criteria-link.sh" "$d/tools/backlog/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/backlog/scope-check.sh" "$d/tools/backlog/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/agent-runner.sh" "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/check-review-marker.sh" "$d/tools/" 2>/dev/null
  cp -R "$PROJECT_ROOT/tools/agent-backends/." "$d/tools/agent-backends/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/agent-prompts/"*.md "$d/tools/agent-prompts/" 2>/dev/null
  cp "$PROJECT_ROOT/scripts/agent-hooks/lib/verdict.sh" "$d/scripts/agent-hooks/lib/" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q -b develop . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo seed > seed.txt; git add -A; git commit -qm init 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}
_story() { # _story <archivo> <id> <status> <deps>
  cat > "backlog/$1" <<EOF
---
id: $2
titulo: Historia $2
status: $3
depends_on: [$4]
base: develop
scope: |
  **
---
## Criterios de aceptación
1. Dado X cuando Y entonces Z.

## Verificación de criterios
1. n/a-manual — historia de juguete del harness, sin código que verificar
EOF
}

# ════════════════════════════════════════════════════════════════════
# f-run-a-medias-exit0 · f-criterio6-sin-test — cerrar no es "salir con 0"
# ════════════════════════════════════════════════════════════════════
_hist_con_verificacion() { # <archivo> <id> <n-criterios> <lineas-verificacion>
  cat > "backlog/$1" <<EOF
---
id: $2
status: ready
depends_on: []
base: develop
---
## Criterios de aceptación
1. Dado X cuando Y entonces Z.
2. Dado A cuando B entonces C.

## Verificación de criterios
$4
EOF
}

_case_criterios_sin_test_bloquean() {
  _hist_con_verificacion 0009-i.md 0009 2 "1. Tests/FooTests.swift::testUno"
  mkdir -p Tests; printf 'test\n' > Tests/FooTests.swift
  bash tools/backlog/criteria-link.sh backlog/0009-i.md >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un criterio SIN test pasó el gate"; return 1; }
}
test_criterio_sin_test_no_pasa() { _bl_sandbox _case_criterios_sin_test_bloquean; }

_case_criterios_con_test_pasan() {
  _hist_con_verificacion 0009-i.md 0009 2 "1. Tests/FooTests.swift::testUno
2. n/a-manual — es un criterio visual, verificado en captura"
  mkdir -p Tests; printf 'test\n' > Tests/FooTests.swift
  local out; out="$(bash tools/backlog/criteria-link.sh backlog/0009-i.md 2>&1)"
  case "$out" in *"total=2 sin_test=0"*) return 0 ;; esac
  echo "    una historia bien verificada fue rechazada: $out"; return 1
}
test_criterios_con_test_o_excepcion_pasan() { _bl_sandbox _case_criterios_con_test_pasan; }

_case_test_fantasma_no_cuenta() {
  # Mismo fallo que los detectores citados que ya no existían, un nivel arriba:
  # validar solo que el campo esté relleno deja pasar tests que no existen.
  _hist_con_verificacion 0009-i.md 0009 2 "1. Tests/NoExiste.swift::testUno
2. n/a-manual — visual"
  local out; out="$(bash tools/backlog/criteria-link.sh backlog/0009-i.md 2>&1)"
  case "$out" in *"NO existe"*) return 0 ;; esac
  echo "    un test FANTASMA se dio por válido: $out"; return 1
}
test_test_citado_inexistente_no_cuenta() { _bl_sandbox _case_test_fantasma_no_cuenta; }

_case_historia_sin_criterios_es_noop() {
  # FALSO POSITIVO guard: sin criterios no hay nada que exigir. (El guard de
  # "historia sin criterios" es otro y vive en run.sh.)
  printf -- '---\nid: 0009\nstatus: ready\n---\n# vacía\n' > backlog/0009-i.md
  local out; out="$(bash tools/backlog/criteria-link.sh backlog/0009-i.md 2>&1)"; local rc=$?
  [ "$rc" = "0" ] || { echo "    una historia sin criterios fue rechazada (exit $rc)"; return 1; }
  case "$out" in *"total=0"*) return 0 ;; esac
  echo "    contó criterios donde no los hay: $out"; return 1
}
test_historia_sin_criterios_no_exige_verificacion() {
  _bl_sandbox _case_historia_sin_criterios_es_noop
}

_case_lista_posterior_no_infla_el_total() {
  # FALSO POSITIVO real esperando a pasar: cualquier lista numerada MÁS ABAJO
  # en la historia (notas técnicas, bloqueos) inflaría el total y el gate
  # pediría cobertura de criterios que no existen.
  cat > backlog/0009-i.md <<'EOF'
---
id: 0009
status: ready
---
## Criterios de aceptación
1. Dado X cuando Y entonces Z.

## Verificación de criterios
1. n/a-manual — visual

## Notas técnicas
1. Mira el adapter de red.
2. Ojo con el timeout.
EOF
  local out; out="$(bash tools/backlog/criteria-link.sh backlog/0009-i.md 2>&1)"
  case "$out" in *"total=1 sin_test=0"*) return 0 ;; esac
  echo "    una lista de otra sección infló el conteo: $out"; return 1
}
test_listas_de_otras_secciones_no_cuentan_como_criterios() {
  _bl_sandbox _case_lista_posterior_no_infla_el_total
}

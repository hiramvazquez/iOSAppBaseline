#!/usr/bin/env bash
# El Anillo 3 es el único ANILLO que puede estar mudo sin que nada lo diga:
# el `--selftest` valida detectores, y un anillo ausente no es un detector
# roto — es un razonamiento roto. §14.3 justifica el fail-open local con
# "CI lo bloqueará"; sin CI eso es fail-open definitivo. Estos tests fijan
# las tres respuestas del detector y su falso positivo.

_r3_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/ci"
  cp "$PROJECT_ROOT/tools/check-ring3.sh" "$d/tools/"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo x > seed.txt; git add seed.txt; git commit -qm init 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_sin_remoto_ni_ci_falla() {
  bash tools/check-ring3.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un repo SIN remoto y SIN CI pasó como Anillo 3 operativo"; return 1; }
}
test_sin_remoto_ni_ci_es_anillo_ausente() { _r3_sandbox _case_sin_remoto_ni_ci_falla; }

_case_solo_el_remote_del_template_no_cuenta() {
  # EL VERDE FALSO QUE SE APAGÓ SOLO. `tools/upgrade.sh` registra el remote
  # `template` en su primera pasada, y con un `[ -n "$(git remote)" ]` a secas
  # eso bastaba para declarar el Anillo 3 cableado — o sea que el mecanismo de
  # upgrade desactivaba este gate como efecto secundario. Cazado en un
  # adoptante real: sin `origin`, con el workflow presente y `template` como
  # único remote, decía ✅ mientras su CI no podía correr en ningún sitio.
  git remote add template https://example.invalid/harness.git 2>/dev/null
  mkdir -p .github/workflows
  printf 'name: gates\njobs:\n  g:\n    steps:\n      - run: bash ci/run-gates.sh\n' \
    > .github/workflows/gates.yml
  local out rc; out="$(bash tools/check-ring3.sh 2>&1)"; rc=$?
  [ "$rc" = "1" ] || { echo "    el remote del template se contó como Anillo 3 (exit $rc): $out"; return 1; }
  printf '%s' "$out" | grep -q 'remote=no' \
    || { echo "    el resumen debería reportar remote=no con solo el remote del template: $out"; return 1; }
  printf '%s' "$out" | grep -q "ÚNICO remote es 'template'" \
    || { echo "    falló, pero el diagnóstico no explica que el remote es el del harness"; return 1; }
}
test_solo_el_remote_del_template_no_es_anillo_3() { _r3_sandbox _case_solo_el_remote_del_template_no_cuenta; }

_case_template_mas_origin_si_cuenta() {
  # La otra mitad: tener el remote del template NO debe penalizar a quien sí
  # tiene su origin. Sin este test, "arreglar" lo de arriba ignorando todos
  # los remotes pasaría inadvertido.
  git remote add template https://example.invalid/harness.git 2>/dev/null
  git remote add origin https://example.invalid/mi-proyecto.git 2>/dev/null
  mkdir -p .github/workflows
  printf 'name: gates\njobs:\n  g:\n    steps:\n      - run: bash ci/run-gates.sh\n' \
    > .github/workflows/gates.yml
  local rc; bash tools/check-ring3.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || { echo "    tener el remote del template ADEMÁS de origin tumbó el anillo (exit $rc)"; return 1; }
}
test_template_junto_a_origin_sigue_siendo_anillo_3() { _r3_sandbox _case_template_mas_origin_si_cuenta; }

_case_remoto_sin_ci_falla() {
  # El caso más engañoso: hay remoto, así que "parece" que hay CI.
  git remote add origin https://example.invalid/x.git 2>/dev/null
  local out; out="$(bash tools/check-ring3.sh 2>&1)"
  printf '%s' "$out" | grep -q 'ci=no' \
    || { echo "    con remoto pero sin workflow, el resumen no reporta ci=no: $out"; return 1; }
  bash tools/check-ring3.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    remoto SIN workflow de gates pasó como Anillo 3 operativo"; return 1; }
}
test_remoto_sin_workflow_de_gates_no_basta() { _r3_sandbox _case_remoto_sin_ci_falla; }

_case_workflow_ajeno_no_cuenta() {
  # FALSO NEGATIVO que importa: un workflow que existe pero NO ejecuta los
  # gates del harness (deploy, release notes, un lint suelto) no es Anillo 3.
  # Contarlo daría por cubierto justo lo que no cubre.
  git remote add origin https://example.invalid/x.git 2>/dev/null
  mkdir -p .github/workflows
  printf 'name: deploy\njobs:\n  d:\n    steps:\n      - run: echo desplegando\n' \
    > .github/workflows/deploy.yml
  bash tools/check-ring3.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un workflow que NO corre gates se contó como Anillo 3"; return 1; }
}
test_un_workflow_cualquiera_no_es_anillo_3() { _r3_sandbox _case_workflow_ajeno_no_cuenta; }

_case_remoto_mas_gates_pasa() {
  git remote add origin https://example.invalid/x.git 2>/dev/null
  mkdir -p .github/workflows
  printf 'name: gates\njobs:\n  g:\n    steps:\n      - run: bash ci/run-gates.sh\n' \
    > .github/workflows/gates.yml
  local out rc
  out="$(bash tools/check-ring3.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || { echo "    remoto + workflow de gates fue rechazado (exit $rc): $out"; return 1; }
  printf '%s' "$out" | grep -q 'remote=yes ci=yes' \
    || { echo "    el contrato de stdout no reporta remote=yes ci=yes: $out"; return 1; }
}
test_remoto_mas_workflow_de_gates_es_anillo_3() { _r3_sandbox _case_remoto_mas_gates_pasa; }

_case_repo_del_harness_cuenta_su_suite() {
  # En el repo del PROPIO harness el producto SON los gates, así que el
  # workflow que corre su suite es exactamente su Anillo 3. Sin esta rama,
  # el template suspendería su propio check — y un detector que no puede
  # aprobar al proyecto que lo define es un detector mal definido.
  git remote add origin https://example.invalid/x.git 2>/dev/null
  mkdir -p .github/workflows
  printf 'name: harness-ci\njobs:\n  s:\n    steps:\n      - run: bash tools/tests/run-tests.sh\n' \
    > .github/workflows/harness-ci.yml
  bash tools/check-ring3.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    el workflow que corre la suite del harness no contó como Anillo 3"; return 1; }
}
test_suite_del_harness_en_ci_cuenta_como_anillo_3() { _r3_sandbox _case_repo_del_harness_cuenta_su_suite; }

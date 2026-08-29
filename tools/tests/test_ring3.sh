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
    # Sin red: el probe de ejecucion consulta la API de GitHub y estos remotes
    # son example.invalid. Un test unitario que sale a internet es lento, flaky
    # y da un resultado distinto segun quien lo corra. El probe tiene su propia
    # cobertura en el checklist en vivo de validate-harness.
    export RING3_CHECK_RUNS=0
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
  printf 'name: gates\non:\n  push:\njobs:\n  g:\n    steps:\n      - run: bash ci/run-gates.sh\n' \
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
  printf 'name: gates\non:\n  push:\njobs:\n  g:\n    steps:\n      - run: bash ci/run-gates.sh\n' \
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
  printf 'name: deploy\non:\n  push:\njobs:\n  d:\n    steps:\n      - run: echo desplegando\n' \
    > .github/workflows/deploy.yml
  bash tools/check-ring3.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un workflow que NO corre gates se contó como Anillo 3"; return 1; }
}
test_un_workflow_cualquiera_no_es_anillo_3() { _r3_sandbox _case_workflow_ajeno_no_cuenta; }

_case_remoto_mas_gates_pasa() {
  git remote add origin https://example.invalid/x.git 2>/dev/null
  mkdir -p .github/workflows
  printf 'name: gates\non:\n  push:\njobs:\n  g:\n    steps:\n      - run: bash ci/run-gates.sh\n' \
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
  printf 'name: harness-ci\non:\n  push:\njobs:\n  s:\n    steps:\n      - run: bash tools/tests/run-tests.sh\n' \
    > .github/workflows/harness-ci.yml
  bash tools/check-ring3.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    el workflow que corre la suite del harness no contó como Anillo 3"; return 1; }
}
test_suite_del_harness_en_ci_cuenta_como_anillo_3() { _r3_sandbox _case_repo_del_harness_cuenta_su_suite; }

# ════════════════════════════════════════════════════════════════════
# ¿el anillo DISPARA? (un workflow manual-only no es un backstop)
# ════════════════════════════════════════════════════════════════════
# Cazado en vivo el 2026-08-29 sobre este mismo repo: `validate-harness`
# declaraba "✅ Anillo 3 cableado: ... gate-0a-macos.yml ejecuta los gates"
# citando un workflow `workflow_dispatch:` puro — que por definición no corre
# solo jamás. El detector recorría los .yml en orden de glob y se quedaba con
# el PRIMERO que mencionara un entrypoint, sin mirar cuándo se dispara.
#
# Aquí el verde era correcto por casualidad (harness-ci.yml sí tiene push),
# pero la lógica no: borra ese archivo y el gate seguía diciendo ✅ con el
# manual. Un backstop que solo existe si alguien se acuerda de pulsarlo no es
# un backstop — es exactamente el fail-open que §14.4 dice que no cometemos.

_case_manual_only_no_cuenta() {
  git remote add origin https://example.invalid/x.git 2>/dev/null
  mkdir -p .github/workflows
  printf 'name: gate-manual\non:\n  workflow_dispatch:\njobs:\n  g:\n    steps:\n      - run: bash ci/run-gates.sh\n' \
    > .github/workflows/gate-manual.yml
  local out rc; out="$(bash tools/check-ring3.sh 2>&1)"; rc=$?
  [ "$rc" = "1" ] \
    || { echo "    un workflow workflow_dispatch-only se contó como Anillo 3 (exit $rc): $out"; return 1; }
  printf '%s' "$out" | grep -q 'ci=no' \
    || { echo "    el resumen no reporta ci=no ante un workflow manual-only: $out"; return 1; }
}
test_workflow_manual_only_no_es_anillo_3() { _r3_sandbox _case_manual_only_no_cuenta; }

_case_manual_no_enmascara_al_automatico() {
  # La regresión concreta: el manual va PRIMERO en orden de glob (gate-* <
  # harness-*). Sin mirar el disparador, el detector citaba el manual y el
  # humano leía un ✅ que apuntaba al archivo equivocado.
  git remote add origin https://example.invalid/x.git 2>/dev/null
  mkdir -p .github/workflows
  printf 'name: gate-manual\non:\n  workflow_dispatch:\njobs:\n  g:\n    steps:\n      - run: bash ci/run-gates.sh\n' \
    > .github/workflows/gate-0a-manual.yml
  printf 'name: ci\non:\n  push:\n    branches: [main]\njobs:\n  g:\n    steps:\n      - run: bash ci/run-gates.sh\n' \
    > .github/workflows/harness-ci.yml
  local out rc; out="$(bash tools/check-ring3.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] \
    || { echo "    con un workflow automático presente el anillo fue rechazado (exit $rc): $out"; return 1; }
  printf '%s' "$out" | grep -q 'harness-ci.yml' \
    || { echo "    el ✅ no cita el workflow AUTOMÁTICO, que es el único que respalda la afirmación: $out"; return 1; }
}
test_el_manual_no_enmascara_al_automatico() { _r3_sandbox _case_manual_no_enmascara_al_automatico; }

_case_disparador_en_linea_cuenta() {
  # `on: [push, pull_request]` en una línea es tan válido como el bloque.
  # Un parser que solo entienda una de las dos formas crea un falso negativo
  # que el adoptante no puede diagnosticar (§14.2).
  git remote add origin https://example.invalid/x.git 2>/dev/null
  mkdir -p .github/workflows
  printf 'name: ci\non: [push, pull_request]\njobs:\n  g:\n    steps:\n      - run: bash ci/run-gates.sh\n' \
    > .github/workflows/gates.yml
  local rc; bash tools/check-ring3.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || { echo "    'on: [push, pull_request]' en línea no se reconoció como disparador (exit $rc)"; return 1; }
}
test_disparador_en_una_linea_tambien_cuenta() { _r3_sandbox _case_disparador_en_linea_cuenta; }

# ════════════════════════════════════════════════════════════════════
# El probe de EJECUCIÓN (cableado ≠ operativo)
# ════════════════════════════════════════════════════════════════════
# El reviewer cazó que estas ~24 líneas nacieron con cobertura CERO: el
# sandbox apaga el probe para no salir a la red, y eso dejaba sin probar la
# máquina de estados entera (ok|not-started|unknown). La objeción "consultar
# la API real sería flaky" confunde dos cosas distintas: salir a internet sí,
# pero PARSEAR su salida es determinista y trivialmente mockeable — el patrón
# de `bin/<tool>` falso + PATH ya vive en test_secret_scan.sh. Aquí se aplica
# a `gh`, así que el probe se prueba sin tocar la red.
#
# Lo que fijan estos tests es la distinción que da sentido al probe:
# CERO steps = el job nunca arrancó (anillo MUDO) · steps > 0 = el anillo
# ejecutó (que su resultado sea rojo es el anillo FUNCIONANDO, no un fallo).

_r3_con_anillo_automatico() { # deja el repo con remoto propio + workflow válido
  git remote add origin https://example.invalid/x.git 2>/dev/null
  mkdir -p .github/workflows bin
  printf 'name: ci\non:\n  push:\njobs:\n  g:\n    steps:\n      - run: bash ci/run-gates.sh\n' \
    > .github/workflows/ci.yml
}

_r3_gh_falso() { # <steps-que-reporta> [status-del-run]  (con --jq, gh imprime ya resuelto)
  local _st="${2:-completed}"
  cat > bin/gh <<FAKE
#!/usr/bin/env bash
case "\$1" in
  run) echo "12345 $_st" ;;
  api) echo $1 ;;
esac
exit 0
FAKE
  chmod +x bin/gh
}

_case_probe_cero_steps_es_mudo() {
  _r3_con_anillo_automatico; _r3_gh_falso 0
  local out rc
  out="$(RING3_CHECK_RUNS=1 PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/check-ring3.sh 2>&1)"; rc=$?
  [ "$rc" = "1" ] \
    || { echo "    un anillo cuyo último run no arrancó (0 steps) pasó como operativo (exit $rc): $out"; return 1; }
  printf '%s' "$out" | grep -q 'runs=not-started' \
    || { echo "    el resumen no reporta runs=not-started: $out"; return 1; }
  printf '%s' "$out" | grep -q 'CERO steps' \
    || { echo "    el diagnóstico no explica que el job nunca arrancó: $out"; return 1; }
}
test_probe_cero_steps_es_anillo_mudo() { _r3_sandbox _case_probe_cero_steps_es_mudo; }

_case_probe_con_steps_es_operativo() {
  # Un CI que EJECUTA es el anillo funcionando, aunque su resultado sea rojo:
  # el probe no debe confundir "falló" con "no corrió". Sin este test, endurecer
  # el probe hasta bloquear con CI en rojo pasaría inadvertido.
  _r3_con_anillo_automatico; _r3_gh_falso 20
  local out rc
  out="$(RING3_CHECK_RUNS=1 PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/check-ring3.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || { echo "    un anillo que SÍ ejecuta fue declarado ausente (exit $rc): $out"; return 1; }
  printf '%s' "$out" | grep -q 'runs=ok' \
    || { echo "    el resumen no reporta runs=ok con steps>0: $out"; return 1; }
}
test_probe_con_steps_es_anillo_operativo() { _r3_sandbox _case_probe_con_steps_es_operativo; }

_case_probe_sin_gh_no_bloquea() {
  # §14.3: no pude mirar ≠ no encontré nada. Sin `gh` el probe NO puede
  # convertir su ceguera en un veredicto — sería el fail-closed espejo del
  # fail-open que este script combate.
  _r3_con_anillo_automatico
  local out rc
  out="$(RING3_CHECK_RUNS=1 PATH="/usr/bin:/bin" bash tools/check-ring3.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || { echo "    sin gh instalado el probe tumbó el anillo (exit $rc): $out"; return 1; }
  printf '%s' "$out" | grep -q 'runs=unknown' \
    || { echo "    sin gh el resumen debería decir runs=unknown: $out"; return 1; }
}
test_probe_sin_gh_no_bloquea() { _r3_sandbox _case_probe_sin_gh_no_bloquea; }

_case_probe_con_gh_roto_no_bloquea() {
  # gh presente pero fallando (sin auth, sin red, repo no encontrado): mismo
  # razonamiento que arriba. Un probe que bloquea cuando no puede consultar
  # dejaría el commit trabado por una VPN caída.
  _r3_con_anillo_automatico
  mkdir -p bin
  printf '#!/usr/bin/env bash\necho "gh: auth required" >&2\nexit 4\n' > bin/gh; chmod +x bin/gh
  local out rc
  out="$(RING3_CHECK_RUNS=1 PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/check-ring3.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || { echo "    con gh roto el probe tumbó el anillo (exit $rc): $out"; return 1; }
  printf '%s' "$out" | grep -q 'runs=unknown' \
    || { echo "    con gh roto el resumen debería decir runs=unknown: $out"; return 1; }
}
test_probe_con_gh_roto_no_bloquea() { _r3_sandbox _case_probe_con_gh_roto_no_bloquea; }

_case_pull_request_target_cuenta() {
  # Falso negativo cazado por el reviewer: `pull_request_target` es un
  # disparador automático real y el boundary de la regex lo rechazaba.
  git remote add origin https://example.invalid/x.git 2>/dev/null
  mkdir -p .github/workflows
  printf 'name: ci\non:\n  pull_request_target:\njobs:\n  g:\n    steps:\n      - run: bash ci/run-gates.sh\n' \
    > .github/workflows/ci.yml
  local rc; RING3_CHECK_RUNS=0 bash tools/check-ring3.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || { echo "    'pull_request_target' no se reconoció como disparador automático (exit $rc)"; return 1; }
}
test_pull_request_target_es_disparador_automatico() { _r3_sandbox _case_pull_request_target_cuenta; }

_case_run_en_cola_no_acusa() {
  # EL FALSO POSITIVO QUE HABRIA BLOQUEADO EL CASO MAS COMUN. Un run recien
  # encolado no tiene steps todavia — igual que uno rechazado por presupuesto.
  # Como el probe corre en cada arranque de sesion, el momento tipico para
  # pillarlo es justo despues de un push, o sea el momento en que el anillo
  # esta funcionando PERFECTAMENTE. Sin el filtro por `status == completed`,
  # esto se diagnosticaba como "anillo mudo" y bloqueaba.
  _r3_con_anillo_automatico; _r3_gh_falso 0 in_progress
  local out rc
  out="$(RING3_CHECK_RUNS=1 PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/check-ring3.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] \
    || { echo "    un run EN CURSO (0 steps todavia) se acuso de anillo mudo (exit $rc): $out"; return 1; }
  printf '%s' "$out" | grep -q 'runs=unknown' \
    || { echo "    un run sin completar deberia dar runs=unknown, no un veredicto: $out"; return 1; }
}
test_run_en_cola_no_se_acusa_de_anillo_mudo() { _r3_sandbox _case_run_en_cola_no_acusa; }

# ════════════════════════════════════════════════════════════════════
# El watchdog: su garantía tiene que estar PROBADA, no comentada
# ════════════════════════════════════════════════════════════════════
# El reviewer mató la versión anterior de esta suite con una mutación de una
# línea: quitó `_con_limite` de las dos llamadas a `gh`, dejándolas SIN límite
# ninguno... y los 16 tests seguían verdes. Ningún fake tardaba, así que nada
# observaba la única propiedad que el watchdog existe para dar. Es el ejemplo
# de libro de §5: un test que pasa con cualquier implementación no es un test.
#
# Importa más de lo que parece porque este código corre en CADA arranque de
# sesión: si el watchdog se rompe, el síntoma no es un fallo, es un agente que
# se queda colgado esperando a `gh` sin que nadie sepa por qué.

_case_gh_colgado_se_corta() {
  _r3_con_anillo_automatico
  mkdir -p bin
  printf '#!/usr/bin/env bash\nsleep 10\necho "12345 completed"\n' > bin/gh; chmod +x bin/gh
  local t0 t1 out rc
  t0=$(date +%s)
  out="$(RING3_CHECK_RUNS=1 RING3_RUNS_TIMEOUT=1 PATH="$(pwd)/bin:/usr/bin:/bin" \
         bash tools/check-ring3.sh 2>&1)"; rc=$?
  t1=$(date +%s)
  [ $((t1 - t0)) -le 5 ] \
    || { echo "    un gh colgado NO se acotó: $((t1-t0))s con RING3_RUNS_TIMEOUT=1"; return 1; }
  [ "$rc" = "0" ] \
    || { echo "    un gh colgado tumbó el anillo (exit $rc) en vez de degradar a unknown"; return 1; }
  printf '%s' "$out" | grep -q 'runs=unknown' \
    || { echo "    un gh que no responde debería dar runs=unknown: $out"; return 1; }
}
test_un_gh_colgado_se_corta_y_no_acusa() { _r3_sandbox _case_gh_colgado_se_corta; }

_case_gh_que_ignora_term_igual_se_corta() {
  # Un límite que el hijo puede ignorar es una sugerencia, no un límite. Con
  # `trap "" TERM` el proceso sobrevivía al TERM y corría entero.
  _r3_con_anillo_automatico
  mkdir -p bin
  printf '#!/usr/bin/env bash\ntrap "" TERM\nsleep 10\n' > bin/gh; chmod +x bin/gh
  local t0 t1 rc
  t0=$(date +%s)
  RING3_CHECK_RUNS=1 RING3_RUNS_TIMEOUT=1 PATH="$(pwd)/bin:/usr/bin:/bin" \
    bash tools/check-ring3.sh >/dev/null 2>&1; rc=$?
  t1=$(date +%s)
  [ $((t1 - t0)) -le 6 ] \
    || { echo "    un gh que ignora TERM corrió entero: $((t1-t0))s con límite 1s (¿falta escalar a KILL?)"; return 1; }
  [ "$rc" = "0" ] || { echo "    tras cortar un gh sordo el anillo quedó acusado (exit $rc)"; return 1; }
}
test_un_gh_que_ignora_term_se_mata_igual() { _r3_sandbox _case_gh_que_ignora_term_igual_se_corta; }

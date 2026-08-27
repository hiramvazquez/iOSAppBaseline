#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# test_e2e_capacidades_declaradas.sh — GOLDEN 1/2/4 del PRD 0004 (fase 10)
# ════════════════════════════════════════════════════════════════════
# Parte de la MATRIZ E2E del PRD 0004, dividida en fase 2a del PRD 0005
# (tools/tests/test_e2e_matrix.sh superaba el hard limit de 400 líneas,
# AGENTS.md §4) por FAMILIA de escenario, no por posición. Este archivo
# cubre el hilo "capacidad DECLARADA vs capacidad DEMOSTRADA" en sus tres
# formas: un manifiesto que gobierna documentos generados (G1), un binario
# roto que tiene que verse roto en TODOS sus consumidores (G2), y un stack
# sin detector que se declara `unsupported` en vez de leerse como limpio (G4).
# Las hermanas de esta matriz — orquestador del backlog, ledger/lecciones,
# gates del Anillo 3, plataformas — viven en los otros `test_e2e_*.sh`.
#
# QUÉ ES ESTO Y QUÉ NO ES. Los unitarios de cada fase (test_capabilities,
# test_capability_probe, test_architecture_capabilities…) siguen siendo la
# red fina: bordes, falsos positivos, contratos de exit. Esto cruza FRONTERAS
# de script —manifiesto→documento, probe→scanner→arranque, clasificador→
# validate-harness— porque un harness puede tener todas sus piezas verdes y
# estar roto en las costuras.
#
# HERMÉTICA POR CONSTRUCCIÓN: ni `claude` ni `semgrep` reales. Los proveedores
# entran por stubs en un `bin/` del sandbox y el PATH se fija a mano, así que
# el resultado no depende de lo que tenga instalado la máquina.

# ── Sandbox con la maquinaria real, no con recortes ──────────────────
# Un E2E que copia solo los tres scripts que va a llamar no prueba la
# integración: prueba el recorte que hizo quien escribió el test. Aquí va la
# maquinaria entera (tools sin su propia suite, scripts, ci, .github) sobre un
# repo git nuevo.
_e2e_repo() { # _e2e_repo <función>
  local d rc; d="$(mktemp -d)"
  cp -R "$PROJECT_ROOT/tools" "$d/tools" 2>/dev/null
  rm -rf "$d/tools/tests"
  cp -R "$PROJECT_ROOT/scripts" "$d/scripts" 2>/dev/null
  cp -R "$PROJECT_ROOT/ci" "$d/ci" 2>/dev/null
  mkdir -p "$d/.github/workflows" "$d/docs/process" "$d/backlog"
  cp "$PROJECT_ROOT/.github/workflows/harness-ci.yml" "$d/.github/workflows/" 2>/dev/null
  cp "$PROJECT_ROOT/AGENTS.md" "$d/AGENTS.md" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q -b develop . 2>/dev/null
    git config user.email t@t.t; git config user.name t
    echo seed > seed.txt
    git add -A >/dev/null 2>&1
    git commit -qm "seed: maquinaria del harness" >/dev/null 2>&1
    "$1"
  )
  rc=$?
  rm -rf "$d"
  return $rc
}

# ════════════════════════════════════════════════════════════════════
# GOLDEN 1 — manifiesto → bloques generados, sin tocar la prosa
# ════════════════════════════════════════════════════════════════════
# Los unitarios cubren cada modo por separado. Lo que se cruza aquí es el
# CICLO de vida completo sobre un documento con prosa antes y después del
# bloque: install → check limpio → el manifiesto cambia → drift → write →
# check limpio, con la prosa intacta en las dos orillas.
_case_g1_ciclo_manifiesto_documento() {
  mkdir -p docs
  cat > tools/capabilities.json <<'JSON'
{"schema":1,
 "documents":["docs/OPS.md"],
 "capabilities":{
   "ring3":{"title":"CI ejecuta los gates","provider":"ci/run-gates.sh",
            "required_in_full":true,"required_in_lite":false}
 }}
JSON
  printf 'prosa de arriba que nadie generó\n' > docs/OPS.md
  bash tools/render-capabilities.sh --install >/dev/null 2>&1 \
    || { echo "    --install falló sobre un documento sin markers"; return 1; }
  printf '\nprosa de abajo que nadie generó\n' >> docs/OPS.md
  bash tools/render-capabilities.sh --check >/dev/null 2>&1 \
    || { echo "    --check no quedó limpio inmediatamente tras --install"; return 1; }

  sed -i.bak 's/"required_in_lite":false/"required_in_lite":true/' tools/capabilities.json \
    && rm -f tools/capabilities.json.bak
  local err rc
  err="$(bash tools/render-capabilities.sh --check 2>&1)"; rc=$?
  [ "$rc" = 1 ] || { echo "    un bloque desactualizado devolvió $rc (esperaba 1)"; return 1; }
  assert_contains "$err" "docs/OPS.md" || return 1

  bash tools/render-capabilities.sh --write >/dev/null 2>&1 \
    || { echo "    --write falló"; return 1; }
  bash tools/render-capabilities.sh --check >/dev/null 2>&1 \
    || { echo "    tras --write el bloque seguía en drift"; return 1; }
  grep -q 'prosa de arriba' docs/OPS.md && grep -q 'prosa de abajo' docs/OPS.md \
    || { echo "    el renderer se comió prosa libre fuera de los markers"; return 1; }
}
test_golden_01_manifiesto_gobierna_los_bloques_generados() {
  _e2e_repo _case_g1_ciclo_manifiesto_documento
}

# ════════════════════════════════════════════════════════════════════
# GOLDEN 2 — un binario que revienta nunca produce verde, en NINGÚN consumidor
# ════════════════════════════════════════════════════════════════════
# La pata nueva es la cadena: el mismo semgrep roto visto por el probe
# (broken), por el scanner (exit 3 = "no pude mirar", jamás 0) y por el
# arranque (Nivel 2 ROTO). Tres consumidores, un solo hecho.
_case_g2_semgrep_roto_en_toda_la_cadena() {
  mkdir -p bin
  stub bin/semgrep '#!/usr/bin/env bash\ncase "${1:-}" in --version) echo 9.9.9; exit 0 ;; esac\necho "Fatal error: X509 trust anchors: CA store vacío" >&2\nexit 2\n'
  local hermetic="$PWD/bin:/usr/bin:/bin"

  local probe rc
  probe="$(PATH="$hermetic" bash tools/probe-capability.sh semgrep 2>/dev/null)"; rc=$?
  [ "$rc" = 1 ] || { echo "    el probe de un binario roto devolvió $rc (esperaba 1)"; return 1; }
  assert_contains "$probe" '"status":"broken"' || return 1
  assert_contains "$probe" 'X509' || return 1

  # El scanner: 3 = el detector no pudo mirar. Nunca 0. (Sin jq en el PATH
  # hermético el camino es el otro exit 3 del mismo contrato: ambos dicen
  # "no corrí", que es lo que este escenario fija.)
  PATH="$hermetic" bash tools/semgrep-scan.sh --all >/dev/null 2>&1
  rc=$?
  [ "$rc" = 3 ] || { echo "    un semgrep roto dejó el scanner en exit $rc (esperaba 3)"; return 1; }

  local report
  report="$(PATH="$hermetic" bash scripts/agent-hooks/session-start.sh --report 2>&1 </dev/null)"
  assert_contains "$report" "Nivel 2 ROTO" || return 1
}
test_golden_02_binario_roto_no_es_verde_en_ningun_consumidor() {
  _e2e_repo _case_g2_semgrep_roto_en_toda_la_cadena
}

# ════════════════════════════════════════════════════════════════════
# GOLDEN 4 — sin detector de ciclos se dice `unsupported`, no "sin ciclos"
# ════════════════════════════════════════════════════════════════════
# La pata nueva es el consumidor: `validate-harness` tiene que repetir el
# estado declarado, no traducirlo a silencio (que es como se lee "todo bien").
_case_g4_ausencia_no_es_arquitectura_limpia() {
  local out rc
  out="$(bash tools/architecture-check.sh all 2>&1)"; rc=$?
  [ "$rc" = 1 ] || { echo "    sin config el clasificador devolvió $rc (esperaba 1)"; return 1; }
  assert_contains "$out" '"status":"missing"' || return 1

  cat > tools/architecture.conf <<'JSON'
{"schema":1,"capabilities":{
  "architecture_cycles":{"status":"unsupported","reason":"el stack no trae detector de ciclos"},
  "architecture_complexity":{"status":"unsupported","reason":"sin adapter de complejidad"}}}
JSON
  out="$(bash tools/architecture-check.sh all 2>&1)"; rc=$?
  [ "$rc" = 0 ] || { echo "    unsupported explícito devolvió $rc (esperaba 0)"; return 1; }
  assert_contains "$out" '"status":"unsupported"' || return 1
  assert_contains "$out" 'ARCHITECTURE_SUMMARY operational=0 unsupported=2 missing=0 broken=0' || return 1

  local vh
  vh="$(PATH="/usr/bin:/bin" bash tools/validate-harness.sh 2>&1 </dev/null)"
  assert_contains "$vh" "architecture_cycles unsupported" || return 1
  case "$vh" in
    *"architecture_cycles operational"*)
      echo "    el consumidor convirtió unsupported en operativo"; return 1 ;;
  esac
}
test_golden_04_stack_sin_detector_declara_unsupported() {
  _e2e_repo _case_g4_ausencia_no_es_arquitectura_limpia
}


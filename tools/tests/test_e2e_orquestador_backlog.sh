#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# test_e2e_orquestador_backlog.sh — GOLDEN 3/5 del PRD 0004 (fase 10)
# ════════════════════════════════════════════════════════════════════
# Parte de la MATRIZ E2E del PRD 0004, dividida en fase 2a del PRD 0005
# (tools/tests/test_e2e_matrix.sh superaba el hard limit de 400 líneas,
# AGENTS.md §4) por FAMILIA de escenario, no por posición. Este archivo
# cubre `tools/backlog/run.sh` como ORQUESTADOR: una historia con scope
# explícito que intenta salirse de él nunca llega a `in-review` (G3), y el
# ciclo de autonomía completo contra un CLI stub —incluida la review
# read-only DEMOSTRADA, no declarada— cierra en `in-review` con evidencia
# ligada al mismo staged SHA (G5). Las hermanas de esta matriz — capacidades
# declaradas, ledger/lecciones, gates del Anillo 3, plataformas — viven en
# los otros `test_e2e_*.sh`.
#
# QUÉ ES ESTO Y QUÉ NO ES. `test_backlog.sh` y `test_backlog_scope.sh` cubren
# el checker y el ciclo con `fake.sh`; esto prueba al ORQUESTADOR completo
# —worktree real, commit real, estado que ve un humano al final— y, en G5,
# el mismo ciclo a través de `claude.sh` con el CLI stubbeado.
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
  # El sandbox es maquinaria copiada SIN app, así que se declara por lo que ES.
  # Sin esto hereda el project.conf del repo anfitrión: en un ADOPTANTE eso es
  # `application`, y `application` declarado + cero fuentes de app es una
  # CONTRADICCIÓN que scope.sh reporta con exit 3 bajo CI=true — tumbando en CI
  # tests que localmente pasan. Cazado cableando el Anillo 3 de un adoptante.
  printf 'project_kind: harness\n' > "$d/tools/project.conf"
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

_e2e_story() { # _e2e_story <archivo> <id> <scope>
  cat > "backlog/$1" <<EOF
---
id: $2
titulo: Historia E2E $2
status: ready
depends_on: []
base: develop
scope: |
  $3
---
## Criterios de aceptación
1. Dado el runner autónomo cuando termina la historia entonces queda evidencia ligada al diff.

## Verificación de criterios
1. n/a-manual — historia del propio harness, sin producto que verificar
EOF
}

# ════════════════════════════════════════════════════════════════════
# GOLDEN 3 — un path fuera de scope no llega a in-review
# ════════════════════════════════════════════════════════════════════
# `test_backlog_scope.sh` prueba el checker; esto prueba al ORQUESTADOR
# usándolo: worktree real, commit real dentro de la rama, y el estado que ve
# un humano al final.
_case_g3_scope_creep_no_cierra() {
  _e2e_story 0001-scope.md 0001 'src/**'
  git add -A && git commit -qm "historia 0001" >/dev/null 2>&1
  stub fake-run.sh '#!/usr/bin/env bash\nset -uo pipefail\nmkdir -p src fuera\nprintf "dentro\\n" > src/dentro.txt\nprintf "creep\\n" > fuera/creep.txt\ngit add -A\nbash tools/agent-backends/fake-evidence.sh approve || exit 10\nGIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$PWD/tools/agent-backends/fake-hooks" git -c user.email=a@a -c user.name=a commit -qm "feat: con creep" >/dev/null 2>&1\n'

  FAKE_RUN_SCRIPT="$PWD/fake-run.sh" FAKE_AUTONOMY_EVIDENCE="$PWD/evidence.log" \
    bash tools/backlog/run.sh --backend fake >/dev/null 2>&1
  local rc=$? estado
  [ "$rc" = 6 ] || { echo "    scope creep devolvió $rc (esperaba 6)"; return 1; }
  estado="$(git show story/0001-scope:backlog/0001-scope.md 2>/dev/null | grep '^status:')"
  case "$estado" in
    *in-review*) echo "    la historia llegó a in-review con un path fuera de scope"; return 1 ;;
    *in-progress*) : ;;
    *) echo "    estado inesperado tras el scope creep: $estado"; return 1 ;;
  esac
}
test_golden_03_scope_fuera_de_contrato_no_llega_a_in_review() {
  _e2e_repo _case_g3_scope_creep_no_cierra
}

# ════════════════════════════════════════════════════════════════════
# GOLDEN 5 — autonomía completa contra un CLI de proveedor STUB
# ════════════════════════════════════════════════════════════════════
# `test_backlog.sh` ya demuestra el ciclo con `fake.sh`. Lo que faltaba —y es
# lo que pide el PRD §10— es el mismo ciclo a través de `claude.sh` con el CLI
# stubbeado, y una verificación que nadie hacía: que la review del adapter sea
# READ-ONLY DE VERDAD (plan + herramientas de lectura), no read-only declarado.
_case_g5_ciclo_autonomo_con_claude_stub() {
  _e2e_story 0002-autonomia.md 0002 'src/**'
  git add -A && git commit -qm "historia 0002" >/dev/null 2>&1
  mkdir -p bin

  # jq hermético: el adapter tiene rama con y sin jq, y cuál corre no puede
  # depender de dónde instaló jq esta máquina. En este flujo el único
  # consumidor de jq es claude.sh.
  stub bin/jq '#!/usr/bin/env bash\npython3 -c "import json,sys; print(json.load(sys.stdin).get(\"result\",\"\"))"\n'

  cat > bin/claude <<'STUB'
#!/usr/bin/env bash
# Stub hermético del CLI: ni red ni modelo. Registra su argv para que el test
# pueda comprobar el contrato con el que lo invocó el adapter.
set -uo pipefail
printf '%s\n' "$*" >> "$CLAUDE_ARGV_LOG"
case " $* " in
  *" --permission-mode plan "*)
    printf '{"result":"VERDICT: GREEN\\nFINDINGS: 0\\nSCOPE: e2e-claude-stub"}\n'
    exit 0 ;;
esac
# Rama `run`: el prompt portable tiene que traer la historia concatenada.
case "$*" in
  *"id: 0002"*) : ;;
  *) echo "stub: el prompt de run no traía la historia" >&2; exit 8 ;;
esac
mkdir -p src
printf 'implementacion\n' > src/feature.txt
git add -A
bash tools/agent-backends/fake-evidence.sh approve || exit 10
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath \
  GIT_CONFIG_VALUE_0="$PWD/tools/agent-backends/fake-hooks" \
  git -c user.email=a@a -c user.name=a commit -qm "feat: e2e" >/dev/null 2>&1 || exit 11
STUB
  chmod +x bin/claude

  local rc estado argv_log="$PWD/claude-argv.log" evidencia="$PWD/evidence.log"
  : > "$argv_log"
  PATH="$PWD/bin:/usr/bin:/bin" CLAUDE_ARGV_LOG="$argv_log" \
    FAKE_AUTONOMY_EVIDENCE="$evidencia" \
    bash tools/backlog/run.sh >/dev/null 2>&1
  rc=$?
  [ "$rc" = 0 ] || { echo "    el ciclo autónomo con claude stub falló (rc=$rc)"; return 1; }
  estado="$(git show story/0002-autonomia:backlog/0002-autonomia.md 2>/dev/null | grep '^status:')"
  case "$estado" in *in-review*) : ;; *) echo "    no cerró en in-review ($estado)"; return 1 ;; esac
  ls .agents/state/backlog/0002-review-*.log >/dev/null 2>&1 \
    || { echo "    la review final no dejó evidencia persistida"; return 1; }

  # Evidencia ligada al MISMO staged SHA: review antes del commit, no después.
  local aprobado commiteado
  aprobado="$(grep '^approved:' "$evidencia" | tail -1)"
  commiteado="$(grep '^committed:' "$evidencia" | tail -1)"
  [ -n "$aprobado" ] || { echo "    no hubo review previa al commit de producto"; return 1; }
  [ "${aprobado#approved:}" = "${commiteado#committed:}" ] \
    || { echo "    review y commit no quedaron ligados al mismo staged SHA"; return 1; }

  # La review del adapter es read-only DEMOSTRADO, no declarado.
  local linea_review
  linea_review="$(grep -- '--permission-mode plan' "$argv_log" | tail -1)"
  [ -n "$linea_review" ] || { echo "    el adapter no invocó la review en modo plan"; return 1; }
  assert_contains "$linea_review" '--output-format json' || return 1
  assert_contains "$linea_review" '--allowedTools' || return 1
  # `*Edit*` cubre también `acceptEdits`: cualquier permiso de escritura en la
  # invocación de review rompe el contrato read_only que el backend declara.
  case "$linea_review" in
    *Edit*|*Write*)
      echo "    la review pidió herramientas de escritura: $linea_review"; return 1 ;;
  esac

  # Y el mismo contrato de review, en CI, sin proveedor instalado.
  PATH="/usr/bin:/bin" AI_REVIEW_REQUIRED=1 GATES_BASE_REF=HEAD~1 \
    bash ci/ai-review.sh --backend fake >/dev/null 2>&1 \
    || { echo "    ai-review con backend fake falló sin claude en PATH"; return 1; }
  grep -q 'VERDICT: GREEN' .agents/state/ci/ai-review.md 2>/dev/null \
    || { echo "    ai-review no dejó veredicto parseable"; return 1; }
}
test_golden_05_autonomia_completa_contra_cli_stub() {
  _e2e_repo _case_g5_ciclo_autonomo_con_claude_stub
}


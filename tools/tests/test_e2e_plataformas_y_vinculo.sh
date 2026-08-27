#!/usr/bin/env bash
# Ruta de ESTE archivo, para poder re-sourcearlo en un subshell (ver el test del
# invariante del smoke, al final): el runner hace `unset -f` de cada test según
# los va ejecutando, así que una función hermana no está disponible más tarde.
_E2E_ESTE_ARCHIVO="${BASH_SOURCE[0]}"
# ¿Este repo queda EXENTO de los checks que miran ARTEFACTOS DEL TEMPLATE?
# → 0 (sí, e imprime el motivo) · 1 (no). Lo usan el golden 10 (que mira los
# workflows del harness) y el vínculo con el PRD 0004 (que mira sus PRDs).
#
# Vive fuera de los tests a propósito: es la ÚNICA ruta por la que se decide la
# exención, y así el test de regresión de abajo ejerce exactamente el mismo
# código que el vínculo real. La primera versión de aquel test sourceaba
# `scope.sh` por su cuenta y quedaba en verde contra un mutante que reinstalaba
# el parseo roto — probaba la librería, no la decisión. Lo cazó el reviewer con
# ese mutante, y es la definición de test decorativo (AGENTS.md §5).
#
# Se reusa `_scope_project_kind`, que valida contra el enum: un typo (`harnes`)
# devuelve vacío y NO exime — la autoprotección del harness cae fail-closed.
_e2e_exime_por_kind() { # $1 = raíz del repo
  local raiz="$1" kind=""
  # shellcheck source=/dev/null
  [ -f "$raiz/tools/lib/scope.sh" ] \
    && kind="$( cd "$raiz" 2>/dev/null && . tools/lib/scope.sh >/dev/null 2>&1; _scope_project_kind 2>/dev/null )"
  case "$kind" in
    application|other)
      printf 'project_kind=%s — los artefactos del template (sus PRDs, sus workflows) no son los del adoptante' "$kind"
      return 0 ;;
  esac
  return 1
}

# ════════════════════════════════════════════════════════════════════
# test_e2e_plataformas_y_vinculo.sh — GOLDEN 10 + el vínculo con el PRD
# ════════════════════════════════════════════════════════════════════
# Parte de la MATRIZ E2E del PRD 0004, dividida en fase 2a del PRD 0005
# (tools/tests/test_e2e_matrix.sh superaba el hard limit de 400 líneas,
# AGENTS.md §4) por FAMILIA de escenario, no por posición. Este archivo
# cubre dos cosas que no encajaban en ninguna otra familia: (a) que la
# matriz de CI declare de verdad las dos plataformas y que el smoke contra
# ESTA máquina no pueda mentir sobre su propio estado (G10); y (b) el
# VÍNCULO mecánico entre el PRD 0004 §9 y los `test_golden_NN_` que lo
# demuestran — sin él, un escenario 11 sin test se leería como Definition
# of Done cumplida. Las hermanas de esta matriz — capacidades declaradas,
# orquestador del backlog, ledger/lecciones, gates del Anillo 3 — viven en
# los otros `test_e2e_*.sh`.
#
# A diferencia de las otras familias, NINGUNO de los dos tests de aquí usa
# el sandbox `_e2e_repo`: G10 corre contra ESTE repo y el smoke es real por
# diseño (§ arriba), y el vínculo lee el PRD y los propios `test_e2e_*.sh`
# del árbol de trabajo — sandboxearlos sería probar una copia, no la matriz.

# ════════════════════════════════════════════════════════════════════
# GOLDEN 10 — dos plataformas, y un smoke real que no puede mentir
# ════════════════════════════════════════════════════════════════════
# Las dos mitades del escenario: (a) la promesa de plataformas es código en
# workflows reales, no una frase en un doc. Desde 2026-08-25 el contrato es
# Linux en cada push (la única pata que ninguna máquina local cubre) y macOS
# a demanda en harness-ci-macos.yml (workflow_dispatch) — el pre-push local
# ya corre la suite en el Mac de quien publica, y macOS consume cupo a 10×
# (f-787568d2; racional en las cabeceras de ambos YAML). Este test fija que
# LAS DOS mitades del contrato nuevo sigan siendo código, no que la matriz
# vieja vuelva. (b) el smoke contra el entorno
# de ESTA máquina no exige un estado concreto —puede faltar semgrep, puede
# estar roto— pero sí que estado y exit code sean el mismo hecho. Un verde
# solo puede salir de un probe que corrió y detectó su fixture.
test_golden_10_dos_plataformas_y_smoke_sin_falso_verde() {
  local wf="$PROJECT_ROOT/.github/workflows/harness-ci.yml"
  local wf_mac="$PROJECT_ROOT/.github/workflows/harness-ci-macos.yml"
  # La mitad (a) mira los workflows DEL HARNESS: un adoptante tiene los suyos
  # (su gates.yml ejecuta ci/run-gates.sh) y no debe cargar con estos. La mitad
  # (b) —el smoke de capacidades— sí corre en todas partes: va sobre ESTA
  # máquina, no sobre artefactos heredados. Que check-ring3 valide el CI real
  # del adoptante es lo que cubre su lado.
  local motivo_g10
  if motivo_g10="$(_e2e_exime_por_kind "$PROJECT_ROOT")"; then
    echo "    (matriz de CI del harness: no aplica — $motivo_g10)"
  else
    [ -f "$wf" ] || { echo "    no hay workflow que ejecute la suite"; return 1; }
    local matriz
    matriz="$(awk '/^ *os: \[/{print; exit}' "$wf")"
    case "$matriz" in
      *ubuntu*) : ;;
      *) echo "    la matriz por push perdió la pata Linux: ${matriz:-ausente}"; return 1 ;;
    esac
    grep -q 'bash tools/tests/run-tests.sh' "$wf" \
      || { echo "    el workflow por push no ejecuta la suite del harness"; return 1; }
    # La pata macOS no desapareció: vive a demanda, y eso también es código.
    [ -f "$wf_mac" ] \
      || { echo "    falta harness-ci-macos.yml: macOS a demanda sería una promesa sin workflow"; return 1; }
    grep -q 'workflow_dispatch' "$wf_mac" \
      || { echo "    harness-ci-macos.yml no es disparable a demanda (sin workflow_dispatch)"; return 1; }
    grep -q 'macos' "$wf_mac" \
      || { echo "    harness-ci-macos.yml no corre en macOS"; return 1; }
    grep -q 'bash tools/tests/run-tests.sh' "$wf_mac" \
      || { echo "    harness-ci-macos.yml no ejecuta la suite del harness"; return 1; }
  fi

  local probe rc estado
  probe="$(PROBE_TIMEOUT_SECS=20 bash "$PROJECT_ROOT/tools/probe-capability.sh" semgrep 2>/dev/null)"
  rc=$?
  estado="$(printf '%s' "$probe" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status","unknown"))' 2>/dev/null \
    || echo unknown)"
  case "$estado:$rc" in
    operational:0|missing:1|broken:1|unknown:3) : ;;
    *)
      echo "    el smoke real emparejó mal estado y exit ($estado:$rc): un falso verde es posible"
      return 1 ;;
  esac
}

# ════════════════════════════════════════════════════════════════════
# EL VÍNCULO — la matriz no puede quedarse atrás del PRD
# ════════════════════════════════════════════════════════════════════
# Sin esto, añadir un escenario golden 11 dejaría la "Definition of Done" en
# verde sin cubrirlo: la lista y su demostración divergen en silencio, que es
# el modo de fallo que este PRD persigue. La fuente es el PRD; el test solo
# comprueba que exista un `test_golden_NN_` por escenario declarado.
#
# ⚠️ La matriz vive dividida en varios `tools/tests/test_e2e_*.sh` (fase 2a
# del PRD 0005 — cada archivo por debajo del hard limit, AGENTS.md §4). El
# vínculo busca en TODOS los que casen ese glob, no en un nombre de archivo
# fijo: un vínculo que solo mirara `test_e2e_matrix.sh` habría quedado
# pasando en falso —0 tests golden encontrados, o peor, el test ni se habría
# corrido— en el momento mismo en que la propia división lo movió.
test_matriz_e2e_cubre_los_diez_escenarios_golden() {
  local prd="$PROJECT_ROOT/docs/process/prds/0004-reconciliar-workflow-agentico.md"
  local archivos=("$PROJECT_ROOT"/tools/tests/test_e2e_*.sh)
  # Este vínculo es del HARNESS sobre su propia trazabilidad: cuadra los goldens
  # contra el PRD que los enumera. En un ADOPTANTE ese PRD no existe —ni debe:
  # es historia del template, no suya (f-12096526)— y exigirlo dejaba la suite
  # en 651/652 nada más adoptar, con un rojo que el adoptante no puede arreglar
  # salvo heredando documentación ajena. La declaración manda (WF-05).
  local motivo
  if motivo="$(_e2e_exime_por_kind "$PROJECT_ROOT")"; then
    echo "    (no aplica: $motivo)"
    return 0
  fi
  [ -f "$prd" ] || { echo "    falta el PRD 0004: la matriz no tiene contra qué cuadrar"; return 1; }
  local total
  total="$(awk '/^## 9\. Escenarios golden/{s=1;next} /^## 10\./{s=0} s && /^[0-9]+\./{n++} END{print n+0}' "$prd")"
  [ "${total:-0}" -gt 0 ] \
    || { echo "    no pude leer los escenarios golden del PRD (¿cambió el encabezado §9?)"; return 1; }

  local i=1 n faltan=""
  while [ "$i" -le "$total" ]; do
    n="$(printf '%02d' "$i")"
    grep -q "^test_golden_${n}_" "${archivos[@]}" || faltan="$faltan $n"
    i=$((i + 1))
  done
  [ -z "$faltan" ] || { echo "    escenarios golden del PRD sin test E2E:$faltan"; return 1; }

  local tiene nfiles
  tiene="$(grep -h '^test_golden_[0-9][0-9]_' "${archivos[@]}" | wc -l | tr -d ' ')"
  nfiles="${#archivos[@]}"
  [ "$tiene" = "$total" ] \
    || { echo "    la matriz declara $tiene tests golden repartidos en $nfiles archivos y el PRD $total escenarios"; return 1; }
}

# ════════════════════════════════════════════════════════════════════
# La exención por project_kind: sus ramas, y lo que NO exime
# ════════════════════════════════════════════════════════════════════
# Los dos checks de arriba se saltan en adoptantes (ni los PRDs ni los
# workflows del harness son suyos) pero DEBEN seguir exigiéndose en el harness. Un parseo ad hoc hacía
# que un typo en `project_kind` desactivara la autoprotección en silencio; se
# reusó `_scope_project_kind`, que valida contra el enum. Esto lo fija.
test_la_exencion_del_vinculo_distingue_harness_de_adoptante() {
  local sb; sb="$(mktemp -d)"
  mkdir -p "$sb/tools/lib"
  cp "$PROJECT_ROOT/tools/lib/scope.sh" "$sb/tools/lib/scope.sh"
  ( cd "$sb" && git init -q . 2>/dev/null )

  # Se ejerce EL HELPER REAL (`_e2e_exime_por_kind`), el mismo que usa
  # el vínculo: si alguien reinstala un parseo propio ahí dentro, esto se pone
  # rojo. Sourcear `scope.sh` por separado aquí dejaba pasar ese mutante.
  _exime_con() { # $1 = contenido de project.conf → 0 si exime, 1 si no
    printf '%s\n' "$1" > "$sb/tools/project.conf"
    _e2e_exime_por_kind "$sb" >/dev/null 2>&1
  }

  local rc=0
  _exime_con 'project_kind: application' \
    || { echo "    un adoptante (application) NO quedó exento: el vínculo le exigiría PRDs ajenos"; rc=1; }
  _exime_con 'project_kind: other' \
    || { echo "    un repo declarado 'other' tampoco quedó exento"; rc=1; }
  ! _exime_con 'project_kind: harness' \
    || { echo "    el HARNESS quedó exento de su propio vínculo: la autoprotección se apagó"; rc=1; }
  # El typo es el caso que motivó reusar el parser canónico: no puede leerse
  # como "adoptante", porque eso desactivaría el self-check sin que nadie lo vea.
  ! _exime_con 'project_kind: harnes' \
    || { echo "    un TYPO en project_kind eximió al harness — fail-open silencioso"; rc=1; }
  # Comentario en línea: el parseo por campos de la lib lo tolera.
  ! _exime_con 'project_kind: harness  # el repo del harness' \
    || { echo "    un comentario en línea rompió el parseo y eximió al harness"; rc=1; }
  # Sin conf declarado → fail-closed (no exime).
  rm -f "$sb/tools/project.conf"
  ! _e2e_exime_por_kind "$sb" >/dev/null 2>&1 \
    || { echo "    sin project.conf declarado la exención se activó sola (debe ser fail-closed)"; rc=1; }

  rm -rf "$sb"; return $rc
}

# El invariante que la exención NO puede romper: aunque la mitad (a) del golden
# 10 se salte (los workflows del harness no son los del adoptante), la mitad
# (b) —el smoke de capacidades sobre ESTA máquina— tiene que seguir corriendo.
# Sin este test, meter el bloque del smoke dentro del `if` dejaría a todos los
# adoptantes sin nivel 2 verificado y nada se pondría rojo: fail-open silencioso
# en el test que existe justamente para impedir falsos verdes. Lo señaló el
# reviewer tras comprobarlo A MANO — y una comprobación a mano que nadie repite
# es exactamente lo que este harness convierte en test.
test_la_exencion_no_se_lleva_por_delante_el_smoke_de_capacidades() {
  local sb; sb="$(mktemp -d)" rc=0
  mkdir -p "$sb/tools/lib" "$sb/tools/tests"
  cp "$PROJECT_ROOT/tools/lib/scope.sh" "$sb/tools/lib/scope.sh"
  printf 'project_kind: application\n' > "$sb/tools/project.conf"
  # Con una fuente de app de verdad: `application` declarado y CERO fuentes es
  # una CONTRADICCIÓN que scope.sh reporta con exit 3 bajo CI=true, y entonces
  # el kind no se lee, no se exime, y el test mediría otra cosa. Un adoptante
  # real tiene código; el sandbox también debe tenerlo.
  mkdir -p "$sb/Sources" && printf 'struct App {}\n' > "$sb/Sources/App.swift"
  # `scope.sh` lee la declaración a través de git (del índice), así que el
  # sandbox tiene que ser un repo de verdad: sin esto el kind sale vacío, NO se
  # exime, y el golden muere en la rama estricta antes de llegar al smoke —
  # fail-closed correcto, pero entonces este test mediría otra cosa.
  ( cd "$sb" && git init -q . && git add -A && git -c user.email=t@t.t -c user.name=t commit -qm sandbox ) >/dev/null 2>&1
  # SIN los workflows del harness: es el estado real de un adoptante, el que
  # activa la exención de la mitad (a).

  # El probe se sustituye por un stub que DEJA RASTRO: así el test no pregunta
  # "¿pasó el golden?" sino "¿llegó a ejecutar el smoke?", que es el invariante.
  cat > "$sb/tools/probe-capability.sh" <<'STUB'
#!/usr/bin/env bash
touch "$(dirname "$0")/../.smoke-corrio"
printf '{"status":"missing"}\n'
exit 1
STUB
  chmod +x "$sb/tools/probe-capability.sh"

  # El archivo se sourcea DE NUEVO dentro del subshell a propósito: `run-tests.sh`
  # hace `unset -f` de cada test en cuanto lo ejecuta (y de los que no casan el
  # filtro, antes de empezar), así que para entonces `test_golden_10_…` ya no
  # existe. Sin este re-source el test daría un falso rojo por "función no
  # encontrada" y no por el invariante que mide.
  ( PROJECT_ROOT="$sb"
    # shellcheck source=/dev/null
    . "$_E2E_ESTE_ARCHIVO" >/dev/null 2>&1
    test_golden_10_dos_plataformas_y_smoke_sin_falso_verde >/dev/null 2>&1 )
  [ -f "$sb/.smoke-corrio" ] \
    || { echo "    la exención de la matriz se llevó por delante el smoke: un adoptante"
         echo "    se quedaría sin la comprobación de capacidades y nada lo delataría"; rc=1; }

  rm -rf "$sb"; return $rc
}

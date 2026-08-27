#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# run-tests.sh — runner de los tests de shell del HARNESS
# ════════════════════════════════════════════════════════════════════
# Los gates son código. Código con lógica de decisión sin test es deuda
# (AGENTS.md §5). Estos tests fijan los INVARIANTES del harness, no del
# producto: si alguien rompe "el ratchet solo baja" o "lite no relaja el
# ratchet", esto falla.
#
#   bash tools/tests/run-tests.sh            # todos
#   bash tools/tests/run-tests.sh verdict    # solo los que matcheen "verdict"
#
# Contrato de un archivo de test: `tools/tests/test_*.sh` que define
# funciones `test_*`. El runner las descubre y las corre en un subshell
# con un repo git temporal como cwd cuando pide aislamiento.
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PROJECT_ROOT
cd "$PROJECT_ROOT"

# ── El entorno del ANFITRIÓN no entra: los tests son herméticos ──────
# Un test cuyo veredicto depende de una variable que él no puso mide otra cosa
# — y lo hace en silencio, dando un rojo que acusa al harness de un fallo del
# entorno. Pasó dos veces con la misma forma: un workflow de CI que pone
# GATES_SKIP_TESTS=1 en el step (legítimo: en Ubuntu no hay Xcode para el build
# de una app iOS) tumbaba `golden_09`, y un `export REVIEWER_OVERRIDE=1` en la
# shell de un dev tumba 12 de los 26 tests de `test_scope_kind.sh` — los que
# comprueban que el gate SIGUE exigiendo review.
#
# Se sanea UNA vez, aquí, en vez de exigir que cada archivo de test recuerde
# blindarse: la lista es corta, cerrada y está en el sitio por el que pasan
# todos. Los tests que necesitan una de estas variables la ponen ELLOS en la
# invocación (que es lo correcto y sigue funcionando: un `VAR=x cmd` gana).
unset GATES_SKIP_TESTS GATES_REQUIRE_SEMGREP GATES_REQUIRE_SOURCE_SETS \
      GATES_REQUIRE_MUTATION GATES_SECRET_MODE GATES_BASE_REF \
      AI_REVIEW_REQUIRED AI_REVIEW_OUT \
      REVIEWER_OVERRIDE REVIEWER_OVERRIDE_REASON \
      VERIFY_OVERRIDE VERIFY_OVERRIDE_REASON VERIFY_CMD VERIFY_CONF \
      MUTATION_SCORE_OVERRIDE 2>/dev/null || true

FILTER="${1:-}"
PASS=0; FAIL=0; FAILED_NAMES=()

# ── Watchdog por test (sin depender de `timeout`, que macOS no trae) ──
# Un test que se CUELGA no falla: bloquea la suite y, en CI, el job entero
# hasta el límite del runner. Es peor que un rojo — un rojo te dice qué pasa
# en segundos; un cuelgue no dice nada durante una hora. Cazado en vivo: un
# mutante del guard de reentrada de un ViewModel produjo un deadlock y colgó
# la suite en vez de fallarla.
#
# Se implementa con un perro guardián en segundo plano en vez de con
# `timeout`: el test es una FUNCIÓN de shell, y `timeout` solo sabe ejecutar
# binarios — envolverla en `bash -c` la dejaría fuera de alcance. Además así
# no hay dependencia externa que pueda faltar.
TEST_TIMEOUT_SECS="${TEST_TIMEOUT_SECS:-120}"
_run_test() { # _run_test <nombre-de-función> → imprime salida, devuelve rc (124 = colgado)
  local fn="$1" tmp pid wd rc
  tmp="$(mktemp)"
  # Ambos hijos van con stdout/stderr DESATADOS del pipe del llamador. Sin
  # esto, `out="$( _run_test … )"` esperaría a que el perro guardián cerrara
  # el pipe — o sea, los 120s completos en CADA test. El primer intento colgó
  # la suite entera justo con el mecanismo que existe para evitar cuelgues.
  ( "$fn" >"$tmp" 2>&1 ) >/dev/null 2>&1 & pid=$!
  ( sleep "$TEST_TIMEOUT_SECS"; kill -9 "$pid" 2>/dev/null ) >/dev/null 2>&1 & wd=$!
  wait "$pid" 2>/dev/null; rc=$?
  # ⚠️ `kill "$wd"` mata la SUBSHELL del perro guardián, no a su hijo `sleep`:
  # cada test filtraba un `sleep 120` huérfano (medido: 23 tras 23 tests). En
  # una máquina de desarrollo es basura; en un runner macOS de 3 cores son
  # cientos de slots de proceso ocupados — la presión bajo la que nació el
  # flaky de WF-01. Se mata primero a los HIJOS del guardián y luego a él.
  pkill -P "$wd" -x sleep 2>/dev/null   # -x sleep: si el pid de wd se reciclo, no matamos a un inocente
  kill "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
  if [ "$rc" -ge 128 ]; then
    printf '    ⏱  el test se COLGÓ (>%ss) — no falló, se quedó esperando.\n' "$TEST_TIMEOUT_SECS"
    printf '    Un cuelgue en CI consume el job entero sin decir nada. Busca\n'
    printf '    deadlocks, esperas sin timeout, o algo que pida stdin.\n'
    rm -f "$tmp"; return 124
  fi
  cat "$tmp"; rm -f "$tmp"; return "$rc"
}

# ── Stub de scripts en el sandbox ───────────────────────────────────
# `printf ... > tools/x.sh` sobre un archivo COPIADO hereda su modo y sus
# flags. Eso hizo que la suite fuera verde en Linux y roja en macOS con
# "Permission denied" AL ESCRIBIR el stub: los archivos habían llegado al
# repo por un canal que los dejó en modo 700, y el sandbox los arrastró.
#
# Un test cuyo resultado depende de los PERMISOS del archivo que sobrescribe
# no está probando lo que cree — y falla de forma intermitente entre máquinas,
# que es la peor clase de test. `stub` elimina primero y crea limpio.
#
#   stub <ruta> <contenido-del-script>
stub() {
  local path="$1"; shift
  mkdir -p "$(dirname "$path")" 2>/dev/null
  rm -f "$path"
  # %b (no %s): el contenido llega con \n literales, igual que en los
  # `printf '...\n...'` que este helper sustituye. Con %s los stubs saldrían
  # en una sola línea y "funcionarían" de formas absurdas.
  printf '%b' "$*" > "$path"
  chmod +x "$path" 2>/dev/null
}
export -f stub 2>/dev/null || true

# ── Aserciones disponibles para los tests ───────────────────────────
assert_eq() {
  if [ "$1" = "$2" ]; then return 0; fi
  echo "    esperado: [$1]"; echo "    obtenido: [$2]"; return 1
}
assert_contains() {
  case "$1" in *"$2"*) return 0 ;; esac
  echo "    esperaba encontrar: [$2]"; echo "    en: [$1]"; return 1
}
assert_exit() { # assert_exit <esperado> <comando...>
  local want="$1"; shift
  "$@" >/dev/null 2>&1; local got=$?
  if [ "$got" = "$want" ]; then return 0; fi
  echo "    exit esperado: $want · obtenido: $got · cmd: $*"; return 1
}

# Crea un repo git desechable y ejecuta el cuerpo dentro. Se limpia siempre.
with_temp_repo() { # with_temp_repo <función>
  local d; d="$(mktemp -d)"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null
    git config user.email t@t.t; git config user.name t
    echo init > .keep; git add .keep; git commit -qm init 2>/dev/null
    "$1"
  )
  local rc=$?
  rm -rf "$d"
  return $rc
}
export -f assert_eq assert_contains assert_exit with_temp_repo

# ── Descubrimiento y ejecución ──────────────────────────────────────
for f in "$PROJECT_ROOT"/tools/tests/test_*.sh; do
  [ -f "$f" ] || continue
  BASE="$(basename "$f")"
  # El filtro casa contra el ARCHIVO o contra el NOMBRE de un test. Si casa el
  # archivo, corren todos sus tests; si no, solo los tests cuyo nombre casa.
  FILE_MATCH=0
  if [ -z "$FILTER" ]; then
    FILE_MATCH=1
  else
    case "$BASE" in *"$FILTER"*) FILE_MATCH=1 ;; esac
  fi

  # shellcheck disable=SC1090
  . "$f"
  ALL_TESTS="$(declare -F | awk '{print $3}' | grep '^test_' || true)"

  # ¿Hay algo que correr en este archivo?
  if [ "$FILE_MATCH" -eq 0 ]; then
    HAS=0
    for t in $ALL_TESTS; do case "$t" in *"$FILTER"*) HAS=1 ;; esac; done
    if [ "$HAS" -eq 0 ]; then
      for t in $ALL_TESTS; do unset -f "$t"; done
      continue
    fi
  fi

  echo ""
  echo "━━━ $BASE ━━━"
  for t in $ALL_TESTS; do
    if [ "$FILE_MATCH" -eq 0 ]; then
      case "$t" in *"$FILTER"*) : ;; *) unset -f "$t"; continue ;; esac
    fi
    out="$( _run_test "$t" )"; rc=$?
    if [ $rc -eq 0 ]; then
      PASS=$((PASS+1)); printf '  ✅ %s\n' "$t"
    else
      FAIL=$((FAIL+1)); FAILED_NAMES+=("$BASE::$t"); printf '  ❌ %s\n' "$t"
      [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/     /'
    fi
    unset -f "$t"
  done
done

echo ""
echo "────────────────────────────────────────"
# El conjunto VACÍO no aprueba: "0 tests, 0 fallos, ✅" es un gate mudo con
# disfraz de gate verde — exactamente lo que este harness combate. Si los
# test_*.sh desaparecen (clone parcial, borrado accidental), esto tiene que
# GRITAR, porque canon-enforce CHECK 4 y ci/run-gates.sh paso 1 dependen de
# que esta suite exista. Ausencia de evidencia no es evidencia.
if [ "$PASS" -eq 0 ] && [ "$FAIL" -eq 0 ]; then
  if [ -n "$FILTER" ]; then
    echo "⚠️  0 tests matchearon el filtro '$FILTER' (¿typo?)."
    exit 0
  fi
  echo "❌ 0 tests descubiertos en tools/tests/test_*.sh — la suite del harness"
  echo "   NO EXISTE en esta copia. Un runner que aprueba el conjunto vacío es"
  echo "   un gate mudo. Restaura los tests antes de confiar en ningún gate."
  exit 1
fi
if [ "$FAIL" -eq 0 ]; then
  echo "✅ tests del harness: $PASS pasaron, 0 fallaron."
  exit 0
fi
echo "❌ tests del harness: $PASS pasaron, $FAIL FALLARON:"
for n in "${FAILED_NAMES[@]}"; do echo "   - $n"; done
exit 1

#!/usr/bin/env bash
# Boundary portable para agentes: run (salida opaca) y review (veredicto parseable).
# Exit 124 = timeout; cancelación propaga 128+señal. En ambos casos termina el
# grupo completo del backend para no dejar procesos huérfanos.
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 3

MODE="${1:-}"; [ -n "$MODE" ] && shift || true
BACKEND=claude; PROMPT_FILE=""; CWD="$ROOT"; BASE=""; HEAD_REF=""
TIMEOUT=900; REQUIRE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --backend|--prompt-file|--cwd|--base|--head|--timeout|--require)
      [ $# -ge 2 ] || { echo "agent-runner: falta valor para $1" >&2; exit 3; }
      case "$1" in
        --backend) BACKEND="$2" ;; --prompt-file) PROMPT_FILE="$2" ;; --cwd) CWD="$2" ;;
        --base) BASE="$2" ;; --head) HEAD_REF="$2" ;; --timeout) TIMEOUT="$2" ;;
        --require) REQUIRE="$2" ;;
      esac
      shift 2 ;;
    *) echo "agent-runner: argumento desconocido: $1" >&2; exit 3 ;;
  esac
done
case "$MODE" in run|review|capabilities) ;; *) echo "agent-runner: usa run|review|capabilities" >&2; exit 3 ;; esac
case "$BACKEND" in ''|*[!A-Za-z0-9_-]*) echo "agent-runner: backend inválido" >&2; exit 3 ;; esac
case "$TIMEOUT" in ''|*[!0-9]*|0) echo "agent-runner: timeout inválido" >&2; exit 3 ;; esac
ADAPTER="$ROOT/tools/agent-backends/$BACKEND.sh"
[ -x "$ADAPTER" ] || { echo "agent-runner: backend unsupported: $BACKEND" >&2; exit 3; }

resolve_inside() {
  python3 - "$ROOT" "$1" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1]).resolve(); value=Path(sys.argv[2])
path=(value if value.is_absolute() else root/value).resolve(strict=True)
try: path.relative_to(root)
except ValueError: raise SystemExit(1)
print(path)
PY
}
if [ "$MODE" != capabilities ]; then
  # rc=1 es contrato (ausente/fuera del repo); cualquier otro rc es
  # INFRAESTRUCTURA (python3 no pudo ni correr) y el diagnostico lo dice:
  # un exit 3 mudo o ambiguo se disfraza de flake del watchdog (WF-01).
  PROMPT_ABS="$(resolve_inside "$PROMPT_FILE" 2>/dev/null)"; RES_RC=$?
  [ "$RES_RC" -eq 0 ] || { if [ "$RES_RC" -eq 1 ]; then
      echo "agent-runner: prompt ausente/fuera del repo" >&2; else
      echo "agent-runner: no pude resolver el prompt (python3 rc=$RES_RC)" >&2; fi; exit 3; }
  CWD_ABS="$(resolve_inside "$CWD" 2>/dev/null)"; RES_RC=$?
  [ "$RES_RC" -eq 0 ] || { if [ "$RES_RC" -eq 1 ]; then
      echo "agent-runner: cwd ausente/fuera del repo" >&2; else
      echo "agent-runner: no pude resolver el cwd (python3 rc=$RES_RC)" >&2; fi; exit 3; }
  [ -d "$CWD_ABS" ] || { echo "agent-runner: cwd no es directorio" >&2; exit 3; }
fi

if [ "$MODE" = review ]; then
  for ref in "$BASE" "$HEAD_REF"; do
    [ -n "$ref" ] && [[ "$ref" != -* ]] \
      && git -C "$CWD_ABS" rev-parse --verify "${ref}^{commit}" >/dev/null 2>&1 \
      || { echo "agent-runner: ref review inválida" >&2; exit 3; }
  done
fi

CAPS="$($ADAPTER capabilities 2>/dev/null)" \
  || { echo "agent-runner: backend no declara capacidades" >&2; exit 3; }
cap_true() { case " $CAPS " in *" $1=true "*) return 0 ;; *) return 1 ;; esac; }
case "$MODE" in
  run) MODE_REQUIRE=run ;;
  review) MODE_REQUIRE=review,read_only ;;
  capabilities) MODE_REQUIRE="" ;;
esac
ALL_REQUIRE="$MODE_REQUIRE${MODE_REQUIRE:+${REQUIRE:+,}}$REQUIRE"
for capability in $(printf '%s' "$ALL_REQUIRE" | tr ',' ' '); do
  case "$capability" in run|review|read_only|subagents|hooks) : ;;
    *) echo "agent-runner: capacidad inválida: $capability" >&2; exit 3 ;;
  esac
  cap_true "$capability" \
    || { echo "agent-runner: backend unsupported; requiere $capability ($CAPS)" >&2; exit 3; }
done
[ "$MODE" = capabilities ] && { printf '%s\n' "$CAPS"; exit 0; }

# Python crea una sesión propia para el backend: así TERM/KILL alcanzan al
# adapter y a todos sus descendientes. La gracia termina SIEMPRE en KILL del
# grupo; que el líder haya salido no demuestra que un nieto no ignore TERM.
WATCHDOG_CODE='
import os
import signal
import subprocess
import sys
import time

# El watchdog NO hereda la politica de SIGCHLD del entorno: SIG_IGN
# sobrevive fork+exec (incluso a traves de bash), el kernel auto-reapea y
# waitpid da ECHILD — CPython lo traduce a returncode 0 (subprocess.
# _try_wait): timeout y fallos del backend se volverian "exito". Visto en
# rojo en test_sigchld_ignorado_no_apaga_el_gate. SIG_DFL lo restaura.
signal.signal(signal.SIGCHLD, signal.SIG_DFL)

timeout = int(sys.argv[1])
command = sys.argv[2:]
setsid_delay = os.environ.get("AR_TEST_SETSID_DELAY", "")
try:
    if setsid_delay:
        # SOLO tests: retrasa setsid+exec para simular un backend LENTO EN
        # INSTALARSE (saturacion de CI) sin depender de carga real. Popen
        # espera al exec (errpipe), asi que el reloj del timeout arranca
        # con el backend ya vivo — lo que fija el test de separacion
        # arranque/ejecucion. La carrera "killpg antes de setsid" quedo
        # DESCARTADA por esto mismo: killpg tras Popen siempre ve al grupo.
        delay_seconds = float(setsid_delay)
        def _slow_setsid():
            time.sleep(delay_seconds)
            os.setsid()
        process = subprocess.Popen(command, preexec_fn=_slow_setsid)
    else:
        process = subprocess.Popen(command, start_new_session=True)
except OSError as exc:
    print("agent-runner: no pude iniciar backend: " + str(exc), file=sys.stderr)
    raise SystemExit(3)

cancelled = None

class Cancelled(Exception):
    pass

def sweep_group():
    # El grupo del backend se barre SIEMPRE — exito, fallo, timeout o
    # cancelacion: el lider muerto no arrastra a sus nietos y un runner
    # sincrono no deja procesos detras (visto en rojo en
    # test_run_exitoso_no_deja_nietos_vivos). El pgid persiste mientras el
    # grupo tenga miembros aunque el lider ya este reapeado; vacio, da
    # ProcessLookupError y no hay nada que barrer. killpg es seguro aqui:
    # Popen no devuelve hasta el exec del hijo (errpipe), asi que el grupo
    # ya existia — la carrera "killpg antes de setsid" no es posible.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass

def on_signal(signum, _frame):
    global cancelled
    cancelled = signum
    try:
        os.killpg(process.pid, signum)
    except ProcessLookupError:
        pass
    raise Cancelled()

def stop_group(first_signal):
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, signal.SIG_IGN)
    try:
        os.killpg(process.pid, first_signal)
    except ProcessLookupError:
        pass
    deadline = time.monotonic() + 1.0
    while process.poll() is None and time.monotonic() < deadline:
        time.sleep(0.05)
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        print("agent-runner: el backend sobrevivio a KILL (no reapeado)", file=sys.stderr)
    sweep_group()

for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(sig, on_signal)

try:
    returncode = process.wait(timeout=timeout)
except subprocess.TimeoutExpired:
    stop_group(signal.SIGTERM)
    print("agent-runner: timeout tras " + str(timeout) + "s", file=sys.stderr)
    # 124 SIEMPRE: pase lo que pase en la limpieza, el timeout ES el contrato
    raise SystemExit(124)
except Cancelled:
    stop_group(cancelled)
    raise SystemExit(128 + cancelled)

sweep_group()
if returncode < 0:
    raise SystemExit(128 - returncode)
raise SystemExit(returncode)
'

if [ "$MODE" = run ]; then
  exec python3 -c "$WATCHDOG_CODE" "$TIMEOUT" \
    "$ADAPTER" run "$PROMPT_ABS" "$CWD_ABS"
fi

# Fallos de INFRAESTRUCTURA previos a armar el watchdog salen por 3 y con
# diagnostico: un exit mudo aqui se disfrazaba en CI de "el timeout de
# review no propago 124" (WF-01, run 32214253577 — el run path no tiene
# mktemp y por eso solo flaqueaba review).
OUT="$(mktemp)" && [ -n "$OUT" ] \
  || { echo "agent-runner: mktemp fallo (TMPDIR=${TMPDIR:-/tmp})" >&2; exit 3; }
ERR="$(mktemp)" && [ -n "$ERR" ] \
  || { rm -f "$OUT"; echo "agent-runner: mktemp fallo (TMPDIR=${TMPDIR:-/tmp})" >&2; exit 3; }
trap 'rm -f "$OUT" "$ERR"' EXIT
WATCHDOG_PID=""; FORWARDED_SIGNAL=0
forward_watchdog() { # forward_watchdog <nombre-señal> <número>
  FORWARDED_SIGNAL="$2"
  [ -z "$WATCHDOG_PID" ] || kill -"$1" "$WATCHDOG_PID" 2>/dev/null || true
}
trap 'forward_watchdog INT 2' INT
trap 'forward_watchdog TERM 15' TERM
trap 'forward_watchdog HUP 1' HUP
python3 -c "$WATCHDOG_CODE" "$TIMEOUT" \
  "$ADAPTER" review "$PROMPT_ABS" "$CWD_ABS" "$BASE" "$HEAD_REF" >"$OUT" 2>"$ERR" &
WATCHDOG_PID=$!
[ "$FORWARDED_SIGNAL" = 0 ] || kill -"$FORWARDED_SIGNAL" "$WATCHDOG_PID" 2>/dev/null || true
wait "$WATCHDOG_PID"; RC=$?
if [ "$FORWARDED_SIGNAL" != 0 ]; then
  # `wait` puede ser interrumpido por el trap antes de que Python termine de
  # limpiar su grupo. La segunda espera garantiza proceso terminado y reaped.
  while kill -0 "$WATCHDOG_PID" 2>/dev/null; do wait "$WATCHDOG_PID" 2>/dev/null || true; done
  exit $((128 + FORWARDED_SIGNAL))
fi
trap - INT TERM HUP
cat "$ERR" >&2
[ "$RC" = 0 ] || exit "$RC"
RESULT="$(cat "$OUT")"
printf '%s\n' "$RESULT"
. "$ROOT/scripts/agent-hooks/lib/verdict.sh"
VERDICT="$(verdict_parse "$RESULT")"
FINDINGS="$(verdict_findings "$RESULT")"
SCOPE="$(verdict_scope "$RESULT")"
[ -n "$FINDINGS" ] && [ -n "$SCOPE" ] \
  || { echo "agent-runner: review sin FINDINGS/SCOPE válidos" >&2; exit 1; }
case "$VERDICT:$FINDINGS" in GREEN:0|AMBER:*) exit 0 ;; RED:*) exit 1 ;; GREEN:*) echo "agent-runner: GREEN contradice FINDINGS=$FINDINGS" >&2; exit 1 ;; *) echo "agent-runner: review sin VERDICT válido" >&2; exit 1 ;; esac

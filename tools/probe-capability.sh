#!/usr/bin/env bash
# Probe funcional de una capacidad. Presencia en PATH no implica operación.
# stdout: un objeto JSON. Exit 0 operational · 1 missing/broken · 3 clasificador incapaz.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 3

CAPABILITY="${1:-}"
if ! command -v python3 >/dev/null 2>&1; then
  printf '{"capability":"%s","status":"unknown","detail":"python3 missing"}\n' "${CAPABILITY:-unknown}"
  exit 3
fi

emit() { # emit <status> <detail>
  PROBE_CAPABILITY="${CAPABILITY:-unknown}" PROBE_STATUS="$1" PROBE_DETAIL="$2" \
  PROBE_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)" \
  PROBE_PLATFORM="$(uname -sm 2>/dev/null || echo unknown)" \
  PROBE_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)" python3 - <<'PY'
import json, os
print(json.dumps({
    "capability": os.environ["PROBE_CAPABILITY"],
    "status": os.environ["PROBE_STATUS"],
    "detail": os.environ["PROBE_DETAIL"],
    "commit": os.environ["PROBE_COMMIT"],
    "platform": os.environ["PROBE_PLATFORM"],
    "checked_at": os.environ["PROBE_AT"],
}, ensure_ascii=False, separators=(",", ":")))
PY
}

case "$CAPABILITY" in
  semgrep)
    if ! command -v semgrep >/dev/null 2>&1; then
      emit missing "semgrep no está en PATH"
      exit 1
    fi
    fixture=""
    for fixture in tools/semgrep/fixtures/*-malo.*; do [ -f "$fixture" ] && break; fixture=""; done
    if [ -z "$fixture" ] || [ ! -d tools/semgrep/rules ]; then
      emit unknown "faltan fixture *-malo o rules"
      exit 3
    fi
    out="$(mktemp)"; err="$(mktemp)"; trap 'rm -f "$out" "$err"' EXIT
    timeout_secs="${PROBE_TIMEOUT_SECS:-15}"
    case "$timeout_secs" in ''|*[!0-9]*|0) emit unknown "PROBE_TIMEOUT_SECS inválido"; exit 3 ;; esac
    runner_status="$(python3 - "$fixture" "$out" "$err" "$timeout_secs" <<'PY'
import os, signal, subprocess, sys

fixture, stdout_path, stderr_path, timeout_raw = sys.argv[1:]
command = ["semgrep", "scan", "--config", "tools/semgrep/rules", "--json",
           "--quiet", "--metrics=off", fixture]
env = os.environ.copy()
env["SEMGREP_ENABLE_VERSION_CHECK"] = "0"
try:
    with open(stdout_path, "wb") as stdout, open(stderr_path, "wb") as stderr:
        process = subprocess.Popen(command, stdout=stdout, stderr=stderr, env=env,
                                   start_new_session=True)
        try:
            print(process.wait(timeout=int(timeout_raw)))
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                pass
            # El líder puede salir con TERM mientras un hijo lo ignora. Mata
            # el GRUPO tras la gracia siempre; ProcessLookupError significa
            # que ya no queda nadie, no un fallo del clasificador.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            print("timeout")
except OSError as exc:
    with open(stderr_path, "w", encoding="utf-8") as stderr:
        stderr.write(str(exc))
    print("spawn-error")
PY
)"
    case "$runner_status" in
      timeout) emit broken "timeout tras ${timeout_secs}s"; exit 1 ;;
      spawn-error) emit broken "no pude ejecutar semgrep"; exit 1 ;;
      ''|-) emit unknown "runner del probe devolvió estado inválido"; exit 3 ;;
      -*|*[!0-9-]*)
        case "$runner_status" in -[0-9]*) : ;; *) emit unknown "runner del probe devolvió estado inválido"; exit 3 ;; esac
        ;;
    esac
    if [ ! -s "$out" ]; then
      detail="$(head -3 "$err" 2>/dev/null | tr '\n' ' ' | cut -c1-500)"
      [ -n "$detail" ] || detail="semgrep no produjo salida JSON"
      case "$detail" in
        *X509*trust\ anchors*) detail="X509 trust anchors: almacén CA vacío o no disponible" ;;
      esac
      emit broken "$detail"
      exit 1
    fi
    parsed="$(python3 - "$out" <<'PY' 2>/dev/null
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    results = data.get("results") if isinstance(data, dict) else None
    errors = data.get("errors") if isinstance(data, dict) else None
    if not isinstance(results, list) or not isinstance(errors, list):
        print("invalid")
    elif errors:
        print("errors")
    elif not results:
        print("mute")
    else:
        print("operational")
except Exception:
    print("invalid")
PY
)"
    if [ "$runner_status" != "0" ]; then
      detail="$(head -3 "$err" 2>/dev/null | tr '\n' ' ' | cut -c1-500)"
      [ -n "$detail" ] || detail="semgrep terminó con exit $runner_status pese a producir JSON"
      emit broken "$detail"
      exit 1
    fi
    case "$parsed" in
      operational) emit operational "fixture detectado"; exit 0 ;;
      errors) emit broken "semgrep cargó con errores de reglas/parsing"; exit 1 ;;
      mute) emit broken "semgrep corrió pero no detectó su fixture malo"; exit 1 ;;
      *) emit broken "semgrep produjo salida no parseable"; exit 1 ;;
    esac
    ;;
  *)
    emit unknown "capacidad sin probe registrado"
    exit 3
    ;;
esac

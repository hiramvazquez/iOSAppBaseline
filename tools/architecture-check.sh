#!/usr/bin/env bash
# Clasifica capacidades arquitectónicas; nunca infiere "sin problemas" de ausencia.
# Exit 0 = operational/unsupported explícito · 1 = missing/broken · 3 = no evaluable.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 3

if ! command -v python3 >/dev/null 2>&1; then
  echo 'ARCHITECTURE_SUMMARY operational=0 unsupported=0 missing=0 broken=0'
  exit 3
fi

exec python3 - "$@" <<'PY'
import argparse
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import sys

KNOWN = ("architecture_cycles", "architecture_complexity")


def summary(counts):
    print("ARCHITECTURE_SUMMARY " + " ".join(
        f"{key}={counts[key]}" for key in ("operational", "unsupported", "missing", "broken")
    ))


def incapable(message):
    print(f"⚠️  architecture-check: {message}", file=sys.stderr)
    summary({key: 0 for key in ("operational", "unsupported", "missing", "broken")})
    raise SystemExit(3)


parser = argparse.ArgumentParser(add_help=True)
parser.add_argument("capability", nargs="?", default="all")
parser.add_argument("--config", default=os.environ.get("ARCHITECTURE_CONF", "tools/architecture.conf"))
parser.add_argument("--timeout", type=int, default=10)
try:
    args = parser.parse_args()
except SystemExit as exc:
    if exc.code == 0:
        raise
    incapable("argumentos inválidos")

if args.capability != "all" and args.capability not in KNOWN:
    incapable(f"capacidad desconocida: {args.capability}")
if args.timeout < 1 or args.timeout > 300:
    incapable("timeout fuera de rango (1..300)")

config_path = Path(args.config)
targets = KNOWN if args.capability == "all" else (args.capability,)
if not config_path.is_file():
    counts = {key: 0 for key in ("operational", "unsupported", "missing", "broken")}
    for capability in targets:
        print(json.dumps({"capability": capability, "status": "missing",
                          "detail": f"config ausente: {config_path}"}, separators=(",", ":")))
        counts["missing"] += 1
    summary(counts)
    raise SystemExit(1)

try:
    data = json.loads(config_path.read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError) as exc:
    incapable(f"config no parseable: {exc}")
if not isinstance(data, dict) or data.get("schema") != 1 or not isinstance(data.get("capabilities"), dict):
    incapable("config debe tener schema=1 y capabilities como objeto")

repo = Path.cwd().resolve()
counts = {key: 0 for key in ("operational", "unsupported", "missing", "broken")}


def emit(capability, status, detail):
    print(json.dumps({"capability": capability, "status": status, "detail": detail},
                     ensure_ascii=False, separators=(",", ":")))
    counts[status] += 1


for capability in targets:
    spec = data["capabilities"].get(capability)
    if spec is None:
        emit(capability, "missing", "capacidad no declarada en config")
        continue
    if not isinstance(spec, dict):
        incapable(f"{capability}: spec debe ser objeto")
    if spec.get("status") == "unsupported":
        reason = spec.get("reason")
        if not isinstance(reason, str) or not reason.strip():
            incapable(f"{capability}: unsupported exige reason")
        emit(capability, "unsupported", reason.strip())
        continue
    if "status" in spec:
        incapable(f"{capability}: status solo puede ser unsupported; operational exige probe")
    command = spec.get("adapter")
    if not isinstance(command, list) or not command or not all(isinstance(x, str) and x for x in command):
        incapable(f"{capability}: adapter debe ser un array de argumentos no vacío")
    executable = command[0]
    if "/" in executable:
        candidate = Path(executable)
        candidate = candidate if candidate.is_absolute() else repo / candidate
        try:
            resolved = candidate.resolve(strict=True)
        except OSError:
            emit(capability, "missing", f"adapter ausente: {executable}")
            continue
        try:
            resolved.relative_to(repo)
        except ValueError:
            incapable(f"{capability}: adapter por path debe vivir dentro del repo")
        executable = str(resolved)
    else:
        resolved_name = shutil.which(executable)
        if not resolved_name:
            emit(capability, "missing", f"adapter ausente en PATH: {executable}")
            continue
        executable = resolved_name
    try:
        process = subprocess.Popen([executable, *command[1:]], cwd=repo, text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   start_new_session=True)
        try:
            stdout, stderr = process.communicate(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                pass
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            emit(capability, "broken", f"probe excedió {args.timeout}s")
            continue
    except OSError as exc:
        emit(capability, "broken", f"adapter no ejecutable: {exc}")
        continue
    marker = f"ARCHITECTURE_PROBE capability={capability} status=operational"
    if process.returncode != 0:
        detail = stderr.strip().splitlines()
        emit(capability, "broken", detail[0][:300] if detail else f"probe exit {process.returncode}")
    elif marker not in stdout.splitlines():
        emit(capability, "broken", "probe salió 0 sin marker operacional exacto")
    else:
        emit(capability, "operational", "probe funcional confirmado")

summary(counts)
raise SystemExit(1 if counts["missing"] or counts["broken"] else 0)
PY

#!/usr/bin/env bash
# Caché local de evidencia verde. Primera versión: SOLO Semgrep staged.
# key incluye diff, HEAD, reglas, binario+versión y plataforma; get aplica TTL;
# put escribe por rename atómico. Un fallo de caché siempre degrada a miss.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 3

python3 - "$@" <<'PY'
import hashlib, json, os, platform, subprocess, sys, tempfile, time
from pathlib import Path

SCHEMA = 1
CACHE_DIR = Path(os.environ.get("GATE_CACHE_DIR", ".agents/state/gate-cache/semgrep"))
GREEN_PAYLOAD = "SEMGREP_SUMMARY errors=0 warns=0\n"

def digest(parts):
    h = hashlib.sha256()
    for label, data in parts:
        h.update(label.encode() + b"\0" + len(data).to_bytes(8, "big") + data)
    return h.hexdigest()

def command(*args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=15)
    if result.returncode != 0:
        raise RuntimeError("comando de identidad falló")
    return result.stdout

def key(args):
    if len(args) < 3 or args[0] != "semgrep-staged":
        return 2
    rules, binary = Path(args[1]), Path(args[2])
    if not rules.is_dir() or not binary.is_file():
        return 3
    # Las operaciones ejecutables van antes del snapshot del índice. Un binario
    # hostil/roto puede mutar el repo durante --version; capturar el diff antes
    # produciría una key vieja que parece recién revalidada.
    version = command(str(binary), "--version").strip()
    parts = [
        ("schema", str(SCHEMA).encode()),
        ("gate", b"semgrep-staged"),
        ("binary", binary.read_bytes()),
        ("version", version),
        ("platform", os.environ.get("GATE_CACHE_PLATFORM", platform.platform()).encode()),
        ("scanner", Path("tools/semgrep-scan.sh").read_bytes()),
        ("cache", Path("tools/gate-cache.sh").read_bytes()),
    ]
    for target in sorted(args[3:]):
        parts.append(("target", os.fsencode(target)))
    for path in sorted(p for p in rules.rglob("*") if p.is_file()):
        rel = path.relative_to(rules).as_posix()
        parts.append((f"rule:{rel}", path.read_bytes()))
    # HEAD+diff se leen al final: representan el estado posterior a todas las
    # consultas anteriores y el caller vuelve a calcular la key en el boundary.
    parts.extend([
        ("head", command("git", "rev-parse", "HEAD").strip()),
        ("diff", command("git", "diff", "--cached", "--binary")),
    ])
    print(digest(parts))
    return 0

def now():
    raw = os.environ.get("GATE_CACHE_NOW")
    return int(raw) if raw is not None else int(time.time())

def cache_path(key_value):
    if len(key_value) != 64 or any(c not in "0123456789abcdef" for c in key_value):
        raise ValueError("key inválida")
    return CACHE_DIR / f"{key_value}.json"

def get(args):
    if len(args) != 1:
        return 2
    try:
        ttl = int(os.environ.get("GATE_CACHE_TTL_SECONDS", "300"))
        if ttl < 0:
            return 3
        item = json.loads(cache_path(args[0]).read_text(encoding="utf-8"))
        if item.get("schema") != SCHEMA or item.get("key") != args[0]:
            return 1
        created = item.get("created_at")
        payload = item.get("payload")
        if not isinstance(created, int) or payload != GREEN_PAYLOAD:
            return 1
        current_time = now()
        if current_time - created > ttl or current_time < created:
            return 1
        sys.stdout.write(payload)
        return 0
    except FileNotFoundError:
        return 1
    except (OSError, ValueError, json.JSONDecodeError):
        return 3

def put(args):
    if len(args) != 2:
        return 2
    payload = args[1] + "\n"
    if payload != GREEN_PAYLOAD:
        return 3
    try:
        target = cache_path(args[0])
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        data = json.dumps({"schema": SCHEMA, "key": args[0], "created_at": now(), "payload": payload},
                          ensure_ascii=False, separators=(",", ":")) + "\n"
        fd, temp_name = tempfile.mkstemp(prefix=".tmp-", dir=CACHE_DIR)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temp_name, target)
        finally:
            if os.path.exists(temp_name):
                os.unlink(temp_name)
        return 0
    except (OSError, ValueError):
        return 3

if len(sys.argv) < 2:
    raise SystemExit(2)
op, args = sys.argv[1], sys.argv[2:]
try:
    rc = {"key": key, "get": get, "put": put}[op](args)
except (KeyError, OSError, RuntimeError, subprocess.TimeoutExpired, ValueError):
    rc = 3
raise SystemExit(rc)
PY

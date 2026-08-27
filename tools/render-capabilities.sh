#!/usr/bin/env bash
# Genera y verifica bloques documentales desde tools/capabilities.json.
# No interpreta prosa libre: solo el contenido entre markers exactos.
# Exit: 0 limpio/escrito · 1 drift · 3 manifiesto/entorno no evaluable.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 3

MODE="${1:---check}"
case "$MODE" in
  --render|--check|--write|--install) ;;
  *) echo "uso: $0 [--render|--check|--write|--install]" >&2; exit 3 ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠️  capabilities: python3 ausente — no pude evaluar el manifiesto." >&2
  exit 3
fi

CAPABILITIES_MANIFEST="${CAPABILITIES_MANIFEST:-tools/capabilities.json}" \
CAPABILITIES_MODE="$MODE" python3 - <<'PY'
import json
import os
import pathlib
import stat
import sys
import tempfile

manifest_path = pathlib.Path(os.environ["CAPABILITIES_MANIFEST"])
mode = os.environ["CAPABILITIES_MODE"]
begin = "<!-- BEGIN GENERATED: capabilities -->"
end = "<!-- END GENERATED: capabilities -->"


def mute(message: str) -> None:
    print(f"⚠️  capabilities: {message}", file=sys.stderr)
    raise SystemExit(3)


try:
    raw = json.loads(manifest_path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    mute(f"no pude leer JSON válido en {manifest_path}: {exc}")

if not isinstance(raw, dict) or raw.get("schema") != 1:
    mute("schema ausente o no soportado (esperaba 1)")
capabilities = raw.get("capabilities")
documents = raw.get("documents")
if not isinstance(capabilities, dict) or not capabilities:
    mute("capabilities debe ser un objeto no vacío")
if not isinstance(documents, list) or any(not isinstance(p, str) for p in documents):
    mute("documents debe ser una lista de paths")

rows = []
for capability_id in sorted(capabilities):
    value = capabilities[capability_id]
    if not isinstance(value, dict):
        mute(f"{capability_id}: definición inválida")
    title = value.get("title")
    provider = value.get("provider")
    full = value.get("required_in_full")
    lite = value.get("required_in_lite")
    if not isinstance(title, str) or not title.strip():
        mute(f"{capability_id}: title requerido")
    if not isinstance(provider, str) or not provider.strip():
        mute(f"{capability_id}: provider requerido")
    if not isinstance(full, bool) or not isinstance(lite, bool):
        mute(f"{capability_id}: required_in_full/lite deben ser booleanos")
    shown_provider = "externo" if provider == "external" else f"`{provider}`"
    rows.append(
        f"| `{capability_id}` | {'sí' if full else 'no'} | "
        f"{'sí' if lite else 'no'} | {shown_provider} | {title} |"
    )

rendered = "\n".join([
    "| Capacidad | Requerida en full | Requerida en lite | Proveedor | Garantía |",
    "|---|:---:|:---:|---|---|",
    *rows,
]) + "\n"
summary = (
    f"CAPABILITIES_SUMMARY total={len(rows)} "
    f"required_full={sum(bool(v['required_in_full']) for v in capabilities.values())} "
    f"required_lite={sum(bool(v['required_in_lite']) for v in capabilities.values())}"
)

if mode == "--render":
    print(rendered, end="")
    print(summary)
    raise SystemExit(0)


repo_root = pathlib.Path.cwd().resolve()


def safe_document(value: str) -> pathlib.Path:
    candidate = pathlib.Path(value)
    if candidate.is_absolute() or ".." in candidate.parts or candidate == pathlib.Path("."):
        mute(f"path documental inseguro: {value}")
    try:
        resolved = (repo_root / candidate).resolve(strict=False)
        if os.path.commonpath((str(repo_root), str(resolved))) != str(repo_root):
            mute(f"path documental escapa del repo: {value}")
    except (OSError, ValueError) as exc:
        mute(f"no pude resolver el path documental {value}: {exc}")
    return candidate


def atomic_write(path: pathlib.Path, content: str) -> None:
    tmp_name = None
    try:
        original_mode = stat.S_IMODE(path.stat().st_mode)
        fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
        os.chmod(tmp_name, original_mode)
        os.replace(tmp_name, path)
        tmp_name = None
    except OSError as exc:
        mute(f"no pude escribir {path} atómicamente: {exc}")
    finally:
        if tmp_name and os.path.exists(tmp_name):
            try:
                os.unlink(tmp_name)
            except OSError:
                pass


drift = []
for value in documents:
    path = safe_document(value)
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        mute(f"no pude leer {path}: {exc}")
    begin_count, end_count = text.count(begin), text.count(end)
    if mode == "--install" and begin_count == 0 and end_count == 0:
        separator = "" if text.endswith("\n\n") else ("\n" if text.endswith("\n") else "\n\n")
        atomic_write(path, text + separator + begin + "\n" + rendered + end + "\n")
        continue
    if begin_count != 1 or end_count != 1:
        mute(f"{path}: esperaba exactamente un par de markers")
    before, rest = text.split(begin, 1)
    current, after = rest.split(end, 1)
    expected = "\n" + rendered
    if current != expected:
        drift.append(str(path))
    if mode in ("--write", "--install") and current != expected:
        updated = before + begin + expected + end + after
        atomic_write(path, updated)

if mode == "--check" and drift:
    for path in drift:
        print(f"❌ capabilities: bloque desactualizado: {path}", file=sys.stderr)
    print(summary)
    raise SystemExit(1)

print(summary)
raise SystemExit(0)
PY

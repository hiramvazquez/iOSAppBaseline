#!/usr/bin/env bash
# Verifica el diff completo de una historia contra `scope: |` del frontmatter.
# Exit 0 dentro · 1 paths fuera · 3 contrato/git/filesystem no evaluable.
set -uo pipefail

PYTHON_BIN="${SCOPE_PYTHON_BIN:-$(command -v python3 2>/dev/null || true)}"
GIT_BIN="${SCOPE_GIT_BIN:-$(command -v git 2>/dev/null || true)}"
case "$PYTHON_BIN" in /*) ;; *) echo "SCOPE_SUMMARY changed=0 outside=0"; exit 3 ;; esac
case "$GIT_BIN" in /*) ;; *) echo "SCOPE_SUMMARY changed=0 outside=0"; exit 3 ;; esac
if [ ! -x "$PYTHON_BIN" ] || [ ! -x "$GIT_BIN" ]; then
  echo "SCOPE_SUMMARY changed=0 outside=0"; exit 3
fi
export SCOPE_GIT_BIN="$GIT_BIN"

exec "$PYTHON_BIN" - "$@" <<'PY'
import argparse
import fnmatch
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys


def fail(message: str) -> None:
    print(f"⚠️  scope-check: {message}", file=sys.stderr)
    print("SCOPE_SUMMARY changed=0 outside=0")
    raise SystemExit(3)


parser = argparse.ArgumentParser(add_help=False)
parser.add_argument("--story", required=True)
parser.add_argument("--base", required=True)
parser.add_argument("--head", required=True)
parser.add_argument("--worktree", required=True)
parser.add_argument("--scope-from")
parser.add_argument("--scope-env")
try:
    args = parser.parse_args()
except SystemExit:
    fail("uso: --story PATH --base REF --head REF --worktree DIR")

try:
    worktree = Path(args.worktree).resolve()
except OSError as exc:
    fail(f"no pude resolver worktree: {exc}")
if not worktree.is_dir():
    fail(f"worktree no existe: {args.worktree}")


def git(*parts: str, check: bool = True) -> bytes:
    try:
        result = subprocess.run([os.environ["SCOPE_GIT_BIN"], "-C", str(worktree), *parts],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as exc:
        fail(f"no pude ejecutar git: {exc}")
    if check and result.returncode != 0:
        detail = result.stderr.decode("utf-8", "replace").strip().splitlines()
        fail(detail[0] if detail else f"git {' '.join(parts)} falló")
    return result.stdout


try:
    repo = Path(git("rev-parse", "--show-toplevel").decode().strip()).resolve()
except (OSError, UnicodeError):
    fail("no pude resolver el repositorio")
if repo != worktree:
    fail("--worktree debe ser la raíz exacta del worktree")
def resolve_ref(ref: str) -> str:
    if ref.startswith("-") or any(char in ref for char in "\0\r\n"):
        fail(f"ref insegura: {ref!r}")
    raw = git("rev-parse", "--verify", f"{ref}^{{commit}}")
    try:
        oid = raw.decode("ascii").strip()
    except UnicodeError:
        fail(f"ref no resoluble: {ref}")
    if not re.fullmatch(r"[0-9a-fA-F]{40,64}", oid):
        fail(f"ref no produjo un commit: {ref}")
    return oid


base_oid = resolve_ref(args.base)
head_oid = resolve_ref(args.head)

story_arg = Path(args.story)
try:
    story_rel_path = story_arg.relative_to(worktree) if story_arg.is_absolute() else story_arg
except ValueError:
    fail("story fuera del worktree")
story_pure = PurePosixPath(story_rel_path.as_posix())
if story_pure.is_absolute() or ".." in story_pure.parts or "\\" in story_rel_path.as_posix():
    fail("story fuera del worktree")
story_rel = story_pure.as_posix().removeprefix("./")
scope_path = Path(args.scope_from) if args.scope_from else worktree / story_rel


def parse_scope(lines: list[str]) -> list[str]:
    if not lines or lines[0].strip() != "---":
        fail("story sin frontmatter")
    end = next((i for i, line in enumerate(lines[1:], 1) if line.strip() == "---"), None)
    if end is None:
        fail("frontmatter sin cierre")
    start = next((i for i, line in enumerate(lines[1:end], 1)
                  if re.fullmatch(r"scope:\s*\|\s*(?:#.*)?", line)), None)
    if start is None:
        fail("frontmatter sin `scope: |`")
    patterns: list[str] = []
    for line in lines[start + 1:end]:
        if line and not line[0].isspace():
            break
        value = line.strip()
        if not value or value.startswith("#"):
            continue
        pure = PurePosixPath(value)
        if pure.is_absolute() or ".." in pure.parts or "\\" in value:
            fail(f"patrón inseguro: {value}")
        patterns.append(value.removeprefix("./"))
    if not patterns:
        fail("scope vacío")
    return patterns


if args.scope_env:
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", args.scope_env):
        fail("nombre de variable de scope inválido")
    scope_text = os.environ.get(args.scope_env)
    if scope_text is None:
        fail(f"variable de scope ausente: {args.scope_env}")
    patterns = parse_scope(scope_text.splitlines())
else:
    try:
        scope_lines = scope_path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as exc:
        fail(f"no pude leer story: {exc}")
    patterns = parse_scope(scope_lines)


def parse_name_status(raw: bytes) -> set[str]:
    fields = raw.split(b"\0")
    paths: set[str] = set()
    i = 0
    while i < len(fields) and fields[i]:
        status = fields[i].decode("utf-8", "surrogateescape")
        i += 1
        count = 2 if status.startswith(("R", "C")) else 1
        if i + count > len(fields):
            fail("salida name-status truncada")
        for _ in range(count):
            paths.add(fields[i].decode("utf-8", "surrogateescape"))
            i += 1
    return paths


changed: set[str] = set()
changed |= parse_name_status(git("diff", "--name-status", "-z", f"{base_oid}...{head_oid}"))
changed |= parse_name_status(git("diff", "--cached", "--name-status", "-z"))
changed |= parse_name_status(git("diff", "--name-status", "-z"))
for item in git("ls-files", "--others", "--exclude-standard", "-z").split(b"\0"):
    if item:
        changed.add(item.decode("utf-8", "surrogateescape"))


def safe_path(value: str) -> str:
    pure = PurePosixPath(value)
    if pure.is_absolute() or ".." in pure.parts or "\\" in value:
        fail(f"git devolvió path inseguro: {value}")
    return pure.as_posix()


automatic = {story_rel}


def glob_matches(path: str, pattern: str) -> bool:
    """Git-like glob: `*` stays in one segment; `**` crosses directories."""
    path_parts = path.split("/")
    pattern_parts = pattern.split("/")
    memo: dict[tuple[int, int], bool] = {}

    def visit(pattern_index: int, path_index: int) -> bool:
        key = (pattern_index, path_index)
        if key in memo:
            return memo[key]
        if pattern_index == len(pattern_parts):
            result = path_index == len(path_parts)
        elif pattern_parts[pattern_index] == "**":
            result = visit(pattern_index + 1, path_index) or (
                path_index < len(path_parts) and visit(pattern_index, path_index + 1)
            )
        else:
            result = path_index < len(path_parts) and fnmatch.fnmatchcase(
                path_parts[path_index], pattern_parts[pattern_index]
            ) and visit(pattern_index + 1, path_index + 1)
        memo[key] = result
        return result

    return visit(0, 0)


def matches(path: str) -> bool:
    if path in automatic:
        return True
    for pattern in patterns:
        if pattern.endswith("/**"):
            prefix = pattern[:-3].rstrip("/")
            if path == prefix or path.startswith(prefix + "/"):
                return True
        elif pattern.endswith("/"):
            if path.startswith(pattern):
                return True
        elif glob_matches(path, pattern):
            return True
    return False


normalized = sorted(safe_path(path) for path in changed)
outside = [path for path in normalized if not matches(path)]
print(f"SCOPE_SUMMARY changed={len(normalized)} outside={len(outside)}")
if outside:
    print("❌ scope-check: paths fuera del frontmatter scope:", file=sys.stderr)
    for path in outside:
        print(f"  · {path}", file=sys.stderr)
    raise SystemExit(1)
raise SystemExit(0)
PY

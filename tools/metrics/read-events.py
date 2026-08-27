#!/usr/bin/env python3
"""Normaliza detecciones v1/v2 sin inventar identidad histórica."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any, Iterable


def infer_phase(source: str) -> str:
    if source in {"post-edit-verify", "linter", "typecheck"}:
        return "in-loop"
    if source in {"reviewer", "security-reviewer", "design-reviewer", "process-judge"}:
        return "review"
    if source == "ci":
        return "ci"
    if source == "human-review":
        return "human"
    if source in {"prod", "user-report", "incident"}:
        return "prod"
    return "gate"


def normalize(raw: dict[str, Any]) -> dict[str, Any]:
    source = str(raw.get("source") or "?")
    is_v2 = raw.get("schema") == 2
    normalized = dict(raw)
    normalized.update(
        {
            "schema": 2 if is_v2 else 1,
            # v1 nunca tuvo identidad. `null` es honesto; fabricar una haría
            # que un dato histórico pareciera enlazable al ledger durable.
            "event_id": raw.get("event_id") if is_v2 else None,
            "phase": raw.get("phase") or infer_phase(source),
            "source": source,
            "duration_ms": raw.get("duration_ms") if is_v2 else None,
            "commit": raw.get("commit") if is_v2 else None,
            "triage": raw.get("triage") or "unknown",
            "n": raw.get("n") if isinstance(raw.get("n"), int) and raw["n"] >= 0 else 1,
        }
    )
    return normalized


def read(path: Path) -> Iterable[dict[str, Any]]:
    if not path.exists():
        return
    with path.open(encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            try:
                raw = json.loads(line)
                if not isinstance(raw, dict):
                    raise ValueError("el evento no es un objeto")
            except (json.JSONDecodeError, ValueError) as error:
                print(f"⚠️  evento inválido en {path}:{line_number}: {error}", file=sys.stderr)
                raise ValueError(f"evento inválido en {path}:{line_number}") from error
            yield normalize(raw)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("uso: read-events.py <detections.jsonl>", file=sys.stderr)
        return 2
    try:
        # Valida el stream completo antes de publicar una sola fila: stdout
        # parcial + exit 3 sigue siendo un artefacto consumible por callers
        # descuidados y no cumple el contrato fail-loud de esta evidencia.
        events = list(read(Path(argv[1])))
    except ValueError:
        return 3
    for event in events:
        print(json.dumps(event, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

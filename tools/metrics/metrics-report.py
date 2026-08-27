#!/usr/bin/env python3
"""Métricas honestas: defects desde findings; actividad/coste desde eventos."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import os
import runpy
import sys
from pathlib import Path
from typing import Any, Iterable


PHASE_SOURCES = {
    "in_loop": {"post-edit-verify", "linter", "typecheck"},
    "gate": {"canon-enforce", "check-drift", "check-layers", "semgrep"},
    "review": {"reviewer", "security-reviewer", "design-reviewer", "process-judge"},
    "ci": {"ci"},
    "human": {"human-review"},
    "prod": {"prod", "user-report", "incident"},
}
DECLARED_GATES = (
    "semgrep", "check-layers", "drift-ratchet", "reviewer-gate", "canon-enforce",
    "post-edit-verify", "secret-scan", "check-review-marker", "conflict-markers",
    "mutation-score", "exec-bits", "reviewer", "skill-reminder",
)


def warn(message: str) -> None:
    print(f"⚠️  {message}", file=sys.stderr)


def load_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    if not path.exists():
        return
    with path.open(encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            try:
                item = json.loads(line)
                if not isinstance(item, dict):
                    raise ValueError("la línea no es un objeto")
            except (json.JSONDecodeError, ValueError) as error:
                warn(f"JSONL inválido en {path}:{line_number}: {error}")
                raise ValueError(f"JSONL inválido en {path}:{line_number}") from error
            yield item


def require_readable(path: Path, label: str) -> None:
    if not path.is_file():
        print(f"⚠️  {label} ausente: {path} — no pude medir.", file=sys.stderr)
        raise SystemExit(3)
    try:
        with path.open(encoding="utf-8"):
            pass
    except OSError as error:
        print(f"⚠️  {label} ilegible: {path}: {error}", file=sys.stderr)
        raise SystemExit(3) from error


def parse_day(value: Any) -> dt.date | None:
    parsed = None
    try:
        parsed = dt.date.fromisoformat(str(value))
    except (TypeError, ValueError):
        warn("fecha inválida; se excluye de la métrica")
    return parsed


def parse_timestamp_day(value: Any) -> dt.date | None:
    if not isinstance(value, str) or "T" not in value:
        warn("timestamp inválido; se excluye de la métrica")
        return None
    normalized = value[:-1] + "+00:00" if value.endswith("Z") else value
    timestamp = None
    try:
        timestamp = dt.datetime.fromisoformat(normalized)
    except ValueError:
        warn("timestamp inválido; se excluye de la métrica")
    if timestamp is None:
        return None
    # Los productores v1/v2 emiten instantes RFC 3339. Una fecha o un
    # datetime sin zona no demuestra en qué ventana ocurrió el evento.
    if timestamp.tzinfo is None:
        warn("timestamp inválido; se excluye de la métrica")
        return None
    return timestamp.astimezone(dt.timezone.utc).date()


def parser_for(metric: str) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog=f"{metric}.sh")
    window = parser.add_mutually_exclusive_group()
    window.add_argument("--days", type=int, default=None, help="días inclusivos; default 30")
    window.add_argument("--since", help="inicio inclusivo YYYY-MM-DD")
    parser.add_argument("--until", help="fin inclusivo YYYY-MM-DD; default hoy")
    parser.add_argument("--json", action="store_true")
    return parser


def resolve_window(args: argparse.Namespace, parser: argparse.ArgumentParser) -> tuple[dt.date, dt.date]:
    today_raw = os.environ.get("METRICS_TODAY")
    today = parse_day(today_raw) if today_raw else dt.datetime.now(dt.timezone.utc).date()
    if today is None:
        parser.error("METRICS_TODAY debe ser YYYY-MM-DD")
    until = parse_day(args.until) if args.until else today
    if until is None:
        parser.error("--until debe ser YYYY-MM-DD")
    if args.since:
        since = parse_day(args.since)
        if since is None:
            parser.error("--since debe ser YYYY-MM-DD")
    else:
        days = 30 if args.days is None else args.days
        if days < 1:
            parser.error("--days debe ser mayor que cero")
        since = until - dt.timedelta(days=days - 1)
    if since > until:
        parser.error("--since no puede ser posterior a --until")
    return since, until


def pct(part: int, total: int) -> int | None:
    return (part * 100) // total if total else None


def phase_for_source(raw: Any) -> str | None:
    # findings.sh conserva primero al descubridor original y anexa redetecciones.
    # Solo ese primer token decide: saltar un source original desconocido para
    # tomar una redetección reconocida fabricaría una clasificación tardía.
    source = str(raw or "").split(",", 1)[0].strip()
    for phase, sources in PHASE_SOURCES.items():
        if source in sources:
            return phase
    return None


def escape_rate(argv: list[str]) -> int:
    parser = parser_for("escape-rate")
    args = parser.parse_args(argv)
    since, until = resolve_window(args, parser)
    ledger = Path(os.environ.get("FINDINGS_LEDGER", "tools/findings/ledger.jsonl"))
    require_readable(ledger, "ledger de findings")

    by_id: dict[str, dict[str, Any]] = {}
    invalid_ids = 0
    try:
        for item in load_jsonl(ledger):
            finding_id = item.get("id")
            if not isinstance(finding_id, str) or not finding_id:
                invalid_ids += 1
                continue
            by_id[finding_id] = item
    except ValueError:
        return 3

    counts = {phase: 0 for phase in PHASE_SOURCES}
    unknown = 0
    invalid_dates = 0
    findings_total = 0
    for item in by_id.values():
        created = parse_day(item.get("createdAt"))
        if created is None:
            invalid_dates += 1
            continue
        if not since <= created <= until:
            continue
        findings_total += 1
        phase = phase_for_source(item.get("source"))
        if phase is None:
            unknown += 1
        else:
            counts[phase] += 1

    classified = sum(counts.values())
    escaped = counts["ci"] + counts["human"] + counts["prod"]
    automated = counts["in_loop"] + counts["gate"] + counts["review"]
    report = {
        "schema": 2,
        "window": {"since": since.isoformat(), "until": until.isoformat()},
        "findings_total": findings_total,
        "classified": classified,
        "unknown": unknown,
        "invalid_dates": invalid_dates,
        "invalid_ids": invalid_ids,
        # `total` se conserva para consumidores v1, pero ahora su denominador
        # explícito son solo findings clasificados, nunca eventos ni unknown.
        "total": classified,
        **counts,
        "escaped": escaped,
        "escape_rate_pct": pct(escaped, classified),
        "automated_pct": pct(automated, classified),
    }
    if args.json:
        print(json.dumps(report, ensure_ascii=False, separators=(",", ":")))
        return 0

    print(f"━━━ Contención por finding único · {since}..{until} ━━━")
    print(f"Findings en ventana: {findings_total} · clasificados: {classified} · unknown: {unknown}")
    print("")
    for phase in ("in_loop", "gate", "review", "ci", "human", "prod"):
        value = counts[phase]
        percentage = pct(value, classified)
        label = "n/a" if percentage is None else f"{percentage}%"
        print(f"  {phase.replace('_', '-'):<9} {value:4d}  {label:>4}")
    escape_label = "n/a" if report["escape_rate_pct"] is None else f'{report["escape_rate_pct"]}%'
    print(f"\nESCAPE RATE: {escape_label} ({escaped}/{classified} findings clasificados)")
    if unknown:
        print("⚠️  unknown queda fuera del denominador; imputarlo bajaría la tasa artificialmente.")
    print("Los eventos NO entran aquí: actividad y latencia viven en gate-value.sh.")
    return 0


def percentile_95(values: list[int]) -> int | None:
    if not values:
        return None
    ordered = sorted(values)
    return ordered[max(0, math.ceil(0.95 * len(ordered)) - 1)]


def gate_value(argv: list[str]) -> int:
    parser = parser_for("gate-value")
    args = parser.parse_args(argv)
    since, until = resolve_window(args, parser)
    detections = Path(os.environ.get("DETECTIONS_LOG", ".agents/state/metrics/detections.jsonl"))
    ledger = Path(os.environ.get("FINDINGS_LEDGER", "tools/findings/ledger.jsonl"))
    require_readable(detections, "telemetría de eventos")
    require_readable(ledger, "ledger de findings")

    linked_ids: set[str] = set()
    try:
        for finding in load_jsonl(ledger):
            events = finding.get("source_event_ids")
            if isinstance(events, list):
                linked_ids.update(value for value in events if isinstance(value, str) and value)
    except ValueError:
        return 3

    reader_api = runpy.run_path(str(Path(__file__).with_name("read-events.py")))
    read_events = reader_api["read"]
    unique_v2: set[str] = set()
    selected: list[dict[str, Any]] = []
    invalid_dates = 0
    duplicate_ids = 0
    try:
        for event in read_events(detections):
            day = parse_timestamp_day(event.get("ts"))
            if day is None:
                invalid_dates += 1
                continue
            if not since <= day <= until:
                continue
            event_id = event.get("event_id")
            if isinstance(event_id, str) and event_id:
                if event_id in unique_v2:
                    duplicate_ids += 1
                    continue
                unique_v2.add(event_id)
            selected.append(event)
    except ValueError:
        return 3

    def blank() -> dict[str, Any]:
        return {"events": 0, "detections": 0, "promoted": 0, "untriaged": 0, "durations": []}

    gates: dict[str, dict[str, Any]] = {}
    legacy_events = 0
    missing_identity = 0
    promoted_events = 0
    all_durations: list[int] = []
    detections_total = 0
    for event in selected:
        source = str(event.get("source") or "?")
        gate = gates.setdefault(source, blank())
        n = event.get("n")
        n = n if isinstance(n, int) and not isinstance(n, bool) and n >= 0 else 1
        gate["events"] += 1
        gate["detections"] += n
        detections_total += n
        event_id = event.get("event_id")
        promoted = isinstance(event_id, str) and bool(event_id) and event_id in linked_ids
        if promoted:
            gate["promoted"] += 1
            promoted_events += 1
        else:
            gate["untriaged"] += 1
        if event.get("schema") == 1:
            legacy_events += 1
        elif not isinstance(event_id, str) or not event_id:
            missing_identity += 1
        duration = event.get("duration_ms")
        if isinstance(duration, int) and not isinstance(duration, bool) and duration >= 0:
            gate["durations"].append(duration)
            all_durations.append(duration)

    gate_reports: dict[str, dict[str, Any]] = {}
    for source, gate in sorted(gates.items()):
        durations = gate.pop("durations")
        gate_reports[source] = {
            **gate,
            "latency_samples": len(durations),
            "latency_coverage_pct": pct(len(durations), gate["events"]),
            "avg_duration_ms": sum(durations) // len(durations) if durations else None,
            "p95_duration_ms": percentile_95(durations),
        }

    events_total = len(selected)
    report = {
        "schema": 2,
        "window": {"since": since.isoformat(), "until": until.isoformat()},
        "events_total": events_total,
        "detections_total": detections_total,
        "legacy_events": legacy_events,
        "missing_identity": missing_identity,
        "duplicate_event_ids": duplicate_ids,
        "invalid_dates": invalid_dates,
        "promoted_events": promoted_events,
        "untriaged_events": events_total - promoted_events,
        # No existe un estado durable de falso positivo. `untriaged` NO es FP.
        "false_positives": None,
        "fp_rate_pct": None,
        "latency_samples": len(all_durations),
        "latency_coverage_pct": pct(len(all_durations), events_total),
        "avg_duration_ms": sum(all_durations) // len(all_durations) if all_durations else None,
        "p95_duration_ms": percentile_95(all_durations),
        "gates": gate_reports,
    }
    if args.json:
        print(json.dumps(report, ensure_ascii=False, separators=(",", ":")))
        return 0

    print(f"━━━ Valor por gate · eventos {since}..{until} ━━━\n")
    print(
        f"Eventos: {events_total} · detecciones agrupadas: {detections_total} · "
        f"promovidos: {promoted_events} · untriaged: {events_total - promoted_events}"
    )
    print("FP rate: n/a — un evento no promovido sigue unknown; no se finge false-positive.\n")
    print(f"  {'GATE':<22} {'EVENTOS':>7} {'N':>7} {'PROM':>6} {'UNK':>6} {'AVG MS':>8} {'P95 MS':>8}")
    sources = list(DECLARED_GATES) + sorted(set(gate_reports) - set(DECLARED_GATES))
    for source in sources:
        gate = gate_reports.get(source)
        if gate is None:
            print(f"  {source:<22} {0:>7} {0:>7} {0:>6} {0:>6} {'n/a':>8} {'n/a':>8}")
            continue
        avg = gate["avg_duration_ms"] if gate["avg_duration_ms"] is not None else "n/a"
        p95 = gate["p95_duration_ms"] if gate["p95_duration_ms"] is not None else "n/a"
        print(
            f"  {source:<22} {gate['events']:>7} {gate['detections']:>7} "
            f"{gate['promoted']:>6} {gate['untriaged']:>6} {str(avg):>8} {str(p95):>8}"
        )
    coverage = report["latency_coverage_pct"]
    print(f"\nCobertura de latencia: {'n/a' if coverage is None else str(coverage) + '%'}")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] not in {"escape-rate", "gate-value"}:
        print("uso: metrics-report.py escape-rate|gate-value [opciones]", file=sys.stderr)
        return 2
    return escape_rate(argv[2:]) if argv[1] == "escape-rate" else gate_value(argv[2:])


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

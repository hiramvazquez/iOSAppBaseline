#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# findings.sh — CLI PORTABLE del Findings Ledger (bash + python3)
# ════════════════════════════════════════════════════════════════════
# Equivalente operativo de findings.ts para máquinas SIN Deno/Node. Ese fue
# el fallo real: el ledger exigía un runtime que no estaba, así que era
# inoperable — 9 findings esperaron días en un pending-import.json porque
# "la herramienta oficial no corre aquí". Un inventario al que no se puede
# escribir no es un inventario.
#
# Mismo JSONL, mismos campos y MISMO INVARIANTE que findings.ts:
#   add/import (detección) NUNCA resucitan un estado terminal
#   (fixed/accepted/wontfix/duplicate); solo refrescan updatedAt.
#   Cerrar es explícito (close/accept).
#
#   bash tools/findings/findings.sh add --title T --area A [--id I] [--severity s]
#        [--tier t] [--source s] [--source-event EVENT_ID] [--detail d]
#        [--effort e] [--links a,b]
#   bash tools/findings/findings.sh close ID --resolution "..."
#   bash tools/findings/findings.sh accept ID --reason "..."
#   bash tools/findings/findings.sh import batch.json
#   bash tools/findings/findings.sh list [--status open] [--json]
#   bash tools/findings/findings.sh render
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ findings.sh necesita python3 (o usa findings.ts con Deno/Node)." >&2
  exit 1
fi

# Todo el trabajo lo hace python3 (JSON de verdad, no sed sobre JSON).
exec python3 - "$@" <<'PYEOF'
import json, sys, os, datetime

LEDGER = "tools/findings/ledger.jsonl"
VIEW   = "docs/process/findings-ledger.md"
TERMINAL = {"fixed", "accepted", "wontfix", "duplicate"}
# UTC, no local. La telemetría sella sus eventos con `date -u`
# (scripts/agent-hooks/lib/io.sh) y la ventana de las métricas se calcula con
# `datetime.now(timezone.utc)` (tools/metrics/metrics-report.py). Con
# `date.today()` las DOS fuentes de la misma métrica corrían con relojes
# distintos y el mismo instante caía en días distintos: al oeste de UTC, un
# finding creado por la tarde quedaba sellado con el día UTC anterior y
# desaparecía de su propia ventana. CI corre en UTC, así que nunca lo veía —
# verde en CI y rojo en la máquina del adoptante unas horas cada día.
# Medido en un adoptante real (UTC-6, 18:09 local = 00:09Z del día siguiente):
# `escape-rate --days 1` devolvía findings_total=0 con el finding recién creado.
today = datetime.datetime.now(datetime.timezone.utc).date().isoformat()

def load():
    if not os.path.exists(LEDGER): return []
    with open(LEDGER, encoding="utf-8") as f:
        return [json.loads(l) for l in f if l.strip()]

def save(items):
    os.makedirs(os.path.dirname(LEDGER), exist_ok=True)
    # separators SIN espacios: el mismo byte-formato que JSON.stringify emitía.
    # Con el default de json.dumps ('"status": "open"', CON espacio) los greps
    # de los hooks ('"status":"open"') contaban 0 abiertos SIEMPRE, en silencio.
    # Los hooks ya son tolerantes a ambos ('"status": ?"open"'), pero dos
    # emisores del mismo formato deben ser byte-idénticos (L-json-espacios).
    with open(LEDGER, "w", encoding="utf-8") as f:
        for i in items:
            f.write(json.dumps(i, ensure_ascii=False, separators=(",", ":")) + "\n")

def fhash(s):
    # Mismo hash que findings.ts (h*31+ord, int32, unsigned hex) para que los
    # ids generados por ambos CLIs coincidan sobre el mismo título+área.
    h = 0
    for c in s:
        h = (h * 31 + ord(c)) & 0xFFFFFFFF
        if h >= 0x80000000: h -= 0x100000000
        h &= 0xFFFFFFFF
    return "f-" + format(h & 0xFFFFFFFF, "x")

def upsert(items, f):
    fid = f.get("id") or fhash((f.get("area") or "") + (f.get("title") or ""))
    incoming_events = unique_strings(f.get("source_event_ids") or [])
    for ex in items:
        if ex["id"] == fid:
            ex["updatedAt"] = today
            src = f.get("source") or ""
            if src and src not in ex.get("source", ""):
                ex["source"] = f"{ex.get('source','')}, {src}".strip(", ")
            if ex.get("status") not in TERMINAL:
                # No-terminal: refresca campos informativos (y estado si viene).
                for k in ("detail", "severity", "tier", "status", "resolution", "effort"):
                    if f.get(k) is not None: ex[k] = f[k]
            if incoming_events:
                ex["source_event_ids"] = unique_strings(
                    (ex.get("source_event_ids") or []) + incoming_events
                )
            # TERMINAL: no se resucita. Solo metadatos/source_event_ids arriba.
            return items
    items.append({
        "id": fid, "title": f.get("title") or "(sin título)", "area": f.get("area") or "?",
        "severity": f.get("severity") or "medium", "tier": f.get("tier"),
        "status": f.get("status") or "open", "source": f.get("source") or "manual",
        "detail": f.get("detail") or "", "effort": f.get("effort"),
        "resolution": f.get("resolution"), "links": f.get("links") or [],
        "source_event_ids": incoming_events,
        "createdAt": f.get("createdAt") or today, "updatedAt": today,
    })
    return items

def render(items):
    open_ = [i for i in items if i["status"] not in TERMINAL]
    closed = [i for i in items if i["status"] in TERMINAL]
    lines = [
        "# Findings Ledger — vista humana",
        "",
        "> **GENERADA — NO editar a mano.** Fuente: `tools/findings/ledger.jsonl`.",
        "> Regenerar: `bash tools/findings/findings.sh render`.",
        "",
        f"Abiertos: **{len(open_)}** · Cerrados: {len(closed)} · Total: {len(items)}",
        "",
        "## Abiertos",
        "",
        "| id | sev | tier | área | título |",
        "|---|---|---|---|---|",
    ]
    for i in sorted(open_, key=lambda x: ({"high":0,"medium":1,"low":2,"info":3}.get(x["severity"],9), x["id"])):
        lines.append(f"| `{i['id']}` | {i['severity']} | {i.get('tier') or '—'} | `{i['area']}` | {i['title']} |")
    if not open_: lines.append("| — | | | | (ninguno) |")
    lines += ["", "## Cerrados", "", "| id | estado | resolución |", "|---|---|---|"]
    for i in closed:
        res = (i.get("resolution") or "")[:100]
        lines.append(f"| `{i['id']}` | {i['status']} | {res} |")
    os.makedirs(os.path.dirname(VIEW), exist_ok=True)
    with open(VIEW, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"✅ render → {VIEW} ({len(items)} hallazgos, {len(open_)} abiertos)")

def flag(rest, name):
    try:
        i = rest.index(f"--{name}"); return rest[i + 1]
    except (ValueError, IndexError):
        return None

def flags(rest, name):
    values = []
    needle = f"--{name}"
    for i, value in enumerate(rest):
        if value == needle and i + 1 < len(rest) and not rest[i + 1].startswith("--"):
            values.append(rest[i + 1])
    return values

def require_flag_values(rest, name):
    needle = f"--{name}"
    for i, value in enumerate(rest):
        if value == needle and (
            i + 1 >= len(rest) or not rest[i + 1] or rest[i + 1].startswith("--")
        ):
            print(f"❌ {needle} requiere un valor.", file=sys.stderr)
            sys.exit(2)

def unique_strings(values):
    result = []
    for value in values:
        if isinstance(value, str) and value and value not in result:
            result.append(value)
    return result

USAGE = """findings.sh — CLI portable del ledger (mismo esquema que findings.ts):
  add --title T --area A [--id I] [--severity high|medium|low] [--tier auto-fix|owner-decision]
      [--source S] [--source-event EVENT_ID] [--detail D] [--effort S|M|L] [--links a,b]
  update ID [--title T] [--area A] [--severity S] [--detail D] [--tier T] [--links a,b]
  close ID --resolution "..."      accept ID --reason "..."
  drop ID --reason "..."           (retira una entrada que NUNCA fue un hallazgo)
  import batch.json [--source-event EVENT_ID]   list [--status open] [--tier T] [--json]
  render"""

args = sys.argv[1:]
cmd = args[0] if args else ""
rest = args[1:]

# --help NUNCA ejecuta nada. Antes, `add --help` interpretaba "--help" como
# flags de un alta y escribía un hallazgo BASURA con title="(sin título)":
# pedirle ayuda al CLI ENSUCIABA la fuente de accountability del proyecto.
# Es fail-open en su peor forma — el daño lo hace la operación que el humano
# creía inofensiva. Cortocircuita antes del dispatch, siempre.
if not cmd or cmd in ("-h", "--help", "help") or "--help" in rest or "-h" in rest:
    print(USAGE); sys.exit(0)

items = load()

if cmd == "add":
    require_flag_values(rest, "source-event")
    # Un `add` sin lo mínimo indispensable FALLA en vez de inventar defaults.
    # Un ledger es accountability: una entrada con área "?" y sin título no
    # es un hallazgo, es ruido que alguien tendrá que limpiar a mano.
    if not flag(rest, "title") or not flag(rest, "area"):
        print("❌ add requiere --title y --area (un hallazgo sin título ni área no es un hallazgo).",
              file=sys.stderr)
        print(USAGE, file=sys.stderr); sys.exit(2)
    _id = flag(rest, "id")
    if _id and any(i["id"] == _id for i in items):
        # `add` con un id existente conservaba el title viejo, así que
        # corregir un título fallaba EN SILENCIO: el humano acababa editando
        # el .jsonl a mano — justo lo que un archivo generado no debería
        # necesitar. Ahora se dice, y se apunta al comando correcto.
        print(f"❌ ya existe un hallazgo con id '{_id}'. Para modificarlo:", file=sys.stderr)
        print(f"   bash tools/findings/findings.sh update {_id} --title \"...\"", file=sys.stderr)
        sys.exit(2)
    items = upsert(items, {k: flag(rest, k) for k in
        ("id","title","area","severity","tier","source","detail","effort","status")} |
        ({"links": flag(rest,"links").split(",")} if flag(rest,"links") else {}) |
        {"source_event_ids": flags(rest, "source-event")})
    save(items); render(items)
elif cmd == "update":
    if not rest or rest[0].startswith("--"):
        print("❌ update requiere el ID del hallazgo.", file=sys.stderr); sys.exit(2)
    target = rest[0]
    hit = next((i for i in items if i["id"] == target), None)
    if hit is None:
        print(f"❌ no existe ningún hallazgo con id '{target}'.", file=sys.stderr); sys.exit(2)
    changed = []
    for k in ("title","area","severity","tier","source","detail","effort","status","resolution"):
        v = flag(rest[1:], k)
        if v is not None:
            hit[k] = v; changed.append(k)
    if flag(rest[1:], "links"):
        hit["links"] = flag(rest[1:], "links").split(","); changed.append("links")
    if not changed:
        print("❌ update sin campos que cambiar (usa --title, --area, --detail, ...).",
              file=sys.stderr); sys.exit(2)
    hit["updatedAt"] = today
    save(items); render(items)
    print(f"✅ {target} actualizado: {', '.join(changed)}")
elif cmd == "drop":
    # Retirada limpia de una entrada que NUNCA fue un hallazgo (p.ej. la que
    # creaba `add --help`). No es lo mismo que `close`: cerrar afirma que
    # hubo un problema y se resolvió. Esto afirma que no lo hubo.
    if not rest or rest[0].startswith("--"):
        print("❌ drop requiere el ID a retirar.", file=sys.stderr); sys.exit(2)
    if not flag(rest[1:], "reason"):
        print("❌ drop requiere --reason: retirar del ledger sin explicar por qué es",
              file=sys.stderr)
        print("   exactamente como borrar evidencia. Queda en el historial de git.",
              file=sys.stderr); sys.exit(2)
    before = len(items)
    items = [i for i in items if i["id"] != rest[0]]
    if len(items) == before:
        print(f"❌ no existe ningún hallazgo con id '{rest[0]}'.", file=sys.stderr); sys.exit(2)
    save(items); render(items)
    print(f"✅ {rest[0]} retirado del ledger — {flag(rest[1:], 'reason')}")
elif cmd == "import":
    if not rest or rest[0].startswith("--"):
        print("❌ import requiere el archivo JSON del batch.", file=sys.stderr); sys.exit(2)
    require_flag_values(rest[1:], "source-event")
    with open(rest[0], encoding="utf-8") as f: batch = json.load(f)
    cli_events = flags(rest[1:], "source-event")
    for b in batch:
        promoted = dict(b)
        promoted["source_event_ids"] = unique_strings(
            (b.get("source_event_ids") or []) + cli_events
        )
        items = upsert(items, promoted)
    save(items); render(items)
elif cmd == "close":
    for i in items:
        if i["id"] == rest[0]:
            i["status"] = "fixed"; i["resolution"] = flag(rest,"resolution") or "fixed"; i["updatedAt"] = today
    save(items); render(items)
elif cmd == "accept":
    for i in items:
        if i["id"] == rest[0]:
            i["status"] = "accepted"; i["tier"] = "accepted"
            i["resolution"] = flag(rest,"reason") or "aceptado"; i["updatedAt"] = today
    save(items); render(items)
elif cmd == "list":
    r = items
    if flag(rest,"status") == "open": r = [i for i in r if i["status"] not in TERMINAL]
    elif flag(rest,"status"): r = [i for i in r if i["status"] == flag(rest,"status")]
    if flag(rest,"tier"): r = [i for i in r if i.get("tier") == flag(rest,"tier")]
    if "--json" in rest: print(json.dumps(r, ensure_ascii=False, indent=2))
    else:
        for i in r: print(f"{i['id']} [{i['status']}/{i['severity']}] {i['title']}")
elif cmd == "render":
    render(items)
else:
    print(f"❌ comando desconocido: '{cmd}'", file=sys.stderr)
    print(USAGE, file=sys.stderr); sys.exit(2)
PYEOF

#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-finding-refs.sh — un id de finding citado tiene que EXISTIR
# ════════════════════════════════════════════════════════════════════
# El ledger es el inventario único de hallazgos (§10) y la doc lo cita por id:
# "cerrado en `f-marker-spoof`", "ver `f-range-failopen`". Esa cita es el único
# puente entre la prosa y el estado terminal — y hasta hoy nadie la comprobaba.
#
# Un id fantasma es peor que una cita ausente, y por un motivo concreto: LEE
# COMO CERRADO. Quien encuentra "decidido en `f-xxxxxxx`" no vuelve a abrir el
# tema; da por hecho que hay una entrada con su tier, su razón y su fecha. Si esa
# entrada no existe, el hallazgo se evaporó **con el aspecto de haberse cerrado**,
# que es exactamente el modo de fallo que el ledger existe para impedir. Y se
# produce solo: basta un typo, un id inventado de memoria tras una compactación,
# o renombrar una entrada sin repasar quién la citaba.
#
#   bash tools/check-finding-refs.sh
#
# Contrato de salida:  FINDING_REFS citas=<N> fantasma=<M>
# Exit: 0 todas las citas resuelven · 1 hay ids fantasma · 3 no pude mirar
#
# ── Qué cuenta como CITA (y por qué tan estrecho) ──────────────────
# Solo un span de código en línea: `f-algo`. NO el texto suelto, y NO lo que
# viva dentro de un bloque ``` (ahí están los ejemplos de uso del CLI, con sus
# `f-xxxx` de mentira).
#
# La primera versión de este check buscaba `f-[a-z0-9-]+` en el texto crudo, y
# su primer falso positivo salió —cómo no— contra este mismo repo: casó
# `f-nature` dentro de `check-diff-nature`. La subcadena de un nombre que
# HABLA de otra cosa. Es la cuarta vez que este harness tropieza con la misma
# ley y ya está escrita en `lessons_learned.md`:
#
#   **si un detector puede dispararse con el texto que HABLA de la cosa, no
#     está mirando la cosa.**
#
# Los acentos graves son la marca que el autor pone deliberadamente para decir
# "esto es un identificador". Exigirlos convierte una heurística en una lectura.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

LEDGER="${FINDINGS_LEDGER:-tools/findings/ledger.jsonl}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠️  check-finding-refs: python3 ausente — NO he podido mirar." >&2
  echo "FINDING_REFS citas=0 fantasma=0"
  exit 3
fi

if [ ! -f "$LEDGER" ]; then
  # Sin ledger no hay contra qué resolver. Es un 3 (no pude mirar), no un 0:
  # un repo recién adoptado sin ledger no debe leerse como "todas las citas
  # resuelven" — leería como verde justo el caso en que no hay nada que mirar.
  echo "⚠️  check-finding-refs: no existe $LEDGER — nada contra qué resolver." >&2
  echo "FINDING_REFS citas=0 fantasma=0"
  exit 3
fi

CFR_LEDGER="$LEDGER" python3 - <<'PY'
import json, os, re, sys

ledger = os.environ["CFR_LEDGER"]

ids = set()
malas = 0
with open(ledger, encoding="utf-8") as f:
    for n, linea in enumerate(f, 1):
        linea = linea.strip()
        if not linea:
            continue
        try:
            d = json.loads(linea)
        except json.JSONDecodeError:
            malas += 1
            continue
        if isinstance(d, dict) and d.get("id"):
            ids.add(str(d["id"]))

if malas:
    # Un ledger con líneas rotas haría este check MENTIR hacia el rojo (ids
    # reales que parecen fantasma). Se para y se dice, en vez de acusar.
    print(f"⚠️  check-finding-refs: {malas} línea(s) del ledger no son JSON — arréglalas primero.",
          file=sys.stderr)
    print("FINDING_REFS citas=0 fantasma=0")
    sys.exit(3)

# Un span de código en línea cuyo contenido ENTERO es un id.
CITA = re.compile(r'`(f-[0-9a-z][0-9a-z-]*)`')
# Un placeholder no es un id: `f-xxxx` en un ejemplo de uso no cita nada.
PLACEHOLDER = re.compile(r'^f-[xn?]+$')

def sin_bloques(texto):
    """Quita los bloques ``` — dentro viven los ejemplos del CLI."""
    fuera, dentro = [], False
    for l in texto.splitlines():
        if l.lstrip().startswith("```"):
            dentro = not dentro
            continue
        if not dentro:
            fuera.append(l)
    return "\n".join(fuera)

archivos = []
for raiz, dirs, files in os.walk("."):
    dirs[:] = [d for d in dirs if d not in (".git", "node_modules", ".build")]
    for fn in files:
        if fn.endswith(".md"):
            archivos.append(os.path.join(raiz, fn).lstrip("./"))
archivos.sort()

total, fantasma = 0, []
for ruta in archivos:
    try:
        with open(ruta, encoding="utf-8") as f:
            cuerpo = sin_bloques(f.read())
    except (OSError, UnicodeDecodeError):
        continue
    for n, linea in enumerate(cuerpo.splitlines(), 1):
        for fid in CITA.findall(linea):
            if PLACEHOLDER.match(fid):
                continue
            total += 1
            if fid not in ids:
                fantasma.append((ruta, fid))

print(f"FINDING_REFS citas={total} fantasma={len(fantasma)}")

if fantasma:
    print("")
    print(f"❌ {len(fantasma)} cita(s) a findings que NO existen en {ledger}:")
    for ruta, fid in fantasma:
        print(f"  - {ruta}: `{fid}`")
    print("")
    print("Un id fantasma LEE COMO CERRADO: quien lo encuentra da por hecho que hay")
    print("una entrada con su tier y su razón, y no vuelve a abrir el tema. El")
    print("hallazgo se evaporó con el aspecto de haberse cerrado — justo lo que el")
    print("ledger existe para impedir (AGENTS.md §10).")
    print("")
    print("Arréglalo en el MISMO cambio, de una de las dos formas:")
    print("  · el hallazgo es real  → créalo:")
    print("      bash tools/findings/findings.sh add --title \"...\" --area \"...\" \\")
    print("           --severity high|medium|low --tier auto-fix|owner-decision")
    print("  · la cita está mal     → corrige el id (o quita los acentos graves si")
    print("    de verdad no estabas citando un finding).")
    sys.exit(1)

print(f"✅ check-finding-refs: las {total} citas a findings resuelven contra el ledger.")
PY

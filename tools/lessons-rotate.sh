#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# lessons-rotate.sh — una lección MECANIZADA ya no necesita leerse
# ════════════════════════════════════════════════════════════════════
# EL COROLARIO QUE FALTABA. El harness afirma: "error cometido → lección →
# detector → error mecánicamente imposible". Si eso es cierto, entonces una
# lección cuyo detector está VERIFICADO EN CI ya no depende de que nadie la
# recuerde: su cumplimiento está garantizado por una máquina. Seguir
# obligando a leerla es cobrar dos veces por el mismo seguro.
#
# El problema que resuelve es real y crece solo: `lessons_learned.md` no
# tiene mecanismo de caducidad, así que crece monótonamente y CADA proyecto
# nacido del template hereda el archivo entero. Cada sesión de cada agente
# paga ese peaje de contexto — y el propio AGENTS.md advierte contra el
# monolito mientras este archivo camina hacia serlo.
#
# CRITERIO DE ARCHIVO (deliberadamente conservador — archivar de más sería
# perder la lección de verdad):
#   ARCHIVABLE  · su `Detector:` cita al menos un `tools/tests/test_*.sh`
#                 que EXISTE. Esa suite corre entera en el Anillo 3, así que
#                 la regla está mecánicamente garantizada, no recordada.
#   SE QUEDA    · `n/a-manual` (juicio no mecanizable: la prosa ES el
#                 mecanismo) · detector que solo cita docs o un script sin
#                 test propio (garantía parcial) · lección marcada a mano
#                 con `<!-- KEEP-VISIBLE: razón -->` (veto del owner).
#
# Nada se borra JAMÁS: se mueve a `docs/process/lessons_archive.md`, que
# sigue versionado, sigue siendo grep-able y sigue verificado por
# `lesson-detector-link.sh`. Lo que cambia es qué se lee por defecto.
#
#   bash tools/lessons-rotate.sh            # informe: qué archivarías y por qué
#   bash tools/lessons-rotate.sh --apply    # mueve las ARCHIVABLE al archivo
#
# Contrato de stdout:  ROTATE_SUMMARY vivas=<N> archivables=<M>
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

DOC="${LESSONS_DOC:-docs/process/lessons_learned.md}"
ARCHIVE="${LESSONS_ARCHIVE:-docs/process/lessons_archive.md}"
MODE="${1:---report}"
[ -f "$DOC" ] || { echo "ROTATE_SUMMARY vivas=0 archivables=0"; exit 0; }

python3 - "$DOC" "$ARCHIVE" "$MODE" <<'PY'
import os, re, sys

doc, archive, mode = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(doc, encoding="utf-8").read()

INDEX_BLOCK = re.compile(
    r"(?ms)^---\n\n## Lecciones mecanizadas \(índice\)\n.*?"
    r"(?=^### \[\d{4}-\d{2}-\d{2}\]|\Z)"
)

# ── Forma canónica (PRD 0005, fase 0c) ──────────────────────────────
# Un `---` al FINAL de una entrada es un separador visual generado, no
# contenido. El ciclo real «insertar lección antes del índice → rotar»
# sedimentaba uno huérfano por tanda archivada: la entrada superviviente
# conservaba su cola de separadores y INDEX_HEAD añadía el suyo, hasta clavar
# el contexto vivo exactamente en su cap de 250 líneas. El recorte va desde el
# final y SOLO desde el final: un `---` interior — p. ej. front-matter dentro
# de un bloque de código ``` — es CONTENIDO y sobrevive, porque el recorte se
# detiene en la primera línea real desde la cola (un fence cerrado termina en
# ```, no en ---). El único separador que el lector ve antes del índice lo
# pone INDEX_HEAD al escribir: así N pasadas convergen a los mismos bytes,
# venga el input con sedimento o limpio.
def canonical(entry):
    lines = entry.strip().splitlines()
    while lines and lines[-1].strip() in ("", "---"):
        lines.pop()
    return "\n".join(lines)

def without_indexes(text):
    # Las lecciones nuevas se agregan al final del doc, que puede quedar
    # DESPUÉS de un índice de una rotación anterior. El índice es una vista
    # generada: se elimina antes de clasificar y se reconstruye completo.
    return INDEX_BLOCK.sub("", text)

def split_document(text):
    # El cuerpo empieza en la primera entrada real; todo lo anterior (cómo
    # usar, plantilla) es cabecera y no se toca.
    entries, head = [], text
    m = re.search(r"^### \[\d{4}-\d{2}-\d{2}\]", text, re.M)
    if m:
        head, body = text[:m.start()], text[m.start():]
        parts = re.split(r"(?m)^(?=### \[\d{4}-\d{2}-\d{2}\])", body)
        entries = [p for p in parts if p.strip()]
    return head, entries

head, live_entries = split_document(without_indexes(raw))
archive_entries = []
if os.path.isfile(archive):
    archive_raw = open(archive, encoding="utf-8").read()
    _, archive_entries = split_document(archive_raw)

# El veto KEEP-VISIBLE es un MARCADOR (comentario HTML que abre su línea), no
# una palabra: la lección que documenta el mecanismo menciona
# `<!-- KEEP-VISIBLE -->` en prosa y con `in text` se auto-vetaba — el
# clasificador disparaba con el texto que HABLA de la cosa, no con la cosa
# (el mismo falso positivo que lesson-detector-link.sh ya caza con `<!-- FILL`).
KEEP_VISIBLE = re.compile(r"(?m)^[ \t]*<!--[ \t]*KEEP-VISIBLE")

def classify(text):
    title = text.splitlines()[0].strip().lstrip("# ").strip()
    if KEEP_VISIBLE.search(text):
        return "viva", title, "veto explícito del owner (KEEP-VISIBLE)"
    det = ""
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("- **Detector:**"):
            det = s
        elif det and s.startswith(("- **", "###", "---")):
            break
        elif det:
            det += " " + s
    if not det:
        return "viva", title, "sin línea Detector (lesson-detector-link ya lo bloquea)"
    if "n/a-manual" in det:
        return "viva", title, "n/a-manual: la prosa ES el mecanismo"
    tests = [t for t in re.findall(r"tools/tests/test_[A-Za-z0-9_]+\.sh", det)
             if os.path.isfile(t)]
    if tests:
        return "archivable", title, f"garantizada por {tests[0]} (corre en el Anillo 3)"
    return "viva", title, "detector sin test propio en la suite: garantía PARCIAL"

# Reconcilia el corpus COMPLETO en cada corrida. El encabezado fechado es la
# identidad humana de una lección: repetir exactamente el mismo cuerpo es un
# retry idempotente; reutilizar el encabezado con otro cuerpo es ambigüedad y
# aborta ANTES de escribir, nunca elige una versión en silencio.
corpus = []
by_heading = {}
for origin, origin_entries in (("live", live_entries), ("archive", archive_entries)):
    for entry in origin_entries:
        normalized = canonical(entry)
        heading = normalized.splitlines()[0].strip()
        previous = by_heading.get(heading)
        if previous is not None:
            if previous[1] != normalized:
                print(
                    f"❌ identidad de lección duplicada con cuerpos distintos: {heading}",
                    file=sys.stderr,
                )
                sys.exit(1)
            continue
        by_heading[heading] = (origin, normalized)
        corpus.append((origin, normalized + "\n"))

vivas, archived = [], []
archivables, restorables = [], []
for origin, entry in corpus:
    kind, title, why = classify(entry)
    record = (title, why, entry)
    if kind == "archivable":
        archived.append(record)
        if origin == "live":
            archivables.append(record)
    else:
        vivas.append(record)
        if origin == "archive":
            restorables.append(record)

print(
    f"ROTATE_SUMMARY vivas={len(vivas)} archivables={len(archivables)} "
    f"restaurables={len(restorables)}"
)

if mode != "--apply":
    print()
    print(f"━━━ Rotación de lecciones ({len(corpus)} entradas) ━━━")
    print()
    print(f"ARCHIVABLES ({len(archivables)}) — su detector es un test que corre en CI:")
    for t, w, _ in archivables:
        print(f"  · {t}\n      {w}")
    if not archivables:
        print("  (ninguna todavía)")
    print()
    print(f"RESTAURABLES ({len(restorables)}) — su garantía mecánica dejó de existir:")
    for t, w, _ in restorables:
        print(f"  · {t}\n      {w}")
    if not restorables:
        print("  (ninguna)")
    print()
    print(f"SE QUEDAN VIVAS ({len(vivas)}) — su cumplimiento aún depende de leerlas:")
    for t, w, _ in vivas:
        print(f"  · {t}\n      {w}")
    print()
    print("Aplica con:  bash tools/lessons-rotate.sh --apply")
    print("Nada se borra: se mueve a", archive, "(versionado y verificado igual).")
    sys.exit(0)

AHEAD = """# Lecciones archivadas — mecanizadas, ya no hace falta leerlas

> **Por qué existe este archivo.** Cada lección de aquí tiene un detector que es un
> test de `tools/tests/` y que corre en el Anillo 3. Su cumplimiento NO depende de que
> nadie la recuerde: está garantizado por una máquina. Mantenerlas en el documento vivo
> cobraba dos veces el mismo seguro — en contexto del agente, en cada sesión.
>
> Siguen versionadas, siguen siendo grep-ables y `lesson-detector-link.sh` las sigue
> verificando. Si alguna vez borras su detector, **devuélvela al documento vivo**: sin
> el test, la regla vuelve a depender de la memoria.
>
> Generado/actualizado por `tools/lessons-rotate.sh --apply`.

"""

# El archivo y el índice son vistas deterministas del corpus reconciliado.
# Si un test desaparece, `classify` devuelve esa entrada al documento vivo.
archived_entries = [entry for _, _, entry in archived]

with open(archive, "w", encoding="utf-8") as f:
    f.write(AHEAD)
    for index, entry in enumerate(archived_entries):
        f.write(entry.rstrip())
        f.write("\n\n" if index < len(archived_entries) - 1 else "\n")

# El doc vivo NO pierde la señal, solo el volumen: cada lección archivada deja
# una línea de índice. Archivarlas del todo cambiaría un problema por otro —
# el agente dejaría de saber siquiera que la regla EXISTE, y se enteraría solo
# al ver fallar un test (una vuelta entera más cara que leer una línea).
# ~10 líneas de prosa por lección pasan a 1: el 90% del ahorro, con el 100%
# de la discoverability.
INDEX_HEAD = """---

## Lecciones mecanizadas (índice)

> Estas ya NO dependen de tu memoria: cada una tiene un test en `tools/tests/` que corre en el
> Anillo 3, así que violarlas hace fallar la suite. Se listan para que sepas que existen; el
> relato completo (síntoma, causa raíz, racional) vive en `docs/process/lessons_archive.md`.
> Si necesitas el detalle de una, búscala ahí — no la reescribas.

"""

def index_line(title, why):
    det = why.replace("garantizada por ", "").replace(" (corre en el Anillo 3)", "")
    return f"- {title} — `{det}`\n"

with open(doc, "w", encoding="utf-8") as f:
    f.write(head.rstrip() + "\n\n")
    for t, w, e in vivas:
        f.write(e.rstrip() + "\n\n")
    if archived_entries:
        f.write(INDEX_HEAD)
        for entry in archived_entries:
            _, title, why = classify(entry)
            f.write(index_line(title, why))

print(f"✅ {len(archivables)} lección(es) movidas a {archive}. Quedan {len(vivas)} vivas.")
for t, _, _ in archivables:
    print(f"   · {t}")
for t, _, _ in restorables:
    print(f"   ↩ {t} volvió al documento vivo: perdió su garantía mecánica.")
print("   Archivo e índice reconciliados desde el conjunto completo.")
print("   Commitea AMBOS archivos en el mismo cambio.")
PY

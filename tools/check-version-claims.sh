#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-version-claims.sh — el gestor de paquetes NO es la fuente
# ════════════════════════════════════════════════════════════════════
# Caso real, y caro: el nivel 4 (mutation score) llevaba semanas declarado
# "no disponible" porque `muter 16` —la versión que sirve Homebrew— no parsea
# los typed throws de Swift 6. La conclusión escrita en el ledger fue "no hay
# upgrade posible". Al mirar el repositorio, `main` tenía el arreglo desde
# 2026-07: el proyecto llevaba meses desarrollando **sin publicar un release**.
# El gate no estaba bloqueado por una limitación de la herramienta; estaba
# bloqueado por una limitación del canal por el que se preguntó.
#
#   **`brew`/`apt`/`npm` responden "cuál es el último RELEASE", no "qué
#     soporta el proyecto". Son preguntas distintas y la respuesta diverge
#     durante meses. Antes de declarar un gate no disponible por versión,
#     mira el repositorio.**
#
# Y el daño de equivocarse aquí es asimétrico: una capa entera de la pirámide
# se declara imposible, se documenta como tal, y nadie vuelve a intentarlo —
# la conclusión negativa se auto-preserva porque desalienta justo la
# comprobación que la refutaría. Es la clase de error que no se cae solo.
#
#   bash tools/check-version-claims.sh
#
# Contrato de salida:  VERSION_CLAIMS afirmaciones=<N> sin_repo=<M>
# Exit: 0 limpio · 1 hay una afirmación sin procedencia · 3 no pude mirar
#
# ── Alcance: SOLO el ledger, y esto no es pereza ───────────────────
# Este check NO mira `lessons_learned.md`. La lección que explica esta regla
# contiene, necesariamente, las palabras "brew", "no hay versión" y "muter 16":
# un detector que la escaneara se dispararía contra el texto que HABLA de la
# cosa en vez de contra la cosa — el falso positivo que este harness ya ha
# pisado cuatro veces y que tiene su propia entrada en las lecciones.
# En el ledger, en cambio, una afirmación de versión no es prosa: es la
# EVIDENCIA con la que se cerró (o se dejó abierto) un hallazgo. Ahí sí se
# exige que la evidencia diga de dónde salió.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

LEDGER="${FINDINGS_LEDGER:-tools/findings/ledger.jsonl}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "⚠️  check-version-claims: python3 ausente — NO he podido mirar." >&2
  echo "VERSION_CLAIMS afirmaciones=0 sin_repo=0"
  exit 3
fi
if [ ! -f "$LEDGER" ]; then
  echo "⚠️  check-version-claims: no existe $LEDGER — nada que mirar." >&2
  echo "VERSION_CLAIMS afirmaciones=0 sin_repo=0"
  exit 3
fi

CVC_LEDGER="$LEDGER" python3 - <<'PY'
import json, os, re, sys

ledger = os.environ["CVC_LEDGER"]

# ── Qué DISPARA ────────────────────────────────────────────────────
# Una afirmación de NO-EXISTENCIA sobre la versión de una herramienta. El
# matiz es el que hace este detector usable:
#
#   · "jq 1.6 se comporta así"            → observación. Se verifica CORRIENDO
#                                            jq. No dispara, y no debe.
#   · "muter 16 no parsea typed throws"   → afirmación de no-existencia. NO se
#                                            puede verificar con la copia que
#                                            tienes: exige mirar la fuente.
#
# Sin esa distinción el check saltaría con cada número de versión del ledger y
# moriría por la ley del 10% en su primera semana.
#
# ⚠️ Y ESO ES EXACTAMENTE LO QUE HIZO en el primer ledger ajeno que vio.
# Medición del adoptante: 3 disparos, 2 falsos positivos (67%). Las dos causas,
# que por separado eran tolerables y juntas rompen el detector:
#
#   1. `<palabra> <número>` es, en prosa española, todas partes: "criterio 6",
#      "la 0006", "Los 3 únicos casts", "nivel 4", "sección 5".
#   2. `tiene` estaba en la lista de verbos, y **en español "no tiene" es
#      CARECER, no "no soporta"**: "no tiene test", "no tiene alternativa".
#
# La lista de verbos se queda solo con los que hablan de SOPORTE. `tiene`,
# `trae` y `cubre` son posesión y cobertura — se van, y con ellos los dos FP,
# sin perder el verdadero positivo (que entra por `parsea`).
_NO_PUEDE = (r'no[ ]+(?:lo[ ]+)?(?:soporta|parsea|entiende|admite|implementa)|'
             r'no[ ]+est[aá][ ]+disponible|'
             r'no[ ]+(?:es|resulta)[ ]+compatible')

# Y el sujeto tiene que poder ser una HERRAMIENTA. Dos filtros baratos que no
# dependen de conocer los nombres de las herramientas del mundo:
#
#   · un número de versión no lleva ceros a la izquierda. "0006" es una
#     historia, un PRD o un ticket — nunca una versión.
#   · el token de delante no puede ser un determinante ni un enumerador. Una
#     herramienta no se llama "los", "la", "criterio" ni "nivel".
#
# Es una lista corta y cerrada de palabras ESTRUCTURALES, no un diccionario:
# cada entrada se defiende sola y no crece con el vocabulario del proyecto.
_NO_ES_HERRAMIENTA = {
    # determinantes / artículos (ES + EN)
    "el", "la", "los", "las", "un", "una", "unos", "unas", "lo", "al", "del",
    "este", "esta", "estos", "estas", "ese", "esa", "esos", "esas", "su", "sus",
    "the", "a", "an", "this", "that", "these", "those", "its",
    # enumeradores: cosas que en este dominio se numeran y NO son herramientas
    "criterio", "criterios", "historia", "historias", "nivel", "niveles",
    "seccion", "sección", "paso", "pasos", "capa", "capas", "anillo", "anillos",
    "regla", "reglas", "punto", "puntos", "fase", "fases", "item", "items",
    "ítem", "prd", "adr", "tipo", "tipos", "opcion", "opción", "opciones",
    "linea", "línea", "lineas", "líneas", "caso", "casos", "ejemplo", "ejemplos",
    "entrada", "entradas", "hallazgo", "hallazgos", "finding", "findings",
    "tabla", "apartado", "capitulo", "capítulo", "test", "tests", "commit",
    "commits", "issue", "issues", "ticket", "step", "layer", "rule", "line",
}
# `versión` NO está en la lista, y es deliberado: "la versión 16 de muter no
# soporta X" es justo el caso que este detector existe para pedir.
_TOOL_VER = re.compile(r'(?<![A-Za-z0-9_.-])([A-Za-z][A-Za-z0-9_.+@/-]{1,24})[ ]+'
                       r'v?(\d+(?:\.\d+)*)(?![0-9])')

_TRAS_LA_VERSION = re.compile(rf'^[^.;|]{{0,90}}?(?:{_NO_PUEDE})', re.I)
# La conclusión negativa en su forma más pura: aquí ni siquiera hay número.
_SIN_VERSION = re.compile(r'no[ ]+(?:hay|existe|queda)[ ]+(?:ning[uú]n[ao]?[ ]+)?'
                          r'(?:versi[oó]n|release|upgrade|actualizaci[oó]n)', re.I)

def dispara(texto):
    """Devuelve la frase que dispara, o None. La afirmación y su sujeto tienen
    que ir en la MISMA oración: el corte en [.;|] impide atribuir una negación
    a un número que estaba tres frases más arriba."""
    m = _SIN_VERSION.search(texto)
    if m:
        return m.group(0)
    for m in _TOOL_VER.finditer(texto):
        nombre, numero = m.group(1), m.group(2)
        if nombre.lower() in _NO_ES_HERRAMIENTA:
            continue
        if len(numero) > 1 and numero[0] == "0":
            continue          # "0006" es una historia, no una versión
        cola = _TRAS_LA_VERSION.search(texto[m.end():])
        if cola:
            return (m.group(0) + cola.group(0)).strip()
    return None

# ── Qué SATISFACE ──────────────────────────────────────────────────
# La procedencia: el repositorio, no el escaparate del gestor de paquetes.
REPO = re.compile(r'github\.com|gitlab\.com|codeberg\.org|bitbucket\.org|'
                  r'\bsr\.ht|git[ ]+ls-remote|git[ ]+log[ ]+upstream', re.I)
# Excepción explícita, con la misma forma que la de las lecciones (`n/a-manual`):
# hay herramientas sin repositorio público, y forzar una URL inventada sería
# peor que no pedir nada. Se DECLARA, para que no se confunda con un olvido.
EXCEPCION = re.compile(r'n/a-repo\b', re.I)

# El gestor de paquetes se nombra solo para poder decir, en el mensaje, qué
# fue lo que se consultó. Nunca satisface por sí mismo: ese es el punto.
GESTOR = re.compile(r'\b(brew|homebrew|apt|apt-get|apt-cache|npm|pnpm|yarn|'
                    r'pip3?|gem|port|choco|winget|mise|asdf|nix|dnf|yum|'
                    r'pacman|scoop)\b', re.I)

CAMPOS = ("title", "detail", "source", "resolution")

afirmaciones, sin_repo, malas = 0, [], 0
with open(ledger, encoding="utf-8") as f:
    for linea in f:
        linea = linea.strip()
        if not linea:
            continue
        try:
            d = json.loads(linea)
        except json.JSONDecodeError:
            malas += 1
            continue
        if not isinstance(d, dict):
            continue
        texto = " | ".join(str(d.get(k) or "") for k in CAMPOS)
        disparo = dispara(texto)
        if not disparo:
            continue
        afirmaciones += 1
        if REPO.search(texto) or EXCEPCION.search(texto):
            continue
        sin_repo.append((d.get("id", "?"), disparo, bool(GESTOR.search(texto))))

if malas:
    print(f"⚠️  check-version-claims: {malas} línea(s) del ledger no son JSON.",
          file=sys.stderr)
    print("VERSION_CLAIMS afirmaciones=0 sin_repo=0")
    sys.exit(3)

print(f"VERSION_CLAIMS afirmaciones={afirmaciones} sin_repo={len(sin_repo)}")

if sin_repo:
    print("")
    print(f"❌ {len(sin_repo)} hallazgo(s) declaran una herramienta incapaz por versión")
    print("   SIN citar de dónde salió esa versión:")
    for fid, frase, hay_gestor in sin_repo:
        print(f"  - {fid}: \"{frase}\"")
        if hay_gestor:
            print("      (el hallazgo cita un gestor de paquetes — y eso es")
            print("       exactamente lo que no basta: ver abajo)")
    print("")
    print("`brew`/`apt`/`npm` contestan \"cuál es el último RELEASE\". Tú preguntaste")
    print("\"qué soporta el proyecto\". Son preguntas distintas, y la respuesta puede")
    print("llevar MESES divergiendo: un proyecto vivo puede pasar un año sin publicar.")
    print("Pasó aquí — el nivel 4 se dio por imposible con el arreglo ya en `main`.")
    print("")
    print("Antes de cerrar el hallazgo, mira la fuente y cítala:")
    print("  git ls-remote --tags https://github.com/<org>/<repo>")
    print("  ...o el issue/commit concreto que confirma (o refuta) la limitación.")
    print("")
    print("Si la herramienta no tiene repositorio público, decláralo — igual que")
    print("`n/a-manual` en las lecciones, para que no parezca un olvido:")
    print("  --resolution \"... n/a-repo — <por qué no hay fuente que mirar>\"")
    sys.exit(1)

print(f"✅ check-version-claims: las {afirmaciones} afirmaciones de versión citan su fuente.")
PY

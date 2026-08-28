#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-source-sets.sh — EL invariante de KMP: commonMain no ve plataforma
# ════════════════════════════════════════════════════════════════════
# `check-layers.sh` modela un grafo por DIRECTORIO: dominio no importa UI, UI no
# importa infraestructura. En Kotlin Multiplatform eso no basta, porque hay un
# SEGUNDO eje que el grafo por directorio no ve: el de source sets.
#
#   commonMain/   código que compila para TODAS las plataformas
#   androidMain/  · iosMain/ · jvmMain/ · jsMain/   implementaciones por target
#
# El invariante que sostiene el modelo entero es uno solo:
#
#   **commonMain no importa nada específico de plataforma.**
#
# Y es EL invariante de KMP porque su violación no se manifiesta donde se comete:
# un `import android.net.Uri` en commonMain compila perfectamente mientras solo
# construyas el target Android, y revienta el día que alguien añade el target iOS
# —semanas después, en el CI de otro— con un error del compilador de Kotlin/Native
# que no apunta al import culpable. El coste de detectarlo tarde es exactamente el
# ~10× por nivel de §14.1, y aquí se paga entero.
#
# Kotlin ya tiene la respuesta correcta para esto: `expect`/`actual`. Este gate no
# la sustituye; hace que no usarla se note el mismo día.
#
#   bash tools/check-source-sets.sh
#
# Contrato de salida:  SOURCE_SETS estado=<...> violaciones=<N>
# Exit: 0 limpio o no aplica · 1 commonMain importa plataforma · 3 no pude mirar
#
# ── Por qué semgrep y no grep (PRD 0005 fase 1c) ────────────────
# `import` es una propiedad SINTÁCTICA. Anclar el grep a inicio de línea tapa el
# caso fácil (`// import android...`) pero no los dos que la gramática sí
# distingue: un bloque `/* */` sin asteriscos de adorno y un string triple
# contienen líneas que EMPIEZAN por `import`. Medido sobre el corpus de
# `test_source_sets.sh`, el grep daba 2 falsos positivos de 5 hits — 40%, cuatro
# veces la ley del 10% (§14.2). Semgrep parsea Kotlin: ahí no hay nada que anclar.
#
# La lista de prefijos NO se duplica en un YAML estático. La regla se genera en
# runtime desde `$PROHIBIDOS`, porque `metavariable-regex` se aplica al nombre de
# import YA PARSEADO — mismo regex, dos motores, una sola fuente de verdad. Una
# `tools/semgrep/rules/kotlin.yaml` fija no podría ver las ampliaciones de
# `source-sets.conf`, y dos listas que divergen son peor que una sola imperfecta.
#
# ── El fallback NO es un apagado (tabla de PRD 0005 §6) ─────────
#   semgrep operativo            → 0 ó 1 según semgrep (fuente primaria)
#   ausente/roto + grep limpio   → 3, y en CI bloquea con GATES_REQUIRE_SOURCE_SETS=1
#   ausente/roto + grep con hit  → 1. El fallback existe EXACTAMENTE para esto:
#                                  degradarlo a 3 aquí sería apagar el gate en la
#                                  única situación en que tenía algo que decir.
#   operativo que SALTA un .kt   → ese archivo pasa por el grep y se reporta.
#                                  "Operativo" no es un hecho binario POR REPO: si
#                                  no digirió un archivo, a ese archivo no lo ha
#                                  mirado nadie.
#
# ── Lo que este detector NO ve, dicho aquí y no descubierto luego ───
# · ``import `android`.net.Uri`` — un segmento prohibido escapado con backticks
#   evade LOS DOS motores. Es deuda preexistente (el grep anclado tampoco lo
#   veía), no una regresión de 1c, y vive en `f-wf06`. Se escribe porque un
#   blind-spot conocido y callado es la forma barata de fingir cobertura.
# · `import a.b.C; import android.net.Uri` — un segundo import tras `;` en la
#   MISMA línea lo caza semgrep y NO el fallback textual, que está anclado a
#   inicio de línea. O sea: el fallback es estrictamente más débil que el
#   primario, que es justo lo que un fallback debe ser mientras siga bloqueando.
#
# ── "No aplica" NO es exit 3, y la diferencia importa ───────────────
# Un repo sin `commonMain` no es un detector que no pudo mirar: es un detector
# que miró y no había nada de lo suyo. Decir 3 ahí lo convertiría en un aviso
# permanente para todo adoptante que no use KMP —la mitad de ellos— y un gate
# que siempre avisa se aprende a ignorar (ley del 10%, §14.2). Se declara el
# estado, que es lo que la fase 2 de este harness ya hace con las capacidades:
# `no-aplica` y `operational` son hechos distintos y se dicen distinto.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

# Sin esto, semgrep intenta un version-check de red al arrancar y en redes
# restringidas se CUELGA — no falla: espera. Este detector corre en el path de
# CADA commit (lefthook), así que un cuelgue aquí congela los commits de
# cualquiera detrás de un firewall, que es justo lo que §14.3 prohíbe: un bug
# del gate no puede trabar el commit. La lección estaba en el archivo histórico
# y arreglada en otros tres invocadores, pero sin detector — así que se repitió.
# Ahora lo fija `test_toda_invocacion_de_semgrep_desactiva_el_version_check`.
export SEMGREP_ENABLE_VERSION_CHECK=0
export SEMGREP_SEND_METRICS=off

# Los temporales viven a nivel de SCRIPT y se limpian con UN trap EXIT — la
# convención real del repo (semgrep-scan.sh, secret-baseline.sh, upgrade.sh…).
# Dos razones, las dos aprendidas en rojo aquí mismo:
#   · `trap ... INT TERM` NO es local a la función. Queda instalado para el
#     resto del script y, como el handler solo borra y no re-lanza, el script
#     deja de morir con SIGTERM: el `timeout` de CI o el watchdog que debía
#     matarlo dejan de poder. Un gate interminable es peor que el fichero
#     temporal que la limpieza venía a salvar (§14.3).
#   · Un handler que referencia LOCALES de la función explota bajo `set -u`
#     cuando salta fuera de ella, y el script sale 1 en vez de 143: el código
#     de salida miente sobre por qué murió.
# EXIT no toca la disposición de señales, así que la terminabilidad se conserva
# y la limpieza es best-effort, que es lo correcto para un fichero de /tmp.
_SS_TMP_REGLA=""; _SS_TMP_SALIDA=""
trap 'rm -f "$_SS_TMP_REGLA" "$_SS_TMP_SALIDA" 2>/dev/null' EXIT

CONF="${SOURCE_SETS_CONF:-tools/source-sets.conf}"

# Prefijos de import prohibidos en commonMain. Se pueden ampliar en el conf, y
# NO se pueden reducir desde ahí: una lista que el proyecto puede recortar deja
# de ser un invariante y pasa a ser una sugerencia (§9, misma lógica que los
# trinquetes).
# ── Por qué `androidx.` NO está entero en esta lista ────────────────
# Estaba, y era un generador de falsos positivos del 100%. Medido contra un
# corpus KMP AJENO (compose-multiplatform de JetBrains, 57 `commonMain`): 31
# violaciones reportadas, 31 falsas. Compose Multiplatform **reusa el namespace
# `androidx.compose`** para código que compila en iOS, desktop y web — JetBrains
# publica esos artefactos bajo `org.jetbrains.compose`. Uno de los hits vivía en
# `html/compose-compiler-integration`, que compila para WEB. Y no es solo Compose:
# `androidx.navigation`, `androidx.lifecycle` y `androidx.savedstate` también son
# multiplataforma hoy. Prohibir `androidx.` a secas acusa al stack KMP más común
# que existe, y un detector así no se corrige: se desactiva entero (§14.2).
# Quedan los subpaquetes que SIGUEN siendo solo-Android. Con ellos, el mismo
# corpus da 0 hits y 0 falsos positivos. Un proyecto que quiera prohibir más
# `androidx` lo añade en `source-sets.conf` — la lista solo puede crecer (§9).
_ANDROIDX_SOLO_ANDROID='androidx\.(core|activity|appcompat|fragment|recyclerview|constraintlayout|work|camera|media|preference)\.'
PROHIBIDOS="android\.|${_ANDROIDX_SOLO_ANDROID}|java\.|javax\.|dalvik\.|platform\.(UIKit|Foundation|darwin)|kotlinx\.cinterop|org\.robolectric|okhttp3\.|com\.google\.android\."   # el punto final es límite de palabra: sin él, `com.google.androidxyz` casaría
if [ -f "$CONF" ]; then
  _extra="$(grep -vE '^[[:space:]]*(#|$)' "$CONF" 2>/dev/null | tr '\n' '|' | sed 's/|$//')"
  [ -n "$_extra" ] && PROHIBIDOS="${PROHIBIDOS}|${_extra}"
fi

# SIN `head -20`, que es lo que había y lo que este propio comentario dos líneas
# más abajo declaraba inaceptable. En el corpus con el que se cerró el gate de
# 1c (compose-multiplatform: 57 `commonMain`) el detector miraba 20 y callaba
# los otros 37 — y en orden de filesystem, o sea que CUÁLES miraba no era ni
# determinista. Eso no es un detector con cobertura parcial: es un gate que
# aprueba lo que no leyó, con la forma exacta de uno que pasó (§14.3).
COMMON="$(find . -type d -name commonMain -not -path './.git/*' 2>/dev/null)"
# Un array, no una cadena que luego se expanda sin comillas: `commonMain` puede
# colgar de una ruta con espacios y un detector que deja de mirar en silencio
# parece un detector que aprueba. La versión pre-1c era inmune porque iteraba
# con `while read`; al pasar a lista había que conservar esa propiedad.
COMMON_DIRS=()
while IFS= read -r _d; do [ -n "$_d" ] && COMMON_DIRS+=("$_d"); done <<< "$COMMON"
if [ -z "$COMMON" ]; then
  echo "SOURCE_SETS estado=no-aplica violaciones=0"
  echo "ℹ️  check-source-sets: este repo no tiene source sets de KMP (sin commonMain/)."
  exit 0
fi

# ── Motor de fallback: el grep de siempre, ahora como red y no como red única
# Solo la SINTAXIS de import, anclada a inicio de línea. Un comentario de una
# línea o una cadena en esa misma línea que NOMBRE `android.net.Uri` no es un
# import. Lo que este anclaje NO puede ver —bloques y strings multilínea— es
# justo lo que el motor primario sí ve.
_grep_en() {  # _grep_en <dir-o-archivo>...
  # `-H` NO es redundante con `-r`, y la diferencia solo se ve en Linux: BSD
  # grep (macOS) imprime el nombre del archivo siempre que se recorre con -r,
  # pero GNU grep lo omite cuando se le pasa UN SOLO archivo explicito. El
  # fallback por archivo saltado hace exactamente eso —`_grep_en "$_f"`—, asi
  # que en Linux la salida era `2:import android.net.Uri`: sin decir en QUE
  # archivo. Dos consecuencias, las dos reales:
  #   · el usuario recibe una violacion que no puede localizar;
  #   · el dedupe por `archivo:linea` no casa contra el hit de semgrep (las
  #     claves son `2` y `Roto.kt`), asi que la MISMA violacion se contaba dos
  #     veces y `violaciones=N` mentia.
  # Lo destapo el CI de Linux; en macOS era invisible. Fijado por
  # test_source_sets_fallback.sh::test_el_fallback_nombra_el_archivo_siempre.
  grep -rHnE "^[[:space:]]*import[[:space:]]+(${PROHIBIDOS})" "$@" \
       --include='*.kt' --include='*.kts' 2>/dev/null || true
}

# ── Motor primario: semgrep sobre la gramática de Kotlin ────────
# Devuelve 0 si MIRÓ de verdad (hits en _SG_HITS, archivos que no digirió en
# _SG_SALTADOS); 1 si no pudo, que es un hecho distinto de "limpio".
_SG_HITS=""; _SG_SALTADOS=""
_semgrep_mira() {
  command -v semgrep >/dev/null 2>&1 || return 1
  command -v python3 >/dev/null 2>&1 || return 1   # sin parser de JSON no leemos su salida
  local regla salida parsed rc
  regla="$(mktemp -t sourcesets-rule.XXXXXX)" || return 1
  _SS_TMP_REGLA="$regla"
  salida="$(mktemp -t sourcesets-out.XXXXXX)" || return 1
  _SS_TMP_SALIDA="$salida"
  # `pattern: import $X` captura el nombre YA PARSEADO; el regex es el MISMO
  # $PROHIBIDOS del fallback, anclado al principio de ese nombre.
  # shellcheck disable=SC2016  # $X es un metavariable de semgrep, NO del shell:
  # tiene que llegar literal al YAML. Se declara en vez de dejar ruido en el lint.
  {
    printf 'rules:\n'
    printf '  - id: kmp-commonmain-no-importa-plataforma\n'
    printf '    languages: [kotlin]\n'
    printf '    severity: ERROR\n'
    printf '    message: commonMain importa plataforma\n'
    printf '    patterns:\n'
    printf '      - pattern: import $X\n'
    printf '      - metavariable-regex:\n'
    printf '          metavariable: $X\n'
    printf '          regex: ^(%s)\n' "$PROHIBIDOS"
  } > "$regla"
  semgrep --config "$regla" --quiet --json --no-git-ignore "${COMMON_DIRS[@]}" > "$salida" 2>/dev/null
  rc=$?
  if [ "$rc" != "0" ] || [ ! -s "$salida" ]; then return 1; fi
  parsed="$(SS_JSON="$salida" python3 -c '
import json, os, sys
try:
    with open(os.environ["SS_JSON"], encoding="utf-8") as fh:
        d = json.load(fh)
except Exception:
    sys.exit(1)
hits = ["%s:%d: import de plataforma" % (r["path"], r["start"]["line"])
        for r in d.get("results", [])]
saltados = sorted({e["path"] for e in (d.get("errors") or []) if e.get("path")})
print("\n".join(hits))
print("---SALTADOS---")
print("\n".join(saltados))
')" || { return 1; }
  _SG_HITS="${parsed%%---SALTADOS---*}"
  _SG_SALTADOS="${parsed#*---SALTADOS---}"
  return 0
}

# ── Registro adopter-owned de "semgrep fue operativo aquí" ──────
# Vive COMMITEADO en tools/project.conf: gitignored no existiría en el checkout
# de CI y la escalada no se activaría jamás; sincronizado heredaría el estado del
# template, que no dice nada del repo del adoptante (PRD 0005 §6, AMBER-3).
# NUNCA se escribe dentro de un git hook: un detector que ensucia el árbol en
# mitad de un commit cuesta más que la escalada que habilita.
_registrar_semgrep_operativo() {
  [ -n "${GIT_INDEX_FILE:-}" ] && return 0
  [ -f tools/project.conf ] || return 0
  grep -q '^source_sets_semgrep:' tools/project.conf 2>/dev/null && return 0
  {
    printf '\n# Escrito por check-source-sets.sh: semgrep analizo Kotlin aqui de\n'
    printf '# verdad, asi que a partir de ahora un "no pude mirar" en CI es una\n'
    printf '# regresion del entorno, no una limitacion de este repo.\n'
    printf 'source_sets_semgrep: operativo\n'
  } >> tools/project.conf
}

HITS=""; ESTADO=""
if _semgrep_mira; then
  ESTADO=operational
  HITS="$(printf '%s' "$_SG_HITS" | grep -v '^$' || true)"
  _saltados="$(printf '%s' "$_SG_SALTADOS" | grep -v '^$' || true)"
  if [ -n "$_saltados" ]; then
    while IFS= read -r _f; do
      [ -f "$_f" ] || continue
      _h="$(_grep_en "$_f")"
      [ -n "$_h" ] && HITS="${HITS}"$'\n'"${_h}"
    done <<< "$_saltados"
    # Dedupe por `archivo:línea`, NO por línea entera: un archivo con
    # PartialParsing sale a la vez en los hits de semgrep y en los saltados, y
    # los dos textos difieren (el mensaje del motor vs la línea cruda del grep),
    # así que un `sort -u` los dejaba pasar a los dos. El exit no cambiaba, pero
    # `violaciones=N` mentía — y un contador que miente es una cifra derivable
    # podrida, que es el pecado del que va la mitad de este PRD.
    HITS="$(printf '%s' "$HITS" | grep -v '^$' | sort -t: -k1,1 -k2,2n -u | awk -F: '
      { clave = $1 ":" $2 } !(clave in visto) { visto[clave] = 1; print }')"
  fi
  _registrar_semgrep_operativo
else
  HITS="$(_grep_en "${COMMON_DIRS[@]}")"
  HITS="$(printf '%s' "$HITS" | grep -v '^$' || true)"
  if [ -z "$HITS" ]; then
    # NO es "limpio": es "no pude mirar". Tratarlo como 0 convertiría un scanner
    # ausente en luz verde permanente, que es el fail-open que §14.3 prohíbe.
    echo "SOURCE_SETS estado=no-pude-mirar violaciones=0"
    {
      echo "⚠️  check-source-sets: semgrep no está operativo, y el fallback textual"
      echo "   no ve dentro de bloques /* */ ni de strings multilínea. El grep no"
      echo "   encontró nada, pero eso NO es un veredicto limpio sobre commonMain."
    } >&2
    [ "${GATES_REQUIRE_SOURCE_SETS:-0}" = "1" ] && exit 1
    exit 3
  fi
  ESTADO=fallback-textual
fi

N="$(printf '%s' "$HITS" | grep -c . || true)"; : "${N:=0}"
echo "SOURCE_SETS estado=$ESTADO violaciones=$N"

if [ "$N" -gt 0 ]; then
  echo ""
  echo "❌ commonMain importa código de plataforma ($N):"
  printf '%s\n' "$HITS" | sed 's/^/  /'
  cat <<'MSG'

commonMain compila para TODAS las plataformas. Esto compila hoy porque solo
estás construyendo un target; el día que se añada otro, revienta en el CI de
alguien más con un error que no apunta aquí.

La respuesta de Kotlin es `expect`/`actual`:

  // commonMain
  expect class Reloj() { fun ahora(): Long }
  // androidMain
  actual class Reloj { actual fun ahora() = System.currentTimeMillis() }

Y si de verdad es común, busca la alternativa multiplataforma
(kotlinx-datetime, okio, ktor) antes de mover el archivo de source set.
MSG
  exit 1
fi
echo "✅ check-source-sets: commonMain no importa plataforma."

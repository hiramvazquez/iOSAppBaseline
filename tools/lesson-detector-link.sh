#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# lesson-detector-link.sh — toda lección debe tener un DETECTOR
# ════════════════════════════════════════════════════════════════════
# ESTE ES EL MECANISMO POR EL QUE LA REVISIÓN HUMANA DECRECE.
#
# La filosofía es la de Tricorder (Google): **todo comentario de review que
# se repite es un bug en tu tooling.** Un equipo que solo escribe lecciones
# acumula prosa que nadie relee y que el agente no puede aplicar de forma
# fiable. Un equipo que convierte cada lección en un detector convierte
# "error cometido una vez" en "error mecánicamente imposible".
#
# Sin este bucle, la curva de esfuerzo de review humano es PLANA: cada
# proyecto nuevo repite los mismos errores. Con él, es decreciente.
#
# La regla: cada entrada de docs/process/lessons_learned.md tiene una línea
# `- **Detector:** <algo>`, y ese algo NO puede ser "manual"/"ninguno" salvo
# que se declare explícitamente `n/a-manual: <razón>` — porque hay lecciones
# que de verdad no son mecanizables (juicio de producto, criterio de diseño),
# y forzarlas produciría detectores ruidosos, que es peor.
#
#   bash tools/lesson-detector-link.sh
#
# Contrato de salida:  LESSONS_SUMMARY total=<N> sin_detector=<M>
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

DOC="${LESSONS_DOC:-docs/process/lessons_learned.md}"
# El ARCHIVO se verifica igual que el doc vivo. Una lección archivada lo está
# PRECISAMENTE porque su detector es un test que corre en CI: si alguien borra
# ese test, la lección deja de estar garantizada y debe volver al doc vivo.
# Sin verificar el archivo, rotar sería una forma silenciosa de esquivar este
# gate — el archivo se convertiría en el sitio donde las lecciones van a morir.
ARCHIVE="${LESSONS_ARCHIVE:-docs/process/lessons_archive.md}"
[ -f "$DOC" ] || { echo "LESSONS_SUMMARY total=0 sin_detector=0"; exit 0; }

# Solo entradas REALES: `### [fecha] título` en el cuerpo del doc. Se ignora
# lo que viva dentro de comentarios HTML (ejemplos del template) o de bloques
# de código con ``` (la plantilla de entrada). Contar esos sería el clásico
# falso positivo que mata la confianza en un detector.
# Ojo al matiz, que costó un falso positivo real: la máquina de estados decide
# sobre una versión SONDA de la línea, no sobre la línea cruda. Dos cosas se
# borran de la sonda antes de mirar:
#   · los spans de código `entre acentos` — una lección que HABLA de `<!-- FILL`
#     no está abriendo un comentario. Sin esto, la primera lección que explicaba
#     la regla de los marcadores FILL se tragó su propio campo `Detector:` y el
#     gate la reportó como huérfana: el detector se disparó con el texto que
#     habla de la cosa en vez de con la cosa.
#   · los comentarios que abren y cierran en la MISMA línea — no abren bloque.
# El `print` sigue siendo de la línea ORIGINAL: la sonda solo decide.
_strip() {
  awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence              { next }
    {
      probe = $0
      gsub(/`[^`]*`/, "", probe)
      gsub(/<!--.*-->/, "", probe)
      if (probe ~ /<!--/) inc = 1
      if (!inc) print
      if (probe ~ /-->/)  inc = 0
    }
  ' "$1"
}
ACTIVE="$(_strip "$DOC")"
[ -f "$ARCHIVE" ] && ACTIVE="$ACTIVE"$'\n'"$(_strip "$ARCHIVE")"

TOTAL=0; MISSING=0; ORPHANS=""
CURRENT=""; HAS_DETECTOR=0

flush() {
  [ -z "$CURRENT" ] && return 0
  TOTAL=$((TOTAL+1))
  if [ "$HAS_DETECTOR" -eq 0 ]; then
    MISSING=$((MISSING+1))
    ORPHANS="${ORPHANS}  - ${CURRENT}"$'\n'
  fi
}

# Una ENTRADA es `### [AAAA-MM-DD] título`. El corchete con fecha es lo que la
# distingue de un `###` de prosa del propio documento — contarlos fue un falso
# positivo real durante la implementación del PRD 0001 (§18 G1: todo gate
# necesita tests de sus falsos positivos, no solo de sus detecciones).
while IFS= read -r line; do
  case "$line" in
    '### ['*)
      flush
      CURRENT="${line#\#\#\# }"
      HAS_DETECTOR=0
      ;;
    '### '*)
      # Encabezado de prosa: cierra la entrada anterior y no abre una nueva.
      flush
      CURRENT=""
      ;;
    *'**Detector:**'*|*'Detector:'*)
      VAL="$(printf '%s' "$line" | sed -E 's/.*[Dd]etector:\*{0,2}[[:space:]]*//; s/[[:space:]]*$//')"
      case "$VAL" in
        ''|'manual'|'ninguno'|'none'|'TODO'|'<'*)
          : ;;                       # declarado pero vacío → no cuenta
        'n/a-manual'*)
          HAS_DETECTOR=1 ;;          # excepción justificada y explícita
        *)
          # El detector citado tiene que EXISTIR. Validar solo que el campo
          # esté relleno dejaba pasar detectores fantasma: una lección citaba
          # un grep de check-drift que ya había sido eliminado, y este script
          # daba el ✅ igual. Si el valor referencia un archivo del repo
          # (token con extensión conocida), comprobamos que existe; la parte
          # `::test_x` de un test se recorta antes de mirar el disco.
          DET_FILE="$(printf '%s' "$VAL" \
            | grep -oE '[A-Za-z0-9_./-]+\.(sh|bash|yaml|yml|conf|toml|json)' \
            | head -1 || true)"
          DET_FILE="${DET_FILE%%::*}"
          if [ -n "$DET_FILE" ] && [ ! -e "$DET_FILE" ]; then
            HAS_DETECTOR=0
            CURRENT="${CURRENT} — detector citado NO existe: ${DET_FILE}"
          else
            HAS_DETECTOR=1
          fi
          # ── …y el TEST citado tiene que existir dentro del archivo ──
          # El archivo existiendo no basta. Cazado escribiendo estas mismas
          # lecciones: una citaba `test_session_start.sh (los cuatro estados)`
          # y el archivo no tenía ni un test de los cuatro estados — el archivo
          # existía, el gate daba verde, y la lección quedaba respaldada por
          # una promesa. Es el mismo agujero que un id de finding fantasma
          # (`check-finding-refs.sh`): la cita LEE COMO CUBIERTO, y nadie
          # vuelve a comprobarlo. Toda la línea se escanea, no solo el primer
          # token: una lección cita varios tests y basta uno inventado.
          if [ "$HAS_DETECTOR" = "1" ]; then
            FALTAN=""
            for _t in $(printf '%s' "$VAL" | grep -oE '::[A-Za-z0-9_]+' | tr -d ':' || true); do
              # El archivo al que pertenece cada test es el ÚLTIMO citado antes
              # que él; en la práctica las lecciones citan un archivo y sus
              # tests, así que se busca en todos los archivos citados en la
              # línea. Un test que exista en cualquiera de ellos cuenta.
              _hallado=0
              for _f in $(printf '%s' "$VAL" | grep -oE '[A-Za-z0-9_./-]+\.(sh|bash)' || true); do
                _f="${_f%%::*}"
                [ -f "$_f" ] || continue
                grep -qE "^[[:space:]]*(function[[:space:]]+)?${_t}[[:space:]]*\(\)" "$_f" 2>/dev/null \
                  && { _hallado=1; break; }
              done
              [ "$_hallado" = "0" ] && FALTAN="${FALTAN} ${_t}"
            done
            if [ -n "$FALTAN" ]; then
              HAS_DETECTOR=0
              CURRENT="${CURRENT} — test(s) citados que NO existen:${FALTAN}"
            fi
          fi ;;
      esac
      ;;
  esac
done <<< "$ACTIVE"
flush

echo "LESSONS_SUMMARY total=$TOTAL sin_detector=$MISSING"

if [ "$MISSING" -gt 0 ]; then
  echo ""
  echo "❌ $MISSING lección(es) sin detector mecánico asociado:"
  printf '%s' "$ORPHANS"
  cat <<'MSG'

Una lección sin detector es prosa: nadie la relee y el agente no la aplica de
forma fiable. Conviértela en un check en el MISMO cambio. Dónde ponerla:

  · patrón de código        → tools/semgrep/rules/*.yaml       (AST, preferido)
  · regla de dependencias   → tools/layers.conf                 (grafo de imports)
  · regla irrompible barata → scripts/agent-hooks/canon-enforce.sh §CHECK 5
  · patrón de seguridad     → .claude/security-patterns.yaml    (coste 0 tokens)
  · algo que solo un test puede fijar → un test en el área

Si de verdad NO es mecanizable (juicio de producto, criterio de diseño), decláralo
explícitamente para que no se confunda con un olvido:

  - **Detector:** n/a-manual — <por qué no se puede automatizar>

Forzar un detector sobre algo no mecanizable produce ruido, y un detector
ruidoso se ignora entero. La excepción es legítima; el silencio no.
MSG
  exit 1
fi

echo "✅ lesson-detector-link: las $TOTAL lecciones tienen detector (o excepción justificada)."
exit 0

#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-prd-tree.sh — el árbol que un PRD DECLARA vs el que EXISTE
# ════════════════════════════════════════════════════════════════════
# La §5 de un PRD ("Estructura de archivos a crear / tocar") es un contrato: le
# dice al implementador —humano o agente— qué archivos entran en el cambio. Y
# como todo contrato escrito solo en prosa, se lee como cumplido (§14.4).
#
# El fallo concreto que existe para cazar: un PRD declara `tools/findings/
# findings.ts` y el archivo real es `findings.sh`. El PRD no miente por maldad,
# miente porque se escribió ANTES y nadie lo recomparó. Un agente que arranca
# con contexto 0 y lee esa §5 va a buscar un archivo que no existe, o peor, lo
# va a CREAR. (Ese caso es real y está en el PRD 0004 de este repo.)
#
# ── Una sola dirección, y es una decisión, no un olvido ─────────────
# Compara DECLARADO → ¿existe?, y NO la inversa (existe → ¿está declarado?).
# La inversa se midió antes de descartarla: 168 de 263 archivos versionados no
# aparecen en ninguna §5, un 64%. Eso no es un gate, es un generador de ruido —
# y §14.2 dice que un detector ruidoso se desactiva entero, llevándose por
# delante la señal buena de la dirección que SÍ funciona. Decisión del owner
# (2026-08-29). Si algún día se quiere la inversa, va acotada a `tools/` y
# `scripts/` (detectores nuevos sin declarar), que es donde tenía valor.
#
# ── Marcador de slice futuro: `[SLICE-FUTURO]` ──────────────────────
# Sin él este detector tiene falsos positivos POR DISEÑO: un PRD por fases
# declara en la §5 archivos que sus fases posteriores todavía no han creado.
# El PRD 0007 de este repo tiene tres (`arrancar.md`, `decisions/_template.md`
# y `check-decision-coverage.sh`, este último con un "CONDICIONADO AL FREEZE"
# escrito al lado). Marcarlos NO es burocracia: es la diferencia entre "este
# archivo falta" y "este archivo todavía no toca", que es justo lo que un
# agente con contexto 0 no puede deducir.
#
# Es un LITERAL entre corchetes y no una palabra suelta a propósito. Se probó
# `PENDIENTE` y colisiona con prosa real de las descripciones ("primera ready
# sin deps pendientes", "entregadas pendientes de ratificación"): un marcador
# que casa con la prosa que convive con él no marca nada. `grep -F`, cero
# interpretación — la misma doctrina que DEAD_CLAIMS en check-execution-map.sh.
#
# ── Qué mira y qué NO, para que el silencio no se lea como verde ────
#   · SOLO los bloques ``` de la §5, y solo hasta `### NO-TOUCH`. El NO-TOUCH
#     declara PROHIBICIONES, no existencias: `ios/ android/ web/` es legítimo
#     en un template que no tiene ninguno de los tres.
#   · SOLO la primera columna (la ruta), nunca la descripción tras `←`. La
#     prosa española está llena de barras que parecen rutas y no lo son:
#     `keep/tune/retire`, `lint/typecheck`, `0/1/3`, `Hiram/Claude`. Medido: el
#     extractor ingenuo sacaba más basura que rutas.
#   · Las líneas de CONTINUACIÓN (las que empiezan con espacio) se ignoran: son
#     descripción envuelta, no declaraciones.
#   · Los GLOBS (`tools/tests/test_*.sh`) no se comparan literalmente; se
#     CUENTAN y se declaran en el resumen. Fingir que se comprueban sería
#     exactamente el pecado de §14.4.
#   · Un PRD cuya §5 no es un árbol (el 0005 usa una TABLA) no se compara, y se
#     DECLARA en el resumen como `sin_arbol`. Un PRD saltado en silencio es un
#     gate que parece haber pasado.
#
# ── Solo se comparan los PRDs VIVOS, y esto no es una escapatoria ───
# Un PRD `Shipped`/`Deprecated` es un REGISTRO HISTÓRICO: su §5 describía el
# plan cuando se escribió, y el repo siguió moviéndose por otros PRDs después.
# El caso real: el PRD 0003 declara `tools/tests/test_backlog.sh`, que el PRD
# 0005 fase 2a dividió en cinco archivos (commit 915f03a). El 0003 no miente —
# describe correctamente lo que entregó en su día.
#
# Y sobre todo: los PRDs 0001-0005 están declarados NO-TOUCH ("histórico") por
# los propios 0005 y 0006. Compararlos produciría un gate ROJO QUE NADIE PUEDE
# PONER VERDE sin violar otro contrato — el gate insatisfacible que §14.3
# describe como deadlock. Se cuentan como `historicos=N` y se declaran; NO se
# saltan en silencio, que sería la otra forma de mentir.
#
# Contrato de stdout: PRD_TREE_SUMMARY declarados=N faltan=N futuros=N globs=N sin_arbol=N historicos=N
# Exit: 0 al día · 1 hay declaraciones que no existen · 3 no pude mirar
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

PRD_DIR="${PRD_TREE_DIR:-docs/process/prds}"
MARCA_FUTURO="${PRD_TREE_FUTURE_MARK:-[SLICE-FUTURO]}"

# ── "No pude mirar" ≠ "no encontré nada" (§14.3) ────────────────────
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  {
    echo "⚠️  prd-tree: esto no es un repo git — no puedo listar los archivos reales."
    echo "   Un gate que no pudo mirar NO es un gate que no encontró nada (§14.3)."
  } >&2
  echo "PRD_TREE_SUMMARY declarados=0 faltan=0 futuros=0 globs=0 sin_arbol=0 historicos=0"
  exit 3
fi
if [ ! -d "$PRD_DIR" ]; then
  {
    echo "⚠️  prd-tree: falta el directorio $PRD_DIR — no hay PRDs que comparar."
    echo "   Un gate que no pudo mirar NO es un gate que no encontró nada (§14.3)."
  } >&2
  echo "PRD_TREE_SUMMARY declarados=0 faltan=0 futuros=0 globs=0 sin_arbol=0 historicos=0"
  exit 3
fi

# El universo de "lo que existe" es el ÍNDICE de git, no el disco: un archivo
# sin versionar no está en el repo para nadie más, así que declararlo cumplido
# sería una verdad que solo vale en esta máquina.
LISTA="$(mktemp)"; trap 'rm -f "$LISTA"' EXIT
git ls-files > "$LISTA" 2>/dev/null || true
if [ ! -s "$LISTA" ]; then
  {
    echo "⚠️  prd-tree: 'git ls-files' no devolvió nada — repo sin archivos versionados."
    echo "   Un gate que no pudo mirar NO es un gate que no encontró nada (§14.3)."
  } >&2
  echo "PRD_TREE_SUMMARY declarados=0 faltan=0 futuros=0 globs=0 sin_arbol=0 historicos=0"
  exit 3
fi

_existe() { # _existe <ruta> → 0 si está versionada (o es un dir con contenido)
  local p="${1%/}"
  grep -qxF "$p" "$LISTA" && return 0
  # Declaración de DIRECTORIO: basta con que exista algo dentro.
  grep -qE "^$(printf '%s' "$p" | sed 's/[][\.*^$/]/\\&/g')/" "$LISTA" && return 0
  return 1
}

# ── El extractor: primera columna de los bloques ``` de la §5 ───────
# `awk` en vez de una tubería de greps porque hay que llevar DOS estados a la
# vez (dentro de la §5 / dentro de un fence) y pararse en `### NO-TOUCH`.
_rutas_de() { # _rutas_de <archivo-prd> → "<nlinea>\t<ruta>" por cada declaración
  awk '
    # Cualquier `## ` que no sea la propia §5 CIERRA la sección. Se probó
    # cortar solo en `## 5b.` / `## 6.` y se escapó: el PRD 0003 titula su
    # sección siguiente `## 6-7. Modelo y flujo`, que no casa `^## *6\.`, y el
    # escaneo siguió hasta un diagrama de flujo donde `schedule/humano` parecía
    # una ruta. Enumerar los encabezados que cierran es una lista que crece
    # para siempre; "cualquier otro ##" no.
    /^## /                          { en_sec = ($0 ~ /^## *5\./); en_fence = 0; next }
    /^### *NO-TOUCH/                { en_sec = 0 }   # prohibiciones, no existencias
    !en_sec                         { next }
    /^```/                          { en_fence = !en_fence; next }
    !en_fence                       { next }
    /^[[:space:]]*$/                { next }
    /^[[:space:]]/                  { next }         # continuación envuelta
    {
      linea = $0
      # La descripción empieza en la flecha: se corta y no se mira más.
      sub(/←.*$/, "", linea)
      # Una línea puede declarar varias rutas separadas por "·".
      n = split(linea, trozos, /·/)
      for (i = 1; i <= n; i++) {
        # Primer token del trozo: la ruta. El resto es prosa.
        split(trozos[i], campos, /[[:space:]]+/)
        for (j = 1; j <= 2 && j in campos; j++) {
          t = campos[j]
          gsub(/^[`"'"'"']+|[`"'"'"',;]+$/, "", t)
          if (t == "") continue
          # ── El filtro de FORMA, que es donde vive el ruido ──────────
          # "Lleva una barra" NO basta: la prosa española está llena de barras
          # que no son rutas y estaban disparando de verdad — `D1/E2:` (un
          # separador ASCII dentro del propio árbol), `schedule/humano`,
          # `keep/tune/retire`, `lint/typecheck`, `0/1/3`, `Hiram/Claude`.
          # Con "lleva barra" la tasa de FP medida fue del 29%, casi el triple
          # del 10% que §14.2 fija como criterio de descarte.
          #
          # Un archivo declarado en una §5 real SIEMPRE termina en extensión
          # conocida o en `/` (directorio). Ninguno de los falsos positivos de
          # arriba lo hace. Medido tras el cambio: 0 FP sobre los 7 PRDs.
          if (t ~ /\/$/ || t ~ /\.(sh|md|json|ya?ml|conf|example|toml|txt|ts|tsx|js|py|swift|kts?|go|rs|rb|java|sql|xml|plist|gradle|lock|cfg|ini)$/) {
            print NR "\t" t
            break
          }
        }
      }
    }
  ' "$1" 2>/dev/null
}

TOT_DECL=0; TOT_FALTAN=0; TOT_FUTUROS=0; TOT_GLOBS=0; TOT_SIN_ARBOL=0; TOT_HIST=0
INFORME=""; SIN_ARBOL_LISTA=""; HIST_LISTA=""

for prd in "$PRD_DIR"/[0-9]*.md; do
  [ -f "$prd" ] || continue
  # Sin campo Status se COMPARA (fail-closed): un PRD sin estado declarado no
  # puede eximirse solo — sería la exención más fácil de conseguir del repo.
  _status="$(grep -m1 -oE '\*\*Status:\*\*[^—·]*' "$prd" 2>/dev/null | tr 'A-Z' 'a-z')"
  case "$_status" in
    *shipped*|*deprecated*)
      TOT_HIST=$((TOT_HIST + 1))
      HIST_LISTA="${HIST_LISTA}     · $prd"$'\n'
      continue ;;
  esac
  rutas="$(_rutas_de "$prd")"
  if [ -z "$rutas" ]; then
    TOT_SIN_ARBOL=$((TOT_SIN_ARBOL + 1))
    SIN_ARBOL_LISTA="${SIN_ARBOL_LISTA}     · $prd"$'\n'
    continue
  fi
  faltan_aqui=""
  while IFS="$(printf '\t')" read -r nlin ruta; do
    [ -z "$ruta" ] && continue
    case "$ruta" in *'*'*) TOT_GLOBS=$((TOT_GLOBS + 1)); continue ;; esac
    TOT_DECL=$((TOT_DECL + 1))
    # El marcador vive en la LÍNEA de la declaración (la que el humano lee).
    if sed -n "${nlin}p" "$prd" 2>/dev/null | grep -qF "$MARCA_FUTURO"; then
      TOT_FUTUROS=$((TOT_FUTUROS + 1)); continue
    fi
    _existe "$ruta" && continue
    TOT_FALTAN=$((TOT_FALTAN + 1))
    faltan_aqui="${faltan_aqui}       línea ${nlin}: ${ruta}"$'\n'
  done <<< "$rutas"
  [ -n "$faltan_aqui" ] && INFORME="${INFORME}     $prd"$'\n'"${faltan_aqui}"
done

echo "PRD_TREE_SUMMARY declarados=$TOT_DECL faltan=$TOT_FALTAN futuros=$TOT_FUTUROS globs=$TOT_GLOBS sin_arbol=$TOT_SIN_ARBOL historicos=$TOT_HIST"

# Lo que NO se comparó se DICE, aunque todo esté verde: un PRD saltado en
# silencio es indistinguible de un PRD que pasó.
if [ -n "$SIN_ARBOL_LISTA" ]; then
  {
    echo "ℹ️  prd-tree: estos PRDs no traen un árbol comparable en §5 (tabla o prosa)"
    echo "   y NO se han comprobado:"
    printf '%s' "$SIN_ARBOL_LISTA"
  } >&2
fi

if [ -n "$HIST_LISTA" ]; then
  {
    echo "ℹ️  prd-tree: estos PRDs son Shipped/Deprecated (registro histórico) y NO"
    echo "   se han comparado — su §5 describe lo que entregaron en su día:"
    printf '%s' "$HIST_LISTA"
  } >&2
fi

[ "$TOT_FALTAN" = "0" ] && exit 0

{
  echo "❌ prd-tree: hay rutas DECLARADAS en la §5 de un PRD que no existen en el repo."
  echo ""
  printf '%s' "$INFORME"
  echo "   La §5 es el contrato que lee el implementador. Un agente que arranca con"
  echo "   contexto 0 buscará esos archivos y, si no los encuentra, los CREARÁ en el"
  echo "   sitio equivocado — o dará por hecho que otro los borró."
  echo ""
  echo "   Tienes tres salidas, y las tres son correctas según el caso:"
  echo "     1. La ruta cambió → actualiza la §5 (es el caso de 'findings.ts' vs '.sh')."
  echo "     2. El archivo es de una fase POSTERIOR → márcalo en su línea con"
  echo "        ${MARCA_FUTURO}, p. ej.:  tools/x.sh   ← ${MARCA_FUTURO} lo entrega la fase 3"
  echo "     3. Ya no entra en el PRD → bórralo de la §5."
} >&2
exit 1

#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-execution-map.sh — el mapa de ejecución no puede quedarse atrás
# ════════════════════════════════════════════════════════════════════
# `docs/process/current_execution_map.md` es la puerta de entrada de cada
# sesión: AGENTS.md §15 lo hace lectura obligatoria y `session-start.sh` +
# `post-compact.sh` extraen su bloque "Estado actual" y lo IMPRIMEN en el
# arranque y tras cada compactación.
#
# Eso lo convierte en el peor sitio del repo para una afirmación caducada: no
# es un doc que alguien podría leer, es un doc que TODOS los agentes leen
# siempre, y su contenido se propaga como si fuera estado verificado.
#
# Y pasó, en un adoptante real. El mapa afirmó "adopción del harness
# completada; sin código de producto todavía" durante CINCO historias shipped,
# con las cuatro capas cableadas de punta a punta contra una API real y su
# suite en verde.
#
# La causa no fue un descuido: `feature-workflow.md` Fase 4 declara el paso
# 4.3 "Update docs/process/current_execution_map.md" y NINGÚN mecanismo lo
# ejecutaba — grep sin resultados en `tools/backlog/` y en las cinco historias
# cerradas. Una regla escrita solo en prosa se lee como cumplida (§14.4). Las
# únicas referencias al mapa en el tooling eran los hooks que lo LEEN: el
# mecanismo existente propagaba la afirmación caducada y ninguno la corregía.
#
# ── QUÉ mide, y por qué NO mide lo que parecería obvio ──────────────
# Mide FRESCURA, no semántica: ¿el mapa se tocó DESPUÉS del último cambio que
# lo invalidaría? Es una comparación de dos fechas de commit — ~0% de falsos
# positivos.
#
# La tentación es escribir un comparador de afirmaciones contra el código. Ya
# se intentó en este repo y está registrado: `check-version-claims.sh` disparó
# al 67% de FP contra prosa española real, muy por encima del 10% que la §14.2
# fija como criterio de descarte. Un detector ruidoso no se arregla: se
# desactiva entero, y con él se pierde la señal buena. Frescura es aburrida y
# se cumple; semántica es ruido.
#
# DOS excepciones a esa regla, y solo estas dos — el design-review del PRD 0005
# cazó que la segunda contradecía este comentario tal como estaba escrito, así
# que se declara con su justificación en vez de fingirse la primera:
#   1. Aserciones LITERALES: si hay archivos bajo los directorios de producto,
#      el mapa no puede contener ciertas frases exactas. `grep -F` de cadenas
#      fijas — FP cero por construcción. Caza reincidencias CONOCIDAS, no la
#      clase; esa honestidad es parte del contrato.
#   2. Cifras DERIVABLES: `[0-9]+ (tests|pruebas|líneas)` en el mapa. Sí es un
#      patrón sobre prosa, pero de FORMA cerrada (un número pegado a tres
#      sustantivos concretos), no un comparador semántico como el que murió al
#      67% de FP. Sus falsos positivos están fijados por
#      test_fp_numeros_no_derivables_no_disparan (fechas, ids de PRD, §,
#      shas, "11 mutantes", nombres *_250_lineas): si esa tasa sube, cae la
#      excepción, no el test.
#
# Contrato de stdout:  EXECUTION_MAP_SUMMARY stale=<0|1>
# Exit: 0 al día · 1 stale · 3 no pude mirar (sin git, sin el doc)
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

MAP="${EXECUTION_MAP_DOC:-docs/process/current_execution_map.md}"
BACKLOG_DIR="${EXECUTION_MAP_BACKLOG_DIR:-backlog}"

# <!-- FILL: los directorios de CÓDIGO DE PRODUCTO de tu proyecto, separados
#      por espacios. Si los dejas vacíos, el detector sigue vigilando el paso a
#      `done` de las historias, pero no puede saber si tu producto avanzó.
#      Ejemplos:  iOS → "App/Domain App/Data App/UI App/App"
#                 web → "src/domain src/data src/ui"
#                 backend → "internal/ cmd/"
#      Un adoptante recién clonado no tiene producto todavía: dejarlo vacío es
#      el default correcto y NO deja el día 1 en rojo. -->
PROD_DIRS="${EXECUTION_MAP_PROD_DIRS:-}"

# <!-- FILL: frases que el mapa NO puede contener cuando ya existe producto.
#      Una por línea, se comparan literalmente (`grep -F`). La de serie es la
#      que mintió cinco historias seguidas en el primer adoptante; añade las
#      tuyas cuando pilles otra. NO pongas aquí patrones ni regex: el valor de
#      esta lista es que no interpreta nada. -->
DEAD_CLAIMS="${EXECUTION_MAP_DEAD_CLAIMS:-sin código de producto}"

# ── "No pude mirar" ≠ "no encontré nada" (§14.3) ────────────────────
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  {
    echo "⚠️  execution-map: esto no es un repo git — no puedo comparar fechas de commit."
    echo "   Un gate que no pudo mirar NO es un gate que no encontró nada (§14.3)."
  } >&2
  echo "EXECUTION_MAP_SUMMARY stale=0"
  exit 3
fi
if [ ! -f "$MAP" ]; then
  {
    echo "⚠️  execution-map: falta $MAP — no hay nada contra lo que comparar."
    echo "   Un gate que no pudo mirar NO es un gate que no encontró nada (§14.3)."
  } >&2
  echo "EXECUTION_MAP_SUMMARY stale=0"
  exit 3
fi

# ── El mapa que se está actualizando AHORA cuenta como fresco ───────
# Sin esto el detector es INSATISFACIBLE justo en el caso que existe para
# provocar: el paso 4.3 pide actualizar el mapa EN EL MISMO COMMIT que el
# cambio que lo invalida, pero `git log` solo ve historia commiteada, así que
# el mapa seguiría midiéndose por su commit VIEJO y el gate bloquearía el
# commit que lo arregla. Es el deadlock literal que describe §14.3.
#
# ⚠️ Exime SOLO de la comparación de fechas. Las aserciones literales de más
# abajo se siguen evaluando: si estás editando el mapa y aun así dejas dentro
# una frase que el árbol desmiente, eso no es "trabajo en curso", es el bug.
EN_CURSO=0
if ! git diff --quiet -- "$MAP" 2>/dev/null || ! git diff --cached --quiet -- "$MAP" 2>/dev/null; then
  EN_CURSO=1
fi

_ultimo_ts() { # _ultimo_ts <path>... → timestamp del último commit, o vacío
  [ "$#" -gt 0 ] || return 0
  # `%ct` (commit date) y no `%at`: el author date se puede reescribir en un
  # rebase y dejaría dos commits reordenados comparándose al revés.
  git log -1 --format=%ct -- "$@" 2>/dev/null
}

TS_MAP="$(_ultimo_ts "$MAP")"
if [ -z "$TS_MAP" ]; then
  # El doc existe pero ningún commit lo ha tocado: no hay historia que comparar.
  #
  # ⚠️ Esto ANTES hacía `exit 0`, y era un agujero: saltaba también las
  # aserciones de CONTENIDO (frases muertas, cifras derivables, afirmaciones de
  # estado), que no dependen de la historia de git para nada. El caso no es
  # teórico — es exactamente el de un adoptante recién clonado, cuyo mapa aún
  # no tiene commit propio: el detector le daba verde a un mapa que podía
  # afirmar cualquier cosa. Un gate que no puede mirar la FRESCURA no es un
  # gate que no pueda mirar NADA.
  #
  # Sin historia, "¿se tocó el mapa después?" no tiene respuesta, y esa es la
  # misma situación que "lo estoy editando ahora": se reutiliza EN_CURSO en vez
  # de inventar una segunda bandera con el mismo significado.
  EN_CURSO=1
fi

# Solo los directorios que existen, o `git log` avisa de pathspec inexistente.
_EXISTENTES=()
for _d in $PROD_DIRS; do [ -d "$_d" ] && _EXISTENTES+=("$_d"); done
TS_PROD=""
[ "${#_EXISTENTES[@]}" -gt 0 ] && TS_PROD="$(_ultimo_ts "${_EXISTENTES[@]}")"

# ── Última TRANSICIÓN de una historia a `status: done` ──────────────
# ⚠️ NO es "el commit más reciente cuyo árbol tenga alguna historia en done":
# eso lo cumple CUALQUIER commit que roce backlog/ en cuanto exista una sola
# historia cerrada, y degenera en "cualquier toque al directorio" — un falso
# positivo garantizado. La pregunta correcta compara con el PADRE.
#
# Y compara por ID de historia, no por RUTA: si comparase rutas, un
# `git mv historia-vieja.md historia-nueva.md` sobre una ya cerrada haría
# aparecer una ruta "nueva en done" y volvería a disparar en falso.
_done_set() { # _done_set <ref> → ids de historias en done, uno por línea
  # Una ref que no resuelve (p. ej. el padre de un commit raíz) devuelve vacío
  # sin error, y esa es exactamente la semántica que queremos: "antes no había
  # nada en done". Verificado, no supuesto.
  git grep -lE '^status:[[:space:]]*done[[:space:]]*$' "$1" -- "$BACKLOG_DIR" 2>/dev/null \
    | sed -E 's|^[^:]*:||; s|.*/||; s|^([0-9]+).*|\1|' | sort -u
}

TS_DONE=""
SHA_DONE=""
if [ -d "$BACKLOG_DIR" ]; then
  while IFS= read -r _sha; do
    [ -z "$_sha" ] && continue
    _aqui="$(_done_set "$_sha")"
    [ -z "$_aqui" ] && continue
    _antes="$(_done_set "${_sha}^")"
    if [ -n "$(comm -23 <(printf '%s\n' "$_aqui") <(printf '%s\n' "$_antes") 2>/dev/null)" ]; then
      TS_DONE="$(git log -1 --format=%ct "$_sha" 2>/dev/null)"
      SHA_DONE="$_sha"
      break
    fi
  done <<< "$(git log --format=%H -- "$BACKLOG_DIR" 2>/dev/null | head -50)"
fi

# ── ¿Hay algo más nuevo que el mapa? ────────────────────────────────
STALE=0
DETALLE=""
if [ "$EN_CURSO" = "0" ]; then
  if [ -n "$TS_PROD" ] && [ "$TS_PROD" -gt "$TS_MAP" ] 2>/dev/null; then
    STALE=1
    DETALLE="${DETALLE}   · código de producto ($(git log -1 --format='%h %s' -- "${_EXISTENTES[@]}" 2>/dev/null))"$'\n'
  fi
  if [ -n "$TS_DONE" ] && [ "$TS_DONE" -gt "$TS_MAP" ] 2>/dev/null; then
    STALE=1
    DETALLE="${DETALLE}   · una historia pasó a done ($(git log -1 --format='%h %s' "$SHA_DONE" 2>/dev/null))"$'\n'
  fi
fi

# ── Las aserciones literales: cadenas fijas, cero interpretación ────
_HAY_PRODUCTO=0
if [ "${#_EXISTENTES[@]}" -gt 0 ]; then
  if find "${_EXISTENTES[@]}" -type f -print -quit 2>/dev/null | grep -q .; then
    _HAY_PRODUCTO=1
  fi
fi
MUERTAS=""
if [ "$_HAY_PRODUCTO" = "1" ]; then
  while IFS= read -r _frase; do
    [ -z "$_frase" ] && continue
    grep -Fq "$_frase" "$MAP" && { MUERTAS="${MUERTAS}     · \"${_frase}\""$'\n'; STALE=1; }
  done <<< "$DEAD_CLAIMS"
fi

# ── Cifras DERIVABLES: lo que un comando recalcula no se copia ──────
# Pasó (`f-wf02-mapa-cifras-podridas`): el mapa declaró "477 tests" con 522
# funciones test_* en el árbol y "236 líneas" de contexto con 250 medidas.
# Nadie recalcula un literal, y este doc se INYECTA con autoridad en cada
# arranque — la cifra podrida viaja como estado verificado (PRD 0005 fase 0b).
#
# El patrón es deliberadamente ESTRECHO: número + espacio + tests/pruebas/
# líneas — las dos familias que ya se pudrieron, en singular/plural y con o
# sin acento. Fechas (2026-08-19), ids de PRD (0004), §14, "11 mutantes",
# nombres tipo `..._250_lineas` (guion bajo, no espacio) o "el escenario 10
# testea" (sigue letra) NO matchean: la ley del 10% (§14.2) dice que un
# detector ruidoso se desactiva entero y se pierde la señal buena. Los casos
# están fijados en test_execution_map.sh, falsos positivos incluidos.
#
# Se evalúa SIEMPRE, también con el mapa en curso (como las frases muertas):
# dejar el conteo copiado en el commit que estás preparando ES el bug.
DERIVABLE_ERE="${EXECUTION_MAP_DERIVABLE_ERE:-[0-9]+[[:space:]]+(tests?|pruebas?|líneas|lineas)([^[:alpha:]]|$)}"
DERIVABLES="$(grep -nE "$DERIVABLE_ERE" "$MAP" 2>/dev/null)"
[ -n "$DERIVABLES" ] && STALE=1


# ── Afirmaciones de ESTADO sin evidencia ────────────────────────────
# Pasó en un adoptante real y NINGÚN gate lo cazó: el mapa afirmaba que
# `gates.yml` "aún no ha corrido nunca". Había corrido y pasado TRES veces. Dos
# agentes seguidos se lo repitieron al owner como cierto, porque este doc se
# inyecta con autoridad en cada arranque (session-start.sh) y tras cada
# compactación (post-compact.sh).
#
# Las cifras derivables de arriba no lo cazaban por una razón de CLASE, no de
# cobertura: "aún no ha corrido nunca" no contiene ningún número. Es una
# afirmación de ESTADO, y el estado se pudre igual que un conteo — peor, porque
# no hay nada en su forma que delate que caducó.
#
# ── Por qué esta lista es CORTA Y CERRADA, y no un detector de negaciones ──
# La tentación es cubrir "la clase": toda negación de estado en español. Eso es
# exactamente el detector que ya murió en este repo — `check-version-claims.sh`
# disparó al 67% de FP contra prosa española real, muy por encima del 10% que
# §14.2 fija como criterio de descarte. Un detector ruidoso no se afina: se
# desactiva entero, y con él se pierde la señal buena.
#
# Así que son CINCO fórmulas literales, elegidas porque cada una AFIRMA UN
# HECHO COMPROBABLE sobre el mundo ("no ha ocurrido", "sigue faltando") en vez
# de expresar una intención o un plan. Medido contra el mapa real de este repo:
# 0 hits — el detector nace verde y solo habla cuando alguien escribe una de las
# cinco. `test_fp_la_lista_de_formulas_es_exactamente_cinco` FIJA el conjunto:
# ampliarlo obliga a tocar el test, que es justo la decisión consciente que
# separa una lista corta de una pendiente resbaladiza.
#
# NO están aquí, a propósito: "falta", "pendiente", "no está" (demasiado
# comunes en prosa de planificación legítima) ni el encabezado real del mapa
# "Lo que NO hacemos todavía" — que es una DECLARACIÓN de alcance diferido, no
# una afirmación sobre si algo ocurrió. Nótese que "NO hacemos todavía" no casa
# "todavía no": el orden importa y por eso la fórmula lleva el "no" detrás.
#
# ── Locale: literales, nunca clases con no-ASCII ────────────────────
# La suite corre con LANG="" (locale C). Ahí `[áa]` NO es "á o a" — son los
# BYTES de `á` en UTF-8 más `a`, y deja de casar lo que casaba en tu shell (ya
# pasó en test_execution_map.sh con `prohíb`). Lo que SÍ funciona en locale C es
# un literal no-ASCII fuera de corchetes. De ahí que cada fórmula acentuada
# aparezca DOS veces, con y sin tilde, como alternativas literales — no como
# una clase. `grep -i` solo pliega las ASCII, que es cuanto necesitamos: las
# tildes van en medio de la palabra, nunca en la inicial.
# ⚠️ `sigue sin` lleva frontera de palabra y las demás no, y es deliberado: lo
# cazó el `reviewer` sobre este mismo diff. Sin ella, el literal casa DENTRO de
# "conSIGUE SIN", "proSIGUE SIN", "perSIGUE SIN" — prosa de progreso
# perfectamente legítima ("el runner consigue sin mocks", "la suite prosigue sin
# fallos"). Mi medición de 0 hits era correcta pero contra un corpus de UNO: el
# mapa de hoy. Las otras cuatro fórmulas se probaron igual y no tienen colisión
# de subcadena plausible en español, así que no se les pone la frontera para no
# pagar complejidad que no compra nada.
STATE_ERE="${EXECUTION_MAP_STATE_ERE:-nunca ha|aún no|aun no|todavía no|todavia no|(^|[^[:alpha:]])sigue sin|es lo único que queda|es lo unico que queda}"

# La evidencia que redime una afirmación de estado: un COMANDO entre backticks
# (quien lo lea puede recomprobarlo en 2 segundos) o un marcador explícito
# `<!-- verificado: ... -->` para lo que ningún comando resuelve.
EVIDENCIA_ERE='`[^`]+`|<!--[[:space:]]*verificado:'

# Ventana de ±1 línea, y no "la misma línea", porque este mapa es markdown que
# ENVUELVE: el claim cae en una línea y el comando que lo respalda en la
# siguiente. Exigir la misma línea convertiría el salto de línea de un párrafo
# en un falso positivo. No es una concesión inventada aquí: es exactamente la
# ventana que ya usa `_adda_infractores` en test_execution_map.sh, contra esta
# misma prosa y por esta misma razón.
SIN_EVIDENCIA=""
while IFS= read -r _n; do
  [ -z "$_n" ] && continue
  _ctx="$(sed -n "$((_n > 1 ? _n - 1 : 1)),$((_n + 1))p" "$MAP" 2>/dev/null)"
  printf '%s\n' "$_ctx" | grep -qE "$EVIDENCIA_ERE" && continue
  SIN_EVIDENCIA="${SIN_EVIDENCIA}     línea ${_n}: $(sed -n "${_n}p" "$MAP")"$'\n'
done <<< "$(grep -inE "$STATE_ERE" "$MAP" 2>/dev/null | cut -d: -f1)"
[ -n "$SIN_EVIDENCIA" ] && STALE=1
echo "EXECUTION_MAP_SUMMARY stale=$STALE"
[ "$STALE" = "0" ] && exit 0

{
  echo "❌ execution-map: $MAP se quedó atrás."
  if [ -n "$MUERTAS" ]; then
    echo ""
    echo "   AFIRMACIONES DESMENTIDAS POR EL ÁRBOL — el mapa dice esto y hay archivos"
    echo "   bajo los directorios de producto:"
    printf '%s' "$MUERTAS"
    echo "   session-start.sh imprime este bloque en CADA arranque: no es un doc"
    echo "   desactualizado, es desinformación inyectada a todos los agentes siguientes."
  fi
  if [ -n "$DERIVABLES" ]; then
    echo ""
    echo "   CIFRAS DERIVABLES COPIADAS — estas líneas fijan como literal un conteo"
    echo "   que un comando recalcula (y que ya se pudrió una vez: 477→522, 236→250):"
    printf '%s\n' "$DERIVABLES" | sed 's/^/     línea /'
    echo "   Sustituye el número por el comando que lo imprime (la suite:"
    echo "   \`bash tools/tests/run-tests.sh\` da el total al final; el contexto lo mide"
    echo "   test_lessons_presupuesto_contexto.sh) o por evidencia commit+fecha SIN la forma 'N tests /"
    echo "   N líneas'. Ver \`f-wf02-mapa-cifras-podridas\` en el ledger."
  fi
  if [ -n "$SIN_EVIDENCIA" ]; then
    echo ""
    echo "   AFIRMACIONES DE ESTADO SIN EVIDENCIA — estas líneas afirman que algo NO ha"
    echo "   ocurrido (o que sigue faltando) sin decir con qué se comprobó:"
    printf '%s' "$SIN_EVIDENCIA"
    echo "   Pasó de verdad en un adoptante: el mapa decía que gates.yml \"aún no ha"
    echo "   corrido nunca\" cuando había corrido y pasado TRES veces, y dos agentes"
    echo "   seguidos se lo repitieron al owner como cierto. Una afirmación de estado"
    echo "   caduca sola y, a diferencia de un conteo, nada en su forma lo delata."
    echo "   Arréglalo de UNA de estas dos formas, en la línea o en su vecina:"
    echo "     · el comando que lo comprueba, entre backticks — p. ej."
    echo "       \"el Anillo 3 sigue sin remoto (\`bash tools/check-ring3.sh\`)\""
    echo "     · o un marcador <!-- verificado: <cómo>, <fecha> --> si ningún comando lo resuelve"
    echo "   Si ya no es cierto, bórralo: es la opción correcta más veces de las que parece."
  fi
  if [ -n "$DETALLE" ]; then
    echo ""
    echo "   Esto se commiteó DESPUÉS de la última vez que se tocó el mapa:"
    printf '%s' "$DETALLE"
  fi
  echo ""
  echo "   Arréglalo actualizando el mapa en ESTE commit (feature-workflow.md paso 4.3)."
  echo "   Regla que conviene adoptar en el propio doc: cero cifras derivables — lo que"
  echo "   un comando puede calcular va como comando, no como literal que caduca solo."
} >&2
exit 1

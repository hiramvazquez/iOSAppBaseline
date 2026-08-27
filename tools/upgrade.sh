#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# upgrade.sh — trae las mejoras del TEMPLATE a tu proyecto sin perder lo tuyo
# ════════════════════════════════════════════════════════════════════
# El modelo: tu proyecto nació de un clone del template y AMBOS evolucionan.
# Tus rellenos (FILLs, skills, confs) viven COMMITEADOS en tu historial, así
# que traer novedades es un merge de 3 vías normal: git funde automáticamente
# todo lo que no choque, y solo pide tu juicio donde ambos tocasteis las
# mismas líneas. Este script automatiza el ciclo y — como todo aquí — no da
# el upgrade por bueno hasta que la EVIDENCIA lo diga: tras el merge corre la
# suite del harness y validate-harness.
#
#   bash tools/upgrade.sh <url-del-template>   # primera vez (registra el remote)
#   bash tools/upgrade.sh                      # siguientes veces
#
# ⚠️  ARRANQUE MANUAL, UNA SOLA VEZ, si tu copia es anterior a la
# auto-actualización (o sea: si este bloque no está en TU tools/upgrade.sh).
# Un script sin el mecanismo no puede traérselo a sí mismo — la pescadilla:
#
#     git fetch template
#     git checkout template/main -- tools/upgrade.sh
#     bash tools/upgrade.sh
#
# A partir de ahí se mantiene solo: comprueba su propia versión contra el
# template antes de nada y se re-lanza actualizado.
#
# Reglas de resolución cuando haya conflicto (imprímelas mentalmente):
#   · MAQUINARIA (scripts/, tools/*.sh, ci/, lefthook.yml, tests) → suele
#     ganar el TEMPLATE: si no la personalizaste, acepta la suya (--theirs).
#   · CONTENIDO TUYO (AGENTS.md §2-3, .agents/skills/, *.conf, layers.conf,
#     docs/process/, backlog/, ratchets) → suele ganar TU versión (--ours);
#     incorpora a mano solo la mejora concreta del template si te interesa.
#   · En duda: mira qué cambió cada lado (git log template/main -- <archivo>).
#
# Exit: 0 upgrade limpio y verificado · 1 precondición/verificación fallida ·
#       2 merge con conflictos (quedan marcados para que los resuelvas)
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

REMOTE="template"
URL="${1:-}"

# ── Guard 1: árbol limpio — un merge sobre trabajo a medias es dolor ─
# Excepción ÚNICA y transitoria: `tools/upgrade.sh` sucio cuando venimos
# re-lanzados por una copia v1, que se auto-parcheaba sobre el árbol. La v2 ya
# no ensucia nada (corre desde /tmp), pero esta excepción tiene que seguir aquí
# hasta que ningún proyecto arranque con una v1 — si la quitas, la pasada de
# transición muere aquí mismo con "hay cambios sin commitear", que es
# exactamente el mensaje menos útil posible para lo que está pasando.
DIRTY="$(git status --porcelain 2>/dev/null | grep -vE '^\?\?' || true)"
if [ -n "${UPGRADE_SELF_UPDATED:-}" ]; then
  DIRTY="$(printf '%s\n' "$DIRTY" | grep -v 'tools/upgrade\.sh$' || true)"
fi
if [ -n "$DIRTY" ]; then
  echo "❌ upgrade: hay cambios sin commitear. Commitea (o stashea) antes de traer el template." >&2
  exit 1
fi

# ── Guard 2: remote registrado (o registrable) ──────────────────────
if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
  if [ -z "$URL" ]; then
    echo "❌ upgrade: no existe el remote '$REMOTE'. Primera vez:" >&2
    echo "   bash tools/upgrade.sh https://github.com/<tu-usuario>/agentic-workflow-template.git" >&2
    exit 1
  fi
  git remote add "$REMOTE" "$URL"
  echo "✓ remote '$REMOTE' → $URL"
fi

# ── Fetch + rama por defecto del template (main, master, o TEMPLATE_BRANCH) ─
git fetch -q "$REMOTE" || { echo "❌ upgrade: fetch de $REMOTE falló (¿red? ¿URL?)." >&2; exit 1; }
BRANCH="${TEMPLATE_BRANCH:-}"
if [ -z "$BRANCH" ]; then
  for b in main master; do
    if git rev-parse -q --verify "refs/remotes/$REMOTE/$b" >/dev/null 2>&1; then BRANCH="$b"; break; fi
  done
fi
if [ -z "$BRANCH" ]; then
  echo "❌ upgrade: no encuentro main/master en '$REMOTE'. Indica la rama: TEMPLATE_BRANCH=<rama> bash tools/upgrade.sh" >&2
  exit 1
fi
# ════════════════════════════════════════════════════════════════════
# AUTO-ACTUALIZACIÓN: la herramienta que trae los arreglos no puede ser
# la única que nunca los recibe — pero TAMPOCO puede parchearse a sí misma
# ════════════════════════════════════════════════════════════════════
# Problema de arranque, cazado en vivo: se arregló `upgrade.sh` en el
# template para soportar proyectos adoptados por copia... y el proyecto que
# lo necesitaba seguía ejecutando SU copia vieja, que fallaba igual. El
# arreglo estaba a un comando de distancia y era inalcanzable con el propio
# mecanismo — como una actualización de software que solo se puede instalar
# con la versión actualizada. De ahí la auto-actualización.
#
# La v1 de esa auto-actualización la hacía ESCRIBIENDO sobre `tools/upgrade.sh`
# en el árbol y re-lanzándose desde ahí. Sonaba razonable y era el bug: el
# archivo quedaba SUCIO respecto al índice, y más abajo (modo SYNC) el delta
# se aplica con `git apply --3way`, que exige worktree == índice para todo lo
# que toca. Como `tools/*.sh` es maquinaria, el delta incluía este archivo y
# git abortaba el parche ENTERO:
#
#     error: tools/upgrade.sh: does not match index
#
# O sea: el mecanismo que reparte los arreglos se rompía a sí mismo justo
# cuando el arreglo le tocaba a él. Cazado en el segundo proyecto real, en la
# primera pasada (f-upgrade-autoparcheo).
#
# La regla que queda, y que vale para cualquier herramienta que se actualice
# a sí misma: **el proceso que corre nunca escribe sobre su propio archivo.**
# Ejecutamos la versión nueva desde una copia TEMPORAL (`exec bash /tmp/...`)
# y dejamos que `tools/upgrade.sh` llegue al árbol por el mismo camino que
# todas las demás piezas de maquinaria — el sync/merge de abajo. Un camino
# menos, y encima el que tenía el caso especial.
#
# (`exec` y no `source`: bash lee los scripts de forma incremental por offset,
# así que reemplazar el archivo en ejecución produce comportamientos absurdos.)
_SELF="tools/upgrade.sh"

if [ -z "${UPGRADE_SELF_TMP:-}" ]; then
  _SELF_NEW="$(mktemp)"; _REEXEC=0
  if git show "$REMOTE/$BRANCH:$_SELF" > "$_SELF_NEW" 2>/dev/null && [ -s "$_SELF_NEW" ]; then
    cmp -s "$_SELF_NEW" "$_SELF" || _REEXEC=1
  fi
  # PUENTE desde la v1: si una copia anterior ya se auto-parcheó sobre el
  # árbol y nos re-lanzó desde ahí, seguimos corriendo desde el archivo del
  # repo. Hay que salir de él igual, o el `git apply` de abajo aborta. Este
  # bloque es lo único que hace que la transición de v1 a v2 sea una sola
  # pasada en vez de un "commitea el auto-parche y vuelve a correr".
  if ! git diff --quiet -- "$_SELF" 2>/dev/null; then
    [ -s "$_SELF_NEW" ] || cp "$_SELF" "$_SELF_NEW"
    _REEXEC=1
  fi
  if [ "$_REEXEC" = "1" ] && [ -s "$_SELF_NEW" ]; then
    chmod +x "$_SELF_NEW"
    echo "🔄 upgrade: corro la versión del template desde una copia temporal."
    echo "   Tu tools/upgrade.sh NO se toca aquí — llega por el propio sync,"
    echo "   como cualquier otra pieza de maquinaria."
    echo ""
    UPGRADE_SELF_UPDATED=1 UPGRADE_SELF_TMP="$_SELF_NEW" exec bash "$_SELF_NEW" "$@"
  fi
  rm -f "$_SELF_NEW"
else
  # Somos el proceso re-lanzado: la copia temporal es nuestra y se va con nosotros.
  trap 'rm -f "$UPGRADE_SELF_TMP"' EXIT
  # Segunda mitad del puente: ya NO corremos desde el archivo del repo, así que
  # devolverlo a su estado commiteado es seguro. Sin esto, el auto-parche de la
  # v1 seguiría ensuciando el índice y el delta seguiría abortando.
  if ! git diff --quiet -- "$_SELF" 2>/dev/null; then
    git checkout -q -- "$_SELF" 2>/dev/null \
      && echo "🔁 upgrade: deshecho el auto-parcheo de $_SELF en tu árbol (llegará por el sync)."
  fi
fi

# La topología se detecta ANTES de decidir si hay novedades: sin ancestro
# común, `rev-list HEAD..template` cuenta SIEMPRE todos los commits del
# template (ninguno es alcanzable desde HEAD), así que "¿estoy al día?" se
# responde con el SHA registrado, no con un conteo que nunca baja a cero.
MERGE_BASE_OK=0
git merge-base HEAD "$REMOTE/$BRANCH" >/dev/null 2>&1 && MERGE_BASE_OK=1
SYNC_RECORD="tools/.template-sync"

if [ "$MERGE_BASE_OK" = "1" ]; then
  NEW="$(git rev-list --count HEAD.."$REMOTE/$BRANCH" 2>/dev/null || echo 0)"
  if [ "${NEW:-0}" = "0" ]; then
    echo "✅ upgrade: ya estás al día con $REMOTE/$BRANCH."
    echo "   (al-día NO re-verifica: si acabas de commitear un sync, la evidencia es"
    echo "    bash tools/tests/run-tests.sh && bash tools/validate-harness.sh --selftest)"
    exit 0
  fi
else
  _REC="$( [ -f "$SYNC_RECORD" ] && awk 'NR==1{print $1; exit}' "$SYNC_RECORD" 2>/dev/null || true)"
  if [ -n "$_REC" ] && [ "$_REC" = "$(git rev-parse "$REMOTE/$BRANCH" 2>/dev/null)" ]; then
    echo "✅ upgrade: ya estás al día con $REMOTE/$BRANCH (sync registrado: ${_REC:0:7})."
    echo "   (al-día NO re-verifica: si acabas de commitear un sync, la evidencia es"
    echo "    bash tools/tests/run-tests.sh && bash tools/validate-harness.sh --selftest)"
    exit 0
  fi
  NEW="$(git rev-list --count "${_REC:+$_REC..}$REMOTE/$BRANCH" 2>/dev/null || echo '?')"
fi
echo "━━━ upgrade: $NEW commit(s) nuevos en el template ━━━"
git log --oneline HEAD.."$REMOTE/$BRANCH" | sed 's/^/   /'

# ════════════════════════════════════════════════════════════════════
# DOS TOPOLOGÍAS, y durante meses solo se contempló una
# ════════════════════════════════════════════════════════════════════
# La cabecera de este script decía "tu proyecto nació de un clone del
# template". Falso para el camino de adopción que la PROPIA doc recomienda
# (docs/ADOPTION.md): copiar el harness DENTRO de un proyecto que ya existe
# — que es lo normal, porque la app suele existir antes que el harness.
# Esos dos repos tienen historias NO RELACIONADAS y `git merge` se niega.
# Resultado: el camino de upgrade estaba roto justo para la ruta de adopción
# principal, y se descubrió el día que hizo falta usarlo de verdad.
#
#   MODO MERGE  · hay ancestro común (clone del template) → merge de 3 vías.
#   MODO SYNC   · sin ancestro común (adopción por copia) → se traen los
#                 paths de MAQUINARIA y se REPORTA el resto. Nunca se toca
#                 contenido del proyecto: eso sigue siendo tuyo por defecto.
#
# En MODO SYNC se registra el SHA del template en `tools/.template-sync`.
# Con ese registro, la próxima vez se puede aplicar solo el DELTA real
# (`git apply --3way`), que produce conflictos únicamente donde ambos lados
# tocaron lo mismo — un merge de 3 vías de facto, sin ancestro compartido.
# (MERGE_BASE_OK y SYNC_RECORD ya se calcularon arriba, antes del "¿al día?")
#
# Maquinaria: se sincroniza. Es el harness, y su fuente de verdad es el
# template (si la personalizaste, tu arreglo necesita SU test — lección del
# archivo-por-fuera-de-upgrade; la verificación de abajo es la red).
# Ojo al añadir maquinaria nueva: si vive en un directorio que NO está aquí, no
# viaja — y el modo de fallo es cruel, porque lo que SÍ viaja es su test. Pasó
# al crear `tools/semgrep/fixtures/`: `tools/tests/` estaba en la lista y el
# corpus no, así que el upgrade habría dejado a los proyectos con un test que
# busca un archivo que nunca llegó. Lo fija test_upgrade.sh::test_sync_trae_la_maquinaria_nueva.
# `backlog/_template.md` está por su nombre exacto a propósito: `backlog/` es
# del proyecto (sus historias), pero la PLANTILLA es harness — y desde que
# `run.sh` exige la sección de verificación de criterios, mandar el gate sin
# mandar la plantilla sería mandar la exigencia sin las instrucciones.
SYNC_PATHS="scripts ci tools/lib lefthook.yml .semgrepignore tools/capabilities.json tools/tests tools/semgrep/rules tools/semgrep/fixtures tools/findings/fixtures tools/metrics tools/agent-backends tools/agent-prompts tools/architecture.conf.example .github/workflows backlog/_template.md"
SYNC_GLOBS="tools/*.sh tools/findings/*.sh tools/findings/*.ts"

# ── Qué cuenta como marcador FILL (y qué NO) ────────────────────────
# Un marcador FILL es un COMENTARIO QUE EMPIEZA por `<!-- FILL`. Ni la palabra
# suelta, ni un `grep` que la busque, ni una mención en prosa.
#
# La primera versión era `grep -q 'FILL'` a secas, y ese matiz no es cosmético:
# con esa regla quedaban marcados como "propiedad compartida" —y por tanto
# CONGELADOS para siempre, sin volver a recibir un solo arreglo— cinco archivos
# de maquinaria pura que solo NOMBRAN la palabra:
#
#   · scripts/agent-hooks/session-start.sh   (avisa de FILLs sin rellenar)
#   · scripts/agent-hooks/inject-context.sh  (idem)
#   · scripts/bootstrap.sh                   (`grep -rn 'FILL:'` en un echo)
#   · tools/validate-harness.sh              (comprueba si run-gates sigue en FILL)
#   · tools/upgrade.sh                       (este archivo, en su cabecera)
#
# El daño es del peor tipo que persigue este harness: silencioso, permanente y
# con cara de éxito — el sync decía "🔒 no tocados, son tuyos" sobre archivos
# que nadie había personalizado nunca. Y la ironía: quien más lo sufría era el
# VERIFICADOR (validate-harness) y el propio upgrade.
FILL_MARKER='^[[:space:]]*([#;]|//|--)?[[:space:]]*<!--[[:space:]]*FILL'

# ── La regla FILL, en UN solo sitio y usada por LOS DOS caminos ─────
# Vivía dentro del camino de PRIMERA sincronización y el del DELTA no la
# consultaba nunca. Consecuencia, vivida por un adoptante: rellenó el FILL de
# `check-execution-map.sh` —que es literalmente lo que el marcador pide— y a
# partir de ahí CADA delta chocaba en esa línea, para siempre. Tuvo que resolver
# a mano y avanzar `tools/.template-sync` él mismo, un archivo que dice "no
# editar a mano".
#
# Es la peor forma del problema: **castiga exactamente la conducta correcta**.
# Y el mensaje de conflicto ("si tenías un arreglo local, MERGEA ambos") empuja
# al sitio equivocado, porque no es un arreglo local — es configuración que el
# propio template pidió.
#
# La regla, corregida por el primer sync real contra un adoptante (f-5fc894be):
# el marcador FILL en el template solo dice "esto PUEDE personalizarse" — la
# propiedad la decide la DIVERGENCIA REAL. Si la copia del adoptante es
# byte-idéntica a la base registrada, nadie la personalizó nunca y se
# sincroniza como cualquier maquinaria. La versión anterior excluía por la
# mera presencia del marcador y congeló gates VÍRGENES para siempre
# (check-review-marker sin el endurecimiento 206bc16, post-edit-verify ciego
# a Bash) mientras sincronizaba los tests que exigían sus versiones nuevas:
# 21 de los 24 rojos del adoptante. Sexta instancia del patrón
# "la-superficie-se-exime" — esta vez vía el canal de sync.
# Sin base registrada (primera sincronización) no hay con qué comparar y se
# conserva el comportamiento conservador: existe + FILL ⇒ no se toca.
_propiedad_compartida() { # _propiedad_compartida <path> → 0 si NO debe tocarse
  [ -f "$1" ] || return 1
  git show "$REMOTE/$BRANCH:$1" 2>/dev/null | grep -qE "$FILL_MARKER" || return 1
  if [ -n "${BASE_REC:-}" ] && git cat-file -e "$BASE_REC:$1" 2>/dev/null; then
    # ¿la copia local difiere de la base? — si NO difiere, es virgen: se sincroniza
    git diff --quiet "$BASE_REC" -- "$1" 2>/dev/null && return 1
  fi
  return 0
}

# Excluir sin decirlo dejaría al adoptante sin el arreglo Y sin saberlo, que es
# la clase de silencio que este harness persigue en todo lo demás.
_reportar_delta_fill() {
  [ -n "${_DELTA_FILL:-}" ] || return 0
  echo ""
  echo "   🔒 Fuera del delta (traen FILL y ya los personalizaste — tuyos):"
  printf '%s\n' "$_DELTA_FILL" | sed 's/^/      · /'
  echo "      Si el template cambió su maquinaria, esos cambios NO han llegado."
  echo "      Míralos y funde a mano lo que te sirva:"
  printf '%s\n' "$_DELTA_FILL" | head -3 | sed "s|^|         git diff HEAD $REMOTE/$BRANCH -- |"
}

# ⚠️  NO se delega el matching en git. Dos capas de fallo silencioso vividas
# aquí, una debajo de la otra:
#   1. `$SYNC_GLOBS` sin comillas → BASH lo expande contra el árbol LOCAL
#      antes de que git lo vea, así que una herramienta NUEVA del template
#      nunca entra en la lista. Nadie se entera.
#   2. Con comillas, `git ls-tree` (plumbing) hace match por PREFIJO, no
#      wildmatch: `tools/*.sh` no casa `tools/una-herramienta.sh`. Devuelve
#      menos archivos de los que crees, sin error.
# Solución: listar el árbol ENTERO del template una vez y filtrar aquí, con
# reglas explícitas que se leen y se testean. Cero semántica implícita.
_es_maquinaria() { # _es_maquinaria <ruta-en-el-template>
  local f="$1" p
  for p in $SYNC_PATHS; do
    [ "$f" = "$p" ] && return 0
    case "$f" in "$p"/*) return 0 ;; esac
  done
  set -f
  for p in $SYNC_GLOBS; do
    # shellcheck disable=SC2254  # el glob DEBE expandirse como patrón
    case "$f" in $p) set +f; return 0 ;; esac
  done
  set +f
  return 1
}

_REPORTADO=0
# ── Un arreglo que llega por sync no cierra el finding que lo pedía ──
# §1.1 dice "detectar no basta — CERRAR", y el canal por el que llega la mitad
# de los arreglos —este script— no tocaba el ledger. Vivido: dos findings
# seguían `open` con el detail diciendo "el fix no ha llegado" y el fix ya
# estaba en el árbol. Lo cazó el juez nocturno, no la persona.
#
# No los cierra automáticamente, y eso es deliberado: cerrar es un acto
# explícito (`findings.sh close --resolution`), y un cierre automático por
# coincidencia de ruta afirmaría que un problema se resolvió sin que nadie lo
# haya comprobado — justo la clase de verde sin evidencia que este harness
# persigue. Solo NOMBRA los que toca, que es lo que faltaba.
# El coste de equivocarse es asimétrico y por eso el filtro es generoso: nombrar
# uno de más cuesta una mirada; callarse uno deja un hallazgo abierto sobre algo
# ya arreglado, que es como el ledger pierde credibilidad.
_findings_tocados() { # _findings_tocados <rutas-del-delta...>
  [ -f tools/findings/ledger.jsonl ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  local rutas="$1"
  [ -n "$rutas" ] || return 0
  UPG_RUTAS="$rutas" python3 - <<'PYEOF' 2>/dev/null || true
import json, os
rutas = [r.strip() for r in os.environ.get("UPG_RUTAS", "").splitlines() if r.strip()]
if not rutas:
    raise SystemExit(0)
tocados = []
for linea in open("tools/findings/ledger.jsonl", encoding="utf-8"):
    linea = linea.strip()
    if not linea:
        continue
    try:
        d = json.loads(linea)
    except json.JSONDecodeError:
        continue
    if d.get("status") not in ("open", "in-progress", None):
        continue
    campos = " ".join(str(d.get(k) or "") for k in ("area", "title")) + " " + \
             " ".join(str(x) for x in (d.get("links") or []))
    for r in rutas:
        # Coincide por ruta completa o por nombre de archivo: un `area` suele
        # decir `tools/x.sh:42`, y a veces solo `x.sh`.
        if r in campos or os.path.basename(r) in campos:
            tocados.append((d.get("id", "?"), (d.get("title") or "")[:70]))
            break
if tocados:
    print("")
    print("   📌 Lo que acabas de traer toca findings ABIERTOS:")
    for fid, t in tocados:
        print(f"      · {fid} — {t}")
    print("   Revísalos: puede que este sync ya los resuelva. Cerrar sigue siendo")
    print("   explícito — `bash tools/findings/findings.sh close <id> --resolution \"...\"`.")
PYEOF
}

_report_no_sincronizado() {
  # Honestidad: lo que el template cambió y NO se ha tocado aquí. Sin esta
  # lista, "upgrade OK" leería como "traído todo", que es justo la clase de
  # falsa confianza que este harness persigue.
  #
  # ⚠️ SE IMPRIME SIEMPRE, también cuando la pasada acaba en conflicto o en
  # fallo. Antes solo salía por el camino feliz, y el resultado fue exactamente
  # el silencio que este bloque existía para evitar: en una pasada que terminó
  # con conflictos, un adoptante se quedó sin saber que le esperaban dos
  # arreglos en `.agents/skills/` y en `docs/` — los descubrió semanas después
  # comparando a mano contra el template. Un aviso que solo aparece cuando todo
  # va bien no es un aviso: es una felicitación.
  [ "$_REPORTADO" = "1" ] && return 0
  _REPORTADO=1
  local base="$1" changed
  # Sin base registrada (primera sincronización) no hay "qué cambió desde X":
  # las historias no están relacionadas y un diff contra el template listaría
  # el repo entero. Se dice lo que SÍ es cierto, en una línea.
  if [ -z "$base" ]; then
    echo ""
    echo "📋 Primera sincronización: solo he tocado MAQUINARIA. Todo lo demás del"
    echo "   template (skills, docs, AGENTS.md, backlog) sigue siendo tuyo y no se"
    echo "   ha traído. Si quieres ver qué trae de nuevo:"
    echo "   git diff HEAD $REMOTE/$BRANCH -- .agents/skills docs AGENTS.md"
    return 0
  fi
  # ⚠️ El filtro es `_es_maquinaria`, LA MISMA función que decide qué se
  # sincroniza. Antes había aquí una lista de regexes escrita a mano que
  # pretendía decir lo mismo — y decía otra cosa: `^tools/[A-Za-z0-9_-]+\.sh$`
  # no casa `tools/backlog/run.sh` (hay una barra de más), y `tools/semgrep/
  # fixtures/` y `backlog/_template.md` ni aparecían. Resultado en un proyecto
  # real: el informe listó como "NO traído" media docena de archivos que SÍ se
  # habían traído, y el adoptante los copió A MANO — justo el flujo inverso que
  # la regla de oro del final de este script prohíbe, provocado por el propio
  # script. Una regla implementada dos veces diverge; esta vive en un solo
  # sitio (README §"Una fuente de verdad").
  # `.claude/settings.json` va aparte porque no es "maquinaria" para el sync
  # (no se copia) pero SÍ se trae, fundido por claves.
  changed="$(git diff --name-only "$base" "$REMOTE/$BRANCH" 2>/dev/null \
    | while IFS= read -r _f; do
        [ -z "$_f" ] && continue
        [ "$_f" = ".claude/settings.json" ] && continue
        _es_maquinaria "$_f" || printf '%s\n' "$_f"
      done)"
  [ -z "$changed" ] && return 0
  echo ""
  echo "📋 El template también cambió esto, y NO lo he tocado (es tuyo o es a juicio):"
  printf '%s\n' "$changed" | sed 's/^/   · /'
  echo "   Míralo con:  git diff HEAD $REMOTE/$BRANCH -- <archivo>"
  echo "   Incorpora a mano solo lo que te interese. Tu contenido no se pisa nunca."
}

_avisar_harness_inoperante() {
  # LO PRIMERO que hay que decir cuando una pasada deja conflictos: si el
  # conflicto cayó dentro de un hook, el harness no está "a medias", está
  # INOPERANTE — y en el peor caso el agente se queda sin poder ejecutar Bash
  # para diagnosticarlo. Pasó en un proyecto real con `reviewer-gate.sh`.
  local roto=""
  for _h in scripts/agent-hooks/*.sh scripts/agent-hooks/lib/*.sh scripts/agent-hooks/adapters/*.sh; do
    [ -f "$_h" ] || continue
    bash -n "$_h" 2>/dev/null || roto="${roto}   · ${_h}"$'\n'
  done
  [ -z "$roto" ] && return 0
  {
    echo ""
    echo "🚨 EL HARNESS ESTÁ INOPERANTE: estos hooks NO parsean (conflictos sin resolver):"
    printf '%s' "$roto"
    echo "   Mientras sigan así, sus gates no se aplican. Si tu cliente edita a través"
    echo "   de Bash, puede que ni siquiera puedas ejecutar comandos para verlos:"
    echo "   resuélvelos con tu EDITOR, no con la terminal."
    echo "   Cuando parseen:  bash tools/tests/run-tests.sh && bash tools/validate-harness.sh --selftest"
  } >&2
}

_fundir_settings() {
  # `.claude/settings.json` es la ÚNICA parte de `.claude/` que es maquinaria:
  # dentro viven los hooks (Anillo 2) y los permisos (Anillo 0). No se puede
  # traer con checkout (pisaría los permisos del proyecto) ni dejar fuera
  # (se queda atrás en silencio, y un gate que no se actualiza no avisa de
  # que no se actualizó). Se funde por claves, y SOLO añadiendo.
  [ -f tools/merge-claude-settings.sh ] || return 0
  local out rc
  out="$(bash tools/merge-claude-settings.sh "$REMOTE/$BRANCH" 2>&1)"; rc=$?
  printf '%s\n' "$out" | grep -v '^SETTINGS_MERGE' | sed 's/^/   /'
  # ⚠️ ESTO NO PUEDE SER UN AVISO. Dentro de settings.json viven los hooks
  # (Anillo 2 entero) y los permisos (Anillo 0). Si el merge revienta y solo
  # imprimimos un ⚠️, el adoptante se queda con el harness anterior y el
  # upgrade dice que fue bien: un anillo entero sin actualizar, en silencio,
  # con cara de éxito. Es exactamente el modo de fallo que este repo persigue.
  # Y no es hipotético: el merge llevaba desde su primer commit reventando
  # contra el settings.json real, y nadie se enteró porque solo avisaba.
  if [ "$rc" = "1" ]; then
    {
      echo ""
      echo "❌ upgrade: el merge de .claude/settings.json FALLÓ."
      echo "   Ahí viven los hooks (Anillo 2) y los permisos (Anillo 0): tu harness"
      echo "   se quedaría en la versión anterior sin que nada más lo dijera."
      echo "   Compara a mano:  git diff HEAD $REMOTE/$BRANCH -- .claude/settings.json"
    } >&2
    return 1
  fi
  return 0
}

if [ "$MERGE_BASE_OK" = "1" ]; then
  # ── MODO MERGE (historia compartida) ──────────────────────────────
  if ! git merge --no-ff --no-edit "$REMOTE/$BRANCH" \
        -m "chore(template): upgrade desde $REMOTE/$BRANCH" 2>/tmp/upgrade-merge-err.$$; then
    CONFLICTS="$(git diff --name-only --diff-filter=U)"
    if [ -z "$CONFLICTS" ]; then
      # NO son conflictos: el merge falló por otra cosa. Decir "resuelve los
      # conflictos" sin conflictos manda al humano a buscar lo que no existe
      # — un diagnóstico equivocado cuesta más que ninguno.
      echo ""
      echo "❌ upgrade: el merge FALLÓ (y no por conflictos: no hay archivos en conflicto)." >&2
      sed 's/^/   /' /tmp/upgrade-merge-err.$$ >&2 2>/dev/null
      rm -f /tmp/upgrade-merge-err.$$
      git merge --abort 2>/dev/null
      echo "   El árbol se dejó como estaba (merge --abort)." >&2
      exit 1
    fi
    rm -f /tmp/upgrade-merge-err.$$
    echo ""
    echo "⚠️  upgrade: conflictos — ambos tocasteis las mismas líneas. Archivos:"
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      case "$f" in
        scripts/*|ci/*|lefthook.yml|tools/tests/*|tools/*.sh)
          echo "   [maquinaria → suele ganar el TEMPLATE]  $f" ;;
        AGENTS.md|.agents/skills/*|tools/*.conf|tools/preset|tools/*-ratchet.json|docs/process/*|backlog/*)
          echo "   [contenido TUYO → suele ganar TU versión] $f" ;;
        *)
          echo "   [a juicio — mira ambos lados]            $f" ;;
      esac
    done <<< "$CONFLICTS"
    echo ""
    echo "   Resuélvelos (git checkout --ours/--theirs <archivo>, o a mano), luego:"
    echo "   git add -A && git commit  — y RE-CORRE este script para la verificación."
    _avisar_harness_inoperante
    exit 2
  fi
  rm -f /tmp/upgrade-merge-err.$$
else
  # ── MODO SYNC (adopción por copia: historias no relacionadas) ─────
  echo ""
  echo "━━━ MODO SYNC: tu repo y el template NO comparten historia ━━━"
  echo "   (normal si adoptaste copiando el harness a un proyecto que ya existía)"
  BASE_REC=""
  [ -f "$SYNC_RECORD" ] && BASE_REC="$(awk 'NR==1{print $1; exit}' "$SYNC_RECORD" 2>/dev/null)"
  if [ -n "$BASE_REC" ] && git cat-file -e "$BASE_REC^{commit}" 2>/dev/null; then
    echo "   Base registrada: $BASE_REC — aplico solo el DELTA de maquinaria."
    # shellcheck disable=SC2086  # los globs DEBEN expandirse aquí
    # Los de propiedad compartida se quedan FUERA del parche. Antes entraban y
    # chocaban en cada delta contra el relleno del adoptante.
    _DELTA_FILL=""
    # UNIÓN de los trees de la base y de HEAD, no solo HEAD (f-fa151ee4): un
    # archivo BORRADO en el template no está en el tree de HEAD, así que con
    # solo ese tree su path jamás entraba al pathspec y el borrado no viajaba
    # — el caso real dejó dos monolitos huérfanos y ~27 tests duplicados en el
    # adoptante. Con el path en la unión, el diff BASE..HEAD trae el hunk de
    # borrado y `apply --3way` lo ejecuta; si el adoptante lo había modificado,
    # el 3way lo convierte en CONFLICTO visible en vez de borrado silencioso.
    # Un path borrado en ambos lados (ya ausente aquí) se salta: nada que hacer.
    _DELTA_PATHS="$( { git ls-tree -r --name-only "$REMOTE/$BRANCH" 2>/dev/null
                       git ls-tree -r --name-only "$BASE_REC" 2>/dev/null; } | sort -u | while IFS= read -r _f; do
        _es_maquinaria "$_f" || continue
        if ! git cat-file -e "$REMOTE/$BRANCH:$_f" 2>/dev/null && [ ! -f "$_f" ]; then continue; fi
        if _propiedad_compartida "$_f"; then printf 'FILL\t%s\n' "$_f"; else printf 'OK\t%s\n' "$_f"; fi
      done)"
    _DELTA_FILL="$(printf '%s\n' "$_DELTA_PATHS" | awk -F'\t' '$1=="FILL"{print $2}')"
    # shellcheck disable=SC2086  # los paths DEBEN expandirse como argumentos
    if git diff "$BASE_REC" "$REMOTE/$BRANCH" -- $(printf '%s\n' "$_DELTA_PATHS" | awk -F'\t' '$1=="OK"{printf "%s ", $2}') > /tmp/upgrade.patch.$$ 2>/dev/null \
       && [ -s /tmp/upgrade.patch.$$ ]; then
      if git apply --3way --whitespace=nowarn /tmp/upgrade.patch.$$ 2>/tmp/upgrade-apply-err.$$; then
        echo "   ✓ delta aplicado limpio."
        _findings_tocados "$(git diff --name-only "$BASE_REC" "$REMOTE/$BRANCH" -- $(printf '%s\n' "$_DELTA_PATHS" | awk -F'\t' '$1=="OK"{printf "%s ", $2}') 2>/dev/null)"
      else
        CONFLICTS="$(git diff --name-only --diff-filter=U)"
        if [ -n "$CONFLICTS" ]; then
          echo ""
          echo "⚠️  upgrade: el delta dejó conflictos (ambos lados tocaron lo mismo):"
          printf '%s\n' "$CONFLICTS" | sed 's/^/   · /'
          echo "   Resuélvelos SIN elegir a ciegas: si tenías un arreglo local en"
          echo "   maquinaria, MERGEA ambos. Un arreglo local sin su test se pierde"
          echo "   en silencio (lección del archivo-por-fuera-de-upgrade)."
          echo "   Luego: git add -A && git commit — y RE-CORRE este script."
          rm -f /tmp/upgrade.patch.$$ /tmp/upgrade-apply-err.$$
          # El conflicto NO cancela el informe: es justo cuando más falta hace,
          # porque la pasada termina antes de tiempo y sin él te quedas sin
          # saber qué más te espera.
          _avisar_harness_inoperante
          _reportar_delta_fill
          _report_no_sincronizado "$BASE_REC"
          exit 2
        fi
        echo "❌ upgrade: no pude aplicar el delta de maquinaria:" >&2
        sed 's/^/   /' /tmp/upgrade-apply-err.$$ >&2 2>/dev/null
        rm -f /tmp/upgrade.patch.$$ /tmp/upgrade-apply-err.$$
        _reportar_delta_fill
        _report_no_sincronizado "$BASE_REC"
        exit 1
      fi
    else
      echo "   (sin cambios de maquinaria desde la base registrada)"
    fi
    # En TODAS las salidas del delta, no solo en la limpia — misma lección que
    # obligó a `_report_no_sincronizado` a imprimir siempre. Y aquí es peor: si
    # lo único que cambió el template fue un archivo con FILL, el delta queda
    # VACÍO y sin este aviso la pasada dice "sin cambios" mientras hay un
    # arreglo esperando. Silencio con cara de éxito.
    _reportar_delta_fill
    rm -f /tmp/upgrade.patch.$$ /tmp/upgrade-apply-err.$$
  else
    # PRIMERA VEZ sin registro: no hay forma de saber qué cambió cada lado,
    # así que se trae la maquinaria ENTERA y se avisa con todas las letras.
    echo ""
    echo "⚠️  PRIMERA SINCRONIZACIÓN (sin base registrada)."
    echo "   Voy a traer la MAQUINARIA COMPLETA del template. Si tenías arreglos"
    echo "   locales en scripts/ o tools/*.sh, esto los SOBRESCRIBE — revisa el"
    echo "   diff antes de commitear. La red es la verificación de abajo (suite +"
    echo "   selftest): un arreglo local con su test lo delata al fallar."
    echo ""
    # UNO A UNO, y cada resultado se declara. La v1 hacía un solo
    # `git checkout ... -- $SYNC_GLOBS 2>/dev/null`: el checkout con pathspec
    # es ATÓMICO, así que un solo patrón sin coincidencias abortaba TODO —
    # y el `2>/dev/null` se comía el error. Resultado real, cazado en el
    # primer uso: trajo los tests de tres herramientas SIN las herramientas,
    # y dijo que había ido bien. Es el mismo patrón que perseguimos todo el
    # día (la operación falla a medias y reporta éxito), esta vez cometido
    # por quien escribía el detector de ese patrón.
    _SYNC_OK=0; _SYNC_FILL=0; _SYNC_FAIL=0; _FILL_LIST=""
    # ARCHIVO a archivo, no path a path. Dos razones, ambas de errores reales
    # cometidos en el primer uso de este modo:
    #
    # 1. `git checkout -- <pathspec>` es ATÓMICO: un patrón sin coincidencias
    #    aborta TODO. Con `2>/dev/null`, en silencio. Trajo los tests de tres
    #    herramientas SIN las herramientas, y reportó éxito.
    # 2. Hay maquinaria con secciones que el template ESPERA que personalices
    #    (`canon-enforce.sh` §CHECK 5, `post-edit-verify.sh`, `lefthook.yml`).
    #    Traerlas enteras devolvió a comentario el guard del `.pbxproj` de un
    #    proyecto real. Regla mecánica y sin listas que mantener: **si la
    #    versión del TEMPLATE trae un marcador FILL, ese archivo es de
    #    propiedad compartida y no se pisa jamás — se reporta.**
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      if _propiedad_compartida "$f"; then
        _FILL_LIST="${_FILL_LIST}${f}"$'\n'; _SYNC_FILL=$((_SYNC_FILL+1)); continue
      fi
      if git checkout "$REMOTE/$BRANCH" -- "$f" 2>/dev/null; then
        _SYNC_OK=$((_SYNC_OK+1))
      else
        echo "   ❌ $f"; _SYNC_FAIL=$((_SYNC_FAIL+1))
      fi
    done < <(git ls-tree -r --name-only "$REMOTE/$BRANCH" 2>/dev/null | while IFS= read -r _f; do _es_maquinaria "$_f" && printf '%s\n' "$_f"; done)

    echo "   ✓  $_SYNC_OK archivo(s) de maquinaria traídos del template"
    if [ "$_SYNC_FILL" -gt 0 ]; then
      echo ""
      echo "   🔒 $_SYNC_FILL archivo(s) NO tocados: el template los trae con FILL, o sea"
      echo "      que espera que TÚ los personalices. Pisarlos borraría tu configuración."
      printf '%s' "$_FILL_LIST" | sed 's/^/      · /'
      echo "      Si quieres las novedades del template en ellos, mézclalas a mano:"
      echo "      git diff HEAD $REMOTE/$BRANCH -- <archivo>"
    fi
    if [ "$_SYNC_FAIL" -gt 0 ]; then
      echo ""
      echo "❌ upgrade: $_SYNC_FAIL archivo(s) fallaron. El sync está INCOMPLETO — no lo" >&2
      echo "   commitees como si estuviera entero: arregla lo de arriba y re-córrelo." >&2
      _report_no_sincronizado "$BASE_REC"
      exit 1
    fi
  fi
  _fundir_settings || _SETTINGS_FAIL=1
  # Los docs son propiedad del adoptante, salvo el fragmento delimitado de
  # capacidades. Se funde de forma estructural: conserva toda su prosa y solo
  # instala/actualiza el bloque generado que exige el manifiesto transportado.
  if [ -f tools/render-capabilities.sh ] && [ -f tools/capabilities.json ]; then
    bash tools/render-capabilities.sh --install \
      || { echo "❌ upgrade: no pude fundir los bloques de capacidades en los docs locales." >&2; exit 1; }
  fi
  # ── project.conf: crearlo con valor inferido si falta (f-12b8155c) ──
  # WF-05 (PRD 0005 §6) lo prometía y no existía: el adoptante vivía con
  # project_kind sin declarar, cayendo a la heurística sin enterarse. Se crea
  # UNA vez, jamás se pisa (el conf es suyo y está fuera de SYNC_PATHS). La
  # inferencia es deliberadamente simple y AVISADA en el propio archivo: un
  # manifiesto de app en la raíz ⇒ application; si no, se deja `other` con la
  # instrucción de revisarlo — inventar un default silencioso sería peor.
  if [ ! -f tools/project.conf ]; then
    _PK="other"
    for _m in *.xcodeproj *.xcworkspace Package.swift package.json build.gradle build.gradle.kts pyproject.toml go.mod Cargo.toml pubspec.yaml; do
      [ -e "$_m" ] && { _PK="application"; break; }
    done
    # Sin manifiesto, la evidencia de WF-05: fuentes de app fuera del harness.
    if [ "$_PK" = "other" ] && find . \( -path ./tools -o -path ./scripts -o -path ./ci \
         -o -path ./docs -o -path ./.agents -o -path ./.git -o -path ./enterprise \
         -o -name fixtures \) -prune -o -type f \( -name '*.swift' -o -name '*.kt' \
         -o -name '*.ts' -o -name '*.tsx' -o -name '*.py' -o -name '*.go' -o -name '*.rb' \
         -o -name '*.cs' -o -name '*.rs' \) -print 2>/dev/null | head -1 | grep -q .; then
      _PK="application"
    fi
    {
      printf '# Creado por tools/upgrade.sh con valor INFERIDO (%s) — revísalo.\n' "$_PK"
      printf '# harness = este repo ES el harness · application = producto con app · other = doc-only/otros\n'
      printf '# Formato: `clave: valor`. Este archivo es TUYO: el sync jamás lo pisa.\n'
      printf 'project_kind: %s\n' "$_PK"
    } > tools/project.conf
    echo "   ✓ tools/project.conf creado (project_kind: $_PK, inferido — revísalo)."
  fi
  printf '%s  # SHA del template sincronizado por tools/upgrade.sh — no editar a mano\n' \
    "$(git rev-parse "$REMOTE/$BRANCH")" > "$SYNC_RECORD"
  git add -A -- $SYNC_PATHS tools .claude/settings.json "$SYNC_RECORD" 2>/dev/null
  _report_no_sincronizado "$BASE_REC"
  echo ""
  echo "━━━ Cambios traídos (staged, SIN commitear a propósito) ━━━"
  git diff --cached --stat | tail -20
  echo ""
  echo "   Revísalos y commitea tú:  git commit -m \"chore(template): sync de maquinaria\""
  echo ""
  echo "   ⚠️  LO QUE ACABAS DE TRAER NO ESTÁ VERIFICADO TODAVÍA. Esta salida se"
  echo "   produce antes de cualquier verificación, y el camino al-día de este"
  echo "   script NO la ejecuta (f-f238608c: una versión anterior de este aviso"
  echo "   mandaba re-correr el script, y ese re-run decía 'al día' sin verificar"
  echo "   nada — el adoptante que lo siguió tenía 24 tests en rojo). La evidencia"
  echo "   la produces TÚ tras commitear:"
  echo "      bash tools/tests/run-tests.sh && bash tools/validate-harness.sh --selftest"
  [ "${_SETTINGS_FAIL:-0}" = "1" ] && exit 1
  exit 2
fi

# ── Verificación: el upgrade no cuenta hasta que la evidencia lo diga ─
# Con --selftest: cada detector debe DEMOSTRAR una detección real tras el
# merge, no solo existir. Es la red contra el modo de fallo más caro de un
# upgrade: un archivo del template que REVIERTE un arreglo local en silencio
# (pasó en vivo con semgrep-scan.sh — un snapshot viejo borró el split de
# .errors[] y solo lo cazó un test que ese arreglo había dejado detrás).
echo ""
echo "━━━ verificando el harness tras el upgrade ━━━"
FAIL=0
bash tools/tests/run-tests.sh >/dev/null 2>&1 || { echo "❌ la suite del harness FALLA tras el merge."; FAIL=1; }
bash tools/validate-harness.sh --selftest >/dev/null 2>&1 || { echo "❌ validate-harness --selftest FALLA tras el merge."; FAIL=1; }
if [ "$FAIL" = "1" ]; then
  echo ""
  echo "   El merge quedó commiteado pero el harness NO está sano. Opciones:"
  echo "   · arregla lo roto ahora (corre los dos comandos de arriba sin >/dev/null y mira), o"
  echo "   · decisión del owner: deshacer con  git reset --hard ORIG_HEAD  (destruye el merge)."
  exit 1
fi
echo "✅ upgrade verificado: suite en verde + validate-harness --selftest OK."
echo "   Repasa 'git show --stat HEAD' y, si un cambio del template pisó un FILL tuyo"
echo "   que git fundió sin conflicto, es un buen momento para revisarlo."
echo ""
echo "   ⚠️  REGLA DE ORO DEL FLUJO INVERSO: si algún archivo del harness te llega"
echo "   por FUERA de este script (copiado a mano, pegado, traído por un puente),"
echo "   corre inmediatamente:  bash tools/tests/run-tests.sh && bash tools/validate-harness.sh --selftest"
echo "   Un archivo que entra sin pasar por aquí se salta esta red — y un arreglo"
echo "   local sin test propio puede quedar revertido EN SILENCIO. Corolario:"
echo "   toda divergencia local deliberada lleva SU test, que es lo que la hace"
echo "   sobrevivir a un cp descuidado (lección 2026-08-09 del primer proyecto)."
exit 0

#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# scope.sh — qué cuenta como PRODUCTO en este repo (fuente única)
# ════════════════════════════════════════════════════════════════════
# La comparten `check-review-marker.sh` y `check-verify-marker.sh`. Antes el
# segundo GREPEABA la línea del primero para no duplicar la lista: funcionaba,
# pero acoplaba dos scripts por el texto de una línea. Aquí vive una vez.
#
# ── Por qué hay dos respuestas y no una ─────────────────────────────
# En un proyecto de app, `tools/` y `scripts/` son ANDAMIO: exigir review por
# tocar un script del harness sería ruido, y el ruido acaba en un
# `REVIEWER_OVERRIDE` de costumbre que apaga el gate de verdad (ley del 10%).
#
# En el repo del PROPIO harness, esos directorios son el PRODUCTO. Medido por un
# adoptante que auditó nuestro historial: **15 commits seguidos sin que el
# reviewer-gate disparara ni una vez**, incluidos el que invirtió la política de
# seguridad de AGENTS.md §6 y el que metió un gate bloqueante nuevo al Anillo 3.
# Salió bien por disciplina del agente (12 invocaciones voluntarias), no por el
# mecanismo. Dicho del modo más incómodo posible: **nuestro propio reviewer-gate
# no había bloqueado un commit en su vida.**
#
# ── Cómo se decide (WF-05, PRD 0005 §6): la DECLARACIÓN gobierna ────
# `tools/project.conf` declara `project_kind: harness|application|other`
# (propiedad del adoptante, fuera del sync — mismo modelo que tools/preset).
# La evidencia (¿hay fuentes de app?) solo VERIFICA: una contradicción
# declarado-vs-evidencia AVISA (y en CI devuelve exit 3), pero JAMÁS cambia
# el criterio — un monorepo con `packages/` declarado `application` obtiene
# el criterio de app sin que ninguna heurística lo discuta.
#
# Sin declaración, el fallback es la heurística de siempre (cero falsos
# positivos nuevos en adoptantes existentes), y el diagnóstico "declara tu
# kind" lo emite session-start UNA vez por sesión — nunca cada commit.

_SCOPE_CONF="tools/project.conf"

# ── De dónde se LEE la declaración, que resultó ser lo importante ───
# Del ÍNDICE (o de HEAD), nunca del árbol de trabajo. La primera versión hacía
# `grep` sobre el archivo en disco, y eso abría un bypass completo del gate,
# reproducido en vivo: editas `project_kind: application`, NO lo stageas, y
# `check-review-marker` pasa de exit 1 a exit 0 declarando "el cambio no toca
# código de producto" — con el diff resultante sin una sola línea de
# project.conf. Sin override, sin entrada en override_log, sin rastro.
#
# El principio general, que vale para cualquier gate: **lo que decide sobre un
# diff se lee de la misma fuente que ese diff.** Si el gate juzga lo staged,
# su configuración se lee del índice; si juzga un rango, de su base. Leer del
# árbol de trabajo deja la decisión en manos de un archivo que no va a viajar
# con el commit, y eso no es una config: es una puerta trasera.
#
# Es la misma clase que f-cb48c808 (el marker firma un diff distinto del
# revisado), atacando la clasificación de scope en vez del binding sha256.
_scope_lee_conf() { # → contenido de project.conf desde la fuente que toca
  # Modo rango (Anillo 3): la declaración es la de la base del rango.
  if [ -n "${SCOPE_BASE_REF:-}" ]; then
    git show "${SCOPE_BASE_REF}:${_SCOPE_CONF}" 2>/dev/null && return 0
  fi
  # Modo normal: el índice. Si el archivo no está trackeado todavía —primer
  # arranque de un adoptante, o el sandbox de un test— no hay nada en el índice
  # y se cae al disco A PROPÓSITO: sin declaración trackeada la tabla de §6 ya
  # exige el fallback heurístico, y un `git show` fallido no debe convertirse en
  # "sin declaración" cuando el archivo sí existe y aún nadie lo commiteó.
  if git ls-files --error-unmatch "$_SCOPE_CONF" >/dev/null 2>&1; then
    git show ":${_SCOPE_CONF}" 2>/dev/null && return 0
  fi
  [ -f "$_SCOPE_CONF" ] && cat "$_SCOPE_CONF" 2>/dev/null
  return 0
}

_scope_project_kind() { # → harness|application|other, o vacío (ausente/ilegible)
  local k
  k="$(_scope_lee_conf | grep -E '^project_kind:' 2>/dev/null | head -1 \
        | sed -E 's/^project_kind:[[:space:]]*//' | awk '{print $1}')"
  case "$k" in harness|application|other) printf '%s' "$k" ;; esac
  return 0
}

# ── La EVIDENCIA, definida (PRD 0005 §6, literal) ───────────────────
# "fuentes de app" = archivos *.swift|kt|java|ts|tsx|js|py|go|rb|cs|rs bajo
# CUALQUIER ruta del repo EXCEPTO tools/ scripts/ ci/ docs/ .agents/
# enterprise/ y **/fixtures/. Cubre monorepos (packages/, services/) y no
# cuenta los .py ni los fixtures del propio harness — los dos contraejemplos
# que tumbaron a la heurística de directorios fijos (hallazgo 1).
_scope_fuentes_de_app() { # → imprime la primera fuente de app hallada (vacío si no hay)
  find . \( -path './.git' -o -path './tools' -o -path './scripts' \
            -o -path './ci' -o -path './docs' -o -path './.agents' \
            -o -path './enterprise' -o -name 'fixtures' \) -prune -o \
       -type f \( -name '*.swift' -o -name '*.kt' -o -name '*.java' \
            -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.py' \
            -o -name '*.go' -o -name '*.rb' -o -name '*.cs' -o -name '*.rs' \) \
       -print 2>/dev/null | head -1
}

# ── Heurística vieja: SOLO como fallback sin declaración ────────────
# Un repo cuyo producto es el harness NO TIENE fuentes de aplicación en los
# directorios convencionales. Es el mismo discriminador que usa
# `verify-run.sh` para detectar un `verify.conf` heredado. Se conserva
# INTACTA para el adoptante que aún no declaró: su comportamiento no cambia
# ni un byte (lo fija test_scope_kind.sh).
_repo_es_el_harness() {
  local p
  p="$(find ios android web src app lib Sources -type f \
        \( -name '*.swift' -o -name '*.kt' -o -name '*.java' -o -name '*.ts' \
           -o -name '*.tsx' -o -name '*.js' -o -name '*.py' -o -name '*.go' \
           -o -name '*.rb' -o -name '*.cs' -o -name '*.rs' \) 2>/dev/null | head -1)"
  [ -z "$p" ]
}

# Proyecto de app: el andamio no exige review.
_NON_PRODUCT_APP='^(docs/|ci/|\.github/|tools/|scripts/|backlog/|enterprise/|\.claude/|\.claude-plugin/|\.codex/|\.cursor/|\.agents/|README|LICENSE|CODEOWNERS|\.gitignore|\.editorconfig|\.gitattributes|lefthook|\.gitleaks|\.semgrepignore|muter\.conf|AGENTS\.md|CLAUDE\.md|GEMINI\.md|(ios|android|web|backend)/AGENTS\.md$)'

# Repo del harness: producto = lo que EJECUTA (tools/, scripts/, ci/, lefthook)
# y lo que es NORMATIVO para los adoptantes (AGENTS.md). Siguen exentos la prosa
# y los REGISTROS: `docs/`, `backlog/`, `README`, y los dos ledgers, que son
# generados o anotados y pedirían un reviewer por cada lección apuntada — eso
# sí sería el ruido que mata el gate.
_NON_PRODUCT_HARNESS='^(docs/|backlog/|enterprise/|\.github/|\.claude/|\.claude-plugin/|\.codex/|\.cursor/|\.agents/|README|LICENSE|CODEOWNERS|\.gitignore|\.editorconfig|\.gitattributes|\.gitleaks|\.semgrepignore|muter\.conf|CLAUDE\.md|GEMINI\.md|tools/findings/ledger\.jsonl$|(ios|android|web|backend)/AGENTS\.md$)'

# ── Las llaves del reino NUNCA se eximen a sí mismas ────────────────
# `tools/project.conf` vive bajo `tools/`, y el criterio de app exime `tools/`.
# Eso hacía que la DECLARACIÓN se auto-eximiera: bastaba stagear el flip a
# `application` junto al cambio y el gate aplicaba el criterio NUEVO al propio
# flip que lo introducía. Reproducido: exit 1 → exit 0 en el mismo commit, sin
# override y sin entrada en override_log.
#
# La primera versión de este arreglo solo cerró la variante SIN stagear (leer
# del índice en vez del disco). Cerrar media puerta es no cerrarla: quedaba la
# variante que además deja el flip A LA VISTA dentro del commit y aun así pasa.
#
# Estos tres archivos deciden SI un gate aplica, así que son producto bajo
# cualquier criterio. No se pueden restar de la ERE de exentos —ERE no tiene
# lookahead—, así que se declaran aparte y los consumidores los vuelven a SUMAR
# después de filtrar. Es más verboso y es a propósito: la resta silenciosa es
# lo que abrió el agujero.
# ── La SUPERFICIE DE ENFORCEMENT nunca es andamio ───────────────────
# Esta lista se quedó corta CINCO veces seguidas. El historial se deja escrito
# porque el patrón vale más que el arreglo:
#   1ª  `project.conf` leído del disco             → flip sin stagear
#   2ª  `project.conf` bajo `tools/`, exento       → flip stageado
#   3ª  los propios scripts del gate, exentos      → editas el gate y se exime solo
#   4ª  `.claude/agents/reviewer.md` (¡el revisor!), `.github/workflows/` y
#       `.codex/`+`.cursor/` — se protegió UN cliente y se dejaron los otros dos
#   5ª  `.gitleaks.toml` y `.semgrepignore` — el gate de SECRETOS, Anillo 1, el
#       de más leverage de todos: añades un path al `allowlist` y no pide review
#
# Las cinco fallaron por lo mismo: **la clasificación era fail-OPEN**. Lo no
# enumerado quedaba exento, así que cada ronda tapaba el agujero recién visto y
# dejaba abierto el siguiente. Ahora los patrones son de FORMA, no de nombre —
# `tools/*.sh`, `tools/*.conf`, `scripts/`, `ci/`— para que un gate nuevo quede
# cubierto el día que se crea y no el día que alguien lo explote.
#
# La propiedad: **todo lo que decide si un gate aplica, lo implementa, lo
# configura, o lo cablea a un cliente, es producto — gobierne quien gobierne el
# resto del repo.** Ante la duda sobre un archivo la pregunta no es "¿es código
# de la app?" sino "¿degradarlo debilita una defensa?".
#
# Bajo `tools/` NO vale `*.sh` a secas, y esto es un límite deliberado: en un
# proyecto de app, `tools/deploy.sh` es tooling del adoptante, no un gate, y
# tratarlo como producto rompía la promesa de la fase 1b (cero falsos positivos
# nuevos para quien no declara nada) — lo cazó su propio test. Así que el patrón
# sigue la CONVENCIÓN DE NOMBRES del harness (`check-`, `verify-`, `secret-`,
# `mutation-`, `drift-`, `semgrep-`, `architecture-`, `probe-`, `gate-`), que un
# gate nuevo hereda y un script del adoptante no.
#
# Y NO se afirma aquí que la lista esté completa. La versión anterior decía
# "para que no haya quinta" y la quinta llegó en la misma sesión — prometer
# exhaustividad en un comentario es justo la clase de afirmación sin test que
# este repo persigue. Lo que sí se sostiene: los tests de `test_scope_kind.sh`
# fijan las cinco vías conocidas, y **un gate con nombre fuera de la convención
# hay que añadirlo aquí, con su test, el día que se escribe.**
scope_siempre_producto() { # → ERE de FORMAS que exigen review, gobierne quien gobierne
  printf '%s' '^(tools/(check|verify|secret|mutation|drift|semgrep|architecture|probe|gate|lesson)-[^/]*|tools/tests/run-tests\.sh$|tools/[^/]*\.conf$|tools/preset$|tools/lib/|tools/semgrep/|lefthook|\.gitleaks|\.semgrepignore$|ci/|\.github/workflows/|\.claude/settings\.json$|\.claude/agents/|\.codex/|\.cursor/|scripts/agent-hooks/)'
}

scope_non_product() {
  case "$(_scope_project_kind)" in
    harness)           printf '%s' "$_NON_PRODUCT_HARNESS" ;;
    # `other` = exención amplia estilo app (AMBER-5): en un repo doc-only sus
    # directorios de contenido no exigen review; quien quiera review sobre
    # docs declara `harness`. La tabla de §6 le asigna el criterio de app.
    application|other) printf '%s' "$_NON_PRODUCT_APP" ;;
    *) if _repo_es_el_harness; then printf '%s' "$_NON_PRODUCT_HARNESS"
       else printf '%s' "$_NON_PRODUCT_APP"; fi ;;
  esac
}

# ── Verificación declarado-vs-evidencia (corre al SOURCEAR) ─────────
# Vive en el top-level del source y no dentro de `scope_non_product` porque
# los consumidores llaman a esa función en un `$(…)`: un exit ahí muere en la
# subshell y el gate ni se entera. Al ejecutarse cuando el gate hace
# `. tools/lib/scope.sh`, el `exit 3` de CI llega al proceso del gate
# (contrato de detectores 0/1/3) sin editar a ningún consumidor.
#
# Solo en CI se corta (CI=true o cualquier GATES_* en el entorno): en local la
# contradicción avisa por stderr y el commit sigue — bloquear en la máquina
# del adoptante por una línea de conf sería el ruido que apaga gates.
# SCOPE_NO_CI_EXIT=1 es la vía de CONSULTA (session-start): jamás sale.
_scope_en_ci() {
  [ "${CI:-}" = "true" ] && return 0
  local vars; vars="$(env | grep '^GATES_' || true)"
  [ -n "$vars" ]
}

_scope_verifica_declaracion() {
  local k ev
  k="$(_scope_project_kind)"
  case "$k" in
    harness)
      ev="$(_scope_fuentes_de_app)"
      [ -n "$ev" ] || return 0 ;;
    application)
      ev="$(_scope_fuentes_de_app)"
      [ -z "$ev" ] || return 0
      ev="(ninguna)" ;;
    *) return 0 ;;  # other: cualquier evidencia vale (§6) · sin declarar: heurística
  esac
  {
    printf 'SCOPE_SUMMARY kind=%s evidencia=contradice\n' "${k}"
    if [ "${k}" = "harness" ]; then
      printf '⚠️  scope: project_kind=harness declarado, pero HAY fuentes de app (p.ej. %s).\n' "${ev#./}"
      printf '   ¿Adopción por copia sin el flip? Corrige tools/project.conf (application u other).\n'
    else
      printf '⚠️  scope: project_kind=application declarado, pero NO hay ni una fuente de app.\n'
      printf '   Si este repo es el harness o doc-only, corrige tools/project.conf (harness u other).\n'
    fi
    printf '   La declaración MANDA (se aplica su criterio); en CI esto devuelve exit 3.\n'
  } >&2
  # El corte de CI exige además el conf TRACKEADO. En un checkout real de CI
  # todo archivo lo está, así que ahí esto no cambia nada; un conf sin
  # trackear delata un SANDBOX (selftest de validate-harness, suites) al que
  # CI=true le llegó heredado del entorno — cortar ahí con 3 rompería esos
  # fixtures por la razón equivocada. El aviso de arriba se emite igual.
  # Lo fija test_scope_kind.sh::test_conf_sin_trackear_con_ci_heredado_no_corta.
  if _scope_en_ci && [ "${SCOPE_NO_CI_EXIT:-0}" != "1" ] \
     && git ls-files --error-unmatch "$_SCOPE_CONF" >/dev/null 2>&1; then
    exit 3
  fi
  return 0
}
_scope_verifica_declaracion

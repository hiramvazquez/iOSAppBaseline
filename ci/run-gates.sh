#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# ci/run-gates.sh — Anillo 3 (CI), PROVIDER-AGNÓSTICO
# ════════════════════════════════════════════════════════════════════
# Punto de entrada ÚNICO de los gates server-side. Lo invoca CUALQUIER CI
# (GitHub, GitLab, Bitbucket, Azure, Jenkins) o nada. No imponemos proveedor.
#
# Es el backstop que cubre lo que los hooks locales NO pueden:
#   - Codex/Cursor (hooks parciales) → completa aquí los eventos/veredictos ausentes.
#   - commits humanos con `--no-verify`.
#   - máquinas sin lefthook instalado.
#
# Orden: de lo más barato y determinista a lo más caro y probabilístico.
# Un fallo en un gate barato hace innecesario correr los caros.
#
# ⚠️  ESTE SCRIPT ES FAIL-CLOSED. Es el único anillo que no depende de que el
# agente se porte bien, así que una herramienta ausente NO puede leerse como
# "gate aprobado". En local los gates avisan; aquí bloquean.
# (La versión inicial solo forzaba semgrep, mientras el PRD §7 prometía los tres.
#  En un runner con gitleaks pero sin `claude`, reportaba "✅ TODOS los gates
#  pasaron" para un commit de Codex que no había pasado por ninguna revisión.
#  Lo cazó el `reviewer` revisando P1.)
#
# Variables (todas con default FAIL-CLOSED; ponlas a 0 para renunciar a un gate
# de forma consciente y visible en la config de tu CI):
#   GATES_SECRET_MODE         history|range|all   (default: history)
#   GATES_BASE_REF            rama base           (default: origin/main)
#   GATES_SKIP_TESTS=1        salta build+tests
#   (GATES_REQUIRE_BUILD ya NO existe: el paso 6 es incondicionalmente
#    fail-closed. Antes el build era opt-in, lo cual contradecía la doctrina —
#    "un gate que no corrió nunca debe parecer un gate que pasó" — justo en el
#    gate más barato y definitivo de todos. Se anota la baja aquí, en la lista
#    de variables, que es donde alguien iría a buscarla.)
#   GATES_REQUIRE_SEMGREP     default 1
#   GATES_REQUIRE_SOURCE_SETS default: 1 si tools/project.conf registra que semgrep
#                             analizó Kotlin aquí alguna vez, si no 0 (un exit 3 del
#                             detector KMP avisa hasta entonces, y bloquea después)
#   GATES_REQUIRE_MUTATION    default: 1 si el piso > 0, si no 0 (durante el
#                             rollout el piso arranca en 0 y el gate no dice nada;
#                             en cuanto mides una vez, medir pasa a ser obligatorio)
#   AI_REVIEW_REQUIRED        default 1
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1
AI_BACKEND=claude
while [ $# -gt 0 ]; do
  case "$1" in
    --backend) [ $# -ge 2 ] || { echo "run-gates: falta backend" >&2; exit 3; }; AI_BACKEND="$2"; shift 2 ;;
    *) echo "run-gates: argumento desconocido: $1" >&2; exit 3 ;;
  esac
done
FAIL=0
step() { echo ""; echo "━━━ $1 ━━━"; }

# ════════════════════════════════════════════════════════════════════
# Nivel 0-2 — deterministas y baratos
# ════════════════════════════════════════════════════════════════════

# 1) Tests del propio HARNESS. Van PRIMERO: si los gates están rotos, nada
#    de lo que diga el resto de este script significa algo.
step "1/8 tests del harness"
if [ -f tools/tests/run-tests.sh ]; then
  bash tools/tests/run-tests.sh || FAIL=1
else
  echo "(sin tests de harness — tools/tests/run-tests.sh ausente)"
fi

# 2) Secretos — OBLIGATORIO en CI (a diferencia de local, aquí sí bloquea).
#
# ⚠️ MODO `range`, NO `history`, y la razón importa: este paso responde a
# "¿ESTE cambio mete un secreto?". El historial completo responde a otra
# pregunta —"¿queda algo enterrado de antes?"— y responderla en cada PR tiene
# un efecto perverso demostrado en vivo: un hallazgo antiguo (en el template,
# el literal del simulacro de ADOPTION §7, del commit de scaffold) deja el paso
# 2 en ROJO PERPETUO para el repo y para todos sus clones. Y un gate siempre
# rojo es peor que un gate ausente: se aprende a ignorar, y con él se ignora el
# rojo del día que sí importa (ley del 10%, AGENTS §14.2).
#
# El historial se escanea donde corresponde: UNA vez al adoptar y luego en un
# job PROGRAMADO (`GATES_SECRET_MODE=history`), donde un hallazgo se tría una
# vez y se registra en `.gitleaks-baseline.json` — ver `tools/secret-baseline.sh`.
# El secreto que se introduce HOY lo cazan igual el Anillo 1 (pre-commit) y
# este paso; el historial no añade nada a esa pregunta.
step "2/8 secret-scan (gitleaks · modo ${GATES_SECRET_MODE:-range})"
if command -v gitleaks >/dev/null 2>&1; then
  bash tools/secret-scan.sh "--${GATES_SECRET_MODE:-range}"; _rc=$?
  # exit 3 = "el detector no pudo mirar" (rango irresoluble). En CI eso BLOQUEA:
  # el fail-open local de §14.3 solo es legítimo porque este backstop existe.
  [ "$_rc" -ne 0 ] && FAIL=1
else
  echo "❌ gitleaks ausente en CI — instálalo en el runner (es obligatorio aquí)."; FAIL=1
fi

# 3) Patrones semánticos (Semgrep/AST) — reemplaza los greps frágiles.
step "3/8 semgrep (patrones AST)"
# En CI, exit 1 (hallazgo) y exit 3 (el detector no pudo correr) fallan IGUAL:
# aquí sí es fail-closed. En local el 3 solo avisa, para no crear un deadlock
# donde un typo en las reglas impide el commit que lo arregla.
if [ -f tools/semgrep-scan.sh ]; then
  bash tools/semgrep-scan.sh; _rc=$?
  if [ "${GATES_REQUIRE_SEMGREP:-1}" = "1" ]; then
    [ "$_rc" -ne 0 ] && FAIL=1
  else
    [ "$_rc" = "1" ] && FAIL=1   # opt-out: solo los hallazgos reales bloquean
  fi
else
  echo "❌ tools/semgrep-scan.sh ausente — el nivel 2 de la pirámide no existe."; FAIL=1
fi

# ════════════════════════════════════════════════════════════════════
# Nivel 3-6 — arquitectura, deuda y CALIDAD DE LOS TESTS
# ════════════════════════════════════════════════════════════════════

# 4) Capas: dirección de imports directos (sin grafo/ciclos; AGENTS.md §3).
step "4/8 check-layers (arquitectura)"
if [ -f tools/check-layers.sh ]; then
  bash tools/check-layers.sh || FAIL=1
else
  echo "(tools/check-layers.sh ausente — saltado)"
fi

# 4b) El SEGUNDO eje, el que el grafo por directorio no ve: en KMP, commonMain
#     no puede importar plataforma. Inerte y silencioso en repos sin commonMain
#     (estado `no-aplica`, exit 0): la mitad de los adoptantes no usa KMP y un
#     aviso permanente para ellos se aprende a ignorar.
if [ -f tools/check-source-sets.sh ]; then
  # Auto-escalada, misma forma que mutation (paso 7): mientras nadie haya visto a
  # semgrep analizar Kotlin en ESTE repo, un exit 3 es una limitación honesta del
  # entorno y solo avisa. En cuanto el propio detector registró `source_sets_semgrep:
  # operativo` en tools/project.conf —commiteado, así que viaja al checkout de CI—,
  # un "no pude mirar" pasa a ser una REGRESIÓN y bloquea: si no, bastaría
  # desinstalar semgrep para que el gate dejara de tener opinión.
  _ss_req="${GATES_REQUIRE_SOURCE_SETS:-}"
  if [ -z "$_ss_req" ]; then
    if grep -q '^source_sets_semgrep:[[:space:]]*operativo' tools/project.conf 2>/dev/null
    then _ss_req=1; else _ss_req=0; fi
  fi
  GATES_REQUIRE_SOURCE_SETS="$_ss_req" bash tools/check-source-sets.sh; _ss_rc=$?
  # 1 = tu código tiene un problema · 3 = el detector no pudo mirar. Los dos
  # bloquean en CI (que es el backstop), pero se DICEN distinto: confundirlos
  # manda a alguien a buscar un import que no existe (§14.3).
  case "$_ss_rc" in
    0) ;;
    3) echo "   (exit 3: el detector no pudo mirar. En CI eso bloquea.)"; FAIL=1 ;;
    *) FAIL=1 ;;
  esac
fi

# 5) Drift ratchet — el conteo no puede haber subido.
step "5/8 drift-ratchet"
bash tools/drift-ratchet.sh --check || FAIL=1

# 6) Build + tests por-plataforma.
step "6/8 build & tests"
if [ "${GATES_SKIP_TESTS:-0}" = "1" ]; then
  echo "(saltado por GATES_SKIP_TESTS=1)"
else
  # El comando vive en `tools/verify.conf` — FUENTE ÚNICA, compartida con el
  # gate local (`tools/verify-run.sh`). Antes era un FILL aquí dentro: solo en
  # CI, y en local NADA ataba un build verde al diff que se commiteaba.
  bash tools/verify-run.sh --ci; _rc=$?
  # exit 3 = sin comando cableado. En CI eso BLOQUEA: un repo donde nadie
  # compila no puede dar el job por verde (§14.3 — el fail-open local solo es
  # legítimo porque este backstop existe).
  [ "$_rc" -ne 0 ] && FAIL=1
fi

# 7) Mutation score — ¿los tests COMPRUEBAN algo?
#    La cobertura es un piso; ESTA es la métrica real. Es el único gate que
#    distingue un test que verifica de uno que solo pasa — el modo de fallo
#    más común del código escrito por agentes.
step "7/8 mutation-score (calidad de los tests)"
if [ -f tools/mutation-score.sh ]; then
  # Auto-escalada: mientras el piso sea 0 el gate no dice nada y no bloquea por
  # falta de runner. En cuanto hay una medición real (piso > 0), medir pasa a
  # ser obligatorio — si no, bastaría desinstalar el runner para "aprobar".
  _floor="$(sed -nE 's/.*"min_score"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' tools/mutation-ratchet.json 2>/dev/null | head -1)"
  : "${_floor:=0}"
  _req="${GATES_REQUIRE_MUTATION:-}"
  [ -z "$_req" ] && { [ "$_floor" -gt 0 ] && _req=1 || _req=0; }
  GATES_REQUIRE_MUTATION="$_req" bash tools/mutation-score.sh --check || FAIL=1
  [ "$_req" = "0" ] && echo "   (piso=0: gate informativo. Sube el piso y pasa a obligatorio automáticamente.)"
else
  echo "❌ tools/mutation-score.sh ausente — sin él nada distingue un test real de uno decorativo."; FAIL=1
fi

# ════════════════════════════════════════════════════════════════════
# Nivel 7-9 — review independiente, evidencia y aprendizaje
# ════════════════════════════════════════════════════════════════════
step "8/8 review independiente + evidencia"

# 8a) ¿Fue revisado? Cubre Codex y commits humanos, que nunca pasan por Anillo 2.
if [ -f tools/check-review-marker.sh ]; then
  bash tools/check-review-marker.sh --range \
    || echo "   (sin marker válido en CI — la evidencia la aporta ai-review, abajo)"
fi

# 8b) Review de IA headless, con contexto FRESCO: el que revisa nunca es el que
#     escribió. Es lo que cierra el hueco de Codex y de los commits humanos, así
#     que es OBLIGATORIO por defecto: si fuera opt-in, un runner sin `claude`
#     aprobaría en silencio justo los commits que este anillo existe para cubrir.
if [ -f ci/ai-review.sh ]; then
  AI_REVIEW_REQUIRED="${AI_REVIEW_REQUIRED:-1}" \
    bash ci/ai-review.sh --backend "$AI_BACKEND" || FAIL=1
else
  echo "❌ ci/ai-review.sh ausente — sin él, Codex y los commits humanos no pasan por ninguna review."; FAIL=1
fi

# 8c) Toda lección aprendida debe tener un detector mecánico asociado. Es el
#     mecanismo concreto por el que la necesidad de review humano DECRECE en
#     vez de mantenerse plana (filosofía Tricorder: un comentario de review
#     que se repite es un bug en tu tooling).
if [ -f tools/lesson-detector-link.sh ]; then
  bash tools/lesson-detector-link.sh || FAIL=1
fi

# 8e) El ledger solo vale si lo que dice se puede COMPROBAR. Dos formas de que
#     deje de valer sin que nadie lo note, cada una con su check:
#       · una cita a un id que no existe → lee como cerrado, y nadie reabre el
#         tema: el hallazgo se evaporó con el aspecto de haberse cerrado.
#       · un hallazgo que declara una herramienta incapaz citando al gestor de
#         paquetes → `brew` sirve el último RELEASE, no lo que soporta el
#         proyecto. Pasó aquí: el nivel 4 se dio por imposible durante semanas
#         con el arreglo ya en `main` del repositorio.
#     Van en el Anillo 3 y en la suite (que corre en pre-push), NO en
#     pre-commit: leen el árbol entero, no el diff staged, así que en cada
#     commit bloquearían por algo que ni siquiera has stageado — el falso
#     positivo que acaba con un `--no-verify` de costumbre (ley del 10%).
# Invocación EXPLÍCITA, no un `for` con `bash "$_chk"`. El bucle era más corto y
# creaba un punto ciego: `test_scope_superficie.sh` deriva la superficie de
# enforcement de lo que ESTE archivo invoca, y solo ve el patrón literal
# `bash <ruta>`. Un gate cableado por indirección quedaba fuera de esa lista sin
# que nada avisara — y peor, el hueco no se notaba porque los tres de aquí
# empiezan por `check-` y la convención de nombres los cubría por casualidad.
# Un cuarto gate con otro nombre habría entrado invisible.
# Se prefiere repetir tres líneas a que el detector mienta (§14.4).
# Y NO vale envolverlo en un helper que haga `bash "$1"`: ese fue mi primer
# intento de arreglo y reintroducía el mismo punto ciego con otra forma. La
# invocación tiene que ser literal para que el detector la vea.
# exit 3 = no pude mirar (sin ledger, sin python3). En CI bloquea, como el resto
# de los gates de este anillo (§14.3).
[ -f tools/check-finding-refs.sh ]   && { bash tools/check-finding-refs.sh   || FAIL=1; }
[ -f tools/check-version-claims.sh ] && { bash tools/check-version-claims.sh || FAIL=1; }
[ -f tools/check-execution-map.sh ]  && { bash tools/check-execution-map.sh  || FAIL=1; }

# 8d) Contención por fase — INFORMATIVO, nunca bloquea.
#     No es un gate: es el termómetro que dice si los gates sirven. Va aquí
#     porque una métrica que hay que acordarse de correr no se corre nunca
#     (vivió meses como script huérfano: cero llamadas desde el informe, desde
#     run-gates y desde CI). Bloquear con ella sería un error opuesto: penaliza
#     al que detecta más, y el objetivo es que detectar salga barato.
if [ -f tools/metrics/escape-rate.sh ]; then
  echo ""
  step "métrica (informativa) — contención por fase"
  bash tools/metrics/escape-rate.sh 2>&1 | head -20 || true
fi

echo ""
[ "$FAIL" -eq 0 ] && { echo "✅ run-gates: TODOS los gates pasaron."; exit 0; }
echo "❌ run-gates: al menos un gate falló (ver arriba)."; exit 1

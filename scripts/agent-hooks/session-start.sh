#!/usr/bin/env bash
# Hook SessionStart, matcher startup|clear (Claude). Con `--report`, matcher resume.
# Tabula rasa por sesión: borra markers de skills leídos + baseline de drift,
# e imprime el estado del proyecto. Observe-only (no bloquea nunca).
#
#   sin args    → reset + reporte   (lo que invoca el hook en startup|clear)
#   --report    → SOLO reporte, sin efectos secundarios (resume, o humano mirando)
#
# El modo --report existe porque observar no puede modificar: ejecutar este
# script "para ver el estado" borraba los markers de skills leídas a mitad de
# sesión y el siguiente Edit quedaba bloqueado — nos pasó (f-session-start-fx).
# Un script que un humano ejecuta para inspeccionar necesita un modo puro.
#
# DEFENSA EN PROFUNDIDAD sobre `source`: aunque settings.json ya enruta por
# matcher (startup|clear → reset · resume → --report · compact → post-compact),
# este script re-verifica el `source` del payload. Si un wrapper mal configurado
# lo invoca en `compact`, resetear aquí re-basearía el drift INCLUYENDO los
# errores que el agente acabara de introducir — pasarían a baseline y jamás se
# bloquearían. Fijado por tools/tests/test_session_start.sh.
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_ROOT" || exit 0

MODE="${1:---reset}"

# El payload del hook llega por stdin; un humano invocando a mano no lo tiene.
# Solo leemos stdin si NO es un TTY (evita colgar la invocación manual).
HOOK_SOURCE=""
if [ ! -t 0 ]; then
  _input="$(cat 2>/dev/null || true)"
  if [ -n "$_input" ] && command -v jq >/dev/null 2>&1; then
    HOOK_SOURCE="$(printf '%s' "$_input" | jq -r '.source // empty' 2>/dev/null || true)"
  fi
fi
case "$HOOK_SOURCE" in
  compact|resume) MODE="--report" ;;
esac

state_dir=".agents/state"
mkdir -p "$state_dir/skills-read" "$state_dir/markers" "$state_dir/trajectory"

# ── HEAD de arranque: el insumo del juez es un RANGO, no una sesión ──
# `session-end` decidía si encolar mirando si el árbol quedó SUCIO. O sea que
# la sesión que cierra bien —commitea y deja limpio— era exactamente la que
# nunca se encolaba, y el juez auditaba sistemáticamente a quien no trabajó
# (medido: la cola apuntaba a una sesión con 7 tool-calls y CERO ediciones,
# mientras las dos que escribieron el adapter no entraron).
# Con el HEAD de arranque guardado, el cierre puede preguntar lo que importa:
# ¿esta sesión produjo commits? Y deja además el rango exacto que el juez debe
# mirar, mejor insumo que un id de sesión cuya trayectoria tiene huecos.
_SH_REC="$state_dir/session-head.txt"
_SH_SID="$(printf '%s' "${_input:-}" | jq -r '.session_id // empty' 2>/dev/null || true)"
: "${_SH_SID:=manual}"
if ! grep -qxF "sid: ${_SH_SID}" "$_SH_REC" 2>/dev/null; then
  {
    printf 'sid: %s\n' "$_SH_SID"
    printf 'head: %s\n' "$(git rev-parse HEAD 2>/dev/null || echo '')"
    printf 'branch: %s\n' "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    printf 'at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$_SH_REC" 2>/dev/null || true
fi
if [ "$MODE" != "--report" ]; then
  # Reset: obliga a re-leer las skills requeridas en cada sesión nueva.
  find "$state_dir/skills-read" -mindepth 1 -delete 2>/dev/null || true
  rm -f "$state_dir/drift-baseline.txt" "$state_dir/drift-baseline.head" 2>/dev/null || true
  # Purga el marker de review si ya EXPIRÓ (TTL 3600s por defecto): un marker
  # zombi de otra sesión no valida nada, pero convierte el error del gate en
  # un confuso "EXPIRADO" en vez del claro "no hay review" — despistó al owner
  # dos veces en vivo. Uno vigente se respeta (sobrevive a un restart rápido).
  _mk="$state_dir/markers/reviewer_run.txt"
  if [ -f "$_mk" ]; then
    _mt=$(stat -c %Y "$_mk" 2>/dev/null || stat -f %m "$_mk" 2>/dev/null || echo 0)
    case "$_mt" in ''|*[!0-9]*) _mt=0 ;; esac
    [ $(( $(date +%s) - _mt )) -gt "${REVIEWER_MARKER_TTL:-3600}" ] && rm -f "$_mk" 2>/dev/null
  fi
fi

echo "═══ <PROJECT> — estado del proyecto ═══"
if command -v git >/dev/null 2>&1; then
  echo "Branch: $(git symbolic-ref --short HEAD 2>/dev/null || echo '(detached)')"
  echo "Último commit: $(git log -1 --pretty=format:'%h %s' 2>/dev/null || echo '(sin commits)')"
fi

map="docs/process/current_execution_map.md"
if [ -f "$map" ]; then
  echo ""
  echo "── Estado actual (extracto) ──"
  awk '/^## Estado actual|^## Current/{flag=1; next} /^## /{flag=0} flag' "$map" | head -15
fi

echo ""
echo "── Salud de configuración ──"
PRESET="$(awk 'NR==1{print $1; exit}' tools/preset 2>/dev/null)"; [ -n "$PRESET" ] || PRESET=full
echo "• Preset: $PRESET  (full=gates bloquean · lite=gates avisan)"
_health=1
# El nivel 4 tiene CUATRO estados y hasta hace poco tres se veían igual
# ("piso 0"). Los dos que importan piden cosas opuestas: "sin cablear" es
# trabajo del adoptante; "el runner no completa" es un bug de la herramienta y
# no se arregla escribiendo conf — mandarte a cablear ahí es mandarte a perder
# la tarde. Lo aprendimos por el camino largo: se declaró muter incompatible
# con Swift 6 basándose en `brew info` (release de 2023) cuando su `main` ya
# lo tenía resuelto desde hacía años.
case "$(bash tools/mutation-score.sh --state 2>/dev/null || echo sin-cablear)" in
  medido) : ;;
  runner-incompleto)
    echo "⚠️  NIVEL 4 CABLEADO PERO SIN VEREDICTO: el runner de mutación está y NO completa su corrida. Esto NO se arregla cablear-más: es un fallo de la herramienta. Aísla el síntoma y abre issue upstream (y comprueba su repositorio, no solo el release de tu gestor de paquetes)."; _health=0 ;;
  sin-cablear)
    echo "⚠️  NIVEL 4 SIN CABLEAR: no hay runner de mutación. AGENTS.md §5 declara el mutation score el árbitro de la calidad de los tests; hasta que exista, esa frase es prosa. Cablea el runner de tu stack (tools/mutation-score.sh §FILL)."; _health=0 ;;
  *)
    echo "⚠️  NIVEL 4 NUNCA MEDIDO: el runner corre, pero nadie ha fijado el piso. Mide una vez (\`bash tools/mutation-score.sh --update\`) y a partir de ahí solo sube."; _health=0 ;;
esac
# El delimitador tras FILL no es cosmetico. Con el prefijo abierto (`<!-- FILL`
# a secas) estos dos avisos casaban tambien `<!-- FILL-HECHO: ... -->`, que es
# el marcador de los huecos ya RESUELTOS: un adoptante que cerrara el hueco con
# esa convencion seguia leyendo "SIN rellenar" en CADA arranque, sobre trabajo
# que ya hizo. Un aviso que no se puede apagar haciendo lo correcto ensena a
# ignorar los avisos, y este es el banner de arranque — el sitio de maxima
# autoridad del harness.
# ⚠️ El atajo de meter el guion en la clase (`[[:space:]:>-]`) NO vale: se come
# `<!-- FILL-->` (guion pegado), que SI es un hueco pendiente. Por eso `-->` va
# como alternativa explicita. Mismo delimitador que skill-reminder.sh:109 y
# harness-report.sh:67, para no tener tres formas de lo mismo.
_SST_FILL_ERE='<!--[[:space:]]*FILL([[:space:]:>]|-->|$)'
grep -qE "Plataformas:\*\*[[:space:]]*$_SST_FILL_ERE" AGENTS.md 2>/dev/null && { echo "⚠️  AGENTS.md §2 (Stack) SIN rellenar — build/test/lenguaje desconocidos."; _health=0; }
_src=0; for d in ios android web src; do [ -d "$d" ] && _src=1; done
[ "$_src" = "0" ] && { echo "⚠️  Sin carpetas de código (ios/android/web/src) — check-drift inactivo."; _health=0; }
# La matriz path→skill vive en tools/skill-matrix.conf (fuente única).
# El check honesto no es "¿hay globs?" sino "¿los globs cubren TU código?":
# los globs iOS de fábrica en un repo Python son un gate que jamás dispara
# pero que un grep ingenuo reporta como 'configurado' — falsa confianza.
if [ -f tools/skill-matrix.conf ]; then
  _uncovered=""
  for _ext in swift kt ts tsx py go java rb; do
    _n="$(find ios android web src app lib Sources -type f -name "*.${_ext}" 2>/dev/null | head -1)"
    [ -z "$_n" ] && continue
    grep -v '^\s*#' tools/skill-matrix.conf 2>/dev/null | grep -q "\.${_ext}\|/\*\*" \
      || _uncovered="${_uncovered} .${_ext}"
  done
  [ -n "$_uncovered" ] && { echo "⚠️  skill-matrix.conf NO cubre extensiones presentes en el repo:${_uncovered} — gate leer-skill MUDO para esos archivos (edita tools/skill-matrix.conf)."; _health=0; }
else
  echo "⚠️  tools/skill-matrix.conf ausente — skill-reminder usa solo sus globs de fábrica."; _health=0
fi
# WF-05 (PRD 0005 §6): el project_kind se DECLARA en tools/project.conf; sin
# declarar, los gates de scope caen a la heurística y ESTE es el único sitio
# que lo dice — una línea por sesión, nunca un aviso por commit (ley del 10%).
# SCOPE_NO_CI_EXIT=1: consulta pura — la lib jamás corta a session-start.
if [ -f tools/lib/scope.sh ]; then
  _pk="$(SCOPE_NO_CI_EXIT=1 bash -c '. tools/lib/scope.sh 2>/dev/null; _scope_project_kind' 2>/dev/null)"
  [ -z "$_pk" ] && { echo "⚠️  project_kind sin declarar — tools/project.conf: los gates de scope infieren por heurística; declara harness|application|other (un repo doc-only sale 'harness' por defecto: declara 'other' si no quieres review sobre su contenido)."; _health=0; }
fi
# La suite del harness aprueba el conjunto vacío si no hay archivos de test:
# "0 tests, 0 fallos, ✅" es exactamente el gate mudo que este harness combate.
_ntests="$(find tools/tests -name 'test_*.sh' 2>/dev/null | wc -l | tr -d ' ')"
[ "${_ntests:-0}" = "0" ] \
  && { echo "⚠️  Suite del harness VACÍA (0 archivos test_*.sh) — canon-enforce CHECK 4 y CI paso 1 pasan en vacuo."; _health=0; }

# ── Niveles de la pirámide que están MUDOS (verification-loop.md) ────
# Un gate no configurado es peor que ausente si el harness lo anuncia como
# activo: da falsa confianza. Aquí se declara explícitamente qué NO cubre.
if [ -x tools/probe-capability.sh ]; then
  _semgrep_probe="$(PROBE_TIMEOUT_SECS="${PROBE_TIMEOUT_SECS:-10}" bash tools/probe-capability.sh semgrep 2>/dev/null)"; _semgrep_rc=$?
  _semgrep_status="$(printf '%s' "$_semgrep_probe" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status","unknown"))' 2>/dev/null || echo unknown)"
  _semgrep_detail="$(printf '%s' "$_semgrep_probe" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("detail","sin diagnóstico"))' 2>/dev/null || echo 'salida no parseable')"
  case "$_semgrep_status:$_semgrep_rc" in
    operational:0) : ;;
    missing:1) echo "⚠️  Nivel 2 MUDO: semgrep ausente — sin detectores AST."; _health=0 ;;
    broken:1) echo "⚠️  Nivel 2 ROTO: semgrep existe pero su probe funcional falla — $_semgrep_detail"; _health=0 ;;
    *) echo "⚠️  Nivel 2 DESCONOCIDO: el probe no pudo clasificar semgrep (exit $_semgrep_rc) — $_semgrep_detail"; _health=0 ;;
  esac
else
  echo "⚠️  Nivel 2 DESCONOCIDO: falta tools/probe-capability.sh; presencia no demuestra operación."; _health=0
fi
grep -qE "$_SST_FILL_ERE" scripts/agent-hooks/post-edit-verify.sh 2>/dev/null \
  && grep -qE '^\s*\*\)\s*:\s*;;' scripts/agent-hooks/post-edit-verify.sh 2>/dev/null \
  && { echo "⚠️  Nivel 1 PARCIAL: post-edit-verify sin lint/typecheck de tu stack (§FILL) — el agente no recibe señal in-loop."; _health=0; }
grep -q '"min_score": 0' tools/mutation-ratchet.json 2>/dev/null \
  && { echo "⚠️  Nivel 4 MUDO: mutation score en 0 — NADA distingue un test real de uno decorativo."; _health=0; }
# El fallo más caro del primer proyecto real: 9 niveles en verde y el build
# roto. La comprobación más barata y definitiva (¿compila?) no puede ser el
# único FILL silencioso mientras semgrep y trinquetes vienen de fábrica.
! bash tools/verify-run.sh --cmd-only >/dev/null 2>&1 \
  && { echo "⚠️  SIN COMPILADOR EN LOS GATES: tools/verify.conf sin cablear — los 9 niveles pueden estar en verde con el build ROTO. Cablea tools/verify.conf ANTES que nada (AGENTS.md §2)."; _health=0; }
command -v gitleaks >/dev/null 2>&1 \
  || echo "⚠️  gitleaks no instalado — el scan de secretos del Anillo 1 no corre en local."
# El ANILLO mudo, no solo el nivel mudo: sin Anillo 3 el fail-open de §14.3
# ("avisa en local, CI bloquea") pierde su segunda mitad y ningún exit 3
# lo bloquea nunca. Declararlo aquí es el mínimo; en preset full,
# validate-harness además FALLA.
if [ -f tools/check-ring3.sh ]; then
  # Se IMPRIME la causa real que reporta el detector, en vez de un texto fijo.
  # El texto fijo decia "sin remoto o sin CI" y desde que check-ring3 tambien
  # detecta "cableado pero no ejecuta" (jobs rechazados por presupuesto) esa
  # frase es sencillamente FALSA en el caso mas interesante: hay remoto y hay
  # CI, y aun asi no hay backstop. Mandaba al owner a arreglar lo que ya
  # estaba bien. Un diagnostico fijo envejece con el detector que resume.
  _r3_out="$(bash tools/check-ring3.sh 2>&1)" || {
    echo "⚠️  ANILLO 3 NO OPERATIVO: todo detector que devuelva exit 3 hace fail-open DEFINITIVO."
    # Por FORMA, no por prefijo: '^[[:space:]]+·' solo casaba la PRIMERA linea
    # de cada vineta y se comia sus continuaciones, asi que el banner imprimia
    # "...el ultimo run" y ahi cortaba — sin el id, sin "CERO steps", sin la
    # causa y sin el remedio. O sea justo la informacion por la que existe esto.
    # Se corta en CONSECUENCIA porque ese parrafo ya lo resume la linea de
    # arriba; lo que se conserva entero es causa + remedio.
    printf '%s\n' "$_r3_out" \
      | awk '/^[[:space:]]+CONSECUENCIA/{exit} /^[[:space:]]+[^[:space:]]/{print}' \
      | sed 's/^[[:space:]]*/   /'
    echo "   Diagnostico completo y remedio:  bash tools/check-ring3.sh"
    _health=0
  }
fi

# ── ¿El Anillo 1 está DORMIDO? ──────────────────────────────────────
# lefthook.yml en el repo no significa nada si nadie corrió `lefthook install`:
# los hooks de git simplemente no existen y TODO el anillo universal calla.
# Nos pasó: el anillo estuvo mudo durante días y nadie lo notó, porque un
# gate que nunca dispara y uno que no existe se ven igual desde fuera (G5).
if [ -f lefthook.yml ] && [ -d .git ]; then
  if [ ! -f .git/hooks/pre-commit ] || ! grep -q lefthook .git/hooks/pre-commit 2>/dev/null; then
    echo "⚠️  ANILLO 1 DORMIDO: lefthook.yml existe pero los hooks de git NO están instalados."
    echo "   Ningún gate corre en git commit/push. Actívalo:  lefthook install"
    _health=0
  fi
fi

[ "$_health" = "1" ] && echo "✓ Stack, código, matriz de skills y pirámide de verificación configurados."

# ── Findings abiertos (AGENTS.md §10: el que toca, cierra) ──────────
if [ -f tools/findings/ledger.jsonl ]; then
  # Tolerante a ambos formatos JSON ('"status":"open"' y '"status": "open"'):
  # findings.sh (python) y findings antiguos difieren en el espaciado, y un grep
  # rígido reportaba 0 abiertos SIEMPRE — silenciosamente (lección L-json-espacios).
  _open="$(grep -cE '"status": ?"open"' tools/findings/ledger.jsonl 2>/dev/null || true)"
  [ "${_open:-0}" -gt 0 ] && { echo ""; echo "── Findings abiertos: $_open (si tocas su área, ciérralos o actualízalos) ──"; }
fi

echo ""
echo "── Guardrails activos ──"
echo "• Anillo 0 (permissions): --no-verify, --amend, --force, lectura de .env y edición"
echo "  de los trinquetes están DENEGADOS de forma nativa. No dependen del modelo."
if [ "$PRESET" = "lite" ]; then
  echo "• Edit/Write: AVISA si no leíste la skill (skill-reminder) — preset lite."
  echo "• git commit: AVISA sin review; trinquete y capas SÍ bloquean (reviewer-gate)."
else
  echo "• Edit/Write: BLOQUEA si no leíste la skill requerida (skill-reminder)."
  echo "• git commit: BLOQUEA sin marker de review válido, o si sube el trinquete, o si"
  echo "  se violan las capas (reviewer-gate + lefthook + CI: los 3 anillos)."
fi
echo "• PostToolUse Edit/Write: lint+typecheck del archivo tocado → de vuelta al agente."
echo "• SubagentStop: el marker de review lo escribe el SISTEMA a partir del VERDICT"
echo "  real del sub-agente. Un marker escrito a mano se RECHAZA."
echo "• Stop: BLOQUEA si introdujiste violaciones/errores nuevos (canon-enforce + drift-stop)."
echo "• SessionStart(compact): reinyecta el digest de reglas + findings tras compactar."
echo "• Markers se borran en cada sesión NUEVA (startup|clear) → re-leer requerido."
exit 0

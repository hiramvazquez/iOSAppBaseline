#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# backlog/run.sh — trabaja UNA historia en un WORKTREE aislado
# ════════════════════════════════════════════════════════════════════
# El ciclo del PRD 0003, con la práctica 2026 de los orquestadores:
#   next.sh elige → `git worktree add` crea un directorio AISLADO con la rama
#   story/<id>-<slug> → agent-runner trabaja AHÍ (los MISMOS gates de
#   siempre: TDD, reviewer VERDICT, trinquetes, capas — el worktree tiene su
#   propio .agents/state, así que markers y baselines arrancan limpios) →
#   commits EN LA RAMA → historia a `in-review` → el humano revisa y mergea.
#
# QUÉ GANA EL WORKTREE frente al checkout in-place anterior:
#   · tu copia de trabajo NUNCA cambia de rama ni se toca — puedes seguir
#     trabajando mientras el agente trabaja su historia
#   · el árbol sucio ya no bloquea el run (antes: guard duro; ahora: aviso)
#   · una rama en `in-review` NO se re-trabaja: el runner la salta hasta tu
#     merge (antes "la retomaba" y podía repetir trabajo ya hecho)
#
# SECUENCIAL a propósito: una historia por invocación (política de
# multi-agent-orchestration.md). El "paralelismo" correcto es tener varias
# ramas independientes esperando review, no varios agentes escribiendo a la
# vez. Repite el ciclo un cron/schedule o un humano.
#
# Exit codes: 0 ok/no-op · 1 precondición/git · 3 infra/backend · 4 trabajo
# pendiente · 5 criterios · 6 scope · 7 review final RED/inválida.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1
BACKEND=claude
while [ $# -gt 0 ]; do
  case "$1" in
    --backend) [ $# -ge 2 ] || { echo "backlog: falta backend" >&2; exit 3; }; BACKEND="$2"; shift 2 ;;
    *) echo "backlog: argumento desconocido: $1" >&2; exit 3 ;;
  esac
done

# ── Árbol sucio: ya NO bloquea (el worktree aísla) — solo informa ───
DIRTY="$(git status --porcelain 2>/dev/null | grep -vE '^\?\?' || true)"
[ -n "$DIRTY" ] && echo "ℹ️  backlog: tu árbol tiene cambios sin commitear — no estorban: la historia se trabaja en un worktree aislado."

# ── Selección ───────────────────────────────────────────────────────
STORY="$(bash tools/backlog/next.sh)"
[ -z "$STORY" ] && { echo "backlog: sin historias ready — nada que hacer."; exit 0; }

_field() { awk -v k="$2" '/^---[[:space:]]*$/{n++;next} n==1 && $1==k":" {sub(/^[^:]*:[[:space:]]*/,""); print; exit}' "$1"; }
_branch_field() { # _branch_field <branch> <archivo> <campo> — lee del contenido de la RAMA
  git show "$1:$2" 2>/dev/null \
    | awk -v k="$3" '/^---[[:space:]]*$/{n++;next} n==1 && $1==k":" {sub(/^[^:]*:[[:space:]]*/,""); print; exit}'
}
_set_status() { # _set_status <archivo> <estado>
  sed -i.bak "s/^status: .*/status: $2/" "$1" && rm -f "$1.bak"
}
ID="$(_field "$STORY" id)"; : "${ID:=$(basename "$STORY" | cut -d- -f1)}"
BASE="$(_field "$STORY" base)"; : "${BASE:=develop}"
case "$BASE" in
  -*) echo "❌ backlog: base insegura en ${STORY}: ${BASE}" >&2; exit 1 ;;
esac
SLUG="$(basename "$STORY" .md | sed "s/^${ID}-\{0,1\}//")"
BRANCH="story/${ID}${SLUG:+-$SLUG}"
WT=".agents/worktrees/${BRANCH//\//-}"

# ── Guard 1: la historia tiene contrato (criterios de aceptación) ───
# Sin criterios no hay escenarios golden que verificar → el agente tendría
# que INVENTAR el "cuándo está bien", que es justo lo que §1.4 prohíbe.
# Commit con PATHSPEC (solo la historia): con el árbol sucio permitido, un
# `git commit` a secas arrastraría lo que el humano tuviera en el index.
if ! grep -qi "riterios de aceptaci" "$STORY" || ! grep -q "Dado " "$STORY"; then
  _set_status "$STORY" blocked
  git commit -qm "chore(backlog): ${ID} blocked — sin criterios de aceptación verificables" -- "$STORY" 2>/dev/null
  echo "⚠️  backlog: ${STORY} BLOCKED — sin criterios de aceptación (Dado/cuando/entonces)."
  echo "   Una historia sin contrato verificable no se trabaja: se devuelve (AGENTS.md §1.4)."
  exit 0
fi

# ── Guard 2: backend portable con todas las capacidades autónomas ──
if ! bash tools/agent-runner.sh capabilities --backend "$BACKEND" \
  --require run,review,read_only,subagents,hooks >/dev/null 2>&1; then
  echo "❌ backlog: backend '$BACKEND' ausente o sin run+review+read_only+subagents+hooks." >&2
  exit 3
fi

# Resuelve intérpretes/herramientas antes de ceder ejecución. Después, un
# agente puede escribir un `bash`, `python3` o `git` antes en PATH; el gate no
# vuelve a consultar ese namespace mutable.
TRUSTED_BASH="$(command -v bash 2>/dev/null || true)"
TRUSTED_PYTHON="$(command -v python3 2>/dev/null || true)"
TRUSTED_GIT="$(command -v git 2>/dev/null || true)"
for TRUSTED_BIN in "$TRUSTED_BASH" "$TRUSTED_PYTHON" "$TRUSTED_GIT"; do
  case "$TRUSTED_BIN" in
    /*) [ -x "$TRUSTED_BIN" ] || { echo "❌ backlog: ejecutable confiable no disponible: $TRUSTED_BIN" >&2; exit 3; } ;;
    *) echo "❌ backlog: no pude fijar ejecutables absolutos para el gate." >&2; exit 3 ;;
  esac
done

# Checker y contrato deben ser blobs commiteados. El árbol puede estar sucio
# en otras rutas porque el worktree aísla, pero no en los archivos que
# decidirán qué se permite: un cambio local sin OID no es autoridad auditable.
if ! git diff --quiet -- tools/backlog/scope-check.sh "$STORY" \
  || ! git diff --cached --quiet -- tools/backlog/scope-check.sh "$STORY"; then
  echo "❌ backlog: checker e historia deben estar commiteados y limpios antes del run." >&2
  exit 1
fi
TRUSTED_SCOPE_SOURCE="$(git show "HEAD:tools/backlog/scope-check.sh" 2>/dev/null)" \
  || { echo "❌ backlog: scope-check no existe en HEAD; commitéalo antes del run." >&2; exit 1; }
TRUSTED_STORY_CONTENT="$(git show "HEAD:${STORY}" 2>/dev/null)" \
  || { echo "❌ backlog: la historia no existe en HEAD; commitéala antes del run." >&2; exit 1; }
TRUSTED_BACKLOG_PROMPT="$(git show HEAD:tools/agent-prompts/backlog.md 2>/dev/null)" \
  || { echo "❌ backlog: falta tools/agent-prompts/backlog.md en HEAD." >&2; exit 1; }
TRUSTED_REVIEW_PROMPT="$(git show HEAD:tools/agent-prompts/review.md 2>/dev/null)" \
  || { echo "❌ backlog: falta tools/agent-prompts/review.md en HEAD." >&2; exit 1; }

# ── Rama nueva o retomar — SIEMPRE vía worktree, jamás checkout aquí ─
if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  BR_STATUS="$(_branch_field "$BRANCH" "$STORY" status)"
  if [ "$BR_STATUS" = "in-review" ]; then
    echo "⏸  backlog: ${ID} ya está in-review en ${BRANCH} — esperando TU merge; no se re-trabaja."
    echo "   Revisa: git diff ${BASE}...${BRANCH}   · al mergear, pon status: done en la base."
    exit 0
  fi
  echo "⚠️  backlog: la rama $BRANCH ya existe — la retomo donde quedó."
  if [ ! -d "$WT" ]; then
    git worktree add "$WT" "$BRANCH" >/dev/null 2>&1 \
      || { echo "❌ backlog: no pude crear el worktree para retomar $BRANCH." >&2; exit 1; }
  fi
else
  if ! git rev-parse --verify "$BASE" >/dev/null 2>&1; then
    git rev-parse --verify main >/dev/null 2>&1 && BASE=main || BASE="$(git rev-parse --abbrev-ref HEAD)"
  fi
  git worktree add "$WT" -b "$BRANCH" "$BASE" >/dev/null 2>&1 \
    || { echo "❌ backlog: git worktree add falló (¿worktree huérfano? git worktree prune)." >&2; exit 1; }
fi

# Los tres anchors de confianza se fijan ANTES de ejecutar código del agente:
# source del checker + historia viven en memoria privada del proceso padre y
# vienen de HEAD; la base se reduce a OID. No hay archivo temporal que otro
# proceso con el mismo UID pueda reescribir.
BASE_OID="$(git rev-parse --verify "${BASE}^{commit}" 2>/dev/null)" \
  || { echo "❌ backlog: no pude fijar el commit base ${BASE}." >&2; exit 1; }

# Estado: in-progress, commiteado EN LA RAMA vía el worktree.
( cd "$WT" && _set_status "$STORY" in-progress \
  && git commit -qm "chore(backlog): ${ID} in-progress" -- "$STORY" 2>/dev/null )

# ── Registro + prompt portable (concatenación literal, sin templates/eval) ─
# Cada run queda en .agents/state/backlog/<id>-<ts>.log (gitignored). Es la
# materia prima de tools/harness-report.sh: sin esto, "¿cómo se comportó el
# agente?" solo se puede responder de memoria — y la memoria no es evidencia.
LOG_DIR="$(pwd)/.agents/state/backlog"; mkdir -p "$LOG_DIR"
RUN_LOG="$LOG_DIR/${ID}-$(date -u +%Y%m%dT%H%M%SZ).log"
PROMPT_FILE="$LOG_DIR/${ID}-prompt.md"
{ printf '%s\n\n' "$TRUSTED_BACKLOG_PROMPT"; printf '%s\n' "$TRUSTED_STORY_CONTENT"; } > "$PROMPT_FILE"
{
  echo "═══ backlog run · story=${STORY} · branch=${BRANCH} · base=${BASE}"
  echo "═══ fecha=$(date -u +%Y-%m-%dT%H:%M:%SZ) · backend=${BACKEND}"
} > "$RUN_LOG"

echo "━━━ backlog: trabajando ${STORY} en ${BRANCH} (worktree ${WT}, base ${BASE}) ━━━"
echo "    log del run: ${RUN_LOG}"
bash tools/agent-runner.sh run --backend "$BACKEND" \
  --require run,review,read_only,subagents,hooks \
  --prompt-file "$PROMPT_FILE" --cwd "$WT" 2>&1 | tee -a "$RUN_LOG"
RC=${PIPESTATUS[0]}
echo "═══ fin del run · rc=$RC" >> "$RUN_LOG"

# ════════════════════════════════════════════════════════════════════
# UN RUN QUE DEJA TRABAJO SIN COMMITEAR NO HA TERMINADO
# ════════════════════════════════════════════════════════════════════
# Cazado en vivo con la 0007: el agente lanzó la suite en background, dijo "me
# notificará al terminar" y ahí acabó su turno. El backend salió con 0, así
# que esto marcaba `in-review` y salía 0 también. Desde fuera la historia
# parecía terminada — pero 691 líneas del adapter estaban sin commitear, el
# composition root sin cablear, y `git diff base...rama` no mostraba nada de
# eso. Si alguien podaba el worktree, se perdían.
#
# El exit code de un sub-proceso dice "el proceso terminó", no "el trabajo
# está hecho". Lo segundo tiene un hecho observable —el árbol de trabajo— y es
# el que hay que mirar. Mismo principio que §14.2: el veredicto es la salida de
# un comando, nunca una afirmación de quien lo ejecutó.
if [ $RC -eq 0 ]; then
  CURRENT_BASE_OID="$("$TRUSTED_GIT" rev-parse --verify "${BASE}^{commit}" 2>/dev/null || true)"
  if [ "$CURRENT_BASE_OID" != "$BASE_OID" ]; then
    ( cd "$WT" && _set_status "$STORY" in-progress \
      && git commit -qm "chore(backlog): ${ID} in-progress — la base cambió durante el run" -- "$STORY" 2>/dev/null ) || true
    echo "❌ backlog: la ref base ${BASE} cambió durante el run; no puedo evaluar un rango estable." >&2
    echo "   Esperado: ${BASE_OID} · actual: ${CURRENT_BASE_OID:-ausente}" >&2
    exit 3
  fi
  PENDIENTE="$( ( cd "$WT" && git status --porcelain 2>/dev/null ) || true )"
  if [ -n "$PENDIENTE" ]; then
    # Respaldo ANTES de nada: que la recuperación no dependa de que nadie
    # pode el worktree por costumbre. Va a .agents/state (gitignored), así
    # que sobrevive a `git worktree remove --force`.
    RESPALDO="$LOG_DIR/${ID}-pendiente-$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "$RESPALDO"
    ( cd "$WT" && git status --porcelain 2>/dev/null | sed 's/^...//' ) \
      | while IFS= read -r f; do
          [ -z "$f" ] && continue
          mkdir -p "$RESPALDO/$(dirname "$f")" 2>/dev/null
          cp "$WT/$f" "$RESPALDO/$f" 2>/dev/null
        done
    ( cd "$WT" && _set_status "$STORY" in-progress \
      && git commit -qm "chore(backlog): ${ID} in-progress — el run acabó con trabajo sin commitear" -- "$STORY" 2>/dev/null )
    {
      echo ""
      echo "❌ backlog: ${ID} NO ha terminado — el run salió con 0 pero dejó trabajo sin commitear:"
      printf '%s\n' "$PENDIENTE" | sed 's/^/     /'
      echo ""
      echo "   La historia queda en 'in-progress' (NO in-review): desde fuera parecería"
      echo "   terminada y \`git diff ${BASE}...${BRANCH}\` no mostraría nada de esto."
      echo "   ⚠️  NO podes el worktree: el trabajo vive en ${WT}"
      echo "   Copia de seguridad: ${RESPALDO}"
      echo "   Revisa, commitea lo que valga y vuelve a lanzar el runner para retomarla."
    } >&2
    exit 4
  fi
  # Y el segundo hecho observable: cada criterio de aceptación cita el test
  # que lo fija. Mismo mecanismo que el `Detector:` de las lecciones, un nivel
  # más arriba — porque un criterio dado por bueno con un `grep` pegado en el
  # informe se cumple hoy y no impide la regresión de mañana.
  if [ -f tools/backlog/criteria-link.sh ]; then
    CRIT_OUT="$( ( cd "$WT" && bash tools/backlog/criteria-link.sh "$STORY" ) 2>&1 )"; CRIT_RC=$?
    if [ "$CRIT_RC" = "1" ]; then
      ( cd "$WT" && _set_status "$STORY" in-progress \
        && git commit -qm "chore(backlog): ${ID} in-progress — criterios sin test que los fije" -- "$STORY" 2>/dev/null )
      {
        echo ""
        printf '%s\n' "$CRIT_OUT"
        echo "   La historia queda en 'in-progress'. El worktree sigue en ${WT}."
      } >&2
      exit 5
    fi
  fi
  # El prompt es instrucción; este gate es evidencia. Mira rango, índice,
  # modificaciones, untracked, deletes y ambos lados de renames.
  if [ -n "$TRUSTED_SCOPE_SOURCE" ]; then
    if SCOPE_OUT="$( ( cd "$WT" && BACKLOG_TRUSTED_STORY="$TRUSTED_STORY_CONTENT" \
      SCOPE_PYTHON_BIN="$TRUSTED_PYTHON" SCOPE_GIT_BIN="$TRUSTED_GIT" \
      "$TRUSTED_BASH" -c "$TRUSTED_SCOPE_SOURCE" -- \
      --story "$STORY" --scope-env BACKLOG_TRUSTED_STORY \
      --base "$BASE_OID" --head HEAD --worktree "$PWD" ) 2>&1 )"; then
      SCOPE_RC=0
    else
      SCOPE_RC=$?
    fi
    if [ "$SCOPE_RC" != "0" ]; then
      ( cd "$WT" && _set_status "$STORY" in-progress \
        && git commit -qm "chore(backlog): ${ID} in-progress — scope mecánico falló" -- "$STORY" 2>/dev/null ) || true
      printf '\n%s\n' "$SCOPE_OUT" >&2
      echo "   La historia queda en 'in-progress': corrige/revierte el scope creep." >&2
      [ "$SCOPE_RC" = "1" ] && exit 6
      exit 3
    fi
  else
    echo "❌ backlog: falta el checker confiable en memoria — no puedo demostrar el scope." >&2
    exit 3
  fi
  # Review final independiente/read-only del rango completo. Guarda la salida
  # antes de cambiar el estado; una review final no valida retroactivamente
  # los commits, pero sí impide presentar el conjunto sin un juicio parseable.
  REVIEW_LOG="$LOG_DIR/${ID}-review-$(date -u +%Y%m%dT%H%M%SZ).log"
  REVIEW_PROMPT_FILE="$LOG_DIR/${ID}-review-prompt.md"
  { printf '%s\n\n' "$TRUSTED_REVIEW_PROMPT"; printf '%s\n' "$TRUSTED_STORY_CONTENT"; } > "$REVIEW_PROMPT_FILE"
  bash tools/agent-runner.sh review --backend "$BACKEND" --require review,read_only \
    --prompt-file "$REVIEW_PROMPT_FILE" --base "$BASE_OID" --head HEAD --cwd "$WT" \
    > "$REVIEW_LOG" 2>&1
  REVIEW_RC=$?
  if [ "$REVIEW_RC" != 0 ]; then
    ( cd "$WT" && _set_status "$STORY" in-progress \
      && git commit -qm "chore(backlog): ${ID} in-progress — review final no aprobó" -- "$STORY" 2>/dev/null ) || true
    echo "❌ backlog: review final no aprobó (rc=$REVIEW_RC). Evidencia: $REVIEW_LOG" >&2
    [ "$REVIEW_RC" = 1 ] && exit 7
    exit "$REVIEW_RC"
  fi
  ( cd "$WT" && _set_status "$STORY" in-review \
    && git commit -qm "chore(backlog): ${ID} in-review — lista para revisión humana" -- "$STORY" 2>/dev/null )
  if git worktree remove "$WT" >/dev/null 2>&1; then :; else
    echo "ℹ️  el worktree quedó con restos sin commitear en ${WT} — inspecciónalo y luego: git worktree remove --force ${WT}"
  fi
  echo "✅ backlog: ${ID} → in-review. Revisa la rama ${BRANCH} (git diff ${BASE}...${BRANCH}) y mergéala a ${BASE} (merge = humano)."
else
  ( cd "$WT" && _set_status "$STORY" blocked \
    && git commit -qm "chore(backlog): ${ID} blocked — el run terminó con rc=$RC" -- "$STORY" 2>/dev/null )
  echo "⚠️  backlog: ${ID} → blocked (rc=$RC). El worktree queda en ${WT} para inspección (bórralo con git worktree remove --force cuando termines)." >&2
fi
exit $RC

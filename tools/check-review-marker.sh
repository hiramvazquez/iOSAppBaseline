#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-review-marker.sh — ¿este cambio fue realmente revisado?
# ════════════════════════════════════════════════════════════════════
# UNA implementación de la verificación, consumida por los TRES anillos:
#   Anillo 1 (lefthook)     → cubre commits humanos y de Codex
#   Anillo 2 (reviewer-gate)→ bloqueo rápido y local en Claude/Cursor
#   Anillo 3 (run-gates)    → backstop server-side
#
# Antes vivía solo en el Anillo 2, así que no hacía falta `--no-verify` para
# saltárselo: bastaba commitear desde otra terminal. Ahora está en los tres.
#
# El marker debe estar ligado a TRES cosas para ser válido:
#   1. tiempo   (TTL)          — un review de ayer no vale para hoy
#   2. HEAD     (sha)          — si commiteaste entremedio, es stale
#   3. diff staged (sha256)    — lo revisado debe ser LO QUE SE COMMITEA
#   + 4. source: hook          — lo escribió el sistema, no el modelo
#
#   bash tools/check-review-marker.sh            # sobre el diff staged
#   bash tools/check-review-marker.sh --range    # sobre origin/main..HEAD (CI)
#   REVIEWER_MARKER_TTL=1800 …                   # TTL en segundos (default 3600)
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

MODE="${1:---staged}"
TTL="${REVIEWER_MARKER_TTL:-3600}"
MARKER=".agents/state/markers/reviewer_run.txt"
# La lista de "NO es código de producto" se personaliza en tools/lib/scope.sh
# (desde 206bc16), no aquí — esta cabecera llevaba un marcador FILL vestigial
# que hacía que upgrade.sh tratara este GATE como propiedad del adoptante y lo
# congelara para siempre en todos los repos por copia (f-5fc894be).
# AGENTS.md/CLAUDE.md (raíz y por plataforma) son META-DOC, no producto: editarlos
# ya tiene su gate humano (permissions.ask del Anillo 0). Sin esta exención, un
# commit de solo-reglas exigía marker de review — falso positivo real cazado en
# vivo (un marker viejo de otra sesión lo convertía en EXPIRADO). Fijado por
# test_review_marker_preset.sh::test_meta_doc_no_exige_marker.
# La lista vive en `tools/lib/scope.sh`, que además decide si ESTE repo es un
# proyecto de app (donde tools/ y scripts/ son andamio) o el repo del propio
# harness (donde son el producto, y donde este gate no había bloqueado un commit
# en su vida). Fallback si la lib no llegó todavía por sync: el criterio de app,
# que es el que no rompe a nadie.
if [ -f tools/lib/scope.sh ]; then
  # shellcheck source=lib/scope.sh
  . tools/lib/scope.sh
  NON_PRODUCT="$(scope_non_product)"
  SIEMPRE_PRODUCTO="$(scope_siempre_producto)"
else
  NON_PRODUCT='^(docs/|ci/|\.github/|tools/|scripts/|backlog/|enterprise/|\.claude/|\.claude-plugin/|\.codex/|\.cursor/|\.agents/|README|LICENSE|CODEOWNERS|\.gitignore|\.editorconfig|\.gitattributes|lefthook|\.gitleaks|\.semgrepignore|muter\.conf|AGENTS\.md|CLAUDE\.md|GEMINI\.md|(ios|android|web|backend)/AGENTS\.md$)'
  SIEMPRE_PRODUCTO='^(tools/(check|verify|secret|mutation|drift|semgrep|architecture|probe|gate|lesson)-[^/]*|tools/tests/run-tests\.sh$|tools/[^/]*\.conf$|tools/preset$|tools/lib/|tools/semgrep/|lefthook|\.gitleaks|\.semgrepignore$|ci/|\.github/workflows/|\.claude/settings\.json$|\.claude/agents/|\.codex/|\.cursor/|scripts/agent-hooks/)'
fi

fail() { echo "$1"; exit 1; }

# ── ¿Hay código de producto en el cambio? ───────────────────────────
if [ "$MODE" = "--range" ]; then
  BASE="${GATES_BASE_REF:-origin/main}"
  CHANGED="$(git diff --name-only "$BASE...HEAD" 2>/dev/null || echo "")"
else
  CHANGED="$(git diff --cached --name-only 2>/dev/null || echo "")"
fi
[ -z "$CHANGED" ] && { echo "✅ review-marker: sin cambios que revisar."; exit 0; }

CRITICAL="$(printf '%s\n' "$CHANGED" | grep -vE "$NON_PRODUCT" || true)"
# Y se vuelven a SUMAR las llaves del reino: la declaración que gobierna un
# gate no puede eximirse a sí misma (ver scope_siempre_producto).
_LLAVES="$(printf '%s\n' "$CHANGED" | grep -E "$SIEMPRE_PRODUCTO" || true)"
CRITICAL="$(printf '%s\n%s\n' "$CRITICAL" "$_LLAVES" | grep -v '^$' | sort -u || true)"
[ -z "$CRITICAL" ] && { echo "✅ review-marker: el cambio no toca código de producto (solo docs/tooling)."; exit 0; }

# ── Commit de MERGE: el contenido YA pasó sus gates en su rama ──────
# Cazado en vivo en el PRIMER merge del primer proyecto: el owner mergeaba
# story/0003 (GREEN en su creación, gates verdes commit a commit) y este gate
# exigía un marker NUEVO para el diff del merge → el merge quedaba a medias
# con MERGE_HEAD colgado. Re-revisar lo ya revisado no añade verificación, y
# el merge es acto del OWNER por doctrina (backlog/README: "el merge es
# SIEMPRE humano"). Solo aplica al modo staged (en --range/CI el análisis es
# sobre el rango completo, donde el merge ya es historia).
if [ "$MODE" != "--range" ]; then
  _GITDIR="$(git rev-parse --git-dir 2>/dev/null)"
  if [ -n "$_GITDIR" ] && [ -f "$_GITDIR/MERGE_HEAD" ]; then
    echo "✅ review-marker: commit de MERGE (MERGE_HEAD presente) — el contenido pasó sus gates en su rama; el merge es acto del owner."
    exit 0
  fi
fi

# ── Preset: `lite` AVISA, `full` BLOQUEA (AGENTS.md §13) ────────────
# Esta comprobación vive AQUÍ, en la implementación compartida, y no en cada
# llamador. Cuando solo estaba en `reviewer-gate.sh` (Anillo 2), lefthook
# (Anillo 1) invocaba este script directo y bloqueaba igual en preset `lite`:
# el agente recibía luz verde y el `git commit` fallaba después, contradiciendo
# lo que §13 promete. Una regla implementada en dos sitios diverge; por eso
# vive en uno solo (README §"Una fuente de verdad").
# Fijado por `tools/tests/test_review_marker_preset.sh`.
PRESET="${WORKFLOW_PRESET:-}"
[ -z "$PRESET" ] && [ -f tools/preset ] && PRESET="$(awk 'NR==1{print $1; exit}' tools/preset 2>/dev/null)"
case "$PRESET" in
  lite)
    echo "⚠️  [lite] review-marker: hay código de producto sin review, pero el preset personal"
    echo "   solo avisa. Considera invocar el sub-agente \`reviewer\`. (Los trinquetes y las"
    echo "   capas SIGUEN duros en lite — ver AGENTS.md §9 y §13.)"
    exit 0 ;;
esac

# ── Override de emergencia, AUDITADO ────────────────────────────────
if [ "${REVIEWER_OVERRIDE:-0}" = "1" ]; then
  mkdir -p .agents/state/markers
  printf '[%s] override en %s · reason=%s · files=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(git rev-parse --short HEAD 2>/dev/null || echo no-repo)" \
    "${REVIEWER_OVERRIDE_REASON:-(SIN RAZÓN — esto es un smell)}" \
    "$(printf '%s' "$CRITICAL" | tr '\n' ',')" \
    >> .agents/state/markers/override_log.txt
  echo "⚠️  review-marker: OVERRIDE activo — registrado en override_log.txt."
  exit 0
fi

# ── 0. ¿Existe? ─────────────────────────────────────────────────────
[ -f "$MARKER" ] || fail "❌ review-marker: NO hay review de estos cambios de producto:
$(printf '%s\n' "$CRITICAL" | sed 's/^/  - /')

Invoca el sub-agente \`reviewer\`. Al terminar debe emitir:
  VERDICT: GREEN|AMBER|RED
El hook SubagentStop escribe el marker automáticamente a partir de ese veredicto.
Override auditado: REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON=\"...\" <comando>"

get() { grep -E "^$1:" "$MARKER" 2>/dev/null | head -1 | sed -E "s/^$1:[[:space:]]*//"; }

# ── 1. ¿Lo escribió el sistema o el modelo? ─────────────────────────
SOURCE="$(get source)"
if [ "$SOURCE" != "hook" ]; then
  fail "❌ review-marker: el marker NO lo escribió el sistema (source='${SOURCE:-ausente}').

Un marker manual no es evidencia de review — es una afirmación del agente.
El marker válido lo produce el hook SubagentStop a partir del veredicto real
del sub-agente \`reviewer\`. Invócalo y deja que emita su VERDICT.
Si de verdad necesitas saltártelo: REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON=\"...\""
fi

# ── 2. ¿El veredicto permite commitear? ─────────────────────────────
VERDICT="$(get verdict)"
case "$VERDICT" in
  GREEN|AMBER) : ;;
  *) fail "❌ review-marker: veredicto '${VERDICT:-ausente}' no permite commitear. Atiende los hallazgos y re-revisa." ;;
esac

# ── 3. Edad ─────────────────────────────────────────────────────────
NOW=$(date +%s)
# ORDEN: primero GNU (-c %Y), luego BSD/macOS (-f %m). Al revés era un bug
# real en Linux: `stat -f` de GNU NO falla — imprime datos del FILESYSTEM
# (con %m, el mount point "/") con exit 0, así que el fallback jamás corría,
# MTIME quedaba no-numérico y el TTL reventaba: el marker VÁLIDO se rechazaba
# siempre en CI. En tu Mac funcionaba — el clásico bug que solo vive en el
# runner. Guard numérico además, por si algún stat exótico imprime otra cosa.
MTIME=$(stat -c %Y "$MARKER" 2>/dev/null || stat -f %m "$MARKER" 2>/dev/null || echo 0)
case "$MTIME" in ''|*[!0-9]*) MTIME=0 ;; esac
[ $((NOW - MTIME)) -gt "$TTL" ] && fail "❌ review-marker: EXPIRADO (>${TTL}s). Re-corre \`reviewer\`."

# ── 4. Binding a HEAD ───────────────────────────────────────────────
MARKED_HEAD="$(get head)"; CUR_HEAD="$(git rev-parse --short HEAD 2>/dev/null || echo '')"
if [ -n "$MARKED_HEAD" ] && [ -n "$CUR_HEAD" ] && [ "$MARKED_HEAD" != "no-repo" ] && [ "$MARKED_HEAD" != "$CUR_HEAD" ]; then
  fail "❌ review-marker: STALE (HEAD cambió ${MARKED_HEAD}→${CUR_HEAD}). Re-corre \`reviewer\`."
fi

# ── 5. Binding al DIFF (solo aplica en modo staged) ─────────────────
if [ "$MODE" != "--range" ]; then
  MARKED_STAGED="$(get staged_sha)"
  CUR_STAGED="$(git diff --cached 2>/dev/null | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | awk '{print $1}')"
  if [ -n "$MARKED_STAGED" ] && [ -n "$CUR_STAGED" ] && [ "$MARKED_STAGED" != "$CUR_STAGED" ]; then
    fail "❌ review-marker: el diff STAGED cambió desde la review (revisado=${MARKED_STAGED:0:12}… actual=${CUR_STAGED:0:12}…).
Lo que se revisó ya no es lo que vas a commitear. Re-corre \`reviewer\`."
  fi
fi

echo "✅ review-marker: válido (agent=$(get agent) verdict=$VERDICT head=$MARKED_HEAD source=hook)."
exit 0

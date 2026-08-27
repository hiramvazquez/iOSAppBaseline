#!/usr/bin/env bash
# Review headless de Anillo 3 a través del boundary portable de agentes.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

BACKEND=claude
while [ $# -gt 0 ]; do
  case "$1" in
    --backend)
      [ $# -ge 2 ] || { echo "ai-review: falta backend" >&2; exit 3; }
      BACKEND="$2"; shift 2 ;;
    *) echo "ai-review: argumento desconocido: $1" >&2; exit 3 ;;
  esac
done

BASE="${GATES_BASE_REF:-origin/main}"
REQUIRED="${AI_REVIEW_REQUIRED:-0}"
RUNNER=tools/agent-runner.sh

if ! bash "$RUNNER" capabilities --backend "$BACKEND" \
  --require review,read_only >/dev/null 2>&1; then
  echo "⚠️  ai-review: backend '$BACKEND' ausente o sin review read-only."
  [ "$REQUIRED" = 1 ] && exit 1
  exit 0
fi

if ! git rev-parse --verify "${BASE}^{commit}" >/dev/null 2>&1; then
  echo "⚠️  ai-review: base '$BASE' no es un commit evaluable."
  [ "$REQUIRED" = 1 ] && exit 1
  exit 0
fi

DIFF_FILES="$(git diff --name-only "$BASE...HEAD" 2>/dev/null)" || {
  echo "⚠️  ai-review: no pude calcular $BASE...HEAD."
  [ "$REQUIRED" = 1 ] && exit 1
  exit 0
}
if [ -z "$DIFF_FILES" ]; then
  echo "✅ ai-review: sin cambios respecto a $BASE."
  exit 0
fi

OUT_DIR="${AI_REVIEW_OUT:-.agents/state/ci}"; mkdir -p "$OUT_DIR"
PROMPT_FILE="$OUT_DIR/review-prompt.md"
{
  cat tools/agent-prompts/review.md
  printf '\nRango solicitado: %s...HEAD\n' "$BASE"
} > "$PROMPT_FILE"

echo "━━━ ai-review sobre $BASE...HEAD ($(printf '%s\n' "$DIFF_FILES" | wc -l | tr -d ' ') archivos) ━━━"
set +e
bash "$RUNNER" review --backend "$BACKEND" --prompt-file "$PROMPT_FILE" \
  --base "$BASE" --head HEAD --cwd "$PWD" \
  > "$OUT_DIR/ai-review.md" 2> "$OUT_DIR/ai-review.err"
RC=$?

RESULT="$(cat "$OUT_DIR/ai-review.md" 2>/dev/null)"
. scripts/agent-hooks/lib/verdict.sh
VERDICT="$(verdict_parse "$RESULT")"
FINDINGS="$(verdict_findings "$RESULT")"
printf '%s\n' "$RESULT" | tail -40

case "$VERDICT" in
  GREEN)
    [ "$RC" = 0 ] || { echo ""; echo "❌ ai-review: GREEN inválido (runner rc=$RC)."; exit 1; }
    echo ""; echo "✅ ai-review: GREEN (${FINDINGS:-0} hallazgos)."; exit 0 ;;
  AMBER)
    [ "$RC" = 0 ] || { echo ""; echo "❌ ai-review: AMBER inválido (runner rc=$RC)."; exit 1; }
    echo ""; echo "⚠️  ai-review: AMBER (${FINDINGS:-?} hallazgos) — revisa el reporte, no bloquea."; exit 0 ;;
  RED) echo ""; echo "❌ ai-review: RED (${FINDINGS:-?} hallazgos). Ver $OUT_DIR/ai-review.md"; exit 1 ;;
  *)
    echo ""
    echo "⚠️  ai-review: backend falló (rc=$RC) o no emitió VERDICT."
    tail -10 "$OUT_DIR/ai-review.err" 2>/dev/null | sed 's/^/   /'
    [ "$REQUIRED" = 1 ] && exit 1
    exit 0 ;;
esac

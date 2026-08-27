#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-verify-marker.sh — ¿ALGUIEN compiló y probó ESTE diff?
# ════════════════════════════════════════════════════════════════════
# Hermano de `check-review-marker.sh`, y existe por la misma razón exacta: el
# review estaba ligado a `sha256(diff staged)` y ninguna ejecución de build o
# de tests lo estaba. Se podía commitear un árbol que ninguna ejecución
# registrada llegó a compilar — con el reviewer en GREEN, los trinquetes
# dentro y las capas limpias, porque ninguno de los tres compila nada.
#
# El marker lo escribe `tools/verify-run.sh`, que es quien EJECUTA. Un marker
# sin `source: tool` se rechaza: igual que con el review, la evidencia la
# produce el sistema, nunca una afirmación del modelo.
#
#   bash tools/check-verify-marker.sh            # sobre el diff staged
#   VERIFY_MARKER_TTL=1800 …                     # TTL en segundos (default 3600)
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

TTL="${VERIFY_MARKER_TTL:-3600}"
MARKER=".agents/state/markers/verify_run.txt"
CONF="${VERIFY_CONF:-tools/verify.conf}"

# La MISMA lista que el review-marker, y por el mismo motivo: tocar docs o
# tooling no exige recompilar la app. Se lee de allí para no tener dos copias
# de la regla — la lección de las reglas implementadas dos veces ya salió cara
# tres veces (README §"Una fuente de verdad").
# Misma fuente que el marker de review: `tools/lib/scope.sh`. Antes esto
# GREPEABA la línea `NON_PRODUCT=` del otro script — funcionaba, pero acoplaba
# dos gates por el texto de una línea, y bastaba reformatearla para que este se
# quedara con su fallback en silencio.
if [ -f tools/lib/scope.sh ]; then
  # shellcheck source=lib/scope.sh
  . tools/lib/scope.sh
  NON_PRODUCT="$(scope_non_product)"
  SIEMPRE_PRODUCTO="$(scope_siempre_producto)"
else
  NON_PRODUCT='^(docs/|ci/|tools/|scripts/|\.agents/|\.claude/|README)'
  SIEMPRE_PRODUCTO='^(tools/(check|verify|secret|mutation|drift|semgrep|architecture|probe|gate|lesson)-[^/]*|tools/tests/run-tests\.sh$|tools/[^/]*\.conf$|tools/preset$|tools/lib/|tools/semgrep/|lefthook|\.gitleaks|\.semgrepignore$|ci/|\.github/workflows/|\.claude/settings\.json$|\.claude/agents/|\.codex/|\.cursor/|scripts/agent-hooks/)'
fi

fail() { echo "$1" >&2; exit 1; }

CHANGED="$(git diff --cached --name-only 2>/dev/null || echo "")"
[ -z "$CHANGED" ] && { echo "✅ verify-marker: sin cambios que verificar."; exit 0; }
CRITICAL="$(printf '%s\n' "$CHANGED" | grep -vE "$NON_PRODUCT" || true)"
# Y se vuelven a SUMAR las llaves del reino: la declaración que gobierna un
# gate no puede eximirse a sí misma (ver scope_siempre_producto).
_LLAVES="$(printf '%s\n' "$CHANGED" | grep -E "$SIEMPRE_PRODUCTO" || true)"
CRITICAL="$(printf '%s\n%s\n' "$CRITICAL" "$_LLAVES" | grep -v '^$' | sort -u || true)"
[ -z "$CRITICAL" ] && { echo "✅ verify-marker: el cambio no toca código de producto."; exit 0; }

# Commit de MERGE: el contenido ya se verificó en su rama (misma doctrina que
# el review-marker; el merge es acto del owner).
_GITDIR="$(git rev-parse --git-dir 2>/dev/null)"
if [ -n "$_GITDIR" ] && [ -f "$_GITDIR/MERGE_HEAD" ]; then
  echo "✅ verify-marker: commit de MERGE — el contenido se verificó en su rama."
  exit 0
fi

# ── Sin comando cableado no se puede exigir evidencia ───────────────
# Es el contrato §14.3: "no pude mirar" (3) avisa en local y bloquea en CI.
# Exigir el marker sin comando sería un deadlock para todo adoptante nuevo.
# El parseo del conf vive en UN sitio: `verify-run.sh --cmd-only`, que ya
# expone ese contrato (0 = hay comando · 3 = no lo hay) y no ejecuta nada.
# Reimplementarlo aquí era el mismo patrón que este delta acababa de arreglar
# en `upgrade.sh`: dos copias coincidían hoy y divergirían en el primer edge
# case que alguien corrigiera en un archivo y no en el otro — y entonces un
# gate bloquearía y el otro no.
if bash tools/verify-run.sh --cmd-only >/dev/null 2>&1; then
  _CMD="ok"
else
  _CMD=""
fi
if [ -z "$_CMD" ]; then
  {
    echo "⚠️  verify-marker: NADIE puede afirmar que esto compila — $CONF sin cablear."
    echo "   No bloqueo aquí (sería un deadlock para un proyecto recién adoptado),"
    echo "   pero que quede dicho: el nivel 3 no existe en este repo todavía."
  } >&2
  exit 3
fi

# ── Preset: `lite` AVISA, `full` BLOQUEA (AGENTS.md §13) ────────────
PRESET="${WORKFLOW_PRESET:-}"
[ -z "$PRESET" ] && [ -f tools/preset ] && PRESET="$(awk 'NR==1{print $1; exit}' tools/preset 2>/dev/null)"
case "$PRESET" in
  lite) echo "⚠️  [lite] verify-marker: commiteas código de producto sin una ejecución verde ligada a este diff. Corre \`bash tools/verify-run.sh\`."; exit 0 ;;
esac

if [ "${VERIFY_OVERRIDE:-0}" = "1" ]; then
  mkdir -p .agents/state/markers
  printf '[%s] verify-override en %s · reason=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$(git rev-parse --short HEAD 2>/dev/null || echo no-repo)" \
    "${VERIFY_OVERRIDE_REASON:-(SIN RAZÓN — esto es un smell)}" \
    >> .agents/state/markers/override_log.txt
  echo "⚠️  verify-marker: OVERRIDE activo — registrado en override_log.txt."
  exit 0
fi

[ -f "$MARKER" ] || fail "❌ verify-marker: NINGUNA ejecución verde está ligada a este cambio:
$(printf '%s\n' "$CRITICAL" | sed 's/^/  - /')

El reviewer no compila, los trinquetes no compilan y las capas no compilan.
Sin esto, puedes commitear un árbol que nadie llegó a construir.

  bash tools/verify-run.sh     ← corre build+tests y firma ESTE diff staged

Override auditado: VERIFY_OVERRIDE=1 VERIFY_OVERRIDE_REASON=\"...\" <comando>"

get() { grep -E "^$1:" "$MARKER" 2>/dev/null | head -1 | sed -E "s/^$1:[[:space:]]*//"; }

[ "$(get source)" = "tool" ] || fail "❌ verify-marker: el marker NO lo escribió la herramienta (source='$(get source)').
Una afirmación de que 'los tests pasan' no es una ejecución. Corre \`bash tools/verify-run.sh\`."

# GNU primero, BSD después — el orden importa: `stat -f` de GNU NO falla,
# imprime datos del filesystem con exit 0, así que el fallback nunca corría y
# el TTL reventaba solo en Linux. Misma trampa que ya costó un CI en rojo.
NOW=$(date +%s)
MTIME=$(stat -c %Y "$MARKER" 2>/dev/null || stat -f %m "$MARKER" 2>/dev/null || echo 0)
case "$MTIME" in ''|*[!0-9]*) MTIME=0 ;; esac
[ $((NOW - MTIME)) -gt "$TTL" ] && fail "❌ verify-marker: EXPIRADO (>${TTL}s). Re-corre \`bash tools/verify-run.sh\`."

MARKED_HEAD="$(get head)"; CUR_HEAD="$(git rev-parse --short HEAD 2>/dev/null || echo '')"
if [ -n "$MARKED_HEAD" ] && [ -n "$CUR_HEAD" ] && [ "$MARKED_HEAD" != "no-repo" ] && [ "$MARKED_HEAD" != "$CUR_HEAD" ]; then
  fail "❌ verify-marker: STALE (HEAD cambió ${MARKED_HEAD}→${CUR_HEAD}). Re-corre \`bash tools/verify-run.sh\`."
fi

MARKED_STAGED="$(get staged_sha)"
CUR_STAGED="$(git diff --cached 2>/dev/null | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | awk '{print $1}')"
if [ -n "$MARKED_STAGED" ] && [ -n "$CUR_STAGED" ] && [ "$MARKED_STAGED" != "$CUR_STAGED" ]; then
  fail "❌ verify-marker: el diff STAGED cambió desde la ejecución (verificado=${MARKED_STAGED:0:12}… actual=${CUR_STAGED:0:12}…).
Lo que compiló y pasó los tests ya NO es lo que vas a commitear. Re-corre \`bash tools/verify-run.sh\`."
fi

echo "✅ verify-marker: válido (cmd=$(get cmd) head=$MARKED_HEAD source=tool)."
exit 0

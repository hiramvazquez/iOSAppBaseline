#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# mark-reviewer-run.sh — FALLBACK MANUAL, ya no es el camino normal
# ════════════════════════════════════════════════════════════════════
# ⚠️  El camino normal es que NADIE ejecute este script.
#
# El marker de review lo escribe el SISTEMA: el hook `SubagentStop`
# (`scripts/agent-hooks/capture-review-verdict.sh`) lo deriva del veredicto
# real del sub-agente `reviewer`. Ese es el único marker que
# `tools/check-review-marker.sh` acepta como evidencia (`source: hook`).
#
# Este script escribe `source: manual-override`, que el gate RECHAZA salvo
# que además pases REVIEWER_OVERRIDE=1. Existe solo para dos casos:
#   - clientes sin hooks (Codex) donde un humano revisó de verdad
#   - depuración del propio harness
#
# Si eres un agente y estabas a punto de ejecutar esto para desbloquear un
# commit: no es el camino. Invoca el sub-agente `reviewer` y deja que emita
# su `VERDICT:`. El sistema hará el resto.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

SCOPE="${1:-(sin scope)}"
DIR=".agents/state/markers"; mkdir -p "$DIR"
HEAD="$(git rev-parse --short HEAD 2>/dev/null || echo no-repo)"
STAGED_SHA="$(git diff --cached 2>/dev/null | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | awk '{print $1}')"

cat > "$DIR/reviewer_run.txt" <<EOF
ts: $(date -u +%Y-%m-%dT%H:%M:%SZ)
agent: (manual)
verdict: ${MANUAL_VERDICT:-AMBER}
scope: $SCOPE
head: $HEAD
staged_sha: $STAGED_SHA
source: manual-override
EOF

printf '[%s] marker MANUAL escrito · head=%s · scope=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$HEAD" "$SCOPE" >> "$DIR/override_log.txt"

cat <<'MSG'
⚠️  Marker MANUAL escrito (source: manual-override) y registrado en override_log.txt.

Este marker NO desbloquea el gate por sí solo: check-review-marker exige
`source: hook`. Para commitear con él necesitas además:

  REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON="..." git commit ...

El camino sin fricción es invocar el sub-agente `reviewer` y dejar que el
hook SubagentStop escriba el marker a partir de su veredicto real.
MSG

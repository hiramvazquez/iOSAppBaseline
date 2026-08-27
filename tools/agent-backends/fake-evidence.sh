#!/usr/bin/env bash
# Instrumentación hermética: registra la review del diff staged que el fake
# va a commitear. El hook consume esta aprobación exacta una sola vez.
set -uo pipefail
[ "${1:-}" = approve ] || exit 3
case "${FAKE_AUTONOMY_EVIDENCE:-}" in /*) : ;; *) exit 3 ;; esac
SHA="$(git diff --cached | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | awk '{print $1}')"
[ -n "$SHA" ] || exit 3
MARKER=.agents/state/markers/reviewer_run.txt
mkdir -p "$(dirname "$MARKER")"
cat > "$MARKER" <<EOF
ts: $(date -u +%Y-%m-%dT%H:%M:%SZ)
agent: fake-reviewer
verdict: GREEN
findings: 0
scope: staged diff instrumentado
head: $(git rev-parse --short HEAD)
staged_sha: $SHA
source: hook
EOF
bash tools/check-review-marker.sh >/dev/null || exit 1
printf 'approved:%s\n' "$SHA" >> "$FAKE_AUTONOMY_EVIDENCE"

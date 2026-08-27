#!/usr/bin/env bash
# Traducción del contrato portable al CLI de Claude; sin lógica del workflow.
set -uo pipefail
case "${1:-}" in
  capabilities)
    command -v claude >/dev/null 2>&1 || exit 3
    echo 'run=true review=true read_only=true subagents=true hooks=true' ;;
  run)
    command -v claude >/dev/null 2>&1 || exit 3
    cd "$3" || exit 3
    if [ -n "${AGENT_CLAUDE_MODEL:-}" ]; then
      exec claude -p "$(cat "$2")" --permission-mode acceptEdits --model "$AGENT_CLAUDE_MODEL"
    fi
    exec claude -p "$(cat "$2")" --permission-mode acceptEdits
    ;;
  review)
    command -v claude >/dev/null 2>&1 || exit 3
    cd "$3" || exit 3
    PROMPT="$(cat "$2")

Rango obligatorio: $4...$5."
    # No carga ninguna fuente de settings: evita hooks de proyecto/usuario con
    # escrituras laterales. El prompt aporta el contrato necesario.
    RAW="$(claude -p "$PROMPT" --output-format json --permission-mode plan \
      --setting-sources "" \
      --allowedTools "Read,Grep,Glob,Bash(git diff:*),Bash(git log:*)")" || exit $?
    if command -v jq >/dev/null 2>&1; then printf '%s' "$RAW" | jq -r '.result // empty'
    else printf '%s\n' "$RAW"; fi
    ;;
  *) exit 3 ;;
esac

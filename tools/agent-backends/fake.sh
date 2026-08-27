#!/usr/bin/env bash
# Backend hermético para tests. Su comportamiento viene de fixtures, no de red/modelos.
set -uo pipefail
case "${1:-}" in
  capabilities)
    if [ "${FAKE_AUTONOMY_EVIDENCE:-}" != "" ] \
      && case "$FAKE_AUTONOMY_EVIDENCE" in /*) true ;; *) false ;; esac \
      && [ -x "$(dirname "$0")/fake-evidence.sh" ] \
      && [ -x "$(dirname "$0")/fake-hooks/pre-commit" ]; then
      echo 'run=true review=true read_only=true subagents=true hooks=true'
    else
      echo 'run=true review=true read_only=true subagents=false hooks=false'
    fi
    ;;
  run)
    if [ -n "${FAKE_RUN_SCRIPT:-}" ]; then
      cd "${3:-}" || exit 3
      if [ -n "${FAKE_AUTONOMY_EVIDENCE:-}" ]; then
        case "$FAKE_AUTONOMY_EVIDENCE" in /*) : ;; *) exit 3 ;; esac
        export GIT_CONFIG_COUNT=1
        export GIT_CONFIG_KEY_0=core.hooksPath
        export GIT_CONFIG_VALUE_0="$PWD/tools/agent-backends/fake-hooks"
      fi
      exec bash "$FAKE_RUN_SCRIPT" "${2:-}" "${3:-}"
    else
      cat "${2:-/dev/null}"
    fi
    ;;
  review)
    if [ -n "${FAKE_REVIEW_SCRIPT:-}" ]; then exec bash "$FAKE_REVIEW_SCRIPT" "${2:-}" "${3:-}" "${4:-}" "${5:-}"
    fi
    printf '%s\n' "${FAKE_REVIEW_RESULT:-VERDICT: GREEN
FINDINGS: 0
SCOPE: fake}" ;;
  *) exit 3 ;;
esac

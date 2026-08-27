#!/usr/bin/env bash
# La regla corta que lee el agente y la guía del reviewer no pueden contradecirse.

test_paths_sensibles_no_autorizan_fail_open() {
  local hits
  hits="$(rg -n 'fail-open OK' AGENTS.md .agents/skills .claude tools/semgrep 2>/dev/null || true)"
  [ -z "$hits" ] && return 0
  echo "    contrato inseguro todavía presente:"
  printf '%s\n' "$hits" | sed 's/^/      /'
  return 1
}

test_authz_cripto_y_validacion_fallan_cerradas() {
  grep -qi 'authn/authz.*cripto.*validación sensible fallan cerradas' AGENTS.md \
    || { echo "    AGENTS.md no exige fail-closed en decisiones sensibles"; return 1; }
  grep -qi 'Fail-closed.*authz/cripto' .agents/skills/security/SKILL.md \
    || { echo "    security skill perdió el mismo contrato"; return 1; }
  grep -qi 'authn/authz.*cripto.*validación sensible fallan cerradas' .claude/claude-security-guidance.md \
    || { echo "    guía del reviewer contradice la fuente canónica"; return 1; }
}

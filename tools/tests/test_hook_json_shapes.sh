#!/usr/bin/env bash
# El SHAPE del JSON de respuesta depende del EVENTO y del CLIENTE — y un shape
# equivocado no da error: el cliente lo IGNORA y el "bloqueo" no bloquea nada.
# Pasó de verdad: hook_json_block emitía hookSpecificOutput.decision para
# SubagentStop, un shape que ese evento ignora → el sub-agente sin contrato
# VERDICT cerraba tranquilamente. Estos tests fijan los shapes correctos.

_io() { . "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"; "$@"; }

test_subagentstop_block_es_top_level() {
  local out
  out="$(_io hook_json_block SubagentStop "sin contrato" 2>/dev/null)"
  printf '%s' "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('decision')=='block', f'esperaba decision:block top-level, hay: {d}'
assert 'reason' in d
" || { echo "    shape incorrecto para SubagentStop: $out"; return 1; }
}

test_stop_block_es_top_level() {
  local out
  out="$(_io hook_json_block Stop "violación" 2>/dev/null)"
  printf '%s' "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('decision')=='block'
" || { echo "    shape incorrecto para Stop: $out"; return 1; }
}

test_pretooluse_block_es_permissiondecision() {
  local out
  out="$(_io hook_json_block PreToolUse "denegado" 2>/dev/null)"
  printf '%s' "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
h=d.get('hookSpecificOutput',{})
assert h.get('permissionDecision')=='deny', f'esperaba permissionDecision:deny, hay: {d}'
" || { echo "    shape incorrecto para PreToolUse: $out"; return 1; }
}

# ── gate-adapter: traduce exit-2 al dialecto de cada cliente ────────
_adapter_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/adapters"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  ( cd "$d" || exit 1; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_adapter_cursor_deny() {
  printf '#!/usr/bin/env bash\necho "bloqueado por X" >&2\nexit 2\n' > scripts/agent-hooks/gate-stub.sh
  local out
  out="$(echo '{}' | bash scripts/agent-hooks/adapters/gate-adapter.sh cursor scripts/agent-hooks/gate-stub.sh 2>/dev/null)"
  printf '%s' "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('permission')=='deny', d
assert 'bloqueado por X' in d.get('agentMessage','')
" || { echo "    adapter cursor no emitió deny: $out"; return 1; }
}
test_adapter_cursor_traduce_exit2_a_deny() { _adapter_sandbox _case_adapter_cursor_deny; }

_case_adapter_codex_deny() {
  printf '#!/usr/bin/env bash\necho "razon Y" >&2\nexit 2\n' > scripts/agent-hooks/gate-stub.sh
  local out
  out="$(echo '{}' | bash scripts/agent-hooks/adapters/gate-adapter.sh codex scripts/agent-hooks/gate-stub.sh 2>/dev/null)"
  printf '%s' "$out" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('permissionDecision')=='deny', d
" || { echo "    adapter codex no emitió permissionDecision:deny: $out"; return 1; }
}
test_adapter_codex_traduce_exit2_a_deny() { _adapter_sandbox _case_adapter_codex_deny; }

# FALSO POSITIVO guard: un gate que PERMITE no debe convertirse en deny.
_case_adapter_allow() {
  printf '#!/usr/bin/env bash\nexit 0\n' > scripts/agent-hooks/gate-stub.sh
  local out rc
  out="$(echo '{}' | bash scripts/agent-hooks/adapters/gate-adapter.sh cursor scripts/agent-hooks/gate-stub.sh 2>/dev/null)"; rc=$?
  [ "$rc" = "0" ] || { echo "    adapter devolvió exit $rc para un gate limpio"; return 1; }
  case "$out" in *'"deny"'*) echo "    adapter emitió deny para un gate limpio"; return 1 ;; esac
  return 0
}
test_adapter_no_bloquea_gate_limpio() { _adapter_sandbox _case_adapter_allow; }

# Fail-open: gate inexistente → permitir (un adapter roto no traba al dev).
_case_adapter_gate_ausente() {
  local rc
  echo '{}' | bash scripts/agent-hooks/adapters/gate-adapter.sh cursor scripts/agent-hooks/no-existe.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || { echo "    gate ausente no fue fail-open (exit $rc)"; return 1; }
}
test_adapter_gate_ausente_es_fail_open() { _adapter_sandbox _case_adapter_gate_ausente; }

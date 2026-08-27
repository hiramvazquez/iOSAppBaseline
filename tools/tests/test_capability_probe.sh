#!/usr/bin/env bash
# Probes funcionales: presente no equivale a operativo.

_probe_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/semgrep/rules" "$d/tools/semgrep/fixtures" "$d/bin"
  [ -f "$PROJECT_ROOT/tools/probe-capability.sh" ] && cp "$PROJECT_ROOT/tools/probe-capability.sh" "$d/tools/"
  cp "$PROJECT_ROOT/tools/semgrep-scan.sh" "$d/tools/"
  [ -f "$PROJECT_ROOT/tools/validate-harness.sh" ] && cp "$PROJECT_ROOT/tools/validate-harness.sh" "$d/tools/"
  # el orquestador viaja con sus checks: sin las libs, validate-harness sale 3 a propósito
  if ls "$PROJECT_ROOT"/tools/lib/validate-*.sh >/dev/null 2>&1; then
    mkdir -p "$d/tools/lib" && cp "$PROJECT_ROOT"/tools/lib/validate-*.sh "$d/tools/lib/"
  fi
  printf 'rules: []\n' > "$d/tools/semgrep/rules/dummy.yaml"
  printf 'print("fixture")\n' > "$d/tools/semgrep/fixtures/python-malo.py"
  (
    cd "$d" || exit 1
    git init -q .; git config user.email t@t.t; git config user.name t
    PATH="$d/bin:/usr/bin:/bin:/usr/sbin:/sbin" "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_json_status() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])'; }

_case_missing() {
  local out rc
  out="$(bash tools/probe-capability.sh semgrep 2>/dev/null)"; rc=$?
  [ "$rc" = "1" ] || { echo "    missing salió $rc: $out"; return 1; }
  assert_eq "missing" "$(_json_status "$out")"
}
test_binario_ausente_es_missing_no_operational() { _probe_sandbox _case_missing; }

_case_broken_x509() {
  stub bin/semgrep '#!/usr/bin/env bash\necho "X509: NO_CERTIFICATE_OR_CRL_FOUND" >&2\nexit 1\n'
  local out rc
  out="$(bash tools/probe-capability.sh semgrep 2>/dev/null)"; rc=$?
  [ "$rc" = "1" ] || { echo "    broken salió $rc: $out"; return 1; }
  assert_eq "broken" "$(_json_status "$out")" || return 1
  assert_contains "$out" 'X509'
}
test_binario_presente_que_crashea_es_broken_con_diagnostico() { _probe_sandbox _case_broken_x509; }

_case_operational() {
  # FALSO POSITIVO: la salud se prueba con un fixture malo; no se infiere de
  # `command -v`, de `--version` ni de una salida limpia sobre input vacío.
  stub bin/semgrep '#!/usr/bin/env bash\nprintf '\''{"results":[{"path":"x","start":{"line":1},"check_id":"probe","extra":{"severity":"ERROR","message":"ok"}}],"errors":[]}\n'\''\n'
  local out rc
  out="$(bash tools/probe-capability.sh semgrep 2>/dev/null)"; rc=$?
  [ "$rc" = "0" ] || { echo "    operational salió $rc: $out"; return 1; }
  assert_eq "operational" "$(_json_status "$out")" || return 1
  printf '%s' "$out" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["commit"]
assert d["platform"]
assert d["checked_at"].endswith("Z")
' >/dev/null
}
test_probe_que_ve_fixture_es_operational() { _probe_sandbox _case_operational; }

_case_json_sano_con_exit_roto_no_es_operational() {
  stub bin/semgrep '#!/usr/bin/env bash\nprintf '\''{"results":[{"path":"x","start":{"line":1},"check_id":"probe","extra":{"severity":"ERROR","message":"ok"}}],"errors":[]}\n'\''\nexit 2\n'
  local out rc
  out="$(bash tools/probe-capability.sh semgrep 2>/dev/null)"; rc=$?
  [ "$rc" = "1" ] || { echo "    JSON sano+exit2 salió $rc: $out"; return 1; }
  assert_eq "broken" "$(_json_status "$out")"
}
test_json_valido_no_oculta_exit_no_cero_del_scanner() { _probe_sandbox _case_json_sano_con_exit_roto_no_es_operational; }

_case_scanner_muerto_por_signal_es_broken() {
  stub bin/semgrep '#!/usr/bin/env bash\nprintf '\''{"results":[],"errors":[]}\n'\''\nkill -TERM $$\n'
  local out rc
  out="$(bash tools/probe-capability.sh semgrep 2>/dev/null)"; rc=$?
  [ "$rc" = "1" ] || { echo "    rc por señal salió $rc: $out"; return 1; }
  assert_eq "broken" "$(_json_status "$out")"
}
test_scanner_muerto_por_signal_no_se_confunde_con_clasificador_roto() {
  _probe_sandbox _case_scanner_muerto_por_signal_es_broken
}

_case_unknown() {
  local out rc
  out="$(bash tools/probe-capability.sh desconocida 2>/dev/null)"; rc=$?
  [ "$rc" = "3" ] || { echo "    capability desconocida salió $rc: $out"; return 1; }
  assert_eq "unknown" "$(_json_status "$out")"
}
test_capability_desconocida_es_clasificador_incapaz_exit3() { _probe_sandbox _case_unknown; }

_case_json_seguro() {
  stub bin/semgrep '#!/usr/bin/env bash\nprintf '\''crash "con comillas"\ny salto\n'\'' >&2\nexit 2\n'
  local out
  out="$(bash tools/probe-capability.sh semgrep 2>/dev/null)" || true
  printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null
}
test_diagnostico_multilinea_sigue_siendo_json_valido() { _probe_sandbox _case_json_seguro; }

_case_timeout_es_broken() {
  stub bin/semgrep '#!/usr/bin/env bash\nsleep 10\n'
  local out rc start end
  start="$(date +%s)"
  out="$(PROBE_TIMEOUT_SECS=1 bash tools/probe-capability.sh semgrep 2>/dev/null)"; rc=$?
  end="$(date +%s)"
  [ "$rc" = "1" ] || { echo "    timeout salió $rc: $out"; return 1; }
  [ $((end-start)) -lt 5 ] || { echo "    el probe tardó $((end-start))s pese al timeout de 1s"; return 1; }
  assert_eq "broken" "$(_json_status "$out")" || return 1
  assert_contains "$out" 'timeout'
}
test_probe_cuelgue_termina_como_broken() { _probe_sandbox _case_timeout_es_broken; }

_case_timeout_mata_descendientes() {
  stub bin/semgrep "#!/usr/bin/env bash\n(trap '' TERM; sleep 30) &\necho \$! > probe-child.pid\nwait\n"
  PROBE_TIMEOUT_SECS=1 bash tools/probe-capability.sh semgrep >/dev/null 2>&1 || true
  local child
  child="$(cat probe-child.pid 2>/dev/null || echo '')"
  [ -n "$child" ] || { echo "    el stub no registró su descendiente"; return 1; }
  if kill -0 "$child" 2>/dev/null; then
    kill -KILL "$child" 2>/dev/null || true
    echo "    el descendiente $child sobrevivió al timeout"
    return 1
  fi
}
test_timeout_limpia_el_grupo_de_procesos_completo() { _probe_sandbox _case_timeout_mata_descendientes; }

_case_validate_no_confunde_presencia_con_salud() {
  stub bin/semgrep '#!/usr/bin/env bash\necho "X509: empty trust anchors" >&2\nexit 1\n'
  local out
  out="$(bash tools/validate-harness.sh 2>&1)" || true
  assert_contains "$out" 'semgrep broken' || return 1
  case "$out" in *'✅ semgrep'*) echo "    validate mostró verde por mera presencia"; return 1 ;; esac
}
test_validate_harness_consume_el_probe_funcional() { _probe_sandbox _case_validate_no_confunde_presencia_con_salud; }

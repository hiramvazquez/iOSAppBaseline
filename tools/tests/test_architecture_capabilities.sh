#!/usr/bin/env bash
# Estados explícitos de ciclos/complejidad: ausencia nunca significa "limpio".

_arch_repo() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/bin"
  cp "$PROJECT_ROOT/tools/architecture-check.sh" "$d/tools/"
  (
    cd "$d" || exit 1
    git init -q .
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_status() { printf '%s\n' "$1" | head -1 | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])'; }

_case_sin_config_missing() {
  local out rc
  out="$(bash tools/architecture-check.sh architecture_cycles 2>/dev/null)"; rc=$?
  [ "$rc" = "1" ] || { echo "    config ausente salió $rc: $out"; return 1; }
  assert_eq missing "$(_status "$out")"
}
test_ausencia_no_se_confunde_con_sin_ciclos() { _arch_repo _case_sin_config_missing; }

_case_unsupported_explicito() {
  # FALSO POSITIVO: "unsupported" es una declaración honesta de cobertura,
  # no evidencia de que el grafo esté limpio ni un fallo del código.
  cp "$PROJECT_ROOT/tools/architecture.conf.example" tools/architecture.conf
  local out rc
  out="$(bash tools/architecture-check.sh architecture_cycles)"; rc=$?
  [ "$rc" = "0" ] || { echo "    unsupported explícito salió $rc: $out"; return 1; }
  assert_eq unsupported "$(_status "$out")"
}
test_stack_sin_detector_declara_unsupported_no_sin_ciclos() { _arch_repo _case_unsupported_explicito; }

_write_adapter_config() {
  cat > tools/architecture.conf <<EOF
{"schema":1,"capabilities":{"architecture_cycles":{"adapter":["$1"]},"architecture_complexity":{"status":"unsupported","reason":"no aplica"}}}
EOF
}

_case_adapter_operational() {
  stub bin/cycles '#!/usr/bin/env bash\necho "ARCHITECTURE_PROBE capability=architecture_cycles status=operational"\n'
  _write_adapter_config ./bin/cycles
  local out
  out="$(bash tools/architecture-check.sh architecture_cycles)" || { echo "    adapter sano falló: $out"; return 1; }
  assert_eq operational "$(_status "$out")"
}
test_adapter_solo_es_operational_con_probe_exacto() { _arch_repo _case_adapter_operational; }

_case_exit_cero_sin_marker_broken() {
  stub bin/cycles '#!/usr/bin/env bash\necho todo-bien\n'
  _write_adapter_config ./bin/cycles
  local out rc
  out="$(bash tools/architecture-check.sh architecture_cycles)"; rc=$?
  [ "$rc" = "1" ] || { echo "    adapter mudo salió $rc: $out"; return 1; }
  assert_eq broken "$(_status "$out")"
}
test_exit_cero_sin_evidencia_no_es_operational() { _arch_repo _case_exit_cero_sin_marker_broken; }

_case_adapter_ausente_missing() {
  _write_adapter_config ./bin/no-existe
  local out rc
  out="$(bash tools/architecture-check.sh architecture_cycles)"; rc=$?
  [ "$rc" = "1" ] || { echo "    adapter ausente salió $rc: $out"; return 1; }
  assert_eq missing "$(_status "$out")"
}
test_adapter_declarado_pero_ausente_es_missing() { _arch_repo _case_adapter_ausente_missing; }

_case_config_rota_exit3() {
  printf '{roto\n' > tools/architecture.conf
  local out rc
  out="$(bash tools/architecture-check.sh architecture_cycles 2>&1)"; rc=$?
  [ "$rc" = "3" ] || { echo "    config rota salió $rc: $out"; return 1; }
  assert_contains "$out" 'ARCHITECTURE_SUMMARY'
}
test_config_rota_es_no_evaluable_exit3() { _arch_repo _case_config_rota_exit3; }

#!/usr/bin/env bash
# La caché acelera solo evidencia verde de Semgrep staged. La clave debe
# representar TODO lo que cambia el significado del scan; misses y fallos
# siempre vuelven al detector real.

_gc_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/semgrep/rules" "$d/bin" "$d/.agents/state"
  cp "$PROJECT_ROOT/tools/semgrep-scan.sh" "$d/tools/"
  cp "$PROJECT_ROOT/tools/gate-cache.sh" "$d/tools/" 2>/dev/null || true
  printf 'rules: []\n' > "$d/tools/semgrep/rules/dummy.yaml"
  cat > "$d/bin/semgrep" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  if [ "${FAKE_MUTATE_ON_VERSION:-0}" = "1" ] && [ ! -f .version-mutated ]; then
    : > .version-mutated
    printf 'eval(input())\n' > app.py
    git add app.py
  fi
  if [ "${FAKE_ADD_TARGET_ON_VERSION:-0}" = "1" ] && [ ! -f .target-mutated ]; then
    : > .target-mutated
    printf 'eval(input())\n' > added.py
    git add added.py
  fi
  echo "${FAKE_VERSION:-fake-semgrep 1}"
  exit 0
fi
printf '%s\n' "$*" >> "${FAKE_CALLS:?}"
if [ "${FAKE_MUTATE:-0}" = "1" ]; then
  printf '# mutado durante scan\n' >> app.py
  git add app.py
fi
if [ -n "${FAKE_RESULT:-}" ]; then
  printf '%s\n' "$FAKE_RESULT"
else
  printf '%s\n' '{"results":[],"errors":[]}'
fi
exit "${FAKE_RC:-0}"
EOF
  chmod +x "$d/bin/semgrep"
  (
    cd "$d" || exit 1
    git init -q .; git config user.email t@t.t; git config user.name t
    echo base > seed; git add seed tools/semgrep/rules/dummy.yaml
    git commit -qm base
    echo 'print("ok")' > app.py; git add app.py
    export PATH="$d/bin:$PATH" FAKE_CALLS="$d/calls"
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_hit_evitar_segundo_scan() {
  bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  [ "$(wc -l < "$FAKE_CALLS" | tr -d ' ')" = "1" ] \
    || { echo "    el mismo diff verde ejecutó Semgrep más de una vez"; return 1; }
}
test_mismo_diff_verde_reutiliza_cache() { _gc_sandbox _case_hit_evitar_segundo_scan; }

_case_diff_reglas_head_binario_invalidan() {
  bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  echo '# cambio staged' >> app.py; git add app.py
  bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  echo '# regla distinta' >> tools/semgrep/rules/dummy.yaml; git add tools/semgrep/rules/dummy.yaml
  bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  echo '# binario distinto' >> bin/semgrep
  bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  [ "$(wc -l < "$FAKE_CALLS" | tr -d ' ')" = "4" ] \
    || { echo "    diff/reglas/binario no invalidaron exactamente cada vez"; return 1; }
}
test_key_incluye_diff_reglas_y_binario() { _gc_sandbox _case_diff_reglas_head_binario_invalidan; }

_case_key_incluye_head_version_y_plataforma() {
  local binary key1 key2 key3 key4
  binary="$(command -v semgrep)"
  key1="$(GATE_CACHE_PLATFORM=p1 FAKE_VERSION=v1 bash tools/gate-cache.sh key semgrep-staged tools/semgrep/rules "$binary")" || return 1
  git reset -q app.py; echo otro > other; git add other; git commit -qm otro; git add app.py
  key2="$(GATE_CACHE_PLATFORM=p1 FAKE_VERSION=v1 bash tools/gate-cache.sh key semgrep-staged tools/semgrep/rules "$binary")" || return 1
  key3="$(GATE_CACHE_PLATFORM=p1 FAKE_VERSION=v2 bash tools/gate-cache.sh key semgrep-staged tools/semgrep/rules "$binary")" || return 1
  key4="$(GATE_CACHE_PLATFORM=p2 FAKE_VERSION=v2 bash tools/gate-cache.sh key semgrep-staged tools/semgrep/rules "$binary")" || return 1
  [ "$key1" != "$key2" ] && [ "$key2" != "$key3" ] && [ "$key3" != "$key4" ] \
    || { echo "    HEAD, versión o plataforma no cambió la key"; return 1; }
}
test_key_incluye_head_version_y_plataforma() { _gc_sandbox _case_key_incluye_head_version_y_plataforma; }

_case_key_incluye_targets_efectivos() {
  local binary key1 key2
  binary="$(command -v semgrep)"
  key1="$(bash tools/gate-cache.sh key semgrep-staged tools/semgrep/rules "$binary" app.py)" || return 1
  key2="$(bash tools/gate-cache.sh key semgrep-staged tools/semgrep/rules "$binary" other.py)" || return 1
  [ "$key1" != "$key2" ] || { echo "    el conjunto de targets no cambió la key"; return 1; }
}
test_key_incluye_targets_efectivos() { _gc_sandbox _case_key_incluye_targets_efectivos; }

_case_exit_no_verde_nunca_cachea() {
  export FAKE_RESULT='{"results":[],"errors":[{"level":"error","message":"boom"}]}'
  bash tools/semgrep-scan.sh --staged >/dev/null 2>&1; [ "$?" = "3" ] || return 1
  bash tools/semgrep-scan.sh --staged >/dev/null 2>&1; [ "$?" = "3" ] || return 1
  [ "$(wc -l < "$FAKE_CALLS" | tr -d ' ')" = "2" ] \
    || { echo "    exit 3 fue cacheado"; return 1; }
}
test_exit3_nunca_se_cachea() { _gc_sandbox _case_exit_no_verde_nunca_cachea; }

_case_exit1_nunca_cachea() {
  export FAKE_RESULT='{"results":[{"path":"app.py","start":{"line":1},"check_id":"x","extra":{"severity":"ERROR","message":"m"}}],"errors":[]}'
  bash tools/semgrep-scan.sh --staged >/dev/null 2>&1; local first=$?
  [ "$first" = "1" ] || { echo "    primer scan con hallazgo devolvió $first"; return 1; }
  bash tools/semgrep-scan.sh --staged >/dev/null 2>&1; local second=$?
  [ "$second" = "1" ] || { echo "    segundo scan con hallazgo devolvió $second"; return 1; }
  [ "$(wc -l < "$FAKE_CALLS" | tr -d ' ')" = "2" ] || { echo "    exit 1 fue cacheado"; return 1; }
}
test_exit1_nunca_se_cachea() { _gc_sandbox _case_exit1_nunca_cachea; }

_case_warning_nunca_cachea() {
  export FAKE_RESULT='{"results":[{"path":"app.py","start":{"line":1},"check_id":"x","extra":{"severity":"WARNING","message":"m"}}],"errors":[]}'
  bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  [ "$(wc -l < "$FAKE_CALLS" | tr -d ' ')" = "2" ] || { echo "    resultado con warnings fue cacheado"; return 1; }
}
test_resultado_con_warnings_no_se_cachea() { _gc_sandbox _case_warning_nunca_cachea; }

_case_modo_all_nunca_cachea() {
  bash tools/semgrep-scan.sh --all >/dev/null 2>&1 || return 1
  bash tools/semgrep-scan.sh --all >/dev/null 2>&1 || return 1
  [ "$(wc -l < "$FAKE_CALLS" | tr -d ' ')" = "2" ] || { echo "    modo --all usó la caché staged"; return 1; }
}
test_cache_solo_aplica_a_staged() { _gc_sandbox _case_modo_all_nunca_cachea; }

_case_cache_corrupta_es_miss() {
  bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  printf 'roto\n' > .agents/state/gate-cache/semgrep/*.json
  bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  [ "$(wc -l < "$FAKE_CALLS" | tr -d ' ')" = "2" ] || { echo "    caché corrupta evitó el scan real"; return 1; }
  ! find .agents/state/gate-cache/semgrep -name '.tmp-*' -print | grep -q . \
    || { echo "    quedaron temporales de escritura atómica"; return 1; }
}
test_cache_corrupta_degrada_a_miss_y_put_es_atomico() { _gc_sandbox _case_cache_corrupta_es_miss; }

_case_payload_no_verde_es_miss() {
  local cache_file key
  GATE_CACHE_NOW=100 bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  cache_file="$(find .agents/state/gate-cache/semgrep -name '*.json' -print -quit)"
  key="$(basename "$cache_file" .json)"
  printf '{"schema":1,"key":"%s","created_at":100,"payload":"SEMGREP_SUMMARY errors=0 warns=99\\n"}\n' \
    "$key" > "$cache_file"
  GATE_CACHE_NOW=100 bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  [ "$(wc -l < "$FAKE_CALLS" | tr -d ' ')" = "2" ] \
    || { echo "    un payload no-verde fabricado evitó el scan real"; return 1; }
}
test_cache_solo_acepta_payload_verde_canonico() { _gc_sandbox _case_payload_no_verde_es_miss; }

_case_target_con_cambios_unstaged_no_cachea() {
  bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  printf '# cambio solo en worktree\n' >> app.py
  bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  [ "$(wc -l < "$FAKE_CALLS" | tr -d ' ')" = "2" ] \
    || { echo "    se reutilizó evidencia staged sobre contenido worktree distinto"; return 1; }
}
test_target_staged_con_cambios_unstaged_desactiva_cache() {
  _gc_sandbox _case_target_con_cambios_unstaged_no_cachea
}

_case_cambio_durante_scan_no_publica_cache() {
  FAKE_MUTATE=1 bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  FAKE_MUTATE=0 bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  [ "$(wc -l < "$FAKE_CALLS" | tr -d ' ')" = "2" ] \
    || { echo "    se publicó cache bajo una key que cambió durante el scan"; return 1; }
}
test_key_se_revalida_antes_de_publicar_cache() { _gc_sandbox _case_cambio_durante_scan_no_publica_cache; }

_case_cambio_durante_version_no_consume_hit() {
  bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  FAKE_MUTATE_ON_VERSION=1 bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  [ "$(wc -l < "$FAKE_CALLS" | tr -d ' ')" = "2" ] \
    || { echo "    un cambio staged durante --version consumió evidencia vieja"; return 1; }
  grep -q 'eval(input())' app.py || { echo "    el fixture no mutó el índice"; return 1; }
}
test_key_captura_mutacion_del_indice_durante_version() {
  _gc_sandbox _case_cambio_durante_version_no_consume_hit
}

_case_target_nuevo_durante_version_se_escanea() {
  bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  FAKE_ADD_TARGET_ON_VERSION=1 bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  [ "$(wc -l < "$FAKE_CALLS" | tr -d ' ')" = "2" ] \
    || { echo "    un target staged nuevo consumió evidencia vieja"; return 1; }
  grep -q 'added.py' "$FAKE_CALLS" \
    || { echo "    el scan real no recibió el target añadido durante --version"; return 1; }
}
test_target_nuevo_durante_version_invalida_hit_y_se_escanea() {
  _gc_sandbox _case_target_nuevo_durante_version_se_escanea
}

_case_ttl_expira() {
  GATE_CACHE_NOW=100 GATE_CACHE_TTL_SECONDS=10 bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  GATE_CACHE_NOW=105 GATE_CACHE_TTL_SECONDS=10 bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  GATE_CACHE_NOW=111 GATE_CACHE_TTL_SECONDS=10 bash tools/semgrep-scan.sh --staged >/dev/null 2>&1 || return 1
  [ "$(wc -l < "$FAKE_CALLS" | tr -d ' ')" = "2" ] \
    || { echo "    TTL no produjo hit antes y miss después del vencimiento"; return 1; }
}
test_cache_expira_por_ttl() { _gc_sandbox _case_ttl_expira; }

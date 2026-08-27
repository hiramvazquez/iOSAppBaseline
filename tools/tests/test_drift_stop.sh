#!/usr/bin/env bash
# drift-stop: bloquea el cierre de turno SOLO por errores NUEVOS respecto al
# baseline de la sesión. Su razón de ser ES su guard de falso positivo: la
# deuda preexistente no puede bloquear a quien no la creó (AGENTS.md §10 la
# gestiona por ledger, no por bloqueo).
# Cierra parte de f-meta-fp-manifiesto.

_ds_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/tools"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  # check-drift stub controlable: reporta lo que haya en drift-fixture.txt
  cat > "$d/tools/check-drift.sh" <<'EOF'
#!/usr/bin/env bash
cat drift-fixture.txt 2>/dev/null
echo "DRIFT_SUMMARY errors=$(grep -c '^❌' drift-fixture.txt 2>/dev/null || echo 0) warns=0"
exit 0
EOF
  chmod +x "$d/tools/check-drift.sh"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo seed > seed.txt; git add -A; git commit -qm init 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}
_stop() { echo '{}' | bash scripts/agent-hooks/drift-stop.sh >/dev/null 2>&1; echo $?; }

# ── FALSO POSITIVO guard: la deuda PREEXISTENTE no bloquea ──────────
_case_deuda_preexistente_no_bloquea() {
  printf '❌ archivo gigante: legacy.swift:9999\n' > drift-fixture.txt
  local r1 r2
  r1="$(_stop)"   # primer Stop: crea baseline (con la deuda dentro) → permite
  r2="$(_stop)"   # segundo Stop: misma deuda, nada nuevo → permite
  [ "$r1" = "0" ] || { echo "    el Stop de baseline bloqueó (rc=$r1)"; return 1; }
  [ "$r2" = "0" ] || { echo "    FALSO POSITIVO: deuda preexistente bloqueó el turno (rc=$r2)"; return 1; }
}
test_deuda_preexistente_no_bloquea() { _ds_sandbox _case_deuda_preexistente_no_bloquea; }

# ── …pero un error NUEVO en la sesión SÍ bloquea ────────────────────
_case_error_nuevo_bloquea() {
  printf '❌ archivo gigante: legacy.swift:9999\n' > drift-fixture.txt
  _stop >/dev/null                     # baseline con 1 error viejo
  printf '❌ archivo gigante: legacy.swift:9999\n❌ secreto: Nuevo.swift:1\n' > drift-fixture.txt
  local r; r="$(_stop)"
  [ "$r" = "2" ] || { echo "    un error NUEVO no bloqueó el cierre (rc=$r)"; return 1; }
}
test_error_nuevo_de_la_sesion_bloquea() { _ds_sandbox _case_error_nuevo_bloquea; }

# ── el baseline se rehace al commitear (HEAD nuevo) ─────────────────
_case_commit_rebasea() {
  printf '❌ e1\n' > drift-fixture.txt
  _stop >/dev/null
  printf '❌ e1\n❌ e2-nuevo\n' > drift-fixture.txt
  # Commit entre medias → HEAD cambia → el siguiente Stop re-basea y permite.
  echo x > f.txt; git add f.txt; git commit -qm c 2>/dev/null
  local r; r="$(_stop)"
  [ "$r" = "0" ] || { echo "    tras commitear no se re-baseó (rc=$r)"; return 1; }
}
test_commitear_rebasea_el_baseline() { _ds_sandbox _case_commit_rebasea; }

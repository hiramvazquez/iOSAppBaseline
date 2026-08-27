#!/usr/bin/env bash
# Manifiesto estructurado de capacidades + bloques documentales generados.

_cap_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/docs"
  cp "$PROJECT_ROOT/tools/tests/fixtures/capabilities.json" "$d/tools/capabilities.json"
  [ -f "$PROJECT_ROOT/tools/render-capabilities.sh" ] \
    && cp "$PROJECT_ROOT/tools/render-capabilities.sh" "$d/tools/render-capabilities.sh"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_render_determinista() {
  local out
  out="$(bash tools/render-capabilities.sh --render 2>&1)" || return 1
  assert_contains "$out" '| `ring3` | sí | no | `tools/check-ring3.sh` |'
  assert_contains "$out" '| `architecture_cycles` | no | no | externo |'
  assert_contains "$out" 'CAPABILITIES_SUMMARY total=3 required_full=2 required_lite=1'
}
test_manifiesto_valido_renderiza_tabla_determinista() { _cap_sandbox _case_render_determinista; }

_case_check_exacto_y_prosa_ignorada() {
  # FALSO POSITIVO: una frase libre contradictoria no pertenece al contrato
  # estructurado; el detector solo juzga el bloque delimitado que sí genera.
  {
    echo 'Esta prosa puede decir CI opcional: el check no intenta interpretarla.'
    echo '<!-- BEGIN GENERATED: capabilities -->'
    bash tools/render-capabilities.sh --render | sed '/^CAPABILITIES_SUMMARY /d'
    echo '<!-- END GENERATED: capabilities -->'
  } > docs/claims.md
  bash tools/render-capabilities.sh --check >/dev/null 2>&1
}
test_check_compara_bloque_y_no_interpreta_prosa_libre() { _cap_sandbox _case_check_exacto_y_prosa_ignorada; }

_case_drift_bloque_falla() {
  printf '%s\n' '<!-- BEGIN GENERATED: capabilities -->' 'contenido viejo' \
    '<!-- END GENERATED: capabilities -->' > docs/claims.md
  local out rc
  out="$(bash tools/render-capabilities.sh --check 2>&1)"; rc=$?
  [ "$rc" = "1" ] || { echo "    drift documental salió con exit $rc: $out"; return 1; }
  assert_contains "$out" 'docs/claims.md'
  assert_contains "$out" 'CAPABILITIES_SUMMARY'
}
test_check_detecta_drift_del_bloque_generado() { _cap_sandbox _case_drift_bloque_falla; }

_case_write_reemplaza_solo_bloque() {
  printf '%s\n' 'antes' '<!-- BEGIN GENERATED: capabilities -->' 'viejo' \
    '<!-- END GENERATED: capabilities -->' 'después' > docs/claims.md
  bash tools/render-capabilities.sh --write >/dev/null 2>&1 || return 1
  grep -q '^antes$' docs/claims.md || return 1
  grep -q '^después$' docs/claims.md || return 1
  grep -q '| `ring3` | sí | no |' docs/claims.md || return 1
  ! grep -q '^viejo$' docs/claims.md
}
test_write_preserva_prosa_y_actualiza_solo_bloque() { _cap_sandbox _case_write_reemplaza_solo_bloque; }

_case_write_no_sigue_symlink_fuera_del_repo() {
  local outside before out rc
  outside="$(mktemp -d)"
  printf '%s\n' '<!-- BEGIN GENERATED: capabilities -->' 'intacto' \
    '<!-- END GENERATED: capabilities -->' > "$outside/claims.md"
  before="$(cksum "$outside/claims.md")"
  rm -rf docs
  ln -s "$outside" docs
  out="$(bash tools/render-capabilities.sh --write 2>&1)"; rc=$?
  [ "$rc" = "3" ] || { rm -rf "$outside"; echo "    symlink fuera del repo salió con exit $rc: $out"; return 1; }
  [ "$(cksum "$outside/claims.md")" = "$before" ] \
    || { rm -rf "$outside"; echo "    --write modificó un target fuera del repo"; return 1; }
  rm -rf "$outside"
}
test_write_rechaza_symlink_que_escapa_del_repo() { _cap_sandbox _case_write_no_sigue_symlink_fuera_del_repo; }

_case_install_agrega_bloque_sin_pisar_prosa() {
  printf 'documentación local del adoptante\n' > docs/claims.md
  bash tools/render-capabilities.sh --install >/dev/null 2>&1 || return 1
  grep -q '^documentación local del adoptante$' docs/claims.md || return 1
  grep -q '^<!-- BEGIN GENERATED: capabilities -->$' docs/claims.md || return 1
  bash tools/render-capabilities.sh --check >/dev/null 2>&1
}
test_install_funde_fragmento_generado_y_preserva_prosa_local() {
  _cap_sandbox _case_install_agrega_bloque_sin_pisar_prosa
}

# GNU primero, BSD despues — el orden IMPORTA y no es estilo: `stat -f` de GNU
# no falla, imprime el estado del FILESYSTEM con exit 0, asi que con BSD delante
# el fallback nunca corre y en Linux esto devolvia un volcado en vez del modo.
# El sintoma era un test rojo que decia "644, esperaba 644": la comparacion
# estaba rota, no el codigo que probaba. Verde en el Mac de quien lo escribio,
# rojo en CI. La misma trampa esta documentada en check-verify-marker.sh y en
# check-review-marker.sh, con este mismo comentario — es la tercera vez.
_file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null
}

_case_write_conserva_permisos() {
  printf '%s\n' '<!-- BEGIN GENERATED: capabilities -->' 'viejo' \
    '<!-- END GENERATED: capabilities -->' > docs/claims.md
  chmod 644 docs/claims.md
  bash tools/render-capabilities.sh --write >/dev/null 2>&1 || return 1
  [ "$(_file_mode docs/claims.md)" = "644" ] \
    || { echo "    --write dejó modo $(_file_mode docs/claims.md), esperaba 644"; return 1; }
}
test_write_atomico_conserva_el_modo_del_documento() { _cap_sandbox _case_write_conserva_permisos; }

_case_error_de_write_es_exit_3() {
  printf '%s\n' '<!-- BEGIN GENERATED: capabilities -->' 'viejo' \
    '<!-- END GENERATED: capabilities -->' > docs/claims.md
  chmod 500 docs
  local out rc
  out="$(bash tools/render-capabilities.sh --write 2>&1)"; rc=$?
  chmod 700 docs
  [ "$rc" = "3" ] || { echo "    fallo de filesystem salió con exit $rc: $out"; return 1; }
  case "$out" in *Traceback*) echo "    el error expuso traceback"; return 1 ;; esac
}
test_error_de_filesystem_es_detector_mudo_sin_traceback() { _cap_sandbox _case_error_de_write_es_exit_3; }

_case_json_roto_es_exit_3() {
  printf '{roto\n' > tools/capabilities.json
  local rc
  bash tools/render-capabilities.sh --check >/dev/null 2>&1; rc=$?
  [ "$rc" = "3" ] || { echo "    JSON ilegible salió con exit $rc, esperaba 3"; return 1; }
}
test_manifiesto_ilegible_es_detector_mudo_no_drift() { _cap_sandbox _case_json_roto_es_exit_3; }

_case_schema_incompleto_es_exit_3() {
  printf '%s\n' '{"schema":1,"capabilities":{},"documents":["docs/claims.md"]}' \
    > tools/capabilities.json
  local rc
  bash tools/render-capabilities.sh --render >/dev/null 2>&1; rc=$?
  [ "$rc" = "3" ] || { echo "    contrato incompleto salió con exit $rc, esperaba 3"; return 1; }
}
test_manifiesto_sin_capacidades_no_aprueba_en_vacio() { _cap_sandbox _case_schema_incompleto_es_exit_3; }

test_manifiesto_real_cubre_los_tres_docs_operativos() {
  python3 - "$PROJECT_ROOT/tools/capabilities.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
want = {"README.md", "docs/ADOPTION.md", "ci/README.md"}
got = set(data.get("documents", []))
if got != want:
    print(f"    documents={sorted(got)}; esperaba {sorted(want)}")
    raise SystemExit(1)
PY
}

test_bloques_operativos_del_repo_no_tienen_drift() {
  (cd "$PROJECT_ROOT" && bash tools/render-capabilities.sh --check >/dev/null)
}

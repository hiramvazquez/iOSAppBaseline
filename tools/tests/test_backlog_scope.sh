#!/usr/bin/env bash
# Scope mecánico del backlog: frontmatter es la única fuente.

_scope_repo() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/backlog" "$d/backlog" "$d/src" "$d/tests"
  [ -f "$PROJECT_ROOT/tools/backlog/scope-check.sh" ] && cp "$PROJECT_ROOT/tools/backlog/scope-check.sh" "$d/tools/backlog/"
  (
    cd "$d" || exit 1
    git init -q -b main .; git config user.email t@t.t; git config user.name t
    printf 'base\n' > src/allowed.txt
    printf 'base\n' > src/rename-me.txt
    git add -A; git commit -qm base
    git switch -qc story-work
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_scope_story() {
  cat > backlog/0001-test.md <<EOF
---
id: 0001
status: in-progress
base: main
scope: |             # única allowlist mecánica; el cuerpo no la amplía
$1
---
## Fuera de scope
- src/forbidden.txt
EOF
}

_scope_run() {
  bash tools/backlog/scope-check.sh --story backlog/0001-test.md \
    --base main --head HEAD --worktree "$PWD"
}

_case_permite_diff_indice_worktree_untracked() {
  _scope_story '  src/**
  tests/**'
  printf 'commit\n' > src/committed.txt
  git add src/committed.txt; git commit -qm allowed
  printf 'staged\n' > tests/staged.txt; git add tests/staged.txt
  printf 'modified\n' >> src/allowed.txt
  printf 'untracked\n' > tests/untracked.txt
  _scope_run >/dev/null
}
test_scope_incluye_rango_indice_modificados_y_untracked() { _scope_repo _case_permite_diff_indice_worktree_untracked; }

_case_fuera_scope_bloquea() {
  _scope_story '  src/allowed.txt'
  printf 'no\n' > src/forbidden.txt
  local out rc
  out="$(_scope_run 2>&1)"; rc=$?
  [ "$rc" = "1" ] || { echo "    fuera de scope salió $rc: $out"; return 1; }
  assert_contains "$out" 'src/forbidden.txt'
}
test_untracked_fuera_de_scope_bloquea() { _scope_repo _case_fuera_scope_bloquea; }

_case_cuerpo_no_amplia_scope() {
  # FALSO POSITIVO: una ruta mencionada bajo "Fuera de scope" no puede
  # convertirse accidentalmente en permiso por un parser que lea el cuerpo.
  _scope_story '  src/allowed.txt'
  printf 'no\n' > src/forbidden.txt
  _scope_run >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    una ruta del cuerpo amplió el frontmatter"; return 1; }
}
test_fuera_de_scope_en_prosa_no_es_allowlist() { _scope_repo _case_cuerpo_no_amplia_scope; }

_case_asterisco_no_cruza_directorios() {
  _scope_story '  src/*.txt'
  mkdir -p src/nested
  printf 'no\n' > src/nested/deep.txt
  _scope_run >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    '*' cruzó un directorio"; return 1; }
}
test_asterisco_simple_no_cruza_directorios() { _scope_repo _case_asterisco_no_cruza_directorios; }

_case_doble_asterisco_si_cruza_directorios() {
  _scope_story '  src/**/*.txt'
  mkdir -p src/nested
  printf 'raíz\n' > src/root.txt
  printf 'profundo\n' > src/nested/deep.txt
  _scope_run >/dev/null
}
test_doble_asterisco_cruza_cero_o_mas_directorios() { _scope_repo _case_doble_asterisco_si_cruza_directorios; }

_case_rename_valida_origen_y_destino() {
  _scope_story '  src/new-name.txt'
  git mv src/rename-me.txt src/new-name.txt
  local out rc
  out="$(_scope_run 2>&1)"; rc=$?
  [ "$rc" = "1" ] || { echo "    rename con origen fuera pasó: $out"; return 1; }
  assert_contains "$out" 'src/rename-me.txt'
}
test_rename_exige_scope_para_origen_y_destino() { _scope_repo _case_rename_valida_origen_y_destino; }

_case_delete_fuera_bloquea() {
  _scope_story '  tests/**'
  git rm -q src/allowed.txt
  _scope_run >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    delete fuera de scope pasó"; return 1; }
}
test_delete_tambien_se_valida() { _scope_repo _case_delete_fuera_bloquea; }

_case_story_permitida_ledger_no() {
  _scope_story '  src/allowed.txt'
  mkdir -p tools/findings docs/process
  printf 'x\n' >> backlog/0001-test.md
  printf '{}\n' > tools/findings/ledger.jsonl
  printf 'vista\n' > docs/process/findings-ledger.md
  local out rc
  out="$(_scope_run 2>&1)"; rc=$?
  [ "$rc" = "1" ] || { echo "    ledger no enumerado salió $rc: $out"; return 1; }
  assert_contains "$out" 'tools/findings/ledger.jsonl'
}
test_solo_story_es_automatica_y_ledger_debe_enumerarse() { _scope_repo _case_story_permitida_ledger_no; }

_case_scope_snapshot_no_se_amplia() {
  _scope_story '  src/allowed.txt'
  cp backlog/0001-test.md trusted-story.md
  sed -i.bak 's#src/allowed.txt#**#' backlog/0001-test.md; rm -f backlog/0001-test.md.bak
  printf 'no\n' > src/forbidden.txt
  bash tools/backlog/scope-check.sh --story backlog/0001-test.md \
    --scope-from "$PWD/trusted-story.md" --base main --head HEAD --worktree "$PWD" >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    ampliar scope después del snapshot autorizó el cambio"; return 1; }
}
test_scope_se_lee_del_snapshot_confiable() { _scope_repo _case_scope_snapshot_no_se_amplia; }

_case_utf8_invalido_exit3() {
  printf '\377\376\n' > backlog/0001-test.md
  local out rc
  out="$(_scope_run 2>&1)"; rc=$?
  [ "$rc" = "3" ] || { echo "    story con UTF-8 inválido no dio exit3: $out"; return 1; }
  case "$out" in *Traceback*) echo "    story inválida filtró traceback"; return 1 ;; esac
}
test_story_ilegible_es_exit3_sin_traceback() { _scope_repo _case_utf8_invalido_exit3; }

_case_scope_invalido_exit3() {
  _scope_story '  ../fuera/**'
  local rc
  _scope_run >/dev/null 2>&1; rc=$?
  [ "$rc" = "3" ] || { echo "    patrón inseguro salió $rc, esperaba 3"; return 1; }
}
test_patron_que_escapa_repo_es_exit3() { _scope_repo _case_scope_invalido_exit3; }

_case_ref_inexistente_exit3() {
  _scope_story '  src/**'
  bash tools/backlog/scope-check.sh --story backlog/0001-test.md \
    --base no-existe --head HEAD --worktree "$PWD" >/dev/null 2>&1
  [ "$?" = "3" ] || { echo "    ref irresoluble no dio exit3"; return 1; }
}
test_ref_irresoluble_no_parece_scope_limpio() { _scope_repo _case_ref_inexistente_exit3; }

_case_ref_opcion_exit3() {
  _scope_story '  src/**'
  bash tools/backlog/scope-check.sh --story backlog/0001-test.md \
    --base=-h --head HEAD --worktree "$PWD" >/dev/null 2>&1
  [ "$?" = "3" ] || { echo "    ref parecida a opción no dio exit3"; return 1; }
}
test_ref_no_puede_inyectar_opciones_git() { _scope_repo _case_ref_opcion_exit3; }

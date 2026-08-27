#!/usr/bin/env bash
# check-conflict-markers: git NO impide commitear marcadores de conflicto —
# solo rechaza paths "unmerged", y un `git add` del archivo con los <<<<<<<
# dentro deja el index "resuelto". Pasó en vivo al concluir el primer merge
# del primer proyecto real: el ledger JSONL quedó corrupto en develop con
# ambos lados del conflicto Y los tres marcadores. Estos tests fijan el
# detector y sus falsos positivos (⅓ de la suite, regla test_meta_fp):
# citar UN marcador en un doc no puede bloquear (ley del 10%).

_cm_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools"
  cp "$PROJECT_ROOT/tools/check-conflict-markers.sh" "$d/tools/"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo x > seed.txt; git add seed.txt; git commit -qm init 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_marcadores_staged_bloquea() {
  # El caso real: archivo "resuelto" a mano dejando los marcadores dentro.
  {
    printf '<%.0s' 1 2 3 4 5 6 7; printf ' HEAD\n'
    echo '{"id":"a","status":"fixed"}'
    printf '=%.0s' 1 2 3 4 5 6 7; printf '\n'
    echo '{"id":"a","status":"open"}'
    printf '>%.0s' 1 2 3 4 5 6 7; printf ' rama\n'
  } > ledger.jsonl
  git add ledger.jsonl
  bash tools/check-conflict-markers.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un archivo staged CON marcadores de conflicto pasó el check"; return 1; }
}
test_marcadores_de_conflicto_staged_bloquean() { _cm_sandbox _case_marcadores_staged_bloquea; }

_case_cita_suelta_pasa() {
  # FALSO POSITIVO: un doc que cita solo el marcador de apertura (p. ej. una
  # lección explicando el bug) no contiene un conflicto — no puede bloquear.
  {
    echo '# Lección: marcadores de conflicto'
    printf '<%.0s' 1 2 3 4 5 6 7; printf ' HEAD es el lado tuyo del conflicto\n'
  } > docs.md
  git add docs.md
  bash tools/check-conflict-markers.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    un doc que CITA un marcador suelto fue bloqueado (falso positivo)"; return 1; }
}
test_citar_un_marcador_suelto_pasa() { _cm_sandbox _case_cita_suelta_pasa; }

_case_arbol_limpio_pasa() {
  echo "hola" > normal.txt; git add normal.txt
  bash tools/check-conflict-markers.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    un staged limpio fue bloqueado"; return 1; }
}
test_staged_sin_marcadores_pasa() { _cm_sandbox _case_arbol_limpio_pasa; }

_case_marcador_solo_en_working_tree_pasa() {
  # El check mira el INDEX (lo que se va a commitear), no el working tree:
  # un conflicto a medio resolver SIN stagear no es asunto de este gate.
  {
    printf '<%.0s' 1 2 3 4 5 6 7; printf ' HEAD\n'
    printf '>%.0s' 1 2 3 4 5 6 7; printf ' rama\n'
  } > wip.txt
  echo "otra cosa" > staged.txt; git add staged.txt
  bash tools/check-conflict-markers.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    un marcador SOLO en working tree (sin stagear) bloqueó"; return 1; }
}
test_marcador_sin_stagear_no_bloquea() { _cm_sandbox _case_marcador_solo_en_working_tree_pasa; }

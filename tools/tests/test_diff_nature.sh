#!/usr/bin/env bash
# El coste de una review crece con TODO el diff, no con la parte dudosa.
# Medido: 27 archivos y 5 naturalezas = 3 vueltas de ~150k tokens y 17 min
# cada una; partido por naturaleza, 62k y GREEN a la primera. Nada empujaba
# a partir — el owner tenía que decirlo a mano.
#
# El invariante que estos tests protegen es que sea un AVISO: "cuántas
# naturalezas caben en un commit" es JUICIO (un rename público toca producto,
# tests y docs a la vez y es legítimo). Un bloqueo aquí sería un falso
# positivo permanente, y esos acaban con el gate desactivado.

_dn_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools"
  cp "$PROJECT_ROOT/tools/check-diff-nature.sh" "$d/tools/"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    # El propio script copiado se COMMITEA en el init: si no, cada `git add -A`
    # del test lo stagearía y contaría como una naturaleza extra. Un test que
    # mide su propio andamiaje mide cualquier cosa menos lo que dice medir.
    echo x > seed.txt; git add -A; git commit -qm init 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_lote_mixto_avisa() {
  mkdir -p src tools/tests docs
  echo a > src/App.swift          # producto
  echo b > tools/tests/test_x.sh  # tests
  echo c > docs/guia.md           # docs
  echo d > tools/otra.sh          # maquinaria
  git add -A
  local out; out="$(bash tools/check-diff-nature.sh --staged 2>&1)"
  printf '%s' "$out" | grep -q 'mezcla' \
    || { echo "    un lote de 4 naturalezas no avisó: $out"; return 1; }
}
test_lote_multi_naturaleza_avisa() { _dn_sandbox _case_lote_mixto_avisa; }

_case_nunca_bloquea() {
  # EL INVARIANTE. Si algún día esto devuelve !=0, el reviewer-gate lo
  # propagaría y estaríamos bloqueando por un criterio que es opinable.
  mkdir -p src tools/tests docs backlog
  echo a > src/App.swift; echo b > tools/tests/test_x.sh
  echo c > docs/g.md;     echo d > backlog/0001.md
  echo e > tools/z.sh;    echo f > AGENTS.md
  git add -A
  bash tools/check-diff-nature.sh --staged >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    el aviso BLOQUEÓ (exit != 0): partir es juicio, no regla"; return 1; }
}
test_el_aviso_jamas_bloquea() { _dn_sandbox _case_nunca_bloquea; }

_case_lote_coherente_calla() {
  # FALSO POSITIVO: un commit de una sola naturaleza no puede generar ruido,
  # o el aviso se vuelve fondo y deja de leerse.
  mkdir -p src
  echo a > src/App.swift; echo b > src/Otro.swift
  git add -A
  local out; out="$(bash tools/check-diff-nature.sh --staged 2>&1)"
  printf '%s' "$out" | grep -q 'mezcla' \
    && { echo "    un lote de UNA naturaleza avisó (ruido): $out"; return 1; }
  printf '%s' "$out" | grep -q 'naturalezas=1' \
    || { echo "    el contrato de stdout no reporta naturalezas=1: $out"; return 1; }
}
test_lote_de_una_naturaleza_no_avisa() { _dn_sandbox _case_lote_coherente_calla; }

_case_dos_naturalezas_callan() {
  # Producto + su test es el commit SANO por excelencia (TDD). Avisar ahí
  # sería empujar contra la propia doctrina del harness.
  mkdir -p src tools/tests
  echo a > src/App.swift; echo b > tools/tests/test_app.sh
  git add -A
  local out; out="$(bash tools/check-diff-nature.sh --staged 2>&1)"
  printf '%s' "$out" | grep -q 'mezcla' \
    && { echo "    producto+test (el commit TDD normal) disparó el aviso"; return 1; }
  return 0
}
test_producto_mas_su_test_no_avisa() { _dn_sandbox _case_dos_naturalezas_callan; }

_case_sin_staged_es_noop() {
  local out; out="$(bash tools/check-diff-nature.sh --staged 2>&1)"
  printf '%s' "$out" | grep -q 'archivos=0' \
    || { echo "    sin nada staged no reportó archivos=0: $out"; return 1; }
}
test_sin_nada_staged_es_noop() { _dn_sandbox _case_sin_staged_es_noop; }

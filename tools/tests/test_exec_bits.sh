#!/usr/bin/env bash
# El bit +x se pierde en todo camino que no sea git (puente, cp, descarga).
# Se avisó cinco veces y aun así un commit del harness metió seis
# `mode change 100755 => 100644`. Estos tests fijan el gate que lo impide y,
# sobre todo, su falso positivo: las librerías que se SOURCEAN no llevan +x,
# y si el gate las exigiera tendría un FP permanente y acabaría desactivado.

_eb_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools"
  cp "$PROJECT_ROOT/tools/check-exec-bits.sh" "$d/tools/"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_sh_sin_x_bloquea() {
  printf '#!/usr/bin/env bash\necho hola\n' > script.sh
  chmod -x script.sh
  git add script.sh
  bash tools/check-exec-bits.sh --staged >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un .sh staged SIN bit +x pasó el gate"; return 1; }
}
test_script_staged_sin_bit_x_bloquea() { _eb_sandbox _case_sh_sin_x_bloquea; }

_case_sh_con_x_pasa() {
  printf '#!/usr/bin/env bash\necho hola\n' > script.sh
  chmod +x script.sh
  git add script.sh
  local out rc
  out="$(bash tools/check-exec-bits.sh --staged 2>&1)"; rc=$?
  [ "$rc" = "0" ] || { echo "    un .sh correcto fue bloqueado (exit $rc)"; return 1; }
  printf '%s' "$out" | grep -q 'EXECBITS_SUMMARY missing=0' \
    || { echo "    contrato de stdout roto: $out"; return 1; }
}
test_script_con_bit_x_pasa() { _eb_sandbox _case_sh_con_x_pasa; }

_case_lib_sourceada_exenta() {
  # FALSO POSITIVO que mataría el gate: lib/io.sh se SOURCEA, jamás se
  # ejecuta. Exigirle +x sería exigir una mentira sobre cómo se usa, y un
  # gate con FP permanente se desactiva entero (ley del 10%).
  mkdir -p scripts/agent-hooks/lib
  printf 'hook_allow() { exit 0; }\n' > scripts/agent-hooks/lib/io.sh
  chmod -x scripts/agent-hooks/lib/io.sh
  git add scripts/agent-hooks/lib/io.sh
  bash tools/check-exec-bits.sh --staged >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    una librería sourceada sin +x fue bloqueada (FP)"; return 1; }
}
test_libreria_sourceada_no_necesita_bit_x() { _eb_sandbox _case_lib_sourceada_exenta; }

_case_no_sh_ignorado() {
  printf 'hola\n' > notas.md
  chmod -x notas.md
  git add notas.md
  bash tools/check-exec-bits.sh --staged >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    un archivo que no es .sh fue evaluado por el gate"; return 1; }
}
test_archivo_que_no_es_script_se_ignora() { _eb_sandbox _case_no_sh_ignorado; }

_case_modo_all_ve_el_repo_entero() {
  # `--all` es el modo de auditoría (validate-harness / limpieza puntual):
  # mira lo COMMITEADO, no solo lo staged, que es donde el problema ya se
  # había colado sin que nadie lo parara.
  printf '#!/usr/bin/env bash\n' > viejo.sh
  chmod -x viejo.sh
  git add viejo.sh; git commit -qm x 2>/dev/null
  bash tools/check-exec-bits.sh --all >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    --all no detectó un script YA commiteado sin +x"; return 1; }
}
test_modo_all_detecta_lo_ya_commiteado() { _eb_sandbox _case_modo_all_ve_el_repo_entero; }

_case_fix_repara_y_restagea() {
  # El modo que usa lefthook: repara lo staged, lo vuelve a stagear, y deja
  # el commit seguir. Sin esto, el humano teclea a mano un remedio que la
  # máquina sabe hacer — fricción sin valor (el gate bloqueó dos commits
  # seguidos por lo mismo antes de este cambio).
  printf '#!/usr/bin/env bash\necho hola\n' > script.sh
  chmod -x script.sh
  git add script.sh
  local rc; bash tools/check-exec-bits.sh --fix >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || { echo "    --fix devolvió $rc (esperaba 0: repara, no bloquea)"; return 1; }
  [ -x script.sh ] || { echo "    --fix no puso el bit +x"; return 1; }
  git ls-files -s script.sh 2>/dev/null | grep -q '^100755' \
    || { echo "    --fix no re-stageó el modo corregido (el commit lo perdería)"; return 1; }
}
test_fix_repara_el_bit_y_lo_restagea() { _eb_sandbox _case_fix_repara_y_restagea; }

_case_fix_avisa_siempre() {
  # Reparar EN SILENCIO sería el error opuesto: el bit que falta es el
  # síntoma de un canal de entrega que pierde permisos, y ese dato tiene que
  # llegar al humano aunque el commit no se pare.
  printf '#!/usr/bin/env bash\n' > script.sh
  chmod -x script.sh
  git add script.sh
  local out; out="$(bash tools/check-exec-bits.sh --fix 2>&1)"
  printf '%s' "$out" | grep -q 'reparado' \
    || { echo "    --fix reparó en silencio: se pierde la señal del canal roto"; return 1; }
}
test_fix_nunca_repara_en_silencio() { _eb_sandbox _case_fix_avisa_siempre; }

_case_staged_sigue_bloqueando() {
  # El modo estricto NO se relaja: CI y validate-harness auditan, no reparan.
  printf '#!/usr/bin/env bash\n' > script.sh
  chmod -x script.sh
  git add script.sh
  bash tools/check-exec-bits.sh --staged >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    --staged dejó de bloquear al añadir --fix"; return 1; }
}
test_modo_estricto_sigue_bloqueando() { _eb_sandbox _case_staged_sigue_bloqueando; }

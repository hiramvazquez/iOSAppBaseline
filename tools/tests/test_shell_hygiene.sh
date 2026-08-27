#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# Higiene de shell del harness — detector de una clase entera de bug
# ════════════════════════════════════════════════════════════════════
# El bug que motivó este archivo (PRD 0001 §18 G14):
#
#     fail "STALE (HEAD cambió $MARKED_HEAD→$CUR_HEAD)"
#
# Bash consume los bytes de `→` como parte del nombre de variable, así que
# expande `$MARKED_HEAD→` (una variable que no existe). Con `set -u` eso mata
# el script. Lo mismo con `«$SCOPE»`, `$VAR…`, `$VAR·`: cualquier carácter
# tipográfico pegado a una variable sin llaves.
#
# Es un bug especialmente traicionero en un harness ESCRITO EN ESPAÑOL:
# los mensajes usan →, «», …, · de forma natural, y solo explota en la RAMA
# que imprime ese mensaje. En `check-review-marker.sh` esa rama era
# "el marker está stale" — es decir, se rompía justo cuando el gate tenía
# que bloquear. Se descubrió por accidente, al intentar commitear P2.
#
# Estos tests son un DETECTOR, no un caso: barren todos los .sh del harness.

_shell_files() {
  find "$PROJECT_ROOT/scripts" "$PROJECT_ROOT/tools" "$PROJECT_ROOT/ci" \
       -name '*.sh' -type f 2>/dev/null
}

# ── El bug de G14: $VAR pegado a un carácter no-ASCII ───────────────
test_sin_variables_pegadas_a_caracteres_no_ascii() {
  local hits
  # Se saltan los COMENTARIOS: este mismo archivo documenta el anti-patrón y
  # se detectaba a sí mismo — el falso positivo de G7 otra vez, ahora en el
  # detector recién escrito. Confirma el patrón: el primer falso positivo de
  # un detector aparece en el repo del propio detector.
  hits="$(_shell_files | xargs perl -ne '
      next if /^\s*#/;
      print "$ARGV:$.: $_" if /\$[A-Za-z_]\w*[^\x00-\x7F\s]/;
      close ARGV if eof;
    ' 2>/dev/null)"
  [ -z "$hits" ] && return 0
  echo "    \$VAR pegado a un carácter no-ASCII (bash se lo traga como parte del nombre)."
  echo "    Usa \${VAR} con llaves. Ocurrencias:"
  printf '%s\n' "$hits" | sed 's/^/      /'
  return 1
}

# ── Todos los scripts deben parsear ─────────────────────────────────
test_todos_los_scripts_parsean() {
  local bad=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    bash -n "$f" 2>/dev/null || bad="${bad}      ${f#$PROJECT_ROOT/}"$'\n'
  done < <(_shell_files)
  [ -z "$bad" ] && return 0
  echo "    scripts con error de sintaxis:"; printf '%s' "$bad"; return 1
}

# ── `set -u` en todos: una variable no definida debe gritar ─────────
test_todos_los_scripts_usan_set_u() {
  local bad=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    # Se saltan los archivos que se SOURCEAN, no se ejecutan: los tests y las
    # librerías de `lib/`. En ellos `set -u` lo impone el llamador; ponerlo
    # dentro cambiaría las opciones del shell del que los carga.
    case "${f##*/}" in test_*.sh) continue ;; esac
    case "$f" in */lib/*) continue ;; esac
    grep -qE '^set -[a-z]*u' "$f" 2>/dev/null || bad="${bad}      ${f#$PROJECT_ROOT/}"$'\n'
  done < <(_shell_files)
  [ -z "$bad" ] && return 0
  echo "    sin \`set -u\` (una variable vacía por error pasaría silenciosa):"
  printf '%s' "$bad"; return 1
}

# ── Los hooks derivan PROJECT_ROOT de su propio dirname ─────────────
# Si dependieran del cwd, se comportarían distinto según quién los invoque.
test_los_hooks_no_dependen_del_cwd() {
  local bad=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    grep -q 'PROJECT_ROOT=' "$f" 2>/dev/null || bad="${bad}      ${f#$PROJECT_ROOT/}"$'\n'
  done < <(find "$PROJECT_ROOT/scripts/agent-hooks" -maxdepth 1 -name '*.sh' -type f 2>/dev/null)
  [ -z "$bad" ] && return 0
  echo "    hooks sin PROJECT_ROOT derivado de \$0 (dependerían del cwd):"
  printf '%s' "$bad"; return 1
}

# ── Las reglas de semgrep CARGAN de verdad ──────────────────────────
# `semgrep --validate` solo comprueba el YAML. Un patrón inválido para UNO de
# los `languages` que la regla declara (p.ej. `===` en C#, o `def $F(...):` en
# Java) pasa la validación y revienta la carga del ARCHIVO ENTERO al ejecutar.
# Las 6 reglas de universal.yaml tuvieron tres errores de este tipo, ninguno
# detectado hasta la primera ejecución real (PRD 0001 §18 G15).
test_las_reglas_de_semgrep_cargan() {
  command -v semgrep >/dev/null 2>&1 || return 0   # sin semgrep, no aplica
  local out rc
  out="$(cd "$PROJECT_ROOT" && bash tools/semgrep-scan.sh 2>&1)"; rc=$?
  # 3 = fallo del propio detector (reglas rotas o crash). 0 y 1 son válidos:
  # el repo puede tener hallazgos legítimos y eso no es un fallo de las reglas.
  [ "$rc" != "3" ] && return 0
  echo "    las reglas de semgrep NO cargan — el nivel 2 está mudo:"
  printf '%s\n' "$out" | sed 's/^/      /'
  return 1
}

# ── Los detectores respetan su contrato de stdout ───────────────────
# El conteo del trinquete se parsea de estas líneas: si un detector deja de
# emitirlas, el trinquete lee 0 y aprueba en silencio (mismo patrón que G2).
test_los_detectores_emiten_su_contrato() {
  local bad=""
  grep -q 'DRIFT_SUMMARY errors=' "$PROJECT_ROOT/tools/check-drift.sh"    2>/dev/null || bad="${bad}      check-drift.sh sin DRIFT_SUMMARY"$'\n'
  grep -q 'LAYERS_SUMMARY errors=' "$PROJECT_ROOT/tools/check-layers.sh"  2>/dev/null || bad="${bad}      check-layers.sh sin LAYERS_SUMMARY"$'\n'
  grep -q 'SEMGREP_SUMMARY errors=' "$PROJECT_ROOT/tools/semgrep-scan.sh" 2>/dev/null || bad="${bad}      semgrep-scan.sh sin SEMGREP_SUMMARY"$'\n'
  grep -q 'MUTATION_SUMMARY score=' "$PROJECT_ROOT/tools/mutation-score.sh" 2>/dev/null || bad="${bad}      mutation-score.sh sin MUTATION_SUMMARY"$'\n'
  [ -z "$bad" ] && return 0
  echo "    detectores que rompieron su contrato de salida:"; printf '%s' "$bad"; return 1
}

# ── `stat -f` de GNU no falla: el orden del fallback ES el bug ──────
# Tercera aparicion de la misma trampa en este repo, y la que publico main en
# rojo: `stat -f` en BSD lee el modo/mtime de un ARCHIVO, pero en GNU lee el
# estado del FILESYSTEM — y sale con 0. Asi que
#
#     stat -f '%Lp' "$f" || stat -c '%a' "$f"      # BSD primero
#
# nunca llega al fallback en Linux: devuelve un volcado del filesystem con exit
# 0 y quien compara obtiene basura. Verde en el Mac de quien lo escribe, rojo en
# CI, y el mensaje de error dice "644, esperaba 644" — la comparacion rota
# esconde su propia causa.
#
# El orden correcto es GNU primero, BSD despues, y ya estaba escrito con este
# comentario en check-review-marker.sh y en check-verify-marker.sh. Que volviera
# a pasar es la ley de siempre: una regla implementada tres veces diverge. Esto
# la convierte en mecanica.
test_stat_lee_gnu_primero_y_bsd_despues() {
  local hits
  # Se salta lo que es TEXTO, no sintaxis, por dos vias:
  #   · los COMENTARIOS — los dos archivos que documentan esta trampa la NOMBRAN
  #     en prosa ("`stat -f` de GNU NO falla").
  #   · las CADENAS ENTRECOMILLADAS — este mismo test imprime la forma incorrecta
  #     en su mensaje de error, y se caza a si mismo en la primera pasada. Sexta
  #     vez que pasa en este repo, y aqui la exencion SI es legitima: quien
  #     dictamina que lo entrecomillado es dato no es nuestro criterio, es el
  #     parser de bash. La forma real `stat -f '%Lp' "$f"` sobrevive al desnudado
  #     porque el flag va FUERA de las comillas; solo el formato va dentro.
  hits="$(_shell_files "$PROJECT_ROOT"/tools/tests/*.sh | xargs perl -ne '
      next if /^\s*#/;
      $probe = $_; $probe =~ s/#.*$//;
      $probe =~ s/"[^"]*"//g; $probe =~ s/\x27[^\x27]*\x27//g;
      print "$ARGV:$.: $_" if $probe =~ /stat\s+-f/ && $probe !~ /stat\s+-c.*stat\s+-f/;
      close ARGV if eof;
    ' 2>/dev/null)"
  [ -z "$hits" ] && return 0
  echo "    \`stat -f\` sin un \`stat -c\` DELANTE en la misma linea:"
  printf '%s\n' "$hits" | sed 's/^/      /'
  echo "    En GNU, \`stat -f\` NO falla: imprime el estado del FILESYSTEM con exit 0,"
  echo "    asi que el fallback nunca corre y en Linux lees basura. Orden correcto:"
  echo "      stat -c '%a' \"\$f\" 2>/dev/null || stat -f '%Lp' \"\$f\" 2>/dev/null"
  echo "    Verde en macOS, rojo en CI — asi se publico main en rojo."
  return 1
}

# El runner sanea el entorno del anfitrión antes de correr nada: un test cuyo
# veredicto dependa de una variable que él no puso mide otra cosa, y lo hace en
# silencio. Pasó dos veces (GATES_SKIP_TESTS tumbando golden_09 desde el step de
# CI; REVIEWER_OVERRIDE tumbando 12 de 26 tests de scope_kind desde la shell de
# un dev). Sin este test, borrar el `unset` no pondría nada en rojo.
test_el_runner_sanea_el_entorno_del_anfitrion() {
  local runner="$PROJECT_ROOT/tools/tests/run-tests.sh" falta="" v
  # LAS QUINCE, no una muestra: una versión anterior de este test comprobaba
  # siete y quedaba VERDE si alguien quitaba VERIFY_CMD del unset — con esa
  # sola quitada, `VERIFY_CMD=true bash tools/tests/run-tests.sh verify_marker`
  # da cinco rojos. Un test que cubre la mitad de su contrato invita a recortar
  # la otra mitad con luz verde falsa. Lo cazó el reviewer con ese mutante.
  # El ancla es `unset` + IDENTIFICADOR EN MAYÚSCULAS, no el literal `unset
  # GATES_`: con el literal, reordenar el bloque para que empiece por otra
  # variable dejaba de abrir el rango y el check reportaba las quince como
  # ausentes — un falso positivo que el propio hardening introdujo. (Y la
  # justificación de aquel literal era falsa: los `unset -f` del runner van
  # indentados, así que un ancla en columna 0 nunca los captura.)
  for v in GATES_SKIP_TESTS GATES_REQUIRE_SEMGREP GATES_REQUIRE_SOURCE_SETS \
           GATES_REQUIRE_MUTATION GATES_SECRET_MODE GATES_BASE_REF \
           AI_REVIEW_REQUIRED AI_REVIEW_OUT \
           REVIEWER_OVERRIDE REVIEWER_OVERRIDE_REASON \
           VERIFY_OVERRIDE VERIFY_OVERRIDE_REASON VERIFY_CMD VERIFY_CONF \
           MUTATION_SCORE_OVERRIDE; do
    awk '/^unset [A-Z_]/,/[^\\]$/' "$runner" | grep -qw "$v" || falta="$falta $v"
  done
  [ -z "$falta" ] \
    || { echo "    el runner no sanea variables que alteran gates:$falta"; return 1; }

  # Y que el saneo FUNCIONE, no solo que esté escrito. La comprobación es este
  # test MISMO: corre dentro del runner, así que si el saneo funciona ninguna de
  # esas variables puede estar definida aquí — da igual lo que trajera la shell
  # que lanzó la suite. Con `GATES_SKIP_TESTS=1 bash tools/tests/run-tests.sh`
  # esto es una prueba real; sin nada en el entorno, pasa trivialmente y el
  # check estático de arriba es el que sostiene el contrato.
  # (Invocar el runner desde aquí sería recursión infinita: el filtro casaría
  # con este mismo test. Se intentó y colgó la suite.)
  local sucias="" w
  for w in GATES_SKIP_TESTS GATES_REQUIRE_SEMGREP GATES_REQUIRE_SOURCE_SETS \
           GATES_REQUIRE_MUTATION GATES_SECRET_MODE GATES_BASE_REF \
           AI_REVIEW_REQUIRED AI_REVIEW_OUT \
           REVIEWER_OVERRIDE REVIEWER_OVERRIDE_REASON \
           VERIFY_OVERRIDE VERIFY_OVERRIDE_REASON VERIFY_CMD VERIFY_CONF \
           MUTATION_SCORE_OVERRIDE; do
    [ -z "${!w:-}" ] || sucias="$sucias $w"
  done
  [ -z "$sucias" ] \
    || { echo "    el saneo no surtió efecto: llegaron del anfitrión:$sucias"; return 1; }
}

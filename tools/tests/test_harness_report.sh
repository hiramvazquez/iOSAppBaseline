#!/usr/bin/env bash
# harness-report: la observabilidad NUNCA falla y NUNCA filtra. Un informe que
# revienta cuando el harness está roto es inútil justo cuando más se necesita;
# y un informe que viaja a un chat con un token dentro es un incidente.

_hr_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/findings" "$d/tools/tests" "$d/scripts/agent-hooks/lib" "$d/.agents/state/metrics"
  cp "$PROJECT_ROOT/tools/harness-report.sh" "$d/tools/"
  cp "$PROJECT_ROOT/tools/validate-harness.sh" "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/findings/findings.sh" "$d/tools/findings/" 2>/dev/null
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  ( cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo x > seed; git add seed; git commit -qm init 2>/dev/null
    "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_siempre_exit_0() {
  # Sandbox deliberadamente ROTO (sin preset, sin matriz, sin tests): el
  # informe debe producirse igual y salir 0 — es observabilidad, no un gate.
  bash tools/harness-report.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    el informe falló en un harness roto (justo cuando más se necesita)"; return 1; }
}
test_report_siempre_sale_0() { _hr_sandbox _case_siempre_exit_0; }

_case_secciones_presentes() {
  local out; out="$(bash tools/harness-report.sh 2>/dev/null)"
  local s
  for s in "1. Entorno" "2. Salud" "4. Runs del backlog" "5. Detecciones" "7. Findings" "8. Git"; do
    case "$out" in *"$s"*) : ;; *) echo "    falta la sección '$s'"; return 1 ;; esac
  done
}
test_report_incluye_las_secciones() { _hr_sandbox _case_secciones_presentes; }

_case_redacta_secretos() {
  printf '{"ts":"x","source":"test","rule":"r","area":"a con sk-ABCDEFGH123456789012345678 dentro","n":1}\n' \
    > .agents/state/metrics/detections.jsonl
  local out; out="$(bash tools/harness-report.sh 2>/dev/null)"
  case "$out" in
    *sk-ABCDEFGH123456789012345678*) echo "    un token viajó SIN redactar al informe"; return 1 ;;
    *REDACTED*) return 0 ;;
    *) echo "    ni token ni marca de redacción — ¿la sección de telemetría no salió?"; return 1 ;;
  esac
}
test_report_redacta_tokens() { _hr_sandbox _case_redacta_secretos; }

_case_acota_el_tamano() {
  local i; for i in $(seq 1 300); do
    echo "{\"ts\":\"t$i\",\"source\":\"s\",\"rule\":\"r\",\"area\":\"a\",\"n\":1}"
  done > .agents/state/metrics/detections.jsonl
  # CAPTURA y compara — nada de `informe | grep -q` aquí: el runner corre con
  # `set -o pipefail`, grep -q sale al primer match, el informe muere por
  # SIGPIPE (141) y el pipeline "falla" aunque el match EXISTA. Falso negativo
  # real cazado con instrumentación: la sección mostraba el texto y el grep
  # decía que no. (grep -c sí es seguro: consume toda la entrada.)
  local rep; rep="$(bash tools/harness-report.sh 2>/dev/null)"
  local n; n="$(printf '%s' "$rep" | grep -c '"ts":"t' || true)"
  [ "${n:-0}" -le 40 ] || { echo "    la telemetría no se acotó ($n líneas; el informe debe ser pegable)"; return 1; }
  case "$rep" in
    *"300 líneas en total"*) return 0 ;;
    *) echo "    no declaró el truncado (parecería que 40 es todo lo que hay)"; return 1 ;;
  esac
}
test_report_acota_y_declara_el_truncado() { _hr_sandbox _case_acota_el_tamano; }

_case_inventario_se_calcula_en_runtime() {
  printf '%s\n' '#!/usr/bin/env bash' 'test_uno() { :; }' 'test_dos() { :; }' \
    > tools/tests/test_fixture.sh
  printf '<!-- FILL: uno -->\n<!-- FILL -->\nEsta prosa menciona `<!-- FILL: ejemplo -->` pero no es marker.\n' > placeholders.md
  git add tools/tests/test_fixture.sh placeholders.md
  git commit -qm inventario 2>/dev/null
  # El inventario declara evidence_commit=HEAD: cambios del worktree no deben
  # contaminar el snapshot aunque parezcan tests/markers válidos.
  printf '%s\n' 'test_tres() { :; }' >> tools/tests/test_fixture.sh
  printf '<!-- FILL: tres -->\n' >> placeholders.md
  local out
  out="$(bash tools/harness-report.sh 2>/dev/null)"
  assert_contains "$out" 'tests_discovered=2'
  assert_contains "$out" 'fill_markers=2'
  assert_contains "$out" 'evidence_commit='
}
test_report_calcula_tests_y_fills_sin_conteos_manuales() {
  _hr_sandbox _case_inventario_se_calcula_en_runtime
}


# ════════════════════════════════════════════════════════════════════
# El contador de FILL contaba los YA RESUELTOS como pendientes
# ════════════════════════════════════════════════════════════════════
# Bug real y verificado. El regex delimitaba el marcador con la clase
# `[[:space:]:>-]`, y un `-` AL FINAL de una clase de caracteres es un guion
# LITERAL — no un rango. Así que `<!-- FILL-HECHO: ... -->`, la convención con
# la que un adoptante marca lo que YA rellenó, casaba y se contaba como deuda.
#
# Importa más de lo que parece por DÓNDE sale: `fill_markers` va en el informe
# que un adoptante PEGA para pedir ayuda. Un contador inflado le dice al que
# ayuda que quedan huecos que ya están cerrados — y el informe existe
# precisamente para no tener que fiarse de la memoria de nadie.
#
# El caso `<!-- FILL-->` (guion PEGADO, sin espacio) sigue contando: por eso el
# arreglo es `([[:space:]:>]|-->|$)` y no "quitar el guion", que lo habría
# perdido en silencio. Ese es el mutante que separa el arreglo del atajo.
_case_fill_no_cuenta_los_hechos() {
  # Los marcadores van a PRINCIPIO DE LÍNEA (con el prefijo de comentario
  # opcional que admite el regex): el contador está anclado con `^` a propósito,
  # para no contar una mención a media frase. Esa ancla es parte del contrato y
  # el fixture la respeta en vez de rodearla — si se probara con marcadores a
  # media línea, el test mediría otra cosa y daría 0 sin decir por qué.
  mkdir -p doc
  {
    echo '<!-- FILL: rellena esto -->'
    echo '<!-- FILL-->'
    echo '# <!-- FILL -->'
    # Marcador TRUNCADO: la linea acaba justo tras FILL, sin cierre. Ejercita la
    # alternativa `$` de la ERE, que hasta ahora no la tocaba ningun test — lo
    # cazo el `reviewer` aplicando el mismo criterio que este repo ya aplica a
    # _ADDA_PRECOND: una rama que nadie ejercita es decoracion. Resulto NO ser
    # decoracion (sin la rama, este caso deja de contarse), asi que la rama se
    # queda y lo que faltaba era el fixture.
    echo '<!-- FILL'
  } > doc/pendientes.md
  {
    echo '<!-- FILL-HECHO: Swift 6 -->'
    echo '<!-- FILL-HECHO -->'
  } > doc/hechos.md
  git stage doc
  git commit -qm "fixture de FILL" 2>/dev/null

  local out n
  out="$(bash tools/harness-report.sh 2>/dev/null)"
  n="$(printf '%s\n' "$out" | sed -n 's/^fill_markers=//p' | head -1)"
  [ -n "$n" ] || { echo "    el informe no emitió fill_markers"; return 1; }
  [ "$n" = "4" ] || {
    echo "    fill_markers=$n, esperaba 4 (los pendientes), no 6 (contando FILL-HECHO)"
    echo "    Un '-' al final de una clase de caracteres es LITERAL: [[:space:]:>-]"
    echo "    casa 'FILL-HECHO'. El delimitador correcto es ([[:space:]:>]|-->|\$)."
    return 1; }
}
test_el_contador_de_fill_no_cuenta_los_ya_hechos() {
  _hr_sandbox _case_fill_no_cuenta_los_hechos
}

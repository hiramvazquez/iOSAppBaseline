#!/usr/bin/env bash
# El bucle lección → detector es lo que hace que la revisión humana DECREZCA.
# Si este gate produce falsos positivos, se desactiva, y el bucle se rompe.
#
# Este archivo cubre el CONTRATO CENTRAL de `tools/lesson-detector-link.sh`:
# happy path, las ramas de error (sin detector / "manual" a secas / excepción
# n/a-manual) y que tanto el ARCHIVO como el TEST citados en `Detector:`
# existan de verdad. Los guards de falso positivo (los bordes que matan a un
# detector por CONFIANZA — plantillas, comentarios HTML, prosa) viven en
# `test_lessons_falsos_positivos.sh`; la rotación/archivado de lecciones
# mecanizadas vive en `test_lessons_rotacion.sh`; el presupuesto de contexto
# vivo (línea 250) vive en `test_lessons_presupuesto_contexto.sh`.

_lessons_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/docs/process"
  cp "$PROJECT_ROOT/tools/lesson-detector-link.sh" "$d/tools/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}
_doc() { printf '%s\n' "$1" > docs/process/lessons_learned.md; }

# ── happy path ──────────────────────────────────────────────────────
_case_con_detector() {
  # El detector citado debe EXISTIR (el verificador ahora lo comprueba).
  mkdir -p tools/semgrep/rules; echo 'rules: []' > tools/semgrep/rules/universal.yaml
  _doc '# Lecciones

### [2026-01-01] Secreto de prueba con formato real
- **Qué pasó:** un fixture tenía una API key con formato válido.
- **Regla:** usa formatos obviamente inválidos.
- **Detector:** tools/semgrep/rules/universal.yaml#secreto-hardcodeado
- **Área:** tests/fixtures'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    una lección CON detector fue rechazada"; return 1; }
}
test_leccion_con_detector_pasa() { _lessons_sandbox _case_con_detector; }

# ── ramas de error ──────────────────────────────────────────────────
_case_sin_detector() {
  _doc '# Lecciones

### [2026-01-01] Algo pasó
- **Qué pasó:** cosas.
- **Regla:** no hacerlo otra vez.
- **Área:** src/'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    una lección SIN detector fue aceptada"; return 1; }
}
test_leccion_sin_detector_falla() { _lessons_sandbox _case_sin_detector; }

_case_detector_vacio() {
  _doc '# Lecciones

### [2026-01-01] Algo pasó
- **Detector:** manual'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    'Detector: manual' se aceptó como detector real"; return 1; }
}
test_detector_manual_a_secas_no_cuenta() { _lessons_sandbox _case_detector_vacio; }

_case_excepcion_justificada() {
  # Hay lecciones que de verdad no son mecanizables. La excepción es legítima
  # SI es explícita — forzar un detector sobre algo no mecanizable produce ruido.
  _doc '# Lecciones

### [2026-01-01] Elegimos mal el modelo de pricing
- **Detector:** n/a-manual — es una decisión de producto, no un patrón de código'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    la excepción n/a-manual justificada fue rechazada"; return 1; }
}
test_excepcion_na_manual_es_valida() { _lessons_sandbox _case_excepcion_justificada; }

# ── el detector citado tiene que EXISTIR ────────────────────────────
# Validar solo que el campo esté relleno dejaba pasar detectores FANTASMA:
# una lección citó un grep de check-drift que ya había sido eliminado y el
# verificador daba ✅ igual. Prosa que cita un detector muerto es prosa.
_case_detector_fantasma_falla() {
  _doc '# Lecciones

### [2026-01-01] Error con detector que ya no existe
- **Detector:** tools/detector-que-borramos.sh'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un detector citado INEXISTENTE fue aceptado"; return 1; }
}
test_detector_citado_inexistente_falla() { _lessons_sandbox _case_detector_fantasma_falla; }

_case_doc_ausente() {
  rm -f docs/process/lessons_learned.md
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    falló sin doc de lecciones (debe ser no-op)"; return 1; }
}
test_sin_doc_es_noop() { _lessons_sandbox _case_doc_ausente; }

# ════════════════════════════════════════════════════════════════════
# El ARCHIVO existiendo no basta: el TEST citado también tiene que existir
# ════════════════════════════════════════════════════════════════════
# Cazado escribiendo las lecciones de este mismo día: una citaba
# `test_session_start.sh (los cuatro estados)` y el archivo no tenía ni un test
# de los cuatro estados. El archivo existía → verde. La lección quedaba
# respaldada por una promesa, que es justo lo que este gate existe para impedir.
# Mismo agujero que un id de finding fantasma (tools/check-finding-refs.sh): la
# cita LEE COMO CUBIERTO y nadie vuelve a comprobarla.
_case_test_citado_inexistente() {
  mkdir -p tools/tests
  printf '#!/usr/bin/env bash\ntest_que_si_existe() { :; }\n' > tools/tests/test_x.sh
  _doc '### [2026-01-01] una
- **Detector:** tools/tests/test_x.sh::test_que_si_existe + ::test_que_nunca_se_escribio'
  local out; out="$(bash tools/lesson-detector-link.sh 2>&1)"
  case "$out" in *test_que_nunca_se_escribio*) : ;; *)
    echo "    un ::test citado que no existe pasó el gate:"; printf '%s\n' "$out" | head -4 | sed 's/^/      /'
    return 1 ;; esac
}
test_un_test_citado_que_no_existe_falla() { _lessons_sandbox _case_test_citado_inexistente; }

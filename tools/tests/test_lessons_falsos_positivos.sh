#!/usr/bin/env bash
# GUARDS DE FALSO POSITIVO de `tools/lesson-detector-link.sh` y
# `tools/lessons-rotate.sh`. La ley del 10% (AGENTS.md §14.2): un detector
# ruidoso se desactiva, y con él se rompe el bucle lección → detector
# (AGENTS.md §10). Estos son los bordes cazados en vivo que matan a un
# detector por CONFIANZA, no por lógica: plantillas dentro de code fences,
# ejemplos en comentarios HTML, encabezados de prosa, una lección que
# MENCIONA el marcador sin llevarlo, y el colapso de separadores del
# rotador que no debe tragarse contenido real.
#
# El contrato central (happy path + ramas de error) vive en
# `test_lessons_detector_link.sh`; la rotación/archivado en
# `test_lessons_rotacion.sh`.

_lessons_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/docs/process"
  cp "$PROJECT_ROOT/tools/lesson-detector-link.sh" "$d/tools/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}
_doc() { printf '%s\n' "$1" > docs/process/lessons_learned.md; }

_rot_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/tests" "$d/docs/process"
  cp "$PROJECT_ROOT/tools/lessons-rotate.sh" "$d/tools/"
  cp "$PROJECT_ROOT/tools/lesson-detector-link.sh" "$d/tools/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_plantilla_en_code_fence() {
  # La plantilla de entrada del doc vive dentro de ``` y NO es una lección.
  # Contarla sería el falso positivo clásico que hace desactivar el gate.
  _doc '# Lecciones

## Plantilla

```
### [AAAA-MM-DD] <título corto>
- **Detector:** <check-drift / reviewer / test>
```
'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    FALSO POSITIVO: contó la plantilla del code fence como lección"; return 1; }
}
test_plantilla_en_bloque_de_codigo_no_cuenta() { _lessons_sandbox _case_plantilla_en_code_fence; }

_case_ejemplo_en_comentario_html() {
  _doc '# Lecciones

<!--
### [AAAA-MM-DD] Ejemplo comentado
- Qué pasó: nada, es un ejemplo del template.
-->
'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    FALSO POSITIVO: contó un ejemplo en comentario HTML"; return 1; }
}
test_ejemplo_en_comentario_html_no_cuenta() { _lessons_sandbox _case_ejemplo_en_comentario_html; }

_case_leccion_que_habla_de_comentarios_html() {
  # Falso positivo REAL, y de los caros: al escribir la lección que explica la
  # regla de los marcadores `<!-- FILL`, ese texto —entre acentos, en medio de
  # una frase— abrió un "comentario HTML" para el filtro, que se tragó el resto
  # del documento: el campo `Detector:` de esa lección Y la lección siguiente
  # ENTERA. El gate reportó huérfana a una lección que sí tenía detector, y dejó
  # de contar otra. Es exactamente el patrón que este harness persigue: el
  # detector se disparó con el TEXTO QUE HABLA de la cosa, no con la cosa.
  mkdir -p tools/semgrep/rules; echo 'rules: []' > tools/semgrep/rules/universal.yaml
  _doc '# Lecciones

### [2026-01-01] Un marcador es una forma, no una palabra
- **Regla:** un marcador FILL es un comentario que EMPIEZA por `<!-- FILL`.
- **Detector:** tools/semgrep/rules/universal.yaml
- **Área:** tools/

### [2026-01-02] La lección de después, que no debe desaparecer
- **Detector:** tools/semgrep/rules/universal.yaml
- **Área:** tools/'
  local out; out="$(bash tools/lesson-detector-link.sh 2>&1)"
  case "$out" in *"total=2"*) : ;; *)
    echo "    el filtro se tragó una lección entera: $out"; return 1 ;; esac
  case "$out" in *"sin_detector=0"*) return 0 ;; esac
  echo "    FALSO POSITIVO: una lección que MENCIONA \`<!--\` perdió su Detector: $out"
  return 1
}
test_mencionar_un_comentario_html_no_abre_un_comentario_html() {
  _lessons_sandbox _case_leccion_que_habla_de_comentarios_html
}

_case_encabezado_de_prosa() {
  # El propio doc tiene encabezados `###` explicativos que NO son lecciones.
  # Contarlos fue un falso positivo real (PRD 0001 §18). Una entrada se
  # reconoce por el corchete con fecha: `### [AAAA-MM-DD] …`.
  mkdir -p tools/semgrep/rules; echo 'rules: []' > tools/semgrep/rules/universal.yaml
  _doc '# Lecciones

### Cómo usar este doc
El campo Detector es obligatorio.

### [2026-01-01] Un error real
- **Detector:** tools/semgrep/rules/universal.yaml'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    FALSO POSITIVO: contó un encabezado de prosa como lección"; return 1; }
}
test_encabezado_de_prosa_no_es_leccion() { _lessons_sandbox _case_encabezado_de_prosa; }

# FALSO POSITIVO guard: un detector descrito en prosa (sin ruta de archivo)
# sigue valiendo — no todo detector es un archivo (p. ej. "branch protection").
_case_detector_en_prosa_pasa() {
  _doc '# Lecciones

### [2026-01-01] Algo no mecanizable por archivo
- **Detector:** branch protection en GitHub exige el status check ci-gates'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    un detector válido descrito en prosa fue rechazado"; return 1; }
}
test_detector_en_prosa_sin_ruta_pasa() { _lessons_sandbox _case_detector_en_prosa_pasa; }

_case_prosa_no_absorbe_la_siguiente() {
  # Un encabezado de prosa no debe "prestar" su detector a la entrada siguiente.
  _doc '# Lecciones

### Notas
- **Detector:** algo

### [2026-01-01] Error sin detector
- **Regla:** no repetirlo'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    una entrada sin detector heredó el de un encabezado de prosa"; return 1; }
}
test_prosa_no_presta_su_detector() { _lessons_sandbox _case_prosa_no_absorbe_la_siguiente; }

# ── FALSO POSITIVO nº1: los tests que SÍ existen no pueden acusarse ──
_case_todos_los_tests_citados_existen() {
  mkdir -p tools/tests
  printf '#!/usr/bin/env bash\ntest_uno() { :; }\nfunction test_dos() { :; }\n' > tools/tests/test_x.sh
  _doc '### [2026-01-01] una
- **Detector:** tools/tests/test_x.sh::test_uno + ::test_dos (el guard de FP)'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1 \
    || { echo "    FALSO POSITIVO: acusó a tests que sí existen (incluido el declarado con 'function')"; return 1; }
}
test_los_tests_que_existen_no_se_acusan() { _lessons_sandbox _case_todos_los_tests_citados_existen; }

# ── FALSO POSITIVO nº2: un detector en prosa, sin `::`, sigue valiendo ──
# No toda lección se fija con un test. Exigir un `::` convertiría este gate en
# una máquina de rechazar detectores legítimos (semgrep, layers.conf, un hook),
# y un gate ruidoso se desactiva entero.
_case_detector_sin_tests_citados() {
  mkdir -p tools/semgrep/rules; echo 'rules: []' > tools/semgrep/rules/universal.yaml
  _doc '### [2026-01-01] una
- **Detector:** tools/semgrep/rules/universal.yaml#regla-x'
  bash tools/lesson-detector-link.sh >/dev/null 2>&1 \
    || { echo "    FALSO POSITIVO: un detector que no es un test fue rechazado"; return 1; }
}
test_un_detector_que_no_es_un_test_sigue_valiendo() {
  _lessons_sandbox _case_detector_sin_tests_citados
}

# ── FALSO POSITIVO guard: el colapso no puede tragarse CONTENIDO ────
# Un `---` dentro de un bloque de código ``` (front-matter YAML, un diff, la
# doc del propio separador) es parte del CUERPO de la lección, no un
# separador; y la lección que viene después de un tramo de sedimento tampoco
# puede desaparecer. Tragarse cualquiera de los dos sería perder la lección
# de verdad — el riesgo exacto por el que el criterio de archivo es
# conservador.
_case_colapso_respeta_contenido_de_leccion() {
  printf '#!/usr/bin/env bash\n' > tools/tests/test_ejemplo.sh
  _doc '# Lecciones

### [2026-01-01] Con front-matter en el cuerpo
- **Regla:** el front-matter YAML se delimita con `---`.
- **Detector:** n/a-manual — juicio
- **Área:** x

```yaml
---
clave: valor
---
```

### [2026-01-02] El cuerpo termina en un fence cuya última línea es un separador
- **Regla:** r.
- **Detector:** n/a-manual — juicio
- **Área:** x

```text
---
```

---

---

### [2026-01-03] Mecanizada al final
- **Regla:** r.
- **Detector:** tools/tests/test_ejemplo.sh
- **Área:** x'
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1 || return 1
  grep -q '^### .*Con front-matter en el cuerpo' docs/process/lessons_learned.md \
    || { echo "    FALSO POSITIVO: el colapso se tragó una lección viva entera"; return 1; }
  grep -q '^### .*El cuerpo termina en un fence' docs/process/lessons_learned.md \
    || { echo "    FALSO POSITIVO: desapareció la lección pegada al sedimento"; return 1; }
  grep -q '^clave: valor$' docs/process/lessons_learned.md \
    || { echo "    FALSO POSITIVO: el colapso mutiló el interior de un bloque de código"; return 1; }
  # 3 `---` de contenido (2 del YAML + 1 del fence final) + 1 del índice = 4.
  local n; n="$(grep -c '^---$' docs/process/lessons_learned.md)"
  [ "$n" = "4" ] \
    || { echo "    FALSO POSITIVO: un --- de CONTENIDO fue colapsado, o quedó sedimento (hay $n, esperaba 4)"; return 1; }
}
test_colapso_no_se_traga_contenido_ni_lecciones() {
  _rot_sandbox _case_colapso_respeta_contenido_de_leccion
}

# ── FALSO POSITIVO guard: MENCIONAR el marcador no es LLEVARLO ──────
# El veto KEEP-VISIBLE es un comentario HTML que abre su línea, no una
# palabra. Con `in text` a secas, la lección que DOCUMENTA el mecanismo
# ("…ni las marcadas `<!-- KEEP-VISIBLE -->`…") se auto-vetaba por nombrarlo
# y quedó clavada en el contexto vivo: el clasificador disparó con el texto
# que HABLA de la cosa, no con la cosa — el mismo falso positivo que
# lesson-detector-link.sh ya caza con la mención de `<!-- FILL`.
_case_mencionar_keep_visible_no_veta() {
  printf '#!/usr/bin/env bash\n' > tools/tests/test_ejemplo.sh
  _doc '# Lecciones

### [2026-01-01] Habla del marcador sin llevarlo
- **Regla:** nunca se archivan las marcadas `<!-- KEEP-VISIBLE -->` por el owner.
- **Detector:** tools/tests/test_ejemplo.sh
- **Área:** x

### [2026-01-02] Lleva el marcador de verdad
<!-- KEEP-VISIBLE: el owner quiere verla siempre -->
- **Regla:** r.
- **Detector:** tools/tests/test_ejemplo.sh
- **Área:** x'
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1 || return 1
  grep -q '^### .*Habla del marcador sin llevarlo' docs/process/lessons_learned.md \
    && { echo "    FALSO POSITIVO: mencionar el marcador en prosa vetó el archivado"; return 1; }
  grep -q '^### .*Habla del marcador sin llevarlo' docs/process/lessons_archive.md \
    || { echo "    la lección que solo MENCIONA el marcador no llegó al archivo"; return 1; }
  grep -q '^### .*Lleva el marcador de verdad' docs/process/lessons_learned.md \
    || { echo "    el marcador REAL dejó de vetar el archivado"; return 1; }
  return 0
}
test_mencionar_keep_visible_en_prosa_no_veta_el_archivado() {
  _rot_sandbox _case_mencionar_keep_visible_no_veta
}

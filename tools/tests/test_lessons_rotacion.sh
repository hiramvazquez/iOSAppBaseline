#!/usr/bin/env bash
# ROTACIÓN — una lección MECANIZADA ya no necesita leerse. Cubre el
# CONTRATO de `tools/lessons-rotate.sh`: qué archiva, qué conserva (manual,
# garantía parcial, KEEP-VISIBLE), el índice que deja atrás, la
# idempotencia, la reconciliación de entradas nuevas, la NO-deduplicación
# de cuerpos distintos bajo el mismo título, la reclasificación cuando un
# test desaparece, y la FORMA CANÓNICA (fase 0c del PRD 0005: dos pasadas
# → mismos bytes, exactamente un separador `---` antes del índice).
#
# Los guards de falso positivo del propio colapso (no tragarse contenido,
# no vetar por mención) viven en `test_lessons_falsos_positivos.sh`; los
# checks contra el documento vivo REAL (presupuesto de 250 líneas) viven
# en `test_lessons_presupuesto_contexto.sh`.

# El corolario del propio bucle: si el detector es un test que corre en el
# Anillo 3, la regla está garantizada por una máquina y no por la memoria.
# El riesgo del mecanismo es archivar de MÁS (perder la lección de verdad),
# así que estos tests fijan sobre todo lo que NO debe archivarse.

_rot_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/tests" "$d/docs/process"
  cp "$PROJECT_ROOT/tools/lessons-rotate.sh" "$d/tools/"
  cp "$PROJECT_ROOT/tools/lesson-detector-link.sh" "$d/tools/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_rota_la_mecanizada_y_conserva_la_manual() {
  printf '#!/usr/bin/env bash\n' > tools/tests/test_ejemplo.sh
  _doc '# Lecciones

### [2026-01-01] Con test en la suite
- **Regla:** algo mecánico.
- **Detector:** tools/tests/test_ejemplo.sh::test_x
- **Área:** x

### [2026-01-02] Juicio de producto
- **Regla:** algo opinable.
- **Detector:** n/a-manual — es criterio de diseño
- **Área:** proceso'
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1
  grep -q 'Juicio de producto' docs/process/lessons_learned.md \
    || { echo "    la lección n/a-manual fue archivada: su prosa ES el mecanismo"; return 1; }
  grep -q '^### .*Con test en la suite' docs/process/lessons_learned.md \
    && { echo "    la lección mecanizada sigue entera en el doc vivo"; return 1; }
  grep -q 'Con test en la suite' docs/process/lessons_archive.md \
    || { echo "    la lección mecanizada no llegó al archivo"; return 1; }
  return 0
}
test_rotacion_archiva_mecanizadas_y_respeta_manuales() {
  _rot_sandbox _case_rota_la_mecanizada_y_conserva_la_manual
}

_case_deja_indice() {
  # Archivar SIN dejar rastro cambiaría un problema por otro: el agente
  # dejaría de saber que la regla existe y se enteraría al ver fallar un
  # test — una vuelta entera más cara que leer una línea.
  printf '#!/usr/bin/env bash\n' > tools/tests/test_ejemplo.sh
  _doc '# Lecciones

### [2026-01-01] Regla mecanizada
- **Regla:** algo.
- **Detector:** tools/tests/test_ejemplo.sh
- **Área:** x'
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1
  grep -q 'Regla mecanizada' docs/process/lessons_learned.md \
    || { echo "    no quedó línea de índice: la señal de que la regla existe se perdió"; return 1; }
}
test_rotacion_deja_indice_de_una_linea() { _rot_sandbox _case_deja_indice; }

_case_keep_visible_manda() {
  printf '#!/usr/bin/env bash\n' > tools/tests/test_ejemplo.sh
  _doc '# Lecciones

### [2026-01-01] El owner quiere verla siempre
<!-- KEEP-VISIBLE: duele demasiado como para esconderla -->
- **Regla:** algo.
- **Detector:** tools/tests/test_ejemplo.sh
- **Área:** x'
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1
  grep -q '^### .*owner quiere verla' docs/process/lessons_learned.md \
    || { echo "    KEEP-VISIBLE no protegió la lección del archivado"; return 1; }
}
test_keep_visible_veta_el_archivado() { _rot_sandbox _case_keep_visible_manda; }

_case_detector_sin_test_no_se_archiva() {
  # Garantía PARCIAL: un detector que es un script sin test propio no
  # asegura nada por sí solo. Archivar eso sería archivar una promesa.
  stub tools/otro.sh '#!/usr/bin/env bash\n'
  _doc '# Lecciones

### [2026-01-01] Detector sin test propio
- **Regla:** algo.
- **Detector:** tools/otro.sh
- **Área:** x'
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1
  grep -q '^### .*Detector sin test propio' docs/process/lessons_learned.md \
    || { echo "    se archivó una lección con garantía solo PARCIAL"; return 1; }
}
test_detector_sin_test_en_la_suite_no_se_archiva() {
  _rot_sandbox _case_detector_sin_test_no_se_archiva
}

_case_archivo_sigue_verificado() {
  # Sin esto, rotar sería la forma silenciosa de esquivar el gate de
  # lecciones: el archivo se volvería el sitio donde van a morir.
  mkdir -p docs/process
  printf '# Lecciones\n' > docs/process/lessons_learned.md
  printf '# Archivadas\n\n### [2026-01-01] Detector fantasma\n- **Detector:** tools/tests/test_borrado.sh\n- **Área:** x\n' \
    > docs/process/lessons_archive.md
  bash tools/lesson-detector-link.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    una lección ARCHIVADA con detector inexistente pasó el gate"; return 1; }
}
test_lecciones_archivadas_siguen_verificadas() { _rot_sandbox _case_archivo_sigue_verificado; }

_case_segunda_rotacion_es_noop() {
  printf '#!/usr/bin/env bash\n' > tools/tests/test_ejemplo.sh
  _doc '# Lecciones

### [2026-01-01] Regla mecanizada
- **Detector:** tools/tests/test_ejemplo.sh::test_x'
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1 || return 1
  [ "$(grep -c '^## Lecciones mecanizadas (índice)$' docs/process/lessons_learned.md)" = "1" ] \
    || { echo "    la primera rotación no dejó un índice único"; return 1; }
  cp docs/process/lessons_learned.md live.before
  cp docs/process/lessons_archive.md archive.before
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1 || return 1
  cmp -s live.before docs/process/lessons_learned.md \
    && cmp -s archive.before docs/process/lessons_archive.md \
    || { echo "    aplicar la rotación por segunda vez reescribió el resultado"; return 1; }
}
test_rotacion_aplicada_dos_veces_es_idempotente() {
  _rot_sandbox _case_segunda_rotacion_es_noop
}

_case_reconcilia_lecciones_agregadas_despues_del_indice() {
  printf '#!/usr/bin/env bash\n' > tools/tests/test_ejemplo.sh
  _doc '# Lecciones

### [2026-01-01] Primera mecanizada
- **Detector:** tools/tests/test_ejemplo.sh::test_a'
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1 || return 1
  printf '\n### [2026-01-02] Manual posterior al índice\n- **Detector:** n/a-manual — juicio\n' \
    >> docs/process/lessons_learned.md
  printf '\n### [2026-01-03] Segunda mecanizada\n- **Detector:** tools/tests/test_ejemplo.sh::test_b\n' \
    >> docs/process/lessons_learned.md
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1 || return 1

  [ "$(grep -c '^## Lecciones mecanizadas (índice)$' docs/process/lessons_learned.md)" = "1" ] \
    || { echo "    quedaron índices duplicados al rotar entradas posteriores"; return 1; }
  grep -q '^### .*Manual posterior al índice' docs/process/lessons_learned.md \
    || { echo "    la entrada manual posterior al índice se perdió"; return 1; }
  [ "$(grep -c '^### .*mecanizada' docs/process/lessons_archive.md)" = "2" ] \
    || { echo "    el archivo no contiene exactamente ambas lecciones mecanizadas"; return 1; }
}
test_rotacion_reconstruye_indice_si_hay_entradas_nuevas_despues() {
  _rot_sandbox _case_reconcilia_lecciones_agregadas_despues_del_indice
}

_case_titulo_igual_con_cuerpo_distinto_falla_sin_escribir() {
  printf '#!/usr/bin/env bash\n' > tools/tests/test_ejemplo.sh
  _doc '# Lecciones

### [2026-01-01] Misma identidad
- **Regla:** cuerpo nuevo.
- **Detector:** tools/tests/test_ejemplo.sh::test_x'
  printf '# Archivadas\n\n### [2026-01-01] Misma identidad\n- **Regla:** cuerpo anterior.\n- **Detector:** tools/tests/test_ejemplo.sh::test_x\n' \
    > docs/process/lessons_archive.md
  cp docs/process/lessons_learned.md live.before
  cp docs/process/lessons_archive.md archive.before
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    la colisión de identidad no falló cerrado"; return 1; }
  cmp -s live.before docs/process/lessons_learned.md \
    && cmp -s archive.before docs/process/lessons_archive.md \
    || { echo "    la colisión modificó archivos antes de abortar"; return 1; }
}
test_rotacion_no_deduplica_cuerpos_distintos_bajo_el_mismo_titulo() {
  _rot_sandbox _case_titulo_igual_con_cuerpo_distinto_falla_sin_escribir
}

_case_detector_borrado_devuelve_leccion_al_contexto_vivo() {
  printf '#!/usr/bin/env bash\n' > tools/tests/test_ejemplo.sh
  _doc '# Lecciones

### [2026-01-01] Garantía que caduca
- **Regla:** debe volver si pierde su test.
- **Detector:** tools/tests/test_ejemplo.sh::test_x'
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1 || return 1
  rm -f tools/tests/test_ejemplo.sh
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1 || return 1
  grep -q '^### .*Garantía que caduca' docs/process/lessons_learned.md \
    || { echo "    la lección sin test no volvió al documento vivo"; return 1; }
  grep -q '^### .*Garantía que caduca' docs/process/lessons_archive.md \
    && { echo "    la lección restaurada sigue también en el archivo"; return 1; }
  return 0
}
test_rotacion_reclasifica_archivada_si_su_test_desaparece() {
  _rot_sandbox _case_detector_borrado_devuelve_leccion_al_contexto_vivo
}

# ════════════════════════════════════════════════════════════════════
# FASE 0c (PRD 0005, WF-07) — el rotador es CANÓNICO, no solo estable
# ════════════════════════════════════════════════════════════════════
# El ciclo real «insertar lección antes del índice → rotar» dejaba un `---`
# huérfano más por tanda archivada: la entrada superviviente conservaba su
# cola de separadores y INDEX_HEAD añadía el suyo. Cada pasada era estable
# en bytes, pero ARRASTRABA el sedimento del input para siempre — hasta
# clavar el contexto vivo exactamente en su cap de 250 líneas.

_case_dos_pasadas_bytes_identicos_y_forma_canonica() {
  printf '#!/usr/bin/env bash\n' > tools/tests/test_ejemplo.sh
  _doc '# Lecciones

### [2026-01-01] Viva manual
- **Regla:** r.
- **Detector:** n/a-manual — juicio
- **Área:** x

---

---

---

### [2026-01-02] Mecanizada
- **Regla:** r.
- **Detector:** tools/tests/test_ejemplo.sh
- **Área:** x'
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1 || return 1
  cp docs/process/lessons_learned.md live.1
  cp docs/process/lessons_archive.md archive.1
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1 || return 1
  cmp -s live.1 docs/process/lessons_learned.md \
    || { echo "    dos pasadas seguidas → bytes DISTINTOS en el doc vivo"; return 1; }
  cmp -s archive.1 docs/process/lessons_archive.md \
    || { echo "    dos pasadas seguidas → bytes DISTINTOS en el archivo"; return 1; }
  # Canónico de verdad: el MISMO corpus sin sedimento converge a los MISMOS
  # bytes. Si difieren, la salida depende de la basura acumulada en el input.
  rm -f docs/process/lessons_archive.md
  _doc '# Lecciones

### [2026-01-01] Viva manual
- **Regla:** r.
- **Detector:** n/a-manual — juicio
- **Área:** x

### [2026-01-02] Mecanizada
- **Regla:** r.
- **Detector:** tools/tests/test_ejemplo.sh
- **Área:** x'
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1 || return 1
  cmp -s live.1 docs/process/lessons_learned.md \
    || { echo "    la forma final depende del sedimento del input: no es canónica"; return 1; }
}
test_rotacion_dos_pasadas_bytes_identicos_y_forma_canonica() {
  _rot_sandbox _case_dos_pasadas_bytes_identicos_y_forma_canonica
}

_case_colapsa_separadores_huerfanos_a_uno() {
  printf '#!/usr/bin/env bash\n' > tools/tests/test_ejemplo.sh
  _doc '# Lecciones

### [2026-01-01] Viva manual
- **Regla:** r.
- **Detector:** n/a-manual — juicio
- **Área:** x

---

---

---

### [2026-01-02] Mecanizada
- **Regla:** r.
- **Detector:** tools/tests/test_ejemplo.sh
- **Área:** x'
  bash tools/lessons-rotate.sh --apply >/dev/null 2>&1 || return 1
  local n
  n="$(awk '
    /^## Lecciones mecanizadas \(índice\)$/ { exit }
    /^```/ { fence = !fence }
    !fence && /^---$/ { c++ }
    END { print c + 0 }
  ' docs/process/lessons_learned.md)"
  [ "$n" = "1" ] \
    || { echo "    tras rotar quedan $n separadores --- antes del índice (canónico: exactamente 1)"; return 1; }
}
test_rotar_colapsa_separadores_huerfanos_a_uno_antes_del_indice() {
  _rot_sandbox _case_colapsa_separadores_huerfanos_a_uno
}

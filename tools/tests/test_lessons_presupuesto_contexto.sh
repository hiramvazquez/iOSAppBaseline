#!/usr/bin/env bash
# EL PRESUPUESTO DE CONTEXTO VIVO — estos tests NO usan un sandbox: corren
# contra el `docs/process/lessons_learned.md` y `lessons_archive.md` REALES
# del repo (vía $PROJECT_ROOT), porque lo que fijan es que ESE repositorio
# entrega su doc ya rotado y canónico (fase 8 / fase 0c del PRD 0005), no
# solo que el mecanismo funcione en un sandbox aislado. Sin esto, cada tanda
# de lecciones mecanizadas volvería a inflar el contexto obligatorio aunque
# `tools/lessons-rotate.sh` y sus unit tests (`test_lessons_rotacion.sh`)
# estén en verde.

# La fase 8 no solo entrega el rotador: entrega ESTE repositorio ya rotado.
# Sin fijarlo, cada tanda de lecciones mecanizadas vuelve a inflar el contexto
# obligatorio aunque el mecanismo exista y sus unit tests estén verdes.
test_documento_vivo_real_no_conserva_lecciones_archivables() {
  local out
  out="$(cd "$PROJECT_ROOT" && bash tools/lessons-rotate.sh)" || return 1
  case "$out" in *'ROTATE_SUMMARY '*'archivables=0'*) : ;; *)
    echo "    el documento vivo real aún tiene lecciones mecanizadas por rotar"
    printf '%s\n' "$out" | head -2 | sed 's/^/      /'
    return 1
  esac
  local indexes
  indexes="$(grep -c '^## Lecciones mecanizadas (índice)$' "$PROJECT_ROOT/docs/process/lessons_learned.md" || true)"
  [ "$indexes" = "1" ] || {
    echo "    el documento vivo debe tener un índice mecanizado único; tiene $indexes"
    return 1
  }
  return 0
}

test_contexto_vivo_obligatorio_cabe_en_250_lineas() {
  local index_line
  index_line="$(grep -n '^## Lecciones mecanizadas (índice)$' \
    "$PROJECT_ROOT/docs/process/lessons_learned.md" | cut -d: -f1)"
  [ -n "$index_line" ] || { echo "    falta el límite explícito entre contexto vivo e índice"; return 1; }
  [ $((index_line - 1)) -le 250 ] || {
    echo "    el contexto vivo obligatorio ocupa $((index_line - 1)) líneas (>250)"
    return 1
  }
}

test_regla_canonica_no_carga_el_historico_por_defecto() {
  grep -Fq 'detente en “Lecciones mecanizadas' "$PROJECT_ROOT/AGENTS.md" \
    || { echo "    AGENTS.md no delimita dónde termina la lectura viva"; return 1; }
  grep -Fq 'el histórico no se carga por defecto' "$PROJECT_ROOT/AGENTS.md" \
    || { echo "    AGENTS.md no excluye explícitamente el archivo del arranque"; return 1; }
  grep -Fq 'hasta “Lecciones' "$PROJECT_ROOT/.cursor/rules/00-canonical.mdc" \
    || { echo "    Cursor sigue sin límite explícito para la lectura de lecciones"; return 1; }
}

# El repositorio REAL entrega su doc ya canónico (fase 0c). Sin fijarlo, el
# sedimento vuelve a acumularse en silencio hasta clavar el cap otra vez.
test_documento_vivo_real_sin_separadores_huerfanos() {
  local n
  n="$(awk '
    /^```/ { fence = !fence; next }
    fence { next }
    /^### \[/ { body = 1 }
    /^## Lecciones mecanizadas \(índice\)$/ { exit }
    body && /^---$/ { c++ }
    END { print c + 0 }
  ' "$PROJECT_ROOT/docs/process/lessons_learned.md")"
  [ "$n" = "1" ] || {
    echo "    el doc vivo real tiene $n separadores --- entre lecciones (canónico: 1, justo antes del índice)"
    return 1
  }
}

# El gate de salida de la fase 0c del PRD 0005, literal: dos ejecuciones
# seguidas sobre el corpus REAL → diff de bytes vacío. Corre sobre COPIAS
# (LESSONS_DOC/LESSONS_ARCHIVE) desde la raíz del repo, para que classify
# vea los tests reales de tools/tests/ sin tocar los docs canónicos.
test_rotador_real_dos_pasadas_bytes_identicos() {
  local d ok=1
  d="$(mktemp -d)"
  cp "$PROJECT_ROOT/docs/process/lessons_learned.md" "$d/live.md" || { rm -rf "$d"; return 1; }
  cp "$PROJECT_ROOT/docs/process/lessons_archive.md" "$d/arch.md" || { rm -rf "$d"; return 1; }
  ( cd "$PROJECT_ROOT" && LESSONS_DOC="$d/live.md" LESSONS_ARCHIVE="$d/arch.md" \
      bash tools/lessons-rotate.sh --apply >/dev/null 2>&1 ) || ok=0
  cp "$d/live.md" "$d/live.1"; cp "$d/arch.md" "$d/arch.1"
  ( cd "$PROJECT_ROOT" && LESSONS_DOC="$d/live.md" LESSONS_ARCHIVE="$d/arch.md" \
      bash tools/lessons-rotate.sh --apply >/dev/null 2>&1 ) || ok=0
  [ "$ok" = "1" ] || { rm -rf "$d"; echo "    el rotador falló sobre el corpus real"; return 1; }
  cmp -s "$d/live.1" "$d/live.md" \
    || { rm -rf "$d"; echo "    dos pasadas sobre el corpus REAL → bytes distintos en el doc vivo"; return 1; }
  cmp -s "$d/arch.1" "$d/arch.md" \
    || { rm -rf "$d"; echo "    dos pasadas sobre el corpus REAL → bytes distintos en el archivo"; return 1; }
  rm -rf "$d"
}

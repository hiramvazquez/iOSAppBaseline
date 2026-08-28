#!/usr/bin/env bash
# La FUSION de los dos motores de check-source-sets: semgrep (primario) y el
# grep textual (fallback para lo que semgrep no pudo mirar).
#
# Vive aparte de `test_source_sets.sh` por el limite de tamaño de AGENTS.md §4
# —igual que `test_source_sets_prefijos.sh`, que se separo del mismo archivo por
# la misma razon—. El corte no es arbitrario: estos dos tests son los unicos que
# necesitan controlar la SALIDA de semgrep, y por eso los unicos con stub.
#
# Nota para quien venga: `tools/check-drift.sh` NO mide el tamaño de los `.sh`
# (su check de hard-limit solo mira extensiones de codigo dentro de SRC_DIRS),
# asi que este limite se respeta a mano hasta que ese hueco se cierre. Esta
# division la pidio el reviewer al ver el archivo en 417 lineas.

# ── Un semgrep de mentira, con la salida que el test necesita ───────
# Los dos tests de abajo comprueban qué hace el detector cuando semgrep NO pudo
# analizar un archivo entero. Estaban escritos montando un .kt roto y confiando
# en que semgrep se atragantara con él — y con qué se atraganta cambia entre
# versiones: en macOS (1.172) se atragantaba y en el ubuntu-latest de CI lo
# digería, así que los dos salían VERDES en local y ROJOS en CI, sobre un área
# (KMP) que el proyecto adoptante ni usa. Un test cuyo resultado depende de la
# versión de una herramienta de terceros no verifica el harness: verifica esa
# herramienta.
#
# El detector consume el JSON de semgrep (`results` = hits, `errors[].path` =
# saltados), así que controlando ESE JSON el escenario es exacto y determinista
# en cualquier plataforma. El patrón ya lo usa `_case_un_sigterm_lo_mata_de_verdad`.
# Helpers PROPIOS, no los de test_source_sets.sh. Reusarlos de alli funcionaba
# hoy solo porque el runner sourcea los archivos en orden alfabetico — un
# acoplamiento invisible que se rompe el dia que alguien renombra un archivo, y
# se rompe en forma de "helper no encontrado" a mitad de otra suite. El
# precedente de esta misma division (test_source_sets_prefijos.sh) tambien es
# autocontenido.
_ssf_repo() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/shared/src/commonMain/kotlin" \
           "$d/shared/src/androidMain/kotlin"
  cp "$PROJECT_ROOT/tools/check-source-sets.sh" "$d/tools/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}
_ssf_common() { printf '%s\n' "$@" > shared/src/commonMain/kotlin/Repo.kt; }

_ss_stub_semgrep() { # _ss_stub_semgrep <json-de-una-linea>
  rm -f bin/.stub-ejecutado
  # `stub` es el helper compartido del runner (escribe, hace +x y crea el
  # directorio). El `touch` deja rastro de haberse ejecutado: es lo unico que
  # distingue "el detector uso el stub" de "uso el semgrep real y coincidio".
  # Ver _ss_confirma_stub.
  stub bin/semgrep "#!/bin/sh\ntouch \"\$(dirname \"\$0\")/.stub-ejecutado\"\ncat <<'SEMGREP_JSON'\n$1\nSEMGREP_JSON\n"
}

# Que el stub se este usando DE VERDAD. Sin esto, si el override del PATH dejara
# de resolver, el semgrep real daria el mismo resultado observable en estos dos
# casos —el .kt de los fixtures ya no esta roto, asi que lo parsea entero y
# encuentra el import por el motor primario— y los tests pasarian por
# coincidencia. Es la misma fragilidad silenciosa que motivo esta leccion, un
# nivel mas abajo; la cazo el reviewer.
_ss_confirma_stub() {
  [ -f bin/.stub-ejecutado ] || {
    echo "    el detector NO uso el stub: corrio el semgrep real de esta maquina."
    echo "    Estos dos casos dan el mismo resultado observable con semgrep real"
    echo "    —el .kt del fixture ya no esta roto, asi que lo parsea entero y"
    echo "    encuentra el import por el motor primario—, o sea que el test"
    echo "    habria pasado por coincidencia, no por lo que dice probar."
    return 1; }
}

# AMBER-4 del design-review: "operativo" no es un hecho binario POR REPO. Si
# semgrep se atraganta con UN .kt, ese archivo concreto no lo ha mirado nadie.
_case_el_kt_que_semgrep_no_digiere_pasa_por_el_grep() {
  _ssf_common 'package dominio' 'class Repo'
  printf '%s\n' 'package dominio' 'import android.net.Uri' \
    > shared/src/commonMain/kotlin/Roto.kt
  # CERO hits y el archivo en `errors`: semgrep dice "no pude con este". Lo
  # único que puede salvar la violación es el fallback textual.
  _ss_stub_semgrep '{"results": [], "errors": [{"path": "shared/src/commonMain/kotlin/Roto.kt", "type": "PartialParsing"}]}'
  local out rc
  out="$(PATH="$PWD/bin:$PATH" bash tools/check-source-sets.sh 2>&1)"; rc=$?
  _ss_confirma_stub || return 1
  [ "$rc" = "1" ] || {
    echo "    un .kt que semgrep no pudo parsear entero debe pasar por el grep (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
  case "$out" in *Roto.kt*) : ;; *) echo "    no nombró el archivo saltado"; return 1 ;; esac
}
test_un_kt_que_semgrep_no_digiere_pasa_por_el_grep() {
  _ssf_repo _case_el_kt_que_semgrep_no_digiere_pasa_por_el_grep; }

# ── Doble conteo: el archivo con PartialParsing está en LAS DOS listas ──
# Cazado por la ronda 3 del reviewer. Cuando semgrep parsea a medias, ese
# archivo sale a la vez en sus hits (encontró lo que sí digirió) y en la lista
# de saltados (reportó el error), así que el re-scan por grep lo cuenta otra
# vez. El exit no cambia —sigue 1— pero `violaciones=N` miente, y una cifra
# derivable podrida es el pecado del que va la mitad de este PRD.
_case_partial_parsing_no_cuenta_dos_veces() {
  _ssf_common 'package dominio' 'class Repo'
  printf '%s\n' 'package dominio' 'import android.net.Uri' \
    > shared/src/commonMain/kotlin/Roto.kt
  # El archivo está en LAS DOS listas: semgrep encontró el import de la línea 2
  # por parseo parcial Y reportó que no pudo con el archivo entero. El re-scan
  # por grep vuelve a encontrar esa misma línea, así que sin dedupe por
  # `archivo:línea` la cuenta sale 2.
  _ss_stub_semgrep '{"results": [{"path": "shared/src/commonMain/kotlin/Roto.kt", "start": {"line": 2}}], "errors": [{"path": "shared/src/commonMain/kotlin/Roto.kt", "type": "PartialParsing"}]}'
  local out rc
  out="$(PATH="$PWD/bin:$PATH" bash tools/check-source-sets.sh 2>&1)"; rc=$?
  _ss_confirma_stub || return 1
  [ "$rc" = "1" ] || { echo "    la violación real no bloqueó (exit $rc)"; return 1; }
  case "$out" in *"violaciones=1"*) : ;; *)
    echo "    la MISMA violación se contó más de una vez:"
    printf '%s\n' "$out" | grep -E 'SOURCE_SETS|Roto.kt' | sed 's/^/      /'; return 1 ;; esac
}
test_una_violacion_en_un_kt_parseado_a_medias_se_cuenta_una_vez() {
  _ssf_repo _case_partial_parsing_no_cuenta_dos_veces; }

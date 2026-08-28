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

# ── El fallback SIEMPRE dice en que archivo ─────────────────────────
# Este test existe por un bug que solo se veia en Linux y que llego a CI: BSD
# grep (macOS) imprime el nombre del archivo cuando se recorre con -r, pero GNU
# grep lo OMITE si se le pasa un solo archivo explicito — que es justo lo que
# hace el fallback por archivo saltado. En Linux la violacion salia como
# `2:import android.net.Uri`, sin decir donde, y ademas el dedupe por
# `archivo:linea` no podia casar contra el hit de semgrep, asi que la misma
# violacion se contaba dos veces.
#
# Se prueba sobre UN solo archivo a proposito: con dos o mas, ambos greps
# imprimen el nombre y el bug es invisible.
#
# ⚠️ HONESTIDAD SOBRE SU ALCANCE: este test **no puede fallar en macOS**. Se
# comprobo quitando el `-H`: BSD grep sigue imprimiendo el nombre y el test
# sigue verde. Solo muerde en Linux, o sea en CI. Por eso existe ademas el
# guard estructural de abajo, que si muerde en cualquier plataforma. Un test
# que en tu maquina no puede ponerse rojo no es inutil —cubre el CI— pero
# decir que te protege en local seria mentir.
_case_el_fallback_nombra_el_archivo_siempre() {
  _ssf_common 'package dominio' 'class Repo'
  printf '%s\n' 'package dominio' 'import android.net.Uri' \
    > shared/src/commonMain/kotlin/Roto.kt

  # Sin semgrep: el detector cae al fallback textual entero.
  stub bin/semgrep '#!/bin/sh\nexit 127\n'
  local out
  out="$(PATH="$PWD/bin:$PATH" bash tools/check-source-sets.sh 2>&1)"

  printf '%s' "$out" | grep -qE 'Roto\.kt:[0-9]+' || {
    echo "    el fallback no dijo en QUE archivo esta la violacion."
    echo "    (GNU grep omite el nombre con un solo archivo si falta -H;"
    echo "     el usuario recibe una violacion que no puede localizar)"
    printf '%s\n' "$out" | sed 's/^/      /' | head -6
    return 1; }
}
test_el_fallback_nombra_el_archivo_siempre() {
  _ssf_repo _case_el_fallback_nombra_el_archivo_siempre; }

# El guard que SI muerde en cualquier plataforma. El test de arriba comprueba
# el comportamiento —lo correcto— pero es ciego en macOS; este fija la causa:
# que la invocacion lleve `-H`. Es un test de implementacion, y se acepta a
# sabiendas porque la alternativa es que el unico aviso llegue desde un runner
# de Linux, veinte minutos despues del push. Mismo patron que
# `test_sync_paths_cabe_en_una_linea_como_asume_su_parser`.
test_el_grep_del_fallback_pide_el_nombre_del_archivo() {
  local linea palabra tiene_H="no"
  linea="$(grep -nE '^[[:space:]]*grep .*PROHIBIDOS' "$PROJECT_ROOT/tools/check-source-sets.sh" | head -1)"
  [ -n "$linea" ] || { echo "    no encontre la invocacion de grep en _grep_en"; return 1; }

  # Se mira PALABRA a palabra, y solo las que son flags. Las dos versiones
  # anteriores de este guard fallaron por buscar la letra H como substring:
  #   · en la linea entera, la encontraba dentro del patron entrecomillado
  #     (la H de PROHIBIDOS) y el guard dejaba de morder;
  #   · recortando "todo lo anterior a la primera comilla doble", el mismo
  #     fallo volvia si alguien escribia el patron con comillas simples.
  # Un flag es una palabra que empieza por `-`, y ninguna palabra del patron
  # empieza por `-`, asi que el contenido entrecomillado ya no puede colarse.
  # (Lo cazo el reviewer, las dos veces.)
  # Y dentro de un flag, solo cuenta si el cluster son letras de flags QUE NO
  # LLEVAN ARGUMENTO. `-eHead` es `-e` con el valor "Head" pegado —sintaxis
  # valida y comun— y contiene una H que no es el flag `-H`: con un substring
  # match a secas, anadir un segundo patron con `-e` habria desactivado este
  # guard en silencio. Lo cazo el reviewer, la tercera vez sobre esta misma
  # funcion. La allowlist se declara en vez de escribir un parser de getopt:
  # esto es un test de regresion sobre una invocacion conocida, no un CLI.
  # La lista cubre los flags de grep SIN argumento del synopsis de BSD grep y
  # sus equivalentes GNU. No pretende ser exhaustiva para siempre —si falta uno
  # el guard falla del lado seguro: bloquea de mas, nunca deja pasar un -H
  # ausente—. Si anades uno, comprueba antes que no consuma valor:
  # los que si lo consumen —A B C D d e f m— tienen que quedarse FUERA, o un
  # `-eHead` volveria a colar una H que no es el flag -H.
  # shellcheck disable=SC2086  # el word splitting es justo lo que se busca
  for palabra in $linea; do
    case "$palabra" in
      --with-filename) tiene_H="si"; break ;;
      --*) ;;
      -*H*)
        case "${palabra#-}" in
          *[!rRHnEFGPVSOpybJMXZviwxoclLqszaIuU]*) ;;   # lleva algo que no es flag simple
          *) tiene_H="si"; break ;;
        esac ;;
    esac
  done

  [ "$tiene_H" = "si" ] || {
    echo "    _grep_en invoca grep SIN -H:"
    echo "      $linea"
    echo "    GNU grep omite el nombre del archivo cuando se le pasa un solo"
    echo "    archivo explicito, asi que en Linux la violacion sale sin decir"
    echo "    donde esta y el dedupe por archivo:linea deja de casar. En macOS"
    echo "    no se nota, y por eso este guard existe."
    return 1; }
}

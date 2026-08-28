#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# EL invariante de KMP: commonMain no importa plataforma
# ════════════════════════════════════════════════════════════════════
# El harness modelaba un solo eje —el grafo por directorio de check-layers— y
# KMP añade otro que ese grafo no ve: el de source sets. Un `import android.*`
# en commonMain compila mientras solo construyas Android y revienta semanas
# después, al añadir el target iOS, en el CI de otro y con un error que no
# apunta al import. Es el ~10x por nivel de §14.1 pagado entero.

_ss_repo() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/shared/src/commonMain/kotlin" \
           "$d/shared/src/androidMain/kotlin"
  cp "$PROJECT_ROOT/tools/check-source-sets.sh" "$d/tools/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}
_common() { printf '%s\n' "$@" > shared/src/commonMain/kotlin/Repo.kt; }

_case_import_de_plataforma_en_common_bloquea() {
  _common 'package dominio' 'import android.net.Uri' '' 'class Repo'
  local out rc; out="$(bash tools/check-source-sets.sh 2>&1)"; rc=$?
  [ "$rc" = "1" ] || { echo "    un import de plataforma en commonMain NO bloqueó (exit $rc)"; return 1; }
  case "$out" in *Repo.kt*) : ;; *) echo "    no dijo qué archivo"; return 1 ;; esac
  case "$out" in *expect*) : ;; *) echo "    no apuntó a expect/actual, que es la salida"; return 1 ;; esac
}
test_commonmain_no_puede_importar_plataforma() { _ss_repo _case_import_de_plataforma_en_common_bloquea; }

_case_el_mismo_import_en_androidmain_es_correcto() {
  # Es el punto entero del eje: lo prohibido en commonMain es lo NORMAL en
  # androidMain. Un detector que no distinga los dos source sets prohíbe usar
  # la plataforma en el sitio donde hay que usarla.
  _common 'package dominio' 'expect class Reloj'
  printf '%s\n' 'package dominio' 'import android.net.Uri' 'actual class Reloj' \
    > shared/src/androidMain/kotlin/Reloj.kt
  bash tools/check-source-sets.sh >/dev/null 2>&1 \
    || { echo "    FALSO POSITIVO: acusó a androidMain, que es donde SÍ toca importar plataforma"; return 1; }
}
test_androidmain_si_puede_importar_plataforma() { _ss_repo _case_el_mismo_import_en_androidmain_es_correcto; }

# ── FALSO POSITIVO: nombrar un paquete no es importarlo ─────────────
# La mina que este repo ya ha pisado siete veces. Un KDoc que explica por qué NO
# se usa `android.net.Uri`, o una cadena con ese texto, no es un import. El
# anclaje se apoya en la gramática de Kotlin —un import solo vale al principio
# de la línea—, no en nuestro criterio.
_case_mencionar_no_es_importar() {
  _common 'package dominio' \
    '// No uses android.net.Uri aquí: rompe iOS. Ver expect/actual.' \
    '/** Antes esto hacía import android.net.Uri y reventó el target iOS. */' \
    'val doc = "import android.net.Uri"' \
    'class Repo'
  local out rc; out="$(bash tools/check-source-sets.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: un comentario/cadena que NOMBRA el paquete contó como import (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_un_comentario_que_nombra_el_paquete_no_es_un_import() { _ss_repo _case_mencionar_no_es_importar; }

# ── FALSO POSITIVO: un repo sin KMP no puede oír este gate jamás ────
# La mitad de los adoptantes no usa KMP. Un aviso permanente para ellos se
# aprende a ignorar, y con él se ignora el del día que importa (§14.2). "No
# aplica" es un hecho distinto de "no pude mirar" y se dice distinto: exit 0.
_case_repo_sin_kmp_calla() {
  rm -rf shared
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  local out rc; out="$(bash tools/check-source-sets.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || { echo "    un repo sin KMP no salió 0 (exit $rc)"; return 1; }
  case "$out" in *no-aplica*) : ;; *)
    echo "    no declaró el estado 'no-aplica': $out"; return 1 ;; esac
  case "$out" in *"❌"*) echo "    un repo sin KMP recibió un ERROR"; return 1 ;; esac
}
test_un_repo_sin_kmp_declara_no_aplica_y_no_avisa() { _ss_repo _case_repo_sin_kmp_calla; }


# ════════════════════════════════════════════════════════════════════
# PRD 0005 fase 1c — semgrep primario, y un fallback que SIGUE bloqueando
# ════════════════════════════════════════════════════════════════════
# `import` es una propiedad SINTÁCTICA y se comprobaba con texto. El anclaje a
# inicio de línea tapa el caso fácil (`// import ...`), pero no el que la
# gramática sí distingue: un bloque `/* */` sin asteriscos de adorno y un string
# triple contienen líneas que EMPIEZAN por `import`. Medido sobre el corpus de
# abajo, el grep daba 2 falsos positivos de 5 hits — 40%, cuatro veces la ley
# del 10% (§14.2). Semgrep parsea Kotlin, así que ahí no hay nada que anclar.
#
# El fallback NO se retira: si semgrep no está, el grep sigue corriendo y una
# violación REAL sigue saliendo 1. Degradar eso a 3 sería apagar el gate en la
# única situación en la que el gate tenía algo que decir (PRD 0005 §6).

_sin_semgrep() { PATH="/usr/bin:/bin" "$@"; }
_semgrep_roto() {   # un binario que existe y revienta ≠ un binario ausente
  mkdir -p bin; printf '#!/bin/sh\necho "boom" >&2\nexit 2\n' > bin/semgrep
  chmod +x bin/semgrep; PATH="$PWD/bin:/usr/bin:/bin" "$@"
}

_case_bloque_comentado_no_es_import() {
  _common 'package dominio' '/*' 'import android.net.Uri' '*/' 'class Repo'
  local out rc; out="$(bash tools/check-source-sets.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: un import dentro de /* */ contó como import (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_un_import_dentro_de_un_bloque_comentado_no_es_un_import() {
  _ss_repo _case_bloque_comentado_no_es_import; }

_case_string_triple_no_es_import() {
  _common 'package dominio' 'val ejemplo = """' 'import android.net.Uri' '"""' 'class Repo'
  local out rc; out="$(bash tools/check-source-sets.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: un import dentro de \"\"\" contó como import (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_un_import_dentro_de_un_string_triple_no_es_un_import() {
  _ss_repo _case_string_triple_no_es_import; }

# El otro lado del mismo filo: parsear no puede AFLOJAR la detección. Espacios
# de más, alias e import con estrella son imports para la gramática, y lo eran
# para el grep — si al cambiar de motor dejaran de serlo, habríamos cambiado
# 2 falsos positivos por 3 falsos negativos, que es peor.
_case_variantes_sintacticas_siguen_bloqueando() {
  local v; local -a variantes=(
    'import   android.net.Uri'
    'import android.net.*'
    'import android.os.Build as B'
  )
  for v in "${variantes[@]}"; do
    _common 'package dominio' "$v" 'class Repo'
    bash tools/check-source-sets.sh >/dev/null 2>&1 \
      && { echo "    FALSO NEGATIVO: '$v' no bloqueó"; return 1; }
  done
  return 0
}
test_alias_estrella_y_espacios_no_evaden_el_detector() {
  _ss_repo _case_variantes_sintacticas_siguen_bloqueando; }

# ── La tabla de fallback de PRD 0005 §6, fila por fila ──────────────
_case_sin_semgrep_violacion_real_bloquea() {
  _common 'package dominio' 'import android.net.Uri' 'class Repo'
  local out rc; out="$(_sin_semgrep bash tools/check-source-sets.sh 2>&1)"; rc=$?
  [ "$rc" = "1" ] || {
    echo "    sin semgrep, una violación REAL no bloqueó (exit $rc) — el fallback existe"
    echo "    exactamente para esto; degradarlo a 3 aquí es apagar el gate"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_sin_semgrep_una_violacion_real_sigue_bloqueando() {
  _ss_repo _case_sin_semgrep_violacion_real_bloquea; }

_case_sin_semgrep_y_limpio_dice_que_no_miro() {
  _common 'package dominio' 'import kotlinx.coroutines.flow.Flow' 'class Repo'
  local out rc; out="$(_sin_semgrep bash tools/check-source-sets.sh 2>&1)"; rc=$?
  [ "$rc" = "3" ] || {
    echo "    sin semgrep y sin hits del grep debe salir 3 (no pude mirar), salió $rc."
    echo "    Un 0 aquí convierte un scanner ausente en luz verde permanente (§14.3)."
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_sin_semgrep_y_limpio_declara_que_no_pudo_mirar() {
  _ss_repo _case_sin_semgrep_y_limpio_dice_que_no_miro; }

_case_en_ci_el_no_pude_mirar_bloquea() {
  _common 'package dominio' 'import kotlinx.coroutines.flow.Flow' 'class Repo'
  local rc; _sin_semgrep env GATES_REQUIRE_SOURCE_SETS=1 \
    bash tools/check-source-sets.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ] || {
    echo "    con GATES_REQUIRE_SOURCE_SETS=1 el exit 3 debe escalar a 1 (bloquea en CI), salió $rc"
    return 1; }
}
test_sin_semgrep_y_limpio_en_ci_bloquea() { _ss_repo _case_en_ci_el_no_pude_mirar_bloquea; }

_case_semgrep_roto_es_como_ausente() {
  # "Instalado" no es "funciona". Un binario que revienta al arrancar es
  # exactamente el estado que este harness tuvo durante días.
  _common 'package dominio' 'import android.net.Uri' 'class Repo'
  local rc; _semgrep_roto bash tools/check-source-sets.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ] || {
    echo "    con semgrep ROTO y una violación real debe bloquear vía fallback, salió $rc"; return 1; }
}
test_semgrep_roto_se_trata_como_ausente_no_como_verde() {
  _ss_repo _case_semgrep_roto_es_como_ausente; }

# ── La fusion semgrep + grep vive en test_source_sets_fallback.sh ───
# Los dos tests que controlan la salida de semgrep con un stub se movieron alli
# por el limite de §4 (este archivo ya se dividio una vez por lo mismo, ver
# test_source_sets_prefijos.sh).

# ── El registro de "semgrep fue operativo aquí" (PRD 0005 §6, AMBER-3) ──
# Habilita la auto-escalada en CI: una vez que semgrep analizó Kotlin en ESTE
# repo, un "no pude mirar" posterior es una regresión del entorno, no una
# limitación del proyecto. Vive commiteado y es del adoptante, así que las dos
# cosas que NO puede hacer son pisarlo y duplicarlo.
_case_el_registro_es_idempotente_y_no_pisa() {
  printf '%s\n' 'project_kind: application' '' '# un comentario del adoptante' > tools/project.conf
  _common 'package dominio' 'class Repo'
  bash tools/check-source-sets.sh >/dev/null 2>&1
  grep -q '^project_kind: application$' tools/project.conf \
    || { echo "    PISÓ lo que el adoptante había declarado"; return 1; }
  grep -q '^# un comentario del adoptante$' tools/project.conf \
    || { echo "    se comió un comentario del adoptante"; return 1; }
  local n; n="$(grep -c '^source_sets_semgrep:' tools/project.conf || true)"
  [ "$n" = "1" ] || { echo "    esperaba 1 registro, hay $n"; return 1; }
  bash tools/check-source-sets.sh >/dev/null 2>&1   # segunda pasada
  n="$(grep -c '^source_sets_semgrep:' tools/project.conf || true)"
  [ "$n" = "1" ] || { echo "    duplicó el registro en la segunda pasada ($n)"; return 1; }
}
test_el_registro_de_semgrep_no_pisa_ni_duplica_el_conf() {
  _ss_repo _case_el_registro_es_idempotente_y_no_pisa; }

# Un detector que ensucia el árbol EN MITAD de un commit cuesta más que la
# escalada que habilita: verify-run se niega a firmar con cambios sin stagear,
# así que un write aquí trabaría el commit que lo dispara.
_case_dentro_de_un_git_hook_no_escribe() {
  printf '%s\n' 'project_kind: application' > tools/project.conf
  _common 'package dominio' 'class Repo'
  GIT_INDEX_FILE=.git/index bash tools/check-source-sets.sh >/dev/null 2>&1
  grep -q '^source_sets_semgrep:' tools/project.conf \
    && { echo "    escribió en tools/project.conf dentro de un git hook"; return 1; }
  return 0
}
test_dentro_de_un_git_hook_el_registro_no_ensucia_el_arbol() {
  _ss_repo _case_dentro_de_un_git_hook_no_escribe; }

# ── Regresión cazada por el reviewer de la fase 1c ──────────────────
# La versión anterior iteraba `while IFS= read -r dir; do ... "$dir"`, inmune a
# espacios. Al pasar los directorios como lista a semgrep y al grep, la primera
# implementación los expandió SIN comillas y un `commonMain` bajo una ruta con
# espacio dejaba de mirarse — en silencio, que es la parte grave: un detector
# que no mira parece un detector que aprueba.
_case_una_ruta_con_espacios_se_sigue_mirando() {
  mkdir -p 'mi modulo/src/commonMain/kotlin'
  printf '%s\n' 'package dominio' 'import android.net.Uri' 'class Repo' \
    > 'mi modulo/src/commonMain/kotlin/Repo.kt'
  local out rc; out="$(bash tools/check-source-sets.sh 2>&1)"; rc=$?
  [ "$rc" = "1" ] || {
    echo "    un commonMain bajo una ruta CON ESPACIOS no se miró (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
  # Y el exit 1 NO basta como aserción. Si semgrep recibe la ruta partida en
  # trozos no encuentra targets, `_semgrep_mira` devuelve "no miré" y el script
  # cae al fallback, que sí la mira: mismo exit 1 por un camino distinto. El
  # diseño se auto-cura y de paso se traga la mutación. Lo que fija que el motor
  # PRIMARIO vio la ruta es el estado, no el código de salida.
  case "$out" in *estado=operational*) : ;; *)
    echo "    exit 1 pero NO por semgrep: el primario no miró la ruta con espacios"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1 ;; esac
  # Y lo mismo por el camino del fallback, que expande la misma lista.
  out="$(_sin_semgrep bash tools/check-source-sets.sh 2>&1)"; rc=$?
  [ "$rc" = "1" ] || { echo "    el fallback tampoco miró la ruta con espacios (exit $rc)"; return 1; }
  case "$out" in *estado=fallback-textual*) : ;; *)
    echo "    el fallback no declaró su estado: $out"; return 1 ;; esac
}
test_un_commonmain_bajo_una_ruta_con_espacios_se_sigue_mirando() {
  _ss_repo _case_una_ruta_con_espacios_se_sigue_mirando; }

# ── Terminabilidad: el detector se deja matar ───────────────────────
# Dos rondas de review seguidas encontraron un bug en las mismas tres líneas de
# limpieza de temporales. La segunda fue peor que la primera: `trap ... INT TERM`
# NO es local a la función, así que quedaba instalado para el resto del script y,
# como el handler solo borraba, el proceso dejaba de morir con SIGTERM — el
# `timeout` de CI o el watchdog que debía matarlo perdían la capacidad. Encima el
# handler leía LOCALES fuera de ámbito y bajo `set -u` reventaba, así que el
# script salía 1 en vez de 143 y el código de salida mentía sobre por qué murió.
# Un gate que no se puede matar es peor que el fichero de /tmp que la limpieza
# venía a salvar (§14.3). Esto se fija con un test o vuelve una tercera vez.
_case_un_sigterm_lo_mata_de_verdad() {
  _common 'package dominio' 'class Repo'
  # La señal tiene que llegar AL PROPIO detector, no a un envoltorio: el trap
  # vive en su proceso. Un semgrep falso que se duerme lo deja parado justo
  # DENTRO de _semgrep_mira, que es donde el trap malo estaba instalado.
  mkdir -p bin; printf '#!/bin/sh\nsleep 30\n' > bin/semgrep; chmod +x bin/semgrep
  PATH="$PWD/bin:/usr/bin:/bin" bash tools/check-source-sets.sh >/dev/null 2>&1 & local pid=$!
  sleep 2; kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null; local rc=$?
  [ "$rc" = "143" ] || {
    echo "    un SIGTERM al detector debía matarlo con 143 y salió $rc"
    case "$rc" in
      0|1) echo "    (se tragó la señal: el trap la 'manejó' sin re-lanzarla ni salir." ;;
    esac
    echo "     Un gate que no se puede matar traba el commit — §14.3.)"
    return 1; }
}
test_un_sigterm_mata_el_detector_en_vez_de_ser_ignorado() {
  _ss_repo _case_un_sigterm_lo_mata_de_verdad; }

# Y la otra mitad del contrato: el trap EXIT sí limpia en el camino normal.
#
# TMPDIR PROPIO, no el compartido. La primera versión contaba `sourcesets-*` en
# el TMPDIR del sistema, y eso es medir una variable GLOBAL: se puso roja en
# cuanto otros agentes corrieron la suite en paralelo y dejaron sus temporales
# ahí (4 ficheros ajenos, comprobado en vivo). Un test que depende de que nadie
# más esté trabajando no es un test, es una coincidencia — y produce
# exactamente la señal intermitente que la fase 0a de este PRD existe para
# erradicar. Con un TMPDIR privado el conteo es del detector y de nadie más.
_case_no_deja_temporales_huerfanos() {
  _common 'package dominio' 'import android.net.Uri' 'class Repo'
  local tmp; tmp="$(mktemp -d)" || return 1
  TMPDIR="$tmp" bash tools/check-source-sets.sh >/dev/null 2>&1
  local quedan; quedan="$(find "$tmp" -maxdepth 1 -name 'sourcesets-*' 2>/dev/null | wc -l | tr -d ' ')"
  rm -rf "$tmp"
  [ "$quedan" = "0" ] || { echo "    dejó $quedan temporal(es) sourcesets-* huérfanos"; return 1; }
}
test_el_camino_normal_no_deja_temporales_huerfanos() {
  _ss_repo _case_no_deja_temporales_huerfanos; }


# ── El detector no puede dejar de mirar en silencio ─────────────────
# Tenía `find ... | head -20`. En el corpus con el que se cerró el gate de la
# fase 1c (57 `commonMain`) eso miraba 20 y callaba 37 — y en orden de
# filesystem, así que CUÁLES miraba no era ni determinista. Un gate que aprueba
# lo que no leyó tiene la forma exacta de uno que pasó (§14.3), y lo cazó el
# reviewer al reproducir la medición a escala completa por su cuenta.
_case_mira_todos_los_commonmain_no_los_primeros() {
  # CUENTA, no posición. Poner la violación "en el último" no vale: `find`
  # devuelve en orden de filesystem, así que cuál cae dentro del tope no es
  # determinista y el test pasaba con el tope puesto. Con una violación en CADA
  # módulo, el número que reporta el detector dice exactamente cuántos miró.
  rm -rf shared
  local i n=30
  for i in $(seq 1 $n); do
    mkdir -p "mod$i/src/commonMain/kotlin"
    printf '%s\n' 'package dominio' 'import android.net.Uri' "class M$i" \
      > "mod$i/src/commonMain/kotlin/A.kt"
  done
  local out rc; out="$(bash tools/check-source-sets.sh 2>&1)"; rc=$?
  [ "$rc" = "1" ] || { echo "    $n módulos en violación y no bloqueó (exit $rc)"; return 1; }
  case "$out" in
    *"violaciones=$n"*) : ;;
    *) echo "    miró solo una PARTE de los $n módulos — un gate que aprueba lo"
       echo "    que no leyó tiene la forma de uno que pasó (§14.3):"
       printf '%s\n' "$out" | grep SOURCE_SETS | sed 's/^/      /'; return 1 ;;
  esac
}
test_con_muchos_modulos_no_deja_de_mirar_los_ultimos() {
  _ss_repo _case_mira_todos_los_commonmain_no_los_primeros; }

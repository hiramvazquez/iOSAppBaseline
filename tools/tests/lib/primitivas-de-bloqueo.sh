#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# primitivas-de-bloqueo.sh — deriva qué funciones de una lib DENIEGAN
# ════════════════════════════════════════════════════════════════════
# Uso:  primitivas-de-bloqueo.sh <lib.sh>
# Salida (stdout), una línea por función:  <nombre> <deniega:0|1> <registra:0|1>
# Exit: 0 si pudo analizar · 3 si el archivo no existe o no se puede sourcear.
#
# POR QUÉ BASH Y NO UNA REGEX. Las dos versiones anteriores de esto eran un
# parser con forma de bash escrito a mano, y las dos tenían puntos ciegos que un
# reviewer encontró por mutación, uno detrás de otro:
#
#   nombre()            ← la llave en la línea siguiente
#   {                     (invisible: la cabecera exigía `{` en la misma línea)
#   function nombre {   ← la keyword `function`
#   nombre() { …; }     ← definición de una sola línea (io.sh tiene una)
#   }                   ← cierre indentado
#   echo ${1}           ← el conteo de llaves se desincronizaba: quitaba `${`
#                          y dejaba su `}`, así que el cuerpo se cerraba antes
#                          y el `exit 2` de después desaparecía
#
# Ir arreglando formas de una en una es perder la carrera: la lista de shapes
# válidos de bash la decide bash, no yo. Así que **el parser es bash**. Se
# sourcea la lib en un subshell limpio y se le pregunta a `declare -f`, que
# devuelve el cuerpo tal y como bash lo parseó: normalizado, sin comentarios
# (gratis: un `# … exit 2 …` en prosa ya no puede dar falso positivo) y con
# todas las formas colapsadas a una. Un shape nuevo de bash no puede escaparse
# porque no hay shape que reconocer.
#
# CONTRAPARTIDA HONESTA, y es un cambio de NATURALEZA, no de implementación:
# sourcear EJECUTA el código de nivel superior del archivo. Vale para una
# librería pensada para ser sourceada —que es el caso de `lib/io.sh` y de las
# fixtures— y NO vale para un ejecutable con efectos. Si algún día se apunta
# esto a un script con `main`, el remedio no es adivinar: es no apuntarlo ahí.
#
# De esa contrapartida se mitiga aquí lo que se puede mitigar barato:
#   · stdin va a `/dev/null` — un `read` de nivel superior colgaba el análisis
#     indefinidamente (fijado por `test_analizar_un_archivo_que_lee_stdin_no_cuelga`);
#   · el entorno va con `env -i`, así que ni funciones exportadas ni `BASH_ENV`
#     del entorno ambiente contaminan el inventario.
# Lo que NO se mitiga y hay que saber: un archivo con efectos reales de nivel
# superior (escribir, borrar, llamar a la red) los ejecutará. Eso no se arregla
# con una redirección, se arregla no apuntando esto ahí.
set -uo pipefail

LIB="${1:-}"
[ -n "$LIB" ] && [ -f "$LIB" ] || {
  printf 'primitivas-de-bloqueo: no puedo leer «%s»\n' "$LIB" >&2; exit 3; }

# El subshell arranca con `env -i` para que una función exportada del entorno
# del llamador no se cuele en el inventario y se atribuya al archivo.
#
# El programa va en una variable y se pasa con `-c`, NO por heredoc dentro de
# `$( … )`: bash 3.2 —el que trae macOS, o sea la máquina donde corre la mitad
# de esta suite— cierra el heredoc en el `)` de la sustitución y el shell de
# fuera acaba ejecutando parte del programa de dentro.
INNER='
set -uo pipefail
antes="$(declare -F | awk "{print \$NF}" | sort)"
. "$1" || exit 3
despues="$(declare -F | awk "{print \$NF}" | sort)"
printf "%s\n" "$antes" > "$TMPA"
printf "%s\n" "$despues" > "$TMPB"
for fn in $(comm -13 "$TMPA" "$TMPB"); do
  cuerpo="$(declare -f "$fn")"
  deniega=0; registra=0
  case "$cuerpo" in
    *"exit 2"*|*permissionDecision*|*"decision:\"block\""*) deniega=1 ;;
  esac
  case "$cuerpo" in *_hook_log_block*) registra=1 ;; esac
  printf "%s %s %s\n" "$fn" "$deniega" "$registra"
done
'

TMPA="$(mktemp)"; TMPB="$(mktemp)"
trap 'rm -f "$TMPA" "$TMPB"' EXIT

# `< /dev/null` NO es decorativo y cuesta cero: sourcear ejecuta el nivel
# superior del archivo, así que un `read` ahí deja el ANÁLISIS colgado
# esperando una entrada que nadie va a escribir. Un test que se cuelga es peor
# que uno que falla —bloquea la suite entera y en CI el job— y es una lección
# ya mecanizada de esta casa.
#
# Se demuestra A/B con stdin conectado a un pipe vivo sin datos (`sleep 30 | …`):
# con la redirección el inventario produce su línea, sin ella no produce nada.
# NO con un FIFO, que fue el primer intento y no distinguía nada: abrirlo para
# lectura bloquea hasta que alguien lo abre para escribir, así que el montaje se
# colgaba antes de ejecutar el script y habría dado rojo con el arreglo puesto.
# Lo fija `test_analizar_un_archivo_que_lee_stdin_no_cuelga`, que mide la SALIDA
# dentro de un plazo y no el exit code de un envoltorio.
salida="$(TMPA="$TMPA" TMPB="$TMPB" env -i TMPA="$TMPA" TMPB="$TMPB" PATH="$PATH" \
  "$(command -v bash)" --noprofile --norc -c "$INNER" bash "$LIB" \
  < /dev/null 2>/dev/null)" || {
  printf 'primitivas-de-bloqueo: no pude sourcear «%s»\n' "$LIB" >&2; exit 3; }

[ -n "$salida" ] || {
  printf 'primitivas-de-bloqueo: «%s» no define ninguna función\n' "$LIB" >&2; exit 3; }
printf '%s\n' "$salida"

#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# writes.sh — qué archivos ESCRIBIÓ un comando de Bash
# ════════════════════════════════════════════════════════════════════
# El agujero que cierra, medido en la sesión que lo motivó: 609 tool-calls,
# 589 de ellas Bash y CERO Edit/Write, para 533 líneas de shell nuevo. Los dos
# hooks que dependen de saber qué archivo se tocó colgaban de `Edit|Write`, así
# que ninguno corrió:
#
#   · `post-edit-verify` — el nivel 1 del bucle (shellcheck + `bash -n`), que
#     es el gate de mayor ROI del harness. No dio ni una señal in-loop.
#   · `track-trajectory` — registraba `python3`, `sed`, `cat` como "path",
#     nunca el archivo, así que el `process-judge` no podía responder su
#     pregunta nº1 (f-ee9787d9, f-153aef5b).
#
# NO SE PARSEA EL COMANDO, SE OBSERVA EL EFECTO. Reconocer escrituras con
# expresiones regulares (`>`, `sed -i`, `tee`, `python3 - <<PY`) es la misma
# carrera perdida que reconocer formas de bash con regex: la lista la decide
# el shell, no nosotros, y se descubre una forma nueva por ronda de review.
# Aquí se compara el ANTES con el DESPUÉS y da igual cómo se escribiera.
#
# ── Por qué CONTENIDO y no marca de tiempo ─────────────────────────
# La primera versión comparaba mtime contra un marcador, y produjo DOS bugs
# distintos de manejo del tiempo antes de funcionar:
#   1. Calculaba el instante con `date -u` (UTC) para un `touch -t` que
#      interpreta hora LOCAL. En una máquina en CST la marca quedaba SEIS HORAS
#      EN EL FUTURO, nada resultaba nunca más nuevo, y el detector devolvía
#      vacío para todo — indistinguible de "no hubo escrituras".
#   2. Ya con el huso bien: `[ a -nt b ]` en el **bash** de macOS compara
#      SEGUNDOS ENTEROS, aunque el sistema de archivos guarde nanosegundos.
#      (La comprobación que lo dio por bueno corrió en zsh, que sí los usa —
#      verificar el primitivo en un shell distinto del que lo ejecuta es su
#      propia lección.) Una escritura dentro del mismo segundo era invisible.
# El tiempo aquí es un proxy del hecho que interesa; el hecho es "¿cambió el
# contenido?". Comparar contenido no depende del huso, ni del shell, ni de la
# granularidad del sistema de archivos, y no tiene ventana que ajustar.
#
# ALCANCE EXACTO, que es lo que no se puede prometer de más:
#   · Ve lo que ve git: modificados, nuevos sin trackear y borrados.
#   · NO ve archivos ignorados por `.gitignore` — y eso es deliberado: el
#     propio harness escribe en `.agents/state/` en cada hook, y si eso
#     contara, cada comando "habría escrito" media docena de archivos.
#   · NO ve escrituras fuera del repo.
#   · Una ruta que contenga un SALTO DE LÍNEA se descarta: la foto es un archivo
#     de líneas y una ruta multilínea la corrompería. Es el único caso que se
#     pierde, y se pierde declarado aquí en vez de en silencio.
#   · Por encima de WRITES_MAX_FILES archivos sucios deja de calcular huellas.
#     Esos archivos salen marcados con `?` en la primera columna, y esa marca
#     importa porque
#     los dos consumidores quieren cosas distintas de la misma señal:
#       – `post-edit-verify` pregunta "¿qué lintar?" y para eso sobre-reportar
#         es seguro: mirar uno de más cuesta un `shellcheck`, mirar uno de
#         menos es el silencio que esta librería existe para eliminar.
#       – `track-trajectory` pregunta "¿qué tocó ESTE comando?" y para eso
#         sobre-reportar es peor que callar: convierte en evidencia archivos
#         que el comando no tocó, y encima de forma permanente (una vez
#         cruzado el tope, hasta un `ls` los arrastraría).
#     Con la marca, cada uno decide: el primero los lintá, el segundo los
#     cuenta aparte como "no lo sé" en vez de afirmarlos.
#     Las dos versiones anteriores fallaron por los dos extremos de esto: la
#     primera emitía una línea constante que coincidía consigo misma y ESCONDÍA
#     ediciones; la segunda las reportaba todas y las AFIRMABA.
#   · Las rutas que salen pueden NO existir (un borrado se reporta). Quien las
#     consuma debe tolerarlo; `post-edit-verify` ya lo hace.
#   · NO hay identidad por invocación: la foto es una sola. Dos comandos de
#     Bash solapados (p. ej. uno en background) pueden pisarse la foto y
#     atribuir mal las escrituras. Es consistente con el contrato best-effort
#     —el peor caso es señal perdida o mal atribuida, nunca un fallo— pero se
#     declara aquí en vez de descubrirse.
#   · Es best-effort y JAMÁS puede romper al hook que la llama: sin snapshot,
#     sin git o sin `cksum`, devuelve vacío y sale 0.

WRITES_MAX_FILES="${WRITES_MAX_FILES:-40}"

# Un salto de línea literal, para poder buscarlo en una ruta.
_WRITES_NL='
'


# _writes_snapshot_file — dónde vive la foto del antes.
_writes_snapshot_file() { printf '%s/.agents/state/bash-writes.snapshot' "${PROJECT_ROOT:-$(pwd)}"; }

# _writes_state — imprime `<huella> <ruta>` por cada archivo que git ve sucio.
# La huella es `cksum` del contenido: barata, sin dependencias nuevas, y
# suficiente para "¿cambió esto?" (no es criptografía, es detección de cambio).
_writes_state() {
  local root="${PROJECT_ROOT:-$(pwd)}" n=0 entrada p _origen
  command -v git >/dev/null 2>&1 || return 0
  # `-z`: registros terminados en NUL y rutas CRUDAS, sin el quoting estilo C.
  # Sin él, `git status --porcelain` entrecomilla y escapa cualquier ruta con
  # comillas, tabulador, salto de línea o —con `core.quotepath` en su default—
  # cualquier byte no ASCII: `archivo_ñ.sh` llegaba como `archivo_\303\261.sh`.
  # Pelar las comillas exteriores no basta, porque la ruta resultante NO EXISTE:
  # aguas abajo se saltaba en silencio, y encima reportada como `ok` en vez de
  # como incierta. Es el mismo agujero silencioso que esta librería cierra,
  # reabierto para otro borde. `-z` no lo parchea: lo elimina.
  # `-uall`: sin él, porcelain COLAPSA un directorio sin trackear en una sola
  # entrada (`?? scripts/`). Eso no es un archivo: no se puede hacer `cksum` de
  # un directorio, así que salía clasificado como BORRADO —un archivo fantasma
  # que nunca existió— y los archivos de dentro quedaban invisibles. Con `-uall`
  # se listan uno a uno, que es lo que hay que mirar.
  git -C "$root" status --porcelain -z -uall 2>/dev/null | while IFS= read -r -d '' entrada; do
    # Formato con -z: `XY<espacio>ruta`. En renombrado/copia, el registro
    # SIGUIENTE trae la ruta origen; se consume y se descarta (interesa la nueva).
    case "${entrada:0:1}" in R|C) IFS= read -r -d '' _origen || true ;; esac
    p="${entrada:3}"
    [ -n "$p" ] || continue
    # Una ruta con salto de línea rompería el formato de la foto. Se descarta.
    # El salto va en una variable con un literal: `$(printf '\n')` devuelve
    # CADENA VACÍA —la sustitución de comandos se come los saltos finales— y el
    # patrón `*""*` casa con todo, así que descartaba TODAS las rutas y el
    # detector volvía a devolver vacío para siempre. Tercer primitivo de esta
    # librería que falla haciendo nada en silencio; por eso los tests corren el
    # ciclo completo en vez de comprobar la pieza.
    case "$p" in *"$_WRITES_NL"*) continue ;; esac
    n=$((n + 1))
    if [ ! -f "$root/$p" ]; then
      # Borrado. Sale con una huella propia para que la comparación lo vea: si
      # antes tenía contenido y ahora no existe, las líneas difieren y se
      # reporta. Si ya estaba borrado en la foto anterior, coinciden y no.
      printf 'BORRADO %s\n' "$p"
    elif [ "$n" -le "$WRITES_MAX_FILES" ]; then
      printf '%s %s\n' "$(cksum < "$root/$p" 2>/dev/null | tr -d ' ')" "$p"
    else
      printf 'SIN-HUELLA %s\n' "$p"
    fi
  done
}

# writes_mark — guarda la foto del ANTES. La llama el PreToolUse de Bash,
# justo antes de que el comando corra.
writes_mark() {
  (
    set +e
    local dir="${PROJECT_ROOT:-$(pwd)}/.agents/state"
    mkdir -p "$dir" 2>/dev/null || exit 0

    # Barrido de temporales huérfanos. Si el proceso muere entre el `mktemp` y
    # el `mv` —el `PostToolUse` tiene 30s de timeout— queda un `.tmp.XXXXXX` de
    # 0 bytes. No corrompe nada (`.agents/state/` está gitignored y el memo
    # válido no se toca), pero en una sesión larga se acumula sin límite.
    #
    # `-mmin +10` y no un borrado a secas: un temporal RECIÉN creado puede ser
    # el de un hook en vuelo, y borrárselo lo dejaría devolviendo vacío — o sea
    # fabricar el silencio que esta librería existe para quitar. Diez minutos
    # son veinte veces el timeout del hook: nada vivo cae ahí.
    find "$dir" -maxdepth 1 -name 'bash-writes.snapshot.memo.tmp.*' \
      -mmin +10 -delete 2>/dev/null

    _writes_state > "$(_writes_snapshot_file)" 2>/dev/null
  ) 2>/dev/null
  return 0
}

# writes_since_mark — imprime, una por línea, `<estado><TAB><ruta>` por cada
# archivo cuya huella cambió respecto de la foto (o que no estaba en ella).
# El estado es `ok` (comparado por contenido) o `?` (no se pudo comparar).
#
# DOS COLUMNAS SEPARADAS POR TABULADOR, y no un prefijo `?` pegado a la ruta:
# un archivo puede llamarse literalmente `?roto.sh`, y con el prefijo pegado su
# escritura CONFIRMADA era indistinguible de una incierta — el consumidor le
# quitaba el `?`, buscaba `roto.sh`, no lo encontraba y callaba. O sea el mismo
# agujero silencioso que esta librería existe para cerrar, reintroducido para
# ese borde.
#
# EL TABULADOR SÍ PUEDE APARECER EN LA RUTA, y decirlo importa porque la versión
# anterior de este comentario afirmaba lo contrario: era cierto con el porcelain
# citado, y dejó de serlo al pasar a `-z` —el arreglo del bug de al lado— porque
# `-z` desactiva el escapado. O sea que un arreglo invalidó la premisa del otro,
# en el mismo archivo, sin que nada avisara. Por eso el CONTRATO es:
#   · la primera columna nunca contiene un tabulador (es `ok`, `?`);
#   · quien consuma esto corta por el PRIMER tabulador y se queda con TODO el
#     resto — no con "el campo 2", que trunca una ruta que traiga otro.
#
# NO borra la foto: en PostToolUse cuelgan varios hooks y todos tienen que
# poder leer la misma respuesta. La foto la pisa el siguiente PreToolUse.
#
# MEMOIZADO contra la foto. En PostToolUse cuelgan DOS consumidores
# (`post-edit-verify` y `track-trajectory`) y cada uno llamaba a esto por su
# cuenta: con el `writes_mark` del PreToolUse, eran TRES recorridos completos
# —un `git status` y hasta WRITES_MAX_FILES `cksum` cada uno— por cada llamada
# a Bash. Medido con 45 archivos sucios: ~150ms por recorrido, o sea medio
# segundo y ~138 forks por comando, en el camino más caliente del harness.
# La clave del memo es la huella de la FOTO: mientras nadie llame a
# `writes_mark`, la respuesta es la misma por contrato —los dos consumidores
# deben ver lo mismo— y el siguiente PreToolUse la invalida sola.
writes_since_mark() {
  (
    set +e
    local snap; snap="$(_writes_snapshot_file)"
    [ -f "$snap" ] || exit 0

    local memo="${snap}.memo" clave
    clave="$(cksum < "$snap" 2>/dev/null | tr -d ' ')"
    if [ -n "$clave" ] && [ -f "$memo" ]; then
      # Primera línea = clave; el resto, la respuesta ya calculada.
      if [ "$(head -n 1 "$memo" 2>/dev/null)" = "$clave" ]; then
        tail -n +2 "$memo" 2>/dev/null
        exit 0
      fi
    fi
    # El resultado se compone en un temporal y se mueve al memo de una pieza:
    # un memo a medias serviría una respuesta truncada como si fuera completa,
    # que es justo la clase de fallo que esta librería persigue.
    #
    # Y NO se envuelve el bucle en `$( … )`. Se intentó, y el `)` del patrón
    # `'SIN-HUELLA '*)` cierra la sustitución de comandos para el parser de
    # bash: error de sintaxis, tragado por el `2>/dev/null` de la envoltura, y
    # la función devolvía vacío para todo. CUARTO primitivo de este archivo que
    # falla haciendo nada en silencio.
    # El temporal lleva sufijo ÚNICO. En `PostToolUse` cuelgan DOS hooks que
    # casan `Bash`, cada uno un proceso aparte, y los dos llaman aquí para el
    # mismo turno: con un nombre fijo podrían abrir y truncar el mismo archivo
    # a la vez, y el `2>/dev/null` de la envoltura se tragaría el destrozo —
    # `tail` serviría un memo corrupto sin una sola señal. Es el patrón que ya
    # usan `lib/io.sh` (mktemp para unicidad concurrente) y `lib/json.sh`
    # (flock); no había razón para que este archivo fuera el único sin él.
    local tmp
    tmp="$(mktemp "${memo}.tmp.XXXXXX" 2>/dev/null)" || tmp="${memo}.tmp.$$"
    {
      [ -n "$clave" ] && printf '%s\n' "$clave"
      _writes_state | while IFS= read -r ahora; do
        [ -n "$ahora" ] || continue
        case "$ahora" in
          # Sin huella no hay comparación posible: se reporta, pero MARCADO con
          # `?` para que quien lo consuma sepa que es "no lo sé", no "cambió".
          'SIN-HUELLA '*) printf '?\t%s\n' "${ahora#* }"; continue ;;
        esac
        # Línea idéntica en la foto ⇒ ni se creó, ni cambió, ni se borró.
        grep -Fxq -- "$ahora" "$snap" 2>/dev/null && continue
        printf 'ok\t%s\n' "${ahora#* }"
      done
    } > "$tmp" 2>/dev/null

    if [ -n "$clave" ]; then
      mv -f "$tmp" "$memo" 2>/dev/null && { tail -n +2 "$memo" 2>/dev/null; exit 0; }
    fi
    tail -n +2 "$tmp" 2>/dev/null
    rm -f "$tmp" 2>/dev/null
    exit 0
  ) 2>/dev/null
  return 0
}

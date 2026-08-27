#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# El nivel 1 tiene que ver también lo que se escribe POR BASH
# ════════════════════════════════════════════════════════════════════
# El agujero, medido: en una sesión de 609 tool-calls, 589 fueron Bash y CERO
# Edit/Write, para 533 líneas de shell nuevo. `post-edit-verify` —el gate de
# mayor ROI del harness— colgaba solo de `Edit|Write`, así que no corrió ni una
# vez (f-ee9787d9); y `track-trajectory` registraba `python3`/`sed`/`cat` como
# "path", nunca el archivo, dejando al `process-judge` sin poder responder su
# pregunta nº1 (f-153aef5b). Los dos síntomas, una sola causa: el harness no
# sabía qué archivo había escrito un comando.
#
# La decisión de diseño que estos tests fijan: NO se parsea el comando, se
# OBSERVA el efecto. Reconocer escrituras con regex (`>`, `sed -i`, `tee`,
# `python3 - <<PY`) es la misma carrera perdida que reconocer formas de bash
# con regex — la lista la decide el shell. Por eso las fixtures de abajo son
# formas DISTINTAS de escribir: si alguien vuelve a un reconocedor sintáctico,
# unas cuantas se ponen rojas.

_bw_repo() { # repo desechable con la lib y un .gitignore realista
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/.agents/state"
  cp "$PROJECT_ROOT/scripts/agent-hooks/lib/writes.sh" "$d/scripts/agent-hooks/lib/"
  printf '.agents/state/\n' > "$d/.gitignore"
  printf 'seed\n' > "$d/seed.txt"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null
    git config user.email t@t.t
    git config user.name t
    git add -A 2>/dev/null
    git commit -qm init 2>/dev/null
    PROJECT_ROOT="$d"
    export PROJECT_ROOT
    # shellcheck disable=SC1091
    . scripts/agent-hooks/lib/writes.sh
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

# La salida es `<estado><TAB><ruta>`. Estos helpers separan las dos preguntas
# que se le hacen: "¿qué rutas salieron?" y "¿con qué estado?".
_rutas() { writes_since_mark | awk -F'\t' '{print $2}' | tr '\n' ' ' | sed 's/ $//'; }
_rutas_ok() { writes_since_mark | awk -F'\t' '$1=="ok"{print $2}' | tr '\n' ' ' | sed 's/ $//'; }

_esperado() { # _esperado <esperado> <obtenido> <caso>
  [ "$2" = "$1" ] && return 0
  echo "    caso «$3»: esperaba [$1] y salió [$2]"
  return 1
}

# ── Las formas de escribir, que es donde vive el bug ────────────────
_case_ve_toda_forma_de_escritura() {
  local rc=0 got

  writes_mark; printf 'x\n' > nuevo.sh
  got="$(_rutas)"
  _esperado "nuevo.sh" "$got" "archivo nuevo por redirección" || rc=1

  # LA CLAVE: un segundo write sobre un archivo YA modificado. Es lo que un
  # `git status` solo no puede ver —la línea de porcelain es idéntica— y es el
  # caso más común que hay: editar dos veces el mismo archivo.
  writes_mark; printf 'y\n' >> nuevo.sh
  got="$(_rutas)"
  _esperado "nuevo.sh" "$got" "SEGUNDA escritura sobre uno ya modificado" || rc=1

  writes_mark; sed -i.bak 's/seed/SEED/' seed.txt 2>/dev/null; rm -f seed.txt.bak
  got="$(_rutas)"
  case "$got" in *seed.txt*) : ;; *) echo "    caso «sed -i»: no vio seed.txt (salió [$got])"; rc=1 ;; esac

  writes_mark; python3 -c "open('porpython.txt','w').write('z')" 2>/dev/null
  got="$(_rutas)"
  case "$got" in *porpython.txt*) : ;; *) echo "    caso «python3 -c»: no lo vio (salió [$got])"; rc=1 ;; esac

  writes_mark; cat > porheredoc.sh <<'FIXTURE'
contenido
FIXTURE
  got="$(_rutas)"
  case "$got" in *porheredoc.sh*) : ;; *) echo "    caso «heredoc»: no lo vio (salió [$got])"; rc=1 ;; esac

  return $rc
}
test_se_ve_toda_forma_de_escritura_sin_parsear_el_comando() {
  _bw_repo _case_ve_toda_forma_de_escritura; }

# ── Falsos positivos: la mitad que hace usable al detector ──────────
# Si un comando de solo lectura "escribiera" archivos, el nivel 1 lintaría en
# cada `ls` y el ruido lo desactivaría entero (ley del 10%, §14.2).
_case_no_inventa_escrituras() {
  local rc=0 got

  writes_mark; ls >/dev/null 2>&1; git status >/dev/null 2>&1
  got="$(_rutas)"
  _esperado "" "$got" "comando de solo lectura" || rc=1

  # El harness escribe en .agents/state/ en CADA hook. Si eso contara, todo
  # comando "habría escrito" media docena de archivos — ruido garantizado.
  writes_mark; printf 'ruido\n' > .agents/state/ruido.txt
  got="$(_rutas)"
  _esperado "" "$got" "escritura a una ruta ignorada por .gitignore" || rc=1

  # Un archivo modificado ANTES de la marca no es de este comando.
  printf 'viejo\n' > previo.txt
  writes_mark; ls >/dev/null 2>&1
  got="$(_rutas)"
  _esperado "" "$got" "archivo escrito ANTES de la marca" || rc=1

  return $rc
}
test_no_se_inventan_escrituras_donde_no_las_hubo() {
  _bw_repo _case_no_inventa_escrituras; }

# ── El tiempo, que es donde estuvieron los dos bugs de verdad ───────
# La detección se basó primero en marcas de tiempo y produjo DOS bugs distintos
# antes de funcionar: (1) la marca se calculaba en UTC para un `touch -t` que
# interpreta hora local, y quedaba seis horas en el futuro — el detector
# devolvía vacío para TODO, indistinguible de "no hubo escrituras"; (2) ya con
# el huso bien, `[ a -nt b ]` en el bash de macOS compara segundos enteros
# aunque el FS guarde nanosegundos, así que una escritura del mismo segundo era
# invisible. Por eso la versión final compara CONTENIDO: sin huso, sin shell y
# sin granularidad de por medio.
#
# Este test corre el ciclo 20 veces seguidas, todas dentro del mismo segundo.
# Es el que habría cazado los dos bugs, y el que caza cualquier regreso a un
# enfoque temporal.
_case_no_depende_de_un_margen_temporal() {
  local i fallos=0 got
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    writes_mark
    printf 'v%s\n' "$i" > ciclo.txt
    got="$(_rutas)"
    case "$got" in *ciclo.txt*) : ;; *) fallos=$((fallos + 1)) ;; esac
  done
  [ "$fallos" = "0" ] || {
    echo "    $fallos de 20 escrituras no se detectaron en el mismo segundo."
    echo "    O el reloj de la marca está desplazado (¿UTC contra hora local?),"
    echo "    o este sistema de archivos no guarda mtime con sub-segundo."
    return 1; }
}
test_la_deteccion_no_depende_de_un_margen_temporal() {
  _bw_repo _case_no_depende_de_un_margen_temporal; }

# ── El modo degradado SOBRE-reporta, nunca sub-reporta ──────────────
# Por encima de WRITES_MAX_FILES deja de calcular huellas. La primera versión
# emitía entonces una línea constante por archivo… y la comparaba consigo
# misma, así que todo lo que pasara del tope salía como "no cambió". Silencio
# indistinguible de "no hubo escrituras" — el mismo modo de fallo que esta
# librería existe para eliminar, reintroducido por la puerta de atrás y
# precisamente en las sesiones grandes que la motivaron. Lo cazó un reviewer.
#
# La dirección correcta no es simétrica: mirar un archivo de más cuesta un
# `shellcheck`; mirar uno de menos cuesta que el nivel 1 vuelva a estar mudo.
_case_el_modo_degradado_no_esconde_cambios() {
  local i got
  for i in $(seq 1 12); do printf 'v0\n' > "sucio$i.txt"; done
  WRITES_MAX_FILES=3
  export WRITES_MAX_FILES
  writes_mark
  # Se toca uno que con seguridad cae en el bucket degradado.
  printf 'CAMBIADO\n' > sucio12.txt
  got="$(_rutas)"
  case "$got" in
    *sucio12.txt*) : ;;
    *) echo "    con el tope superado, un cambio real NO se reportó (salió [$got])."
       echo "    Sub-reportar aquí es el silencio que esta librería viene a quitar."
       return 1 ;;
  esac
}
test_por_encima_del_tope_se_sobre_reporta_en_vez_de_callar() {
  _bw_repo _case_el_modo_degradado_no_esconde_cambios; }

# …pero sobre-reportar NO puede convertirse en evidencia. Los dos consumidores
# quieren cosas distintas de la misma señal: `post-edit-verify` pregunta "¿qué
# lintar?" y mirar de más es barato; `track-trajectory` pregunta "¿qué tocó ESTE
# comando?" y ahí un archivo de más es una afirmación falsa — y permanente,
# porque una vez cruzado el tope hasta un `ls` arrastraría los mismos.
# Por eso lo incierto sale marcado con `?` y cada consumidor decide.
_case_lo_incierto_va_marcado() {
  local i got
  for i in $(seq 1 12); do printf 'v0\n' > "sucio$i.txt"; done
  WRITES_MAX_FILES=3
  export WRITES_MAX_FILES
  writes_mark
  ls >/dev/null 2>&1          # comando de SOLO LECTURA, por encima del tope
  got="$(writes_since_mark)"
  [ -n "$got" ] || { echo "    esperaba rutas inciertas y no salió ninguna"; return 1; }
  printf '%s\n' "$got" | grep -qv '^?	' && {
    echo "    un comando de solo lectura reportó una escritura SIN marcar como"
    echo "    incierta. Eso entra en la trayectoria como evidencia de que este"
    echo "    comando tocó algo que no tocó:"
    printf '%s\n' "$got" | grep -v '^?	' | sed 's/^/      /'
    return 1; }
  # `return 0` explícito: sin él, el estado de la función es el del `grep`
  # anterior —que devuelve 1 justo cuando todo está BIEN— y el test fallaba
  # por su propio código en vez de por lo que mide.
  return 0
}
# El estado va en su propia columna, separado por TABULADOR, y no pegado a la
# ruta. Con un prefijo pegado, un archivo llamado literalmente `?roto.sh` era
# indistinguible de una ruta incierta: el consumidor le quitaba el `?`, buscaba
# `roto.sh`, no existía, y callaba. O sea el agujero silencioso que esta
# librería existe para cerrar, reintroducido para ese borde — y con él, un `.sh`
# con sintaxis rota pasaba sin lintar. Lo cazó un reviewer.
#
# El tabulador no puede colisionar: `git status --porcelain` cita entre comillas
# cualquier ruta que contenga uno, así que una ruta cruda nunca lo trae.
_case_una_ruta_que_empieza_por_interrogante_no_se_confunde() {
  local got estado
  writes_mark
  printf '#!/usr/bin/env bash\nif [ 1 ; then\n' > '?roto.sh'
  got="$(writes_since_mark)"
  printf '%s\n' "$got" | grep -q '?roto\.sh' || {
    echo "    no se vio '?roto.sh' en absoluto (salió [$got])"; return 1; }
  estado="$(printf '%s\n' "$got" | awk -F'\t' '$2=="?roto.sh"{print $1}')"
  [ "$estado" = "ok" ] || {
    echo "    '?roto.sh' se comparó por contenido, así que su estado debía ser"
    echo "    «ok» y salió «${estado}». Con el estado pegado a la ruta, una"
    echo "    escritura CONFIRMADA se leía como incierta y se perdía."
    return 1; }
  [ "$(_rutas_ok)" = "?roto.sh" ] || {
    echo "    la ruta no sobrevive intacta al filtro por estado: [$(_rutas_ok)]"
    return 1; }
}
test_una_ruta_que_empieza_por_interrogante_no_se_confunde_con_la_marca() {
  _bw_repo _case_una_ruta_que_empieza_por_interrogante_no_se_confunde; }

# ── Rutas que git tiene que citar, o que llevan un espacio ──────────
# `git status --porcelain` (sin `-z`) entrecomilla y escapa cualquier ruta con
# comillas, tabulador, salto de línea o —con `core.quotepath` en su default—
# cualquier byte no ASCII: `archivo_ñ.sh` salía como `archivo_\303\261.sh`.
# Pelar las comillas no basta, porque esa ruta NO EXISTE: aguas abajo se saltaba
# en silencio y encima reportada como `ok`. Se arregló con `-z`, que da rutas
# crudas. Este test fija que no vuelva.
_case_rutas_raras_salen_intactas() {
  local rc=0 got
  writes_mark
  printf 'x\n' > 'archivo_ñ.sh'
  printf 'y\n' > 'con espacios.txt'
  got="$(_rutas_ok)"
  case "$got" in
    *'archivo_ñ.sh'*) : ;;
    *) echo "    la ruta no-ASCII no salió intacta: [$got]"; rc=1 ;;
  esac
  case "$got" in
    *'con espacios.txt'*) : ;;
    *) echo "    la ruta con espacio no salió intacta: [$got]"; rc=1 ;;
  esac
  [ -f "$(writes_since_mark | awk -F'\t' '$2 ~ /ñ/ {print $2}')" ] || {
    echo "    la ruta no-ASCII que se reporta NO EXISTE en disco: quien la"
    echo "    consuma la saltará en silencio y encima la creerá confirmada."
    rc=1; }
  return $rc
}
test_las_rutas_que_git_citaria_salen_crudas_e_intactas() {
  _bw_repo _case_rutas_raras_salen_intactas; }

# Y el borde que abrió el propio arreglo anterior: `-z` da rutas CRUDAS, así que
# una ruta SÍ puede traer un tabulador. El comentario del código afirmaba lo
# contrario —era cierto con el porcelain citado y dejó de serlo con `-z`, en el
# mismo archivo y sin que nada avisara—. Quedarse con "el campo 2" trunca la
# ruta y registra como escritura confirmada una que no existe.
_case_una_ruta_con_tabulador_no_se_trunca() {
  local ruta got
  ruta="con$(printf '\t')tab.txt"
  writes_mark
  printf 'x\n' > "$ruta"
  got="$(writes_since_mark | awk -F'\t' '$1=="ok"{sub(/^[^\t]*\t/, ""); print}')"
  [ "$got" = "$ruta" ] || {
    echo "    la ruta con tabulador salió truncada."
    echo "      esperaba: [$(printf '%s' "$ruta" | tr '\t' '@')]"
    echo "      salió:    [$(printf '%s' "$got" | tr '\t' '@')]"
    return 1; }
}
test_una_ruta_con_tabulador_no_se_trunca() {
  _bw_repo _case_una_ruta_con_tabulador_no_se_trunca; }

# El de arriba fija el CONTRATO de la librería… reimplementando el corte dentro
# del propio test, así que no dice nada de si los consumidores lo cumplen: con
# él en verde, revertir cualquiera de los dos a un corte por campo pasaba 17/17.
# Un reviewer lo demostró. Estos dos pasan por los hooks REALES, que es donde
# vivió el bug — y donde volvería a vivir, porque la causa original fue
# exactamente ésta: un arreglo invalidó la premisa del otro y nada avisó.
_case_el_hook_real_linta_una_ruta_con_tabulador() {
  local d="$1" out ruta
  ruta="rota$(printf '\t')nombre.sh"
  printf '{"tool_name":"Bash","tool_input":{"command":"true"}}' \
    | bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  printf '#!/usr/bin/env bash\nif [ 1 ; then\n' > "$ruta"
  out="$(printf '{"tool_name":"Bash","tool_input":{"command":"cat"}}' \
    | bash scripts/agent-hooks/post-edit-verify.sh 2>&1)"
  printf '%s' "$out" | grep -q 'nombre.sh' || {
    echo "    el hook no revisó un .sh con sintaxis rota cuyo nombre trae un"
    echo "    tabulador: la ruta se truncó y el archivo dejó de existir para él."
    echo "    salida: $(printf '%s' "$out" | head -3)"
    return 1; }
}
test_el_hook_real_linta_una_ruta_con_tabulador_en_el_nombre() {
  _pev_repo _case_el_hook_real_linta_una_ruta_con_tabulador; }

_case_la_trayectoria_no_trunca_una_ruta_con_tabulador() {
  local d="$1" linea ruta
  ruta="traza$(printf '\t')nombre.txt"
  printf '{"tool_name":"Bash","tool_input":{"command":"true"}}' \
    | bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  printf 'x\n' > "$ruta"
  printf '{"tool_name":"Bash","session_id":"s-tab","tool_input":{"command":"cat"}}' \
    | bash scripts/agent-hooks/track-trajectory.sh >/dev/null 2>&1
  linea="$(cat .agents/state/trajectory/s-tab.jsonl 2>/dev/null)"
  printf '%s' "$linea" | grep -q 'nombre.txt' || {
    echo "    la trayectoria registró la ruta TRUNCADA en el tabulador: una"
    echo "    escritura «confirmada» de un archivo que no existe."
    echo "    Línea: ${linea:-<vacía>}"
    return 1; }
}
test_la_trayectoria_no_trunca_una_ruta_con_tabulador() {
  _pev_repo _case_la_trayectoria_no_trunca_una_ruta_con_tabulador; }

# Un directorio sin trackear no es un archivo. Porcelain lo COLAPSA en una sola
# entrada (`?? scripts/`) si no se le pide `-uall`, y entonces salía clasificado
# como BORRADO —un archivo fantasma que nunca existió— mientras los archivos de
# dentro quedaban invisibles.
_case_un_directorio_sin_trackear_no_es_un_archivo_fantasma() {
  local got
  mkdir -p sindir
  printf 'x\n' > sindir/dentro.sh
  writes_mark
  printf 'y\n' > sindir/otro.sh
  got="$(_rutas)"
  case "$got" in
    *'sindir/'*'/'*|*'sindir/ '*) : ;;
  esac
  printf '%s\n' "$got" | grep -qE '(^| )sindir/( |$)' && {
    echo "    el directorio salió como si fuera un archivo: [$got]"; return 1; }
  case "$got" in
    *sindir/otro.sh*) : ;;
    *) echo "    no se vio el archivo NUEVO dentro del directorio: [$got]"; return 1 ;;
  esac
  return 0
}
test_un_directorio_sin_trackear_no_se_reporta_como_archivo() {
  _bw_repo _case_un_directorio_sin_trackear_no_es_un_archivo_fantasma; }

# ── El memo: una sola respuesta por foto ────────────────────────────
# En PostToolUse cuelgan dos consumidores y cada uno llamaba por su cuenta: con
# el del PreToolUse, tres recorridos completos por cada comando de Bash. El memo
# los reduce a uno, y de paso hace cumplir un invariante que ya estaba escrito:
# todos los hooks de un mismo turno leen LA MISMA respuesta.
_case_el_memo_da_la_misma_respuesta_hasta_la_proxima_marca() {
  local uno dos tres
  writes_mark
  printf 'x\n' > memo1.txt
  uno="$(_rutas)"
  # Cambia el árbol SIN nueva marca: la respuesta debe ser la misma, porque los
  # dos consumidores del mismo turno tienen que ver lo mismo.
  printf 'y\n' > memo2.txt
  dos="$(_rutas)"
  [ "$uno" = "$dos" ] || {
    echo "    dos consumidores del mismo turno vieron cosas distintas:"
    echo "      [$uno] vs [$dos]"; return 1; }
  # Y una marca nueva SÍ invalida el memo.
  writes_mark
  printf 'z\n' > memo3.txt
  tres="$(_rutas)"
  case "$tres" in
    *memo3.txt*) : ;;
    *) echo "    tras una marca nueva el memo siguió sirviendo lo viejo: [$tres]"; return 1 ;;
  esac
  return 0
}
test_el_memo_sirve_una_respuesta_por_foto_y_la_marca_lo_invalida() {
  _bw_repo _case_el_memo_da_la_misma_respuesta_hasta_la_proxima_marca; }

# Un proceso muerto entre el `mktemp` y el `mv` deja un temporal de 0 bytes.
# No corrompe nada, pero se acumula. Se barre en la marca — y solo lo VIEJO:
# borrar un temporal recién creado sería quitárselo a un hook en vuelo y
# dejarlo devolviendo vacío, o sea fabricar el silencio que esta librería
# existe para quitar.
_case_los_temporales_huerfanos_se_barren_sin_tocar_los_vivos() {
  local dir=".agents/state" viejo nuevo
  viejo="$dir/bash-writes.snapshot.memo.tmp.VIEJOxx"
  nuevo="$dir/bash-writes.snapshot.memo.tmp.NUEVOxx"
  : > "$viejo"; : > "$nuevo"
  # Fecha de hace años: inequívoca sin importar el huso horario, que ya nos
  # costó un bug en esta misma librería.
  touch -t 202001010000 "$viejo" 2>/dev/null
  writes_mark
  [ -f "$viejo" ] && { echo "    el temporal huérfano viejo NO se barrió"; return 1; }
  [ -f "$nuevo" ] || {
    echo "    se barrió un temporal RECIÉN creado: si era de un hook en vuelo,"
    echo "    ese hook acaba de quedarse sin respuesta y sin saberlo."
    return 1; }
  return 0
}
test_los_temporales_huerfanos_se_barren_sin_tocar_los_vivos() {
  _bw_repo _case_los_temporales_huerfanos_se_barren_sin_tocar_los_vivos; }

# Y el consumidor que las serializa: la trayectoria es EVIDENCIA, así que una
# ruta partida en dos es peor que ninguna. Unir por espacio y partir por espacio
# usaba el mismo carácter como separador y como contenido: `con espacios.txt`
# se convertía en `con` y `espacios.txt`, dos archivos que nunca existieron.
_case_la_trayectoria_no_parte_rutas_con_espacio() {
  local d="$1" linea
  printf '{"tool_name":"Bash","tool_input":{"command":"true"}}' \
    | bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  printf 'x\n' > 'con espacios.txt'
  printf '{"tool_name":"Bash","session_id":"s-esp","tool_input":{"command":"cat"}}' \
    | bash scripts/agent-hooks/track-trajectory.sh >/dev/null 2>&1
  linea="$(cat .agents/state/trajectory/s-esp.jsonl 2>/dev/null)"
  printf '%s' "$linea" | grep -q '"con espacios.txt"' || {
    echo "    la ruta con espacio no llegó entera a la trayectoria."
    echo "    Línea: ${linea:-<vacía>}"; return 1; }
  printf '%s' "$linea" | grep -qE '"(con|espacios\.txt)"' && {
    echo "    la ruta se partió en rutas fantasma que nunca existieron."
    echo "    Línea: $linea"; return 1; }
  return 0
}
test_la_trayectoria_no_parte_una_ruta_con_espacio_en_dos() {
  _pev_repo _case_la_trayectoria_no_parte_rutas_con_espacio; }

test_lo_que_no_se_pudo_comparar_sale_marcado_como_incierto() {
  _bw_repo _case_lo_incierto_va_marcado; }

_case_la_trayectoria_no_afirma_lo_incierto() {
  local d="$1" linea i
  for i in $(seq 1 12); do printf 'v0\n' > "sucio$i.txt"; done
  printf '{"tool_name":"Bash","tool_input":{"command":"true"}}' \
    | WRITES_MAX_FILES=3 bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  printf '{"tool_name":"Bash","session_id":"s-inc","tool_input":{"command":"ls"}}' \
    | WRITES_MAX_FILES=3 bash scripts/agent-hooks/track-trajectory.sh >/dev/null 2>&1
  linea="$(cat .agents/state/trajectory/s-inc.jsonl 2>/dev/null)"
  printf '%s' "$linea" | grep -q '"writes":' && {
    echo "    la trayectoria AFIRMÓ escrituras que no se pudieron comparar."
    echo "    Línea: $linea"; return 1; }
  printf '%s' "$linea" | grep -q '"writes_inciertos":' || {
    echo "    tampoco dejó constancia de que la lista estaba incompleta:"
    echo "    sin ese contador, el juez lee 'no escribió nada' — que es la"
    echo "    otra mitad del mismo error. Línea: ${linea:-<vacía>}"
    return 1; }
}
test_la_trayectoria_no_afirma_escrituras_que_no_pudo_comparar() {
  _pev_repo _case_la_trayectoria_no_afirma_lo_incierto; }

# ── Un borrado es una escritura, y el docstring lo prometía ─────────
# La primera versión declaraba "ve borrados" y los descartaba con un `-f`, así
# que un `rm` era invisible — también para la trayectoria, cuyo objetivo es
# justamente que el `process-judge` sepa qué tocó el comando.
_case_un_borrado_se_reporta() {
  local got
  printf 'contenido\n' > paraborrar.txt
  git add paraborrar.txt >/dev/null 2>&1
  writes_mark
  rm -f paraborrar.txt
  got="$(_rutas)"
  case "$got" in
    *paraborrar.txt*) : ;;
    *) echo "    un rm no se reportó (salió [$got]) — el docstring lo promete"; return 1 ;;
  esac
}
test_un_borrado_cuenta_como_escritura() {
  _bw_repo _case_un_borrado_se_reporta; }

# Y la recíproca, para que el arreglo del borrado no se convierta en ruido: un
# archivo que YA estaba borrado antes del comando no lo borró este comando.
_case_un_borrado_previo_no_se_reatribuye() {
  local got
  printf 'contenido\n' > yaborrado.txt
  git add yaborrado.txt >/dev/null 2>&1
  rm -f yaborrado.txt
  writes_mark
  ls >/dev/null 2>&1
  got="$(_rutas)"
  _esperado "" "$got" "borrado ANTERIOR a la marca"
}
test_un_borrado_previo_no_se_atribuye_a_este_comando() {
  _bw_repo _case_un_borrado_previo_no_se_reatribuye; }

# ── Sin foto no hay respuesta, y eso NO puede romper al que llama ───
_case_sin_marca_devuelve_vacio_y_sale_0() {
  # Se escribe algo ANTES de borrar la foto: si el borrado no surtiera efecto,
  # `writes_since_mark` tendría algo que reportar y el test se pondría rojo. Sin
  # esta escritura previa el test pasaría también con la ruta equivocada — y de
  # hecho pasó, apuntando a un nombre de archivo que ya no existía.
  printf 'algo\n' > huerfano.txt
  rm -f .agents/state/bash-writes.snapshot
  local got rc
  got="$(writes_since_mark)"; rc=$?
  [ "$rc" = "0" ] || { echo "    sin marca salió $rc; la telemetría del hook no puede fallar"; return 1; }
  [ -z "$got" ] || { echo "    sin marca inventó escrituras: [$got]"; return 1; }
}
test_sin_marca_devuelve_vacio_sin_romper_al_llamador() {
  _bw_repo _case_sin_marca_devuelve_vacio_y_sale_0; }

# ── Y el cableado: que el hook REAL mire lo escrito por Bash ────────
# Los tests de arriba prueban la librería aislada. Éste prueba la distancia
# entre la librería y el hook, que es donde ya vivió un bug esta misma sesión.
_pev_repo() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/.agents/state"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  printf '.agents/state/\n' > "$d/.gitignore"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null
    git config user.email t@t.t
    git config user.name t
    git add -A 2>/dev/null
    git commit -qm init 2>/dev/null
    "$1" "$d"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_el_hook_real_linta_lo_escrito_por_bash() {
  local d="$1" out
  # PreToolUse Bash deja la marca…
  printf '{"tool_name":"Bash","tool_input":{"command":"true"}}' \
    | bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  [ -f .agents/state/bash-writes.snapshot ] || {
    echo "    el PreToolUse de Bash no dejó la foto del antes: sin ella el nivel 1 no ve nada"; return 1; }
  # …se escribe un .sh con un error de sintaxis REAL, por una vía que ningún
  # parser de comandos reconocería como escritura…
  python3 -c "open('roto.sh','w').write('#!/usr/bin/env bash\nif [ 1 ; then\n')" 2>/dev/null
  # …y el PostToolUse tiene que encontrarlo.
  out="$(printf '{"tool_name":"Bash","tool_input":{"command":"python3 -c ..."}}' \
    | bash scripts/agent-hooks/post-edit-verify.sh 2>&1)"
  printf '%s' "$out" | grep -q 'roto.sh' || {
    echo "    el hook no revisó roto.sh tras escribirlo por Bash. Es f-ee9787d9:"
    echo "    el nivel 1 sigue mudo para todo lo que no pase por Edit/Write."
    echo "    salida: $(printf '%s' "$out" | head -3)"
    return 1; }
}
test_el_hook_real_revisa_lo_que_escribio_un_comando_de_bash() {
  _pev_repo _case_el_hook_real_linta_lo_escrito_por_bash; }

_case_la_trayectoria_registra_el_archivo_no_el_binario() {
  local d="$1" linea
  printf '{"tool_name":"Bash","tool_input":{"command":"true"}}' \
    | bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  python3 -c "open('escrito.txt','w').write('x')" 2>/dev/null
  printf '{"tool_name":"Bash","session_id":"s-traj","tool_input":{"command":"python3 -c ..."}}' \
    | bash scripts/agent-hooks/track-trajectory.sh >/dev/null 2>&1
  linea="$(cat .agents/state/trajectory/s-traj.jsonl 2>/dev/null)"
  printf '%s' "$linea" | grep -q 'escrito.txt' || {
    echo "    la trayectoria no registró el archivo escrito, solo el binario."
    echo "    Con esto el process-judge no puede responder su pregunta nº1"
    echo "    (f-153aef5b). Línea: ${linea:-<vacía>}"
    return 1; }
}
test_la_trayectoria_de_un_bash_registra_el_archivo_escrito() {
  _pev_repo _case_la_trayectoria_registra_el_archivo_no_el_binario; }

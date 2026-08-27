#!/usr/bin/env bash
# El instalador de gitleaks en CI. Vivia copiado en los cinco ejemplos de CI y
# los cinco compartian el mismo bug: pedian un asset que no existe
# (`gitleaks_linux_x64.tar.gz`; el nombre real lleva la version dentro). GitHub
# devolvia un 404 en HTML y el fallo asomaba tres pasos despues como
# `gzip: stdin: not in gzip format`. Un adoptante montaba su Anillo 3, lo veia
# rojo y no tenia forma de saber que el problema era la URL del ejemplo.
#
# Lo que estos tests fijan es lo que hizo caro el bug, no la descarga en si:
# que la logica viva en UN sitio, y que un fallo de instalacion nunca se
# confunda con un scanner que miro y no encontro nada (AGENTS.md §14.3).

# ── El detector de la duplicacion: ningun ejemplo baja gitleaks por su cuenta ──
# Es el test que habria hecho barato el arreglo: seis copias eran seis sitios
# donde corregir la misma linea, y bastaba que una se olvidara.
test_ningun_ejemplo_de_ci_descarga_gitleaks_a_mano() {
  local culpables=""
  while IFS= read -r f; do
    grep -qE 'curl.*gitleaks/gitleaks/releases' "$f" 2>/dev/null && culpables="$culpables $f"
  done < <(find "$PROJECT_ROOT/ci/examples" -type f 2>/dev/null)
  [ -z "$culpables" ] || {
    echo "    estos ejemplos de CI descargan gitleaks por su cuenta en vez de"
    echo "    usar ci/install-gitleaks.sh —la duplicacion que causo el bug—:"
    printf '      %s\n' $culpables
    return 1
  }
}

# ── El contrato de exit codes: una descarga fallida es 3, nunca 0 ──────────
# El 3 dice "el detector no pudo mirar" y en CI BLOQUEA. Si esto devolviera 0,
# un runner sin gitleaks daria verde sin escanear una sola linea: exactamente
# el fail-open silencioso que §14.4 existe para impedir.
test_una_descarga_fallida_devuelve_3_y_no_instala_nada() {
  local d rc; d="$(mktemp -d)"
  # Version inexistente → 404. `command -v` se esquiva sacando gitleaks del PATH,
  # o el script saldria 0 por la via corta de "ya presente".
  env PATH="/usr/bin:/bin:/usr/sbin:/sbin" GITLEAKS_VERSION="0.0.0-no-existe" \
    bash "$PROJECT_ROOT/ci/install-gitleaks.sh" "$d" >/dev/null 2>&1
  rc=$?
  local instalado="no"; [ -e "$d/gitleaks" ] && instalado="si"
  rm -rf "$d"
  [ "$rc" = "3" ] || { echo "    exit=$rc; el contrato §14.3 exige 3 (no pudo mirar), nunca 0"; return 1; }
  [ "$instalado" = "no" ] || { echo "    dejo un archivo en el destino pese a fallar la descarga"; return 1; }
}

# ── El checksum no es decorativo: si no casa, no se instala ────────────────
# Sin red este test no puede correr de verdad; se salta en vez de pasar en
# falso, que seria justo la clase de test que este repo llama decorativo (§5).
test_un_checksum_que_no_casa_aborta_la_instalacion() {
  curl -sSL --fail -o /dev/null --max-time 20 \
    "https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_checksums.txt" \
    >/dev/null 2>&1 || {
      # Se DICE que se salto. Un `return 0` mudo es indistinguible de un test
      # que corrio y paso: la suite reportaria 660/660 sin haber ejercitado
      # nunca la rama del checksum, y nadie podria notarlo leyendo el log.
      echo "    ⏭  SALTADO: sin red hacia GitHub; la rama del checksum NO se ejercito" >&2
      return 0
    }

  local d rc; d="$(mktemp -d)"
  # Se corrompen TODOS los pines a la vez: asi el test no depende de en que
  # plataforma corra (en macOS muerde darwin_arm64, en CI linux_x64).
  sed -E 's/^(SHA256_[a-z0-9_]+)=".*"/\1="0000000000000000000000000000000000000000000000000000000000000000"/' \
    "$PROJECT_ROOT/ci/install-gitleaks.sh" > "$d/mutante.sh"
  grep -q '="0000' "$d/mutante.sh" || { rm -rf "$d"; echo "    el mutante no se aplico: el test no probaria nada"; return 1; }

  env PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash "$d/mutante.sh" "$d" >/dev/null 2>&1
  rc=$?
  local instalado="no"; [ -e "$d/gitleaks" ] && instalado="si"
  rm -rf "$d"
  [ "$rc" = "3" ] || { echo "    con el checksum corrompido salio $rc, no 3"; return 1; }
  [ "$instalado" = "no" ] || { echo "    INSTALO un binario cuyo checksum no casaba"; return 1; }
}

# ── La via corta: reutilizar un gitleaks ya presente SOLO si es el fijado ──
# Fijar la version pierde su sentido si el script acepta en silencio la que
# traiga la imagen base del runner: otra version son otras reglas, y el gate
# mediria algo distinto de lo que mide en la maquina de al lado. Estos dos
# tests no tocan la red: un stub en el PATH hace de gitleaks.
_ig_stub() {  # _ig_stub <dir> <lo que imprime `gitleaks version`>
  printf '#!/bin/sh\necho "%s"\n' "$2" > "$1/gitleaks"
  chmod +x "$1/gitleaks"
}

test_reutiliza_el_gitleaks_presente_si_es_la_version_fijada() {
  local d bin rc; d="$(mktemp -d)"; bin="$d/bin"; mkdir -p "$bin"
  local fijada; fijada="$(grep -E '^VERSION_DE_LOS_PINES=' "$PROJECT_ROOT/ci/install-gitleaks.sh" | cut -d'"' -f2)"
  [ -n "$fijada" ] || { rm -rf "$d"; echo "    no pude leer VERSION_DE_LOS_PINES"; return 1; }
  _ig_stub "$bin" "$fijada"

  # Destino DISTINTO del stub: si tomo el atajo no debe escribir nada aqui.
  mkdir -p "$d/destino"
  env PATH="$bin:/usr/bin:/bin" bash "$PROJECT_ROOT/ci/install-gitleaks.sh" "$d/destino" >/dev/null 2>&1
  rc=$?
  local escribio="no"; [ -e "$d/destino/gitleaks" ] && escribio="si"
  rm -rf "$d"
  [ "$rc" = "0" ] || { echo "    con la version fijada ya presente salio $rc, no 0"; return 1; }
  [ "$escribio" = "no" ] || { echo "    descargo pese a tener ya la version fijada en el PATH"; return 1; }
}

# El caso que de verdad importa: si lo presente NO es lo fijado, no se acepta.
# Se comprueba con una version inexistente para que muera en la descarga sin
# red util: lo que se fija aqui es que NO tomo el atajo, no que instale.
test_no_reutiliza_un_gitleaks_de_otra_version() {
  local d bin rc; d="$(mktemp -d)"; bin="$d/bin"; mkdir -p "$bin" "$d/destino"
  _ig_stub "$bin" "0.0.1-otra"
  env PATH="$bin:/usr/bin:/bin" GITLEAKS_VERSION="0.0.0-no-existe" \
    bash "$PROJECT_ROOT/ci/install-gitleaks.sh" "$d/destino" >/dev/null 2>&1
  rc=$?
  rm -rf "$d"
  # 0 significaria que acepto el binario ajeno sin verificar nada.
  [ "$rc" = "3" ] || { echo "    con otra version en el PATH salio $rc; un 0 seria aceptarla a ciegas"; return 1; }
}

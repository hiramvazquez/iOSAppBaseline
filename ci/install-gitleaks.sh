#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# Instala gitleaks en un runner de CI — UNA sola vez, para todos los CI
# ════════════════════════════════════════════════════════════════════
# Vivia copiado en los cinco ejemplos de CI, y los cinco tenian el mismo
# bug: pedian `releases/latest/download/gitleaks_linux_x64.tar.gz`, un
# asset que NO existe —el nombre real lleva la version dentro
# (`gitleaks_8.30.1_linux_x64.tar.gz`)—. GitHub respondia un 404 en HTML,
# `curl -sSL` sin `--fail` lo entregaba con exit 0, y el error asomaba
# tres pasos despues como `gzip: stdin: not in gzip format`: un mensaje
# que no menciona ni la URL ni el 404. Seis copias del mismo fallo eran
# seis sitios donde arreglarlo; ahora es uno.
#
# Contrato de exit codes (AGENTS.md §14.3):
#   0 = gitleaks instalado y ejecutable
#   3 = no se pudo instalar (red, checksum, plataforma). NO es exito:
#       quien llama decide, y en CI eso BLOQUEA. Un scanner que no se
#       pudo instalar jamas debe parecer un scanner que no encontro nada.
set -uo pipefail

# Version FIJA a proposito: `latest` en un gate de seguridad no es
# reproducible —una version nueva con reglas nuevas pone CI en rojo sin
# que nadie tocara el repo— y ademas impide verificar el checksum. Para
# subirla: mira el changelog, cambia estas dos lineas juntas y saca el
# sha de `gitleaks_<version>_checksums.txt` del propio release.
VERSION_DE_LOS_PINES="8.30.1"
VERSION="${GITLEAKS_VERSION:-$VERSION_DE_LOS_PINES}"
SHA256_linux_x64="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"
SHA256_linux_arm64="e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080"
SHA256_darwin_arm64="b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5"
SHA256_darwin_x64="dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709"

DESTINO="${1:-/usr/local/bin}"

# Si ya hay un gitleaks en el PATH se REUTILIZA solo si es la version fijada.
# Aceptar cualquiera seria contradecir el propio motivo de fijarla: una imagen
# base con otra version trae otras reglas, y el gate mediria algo distinto de
# lo que mide en la maquina de al lado — en silencio, que es lo peor.
if command -v gitleaks >/dev/null 2>&1; then
  presente="$(gitleaks version 2>&1 | head -1 | tr -d '[:space:]')"
  if [ "$presente" = "$VERSION" ]; then
    echo "ℹ️  install-gitleaks: ya presente en la version fijada ($VERSION)"
    exit 0
  fi
  echo "ℹ️  install-gitleaks: hay gitleaks ${presente:-<desconocida>} en el PATH, pero la fijada es $VERSION; se instala la fijada."
fi

case "$(uname -s)" in
  Linux) plataforma="linux" ;;
  Darwin) plataforma="darwin" ;;
  *) echo "⚠️  install-gitleaks: plataforma $(uname -s) no contemplada" >&2; exit 3 ;;
esac
case "$(uname -m)" in
  x86_64|amd64) arco="x64" ;;
  arm64|aarch64) arco="arm64" ;;
  *) echo "⚠️  install-gitleaks: arquitectura $(uname -m) no contemplada" >&2; exit 3 ;;
esac

tarball="gitleaks_${VERSION}_${plataforma}_${arco}.tar.gz"
url="https://github.com/gitleaks/gitleaks/releases/download/v${VERSION}/${tarball}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# `--fail` para que un 404 muera AQUI, con la URL a la vista, y no tres
# pasos mas tarde disfrazado de archivo corrupto.
if ! curl -sSL --fail -o "$tmp/g.tar.gz" "$url"; then
  echo "⚠️  install-gitleaks: no se pudo descargar $url" >&2
  exit 3
fi

# Las cuatro plataformas que de verdad se usan estan fijadas, la de CI y la
# del Mac de quien desarrolla — si solo se fijara la de CI, el camino que
# se ejecuta a diario seria justo el no verificado, y el mutante de este
# checksum no se podria probar en la maquina donde se escribe. En una
# plataforma sin pin se instala igual, pero se DICE que no se verifico.
# Expansion indirecta (`${!var}`) en vez de `eval`: aqui plataforma y arco solo
# pueden tener uno de cuatro valores del `case` de arriba, asi que el `eval` no
# era inyectable — pero obliga a quien lee a demostrarselo. `${!var}` no pide
# esa auditoria.
_pin="SHA256_${plataforma}_${arco}"
esperado="${!_pin:-}"
if [ -n "$esperado" ]; then
  real="$(shasum -a 256 "$tmp/g.tar.gz" 2>/dev/null | awk '{print $1}')"
  [ -n "$real" ] || real="$(sha256sum "$tmp/g.tar.gz" 2>/dev/null | awk '{print $1}')"
  if [ "$real" != "$esperado" ]; then
    echo "❌ install-gitleaks: checksum NO coincide para $tarball" >&2
    echo "   esperado: $esperado" >&2
    echo "   obtenido: ${real:-<no se pudo calcular>}" >&2
    # La causa casi siempre es esta y no un ataque; decirlo ahorra el susto y
    # la hora de buscarlo en el sitio equivocado. Que falle CERRADO al subir la
    # version por env var sin tocar los pines es deliberado: un sha que no
    # corresponde a lo que se descarga no verifica nada.
    if [ "$VERSION" != "$VERSION_DE_LOS_PINES" ]; then
      echo "   ⚠️  pediste la version $VERSION pero los checksums de este script son" >&2
      echo "      de la $VERSION_DE_LOS_PINES. Actualiza los SHA256_* junto con la version," >&2
      echo "      sacandolos de gitleaks_${VERSION}_checksums.txt en el release." >&2
    fi
    exit 3
  fi
else
  echo "ℹ️  install-gitleaks: sin checksum fijado para ${plataforma}_${arco}; se instala SIN verificar."
fi

if ! tar -xzf "$tmp/g.tar.gz" -C "$DESTINO" gitleaks 2>/dev/null; then
  echo "⚠️  install-gitleaks: no se pudo extraer en $DESTINO" >&2
  exit 3
fi

# Se comprueba el binario EN SU DESTINO, no `command -v`: con un destino
# fuera del PATH —lo normal al instalar en un directorio del workspace—
# `command -v` daba exit 3 sobre una instalacion perfectamente correcta.
# Un instalador que reporta fallo tras instalar bien enseña a ignorar su
# exit code, que es lo ultimo que quieres de un gate de seguridad.
[ -x "$DESTINO/gitleaks" ] || { echo "⚠️  install-gitleaks: no quedo un ejecutable en $DESTINO" >&2; exit 3; }
version_instalada="$("$DESTINO/gitleaks" version 2>&1 | head -1)"
if [ -n "$esperado" ]; then
  echo "✅ install-gitleaks: $version_instalada (v${VERSION}, checksum verificado)"
else
  echo "✅ install-gitleaks: $version_instalada (v${VERSION}, SIN verificar)"
fi

#!/usr/bin/env bash
# bootstrap.sh — deja el cascarón listo para TU proyecto.
#   1. Reemplaza el placeholder <PROJECT>/<project> por tu nombre real.
#   2. (Opcional) elimina las plataformas que no uses.
#   3. Crea el symlink CLAUDE.md → AGENTS.md si prefieres esa vía.
#
# Idempotente y conservador: pregunta antes de borrar nada.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "═══ Bootstrap del Agentic Workflow Template ═══"

read -r -p "Nombre del proyecto (kebab-case, ej. acme-app): " PROJECT
[ -z "$PROJECT" ] && { echo "Nombre vacío, aborto."; exit 1; }
# Title-case PORTABLE (BSD/macOS + GNU): mayúscula inicial de cada segmento '-'.
# NO usar `sed \U`: es extensión GNU; en BSD/macOS produce basura como "UacmeUapp".
PROJECT_TITLE=""
IFS='-' read -ra _parts <<< "$PROJECT"
for _p in "${_parts[@]}"; do
  [ -z "$_p" ] && continue
  PROJECT_TITLE="${PROJECT_TITLE}$(printf '%s' "${_p:0:1}" | tr '[:lower:]' '[:upper:]')${_p:1}"
done

# Reemplazo de placeholders en archivos de texto (excluye .git y binarios).
echo "→ Reemplazando <PROJECT> → $PROJECT_TITLE y <project> → $PROJECT ..."
grep -rlZ --exclude-dir=.git -e '<PROJECT>' -e '<project>' . 2>/dev/null \
  | while IFS= read -r -d '' f; do
      sed -i.bak -e "s/<PROJECT>/$PROJECT_TITLE/g" -e "s/<project>/$PROJECT/g" "$f"
      rm -f "$f.bak"
    done

# Plataformas.
echo "→ Plataformas disponibles: ios android web backend"
read -r -p "¿Cuáles usas? (separadas por espacio): " PLATFORMS
for p in ios android web backend; do
  if ! echo " $PLATFORMS " | grep -q " $p "; then
    [ -d "$p" ] && { echo "  - quito $p/"; rm -rf "$p"; }
  fi
done

# Preset de gates (full=equipo, bloquean · lite=personal, avisan).
echo "→ Preset de gates: full (equipo) | lite (personal, gates blandos avisan en vez de bloquear)."
read -r -p "¿Preset? [full/lite] (default full): " PRESET
case "$PRESET" in lite) _p=lite ;; *) _p=full ;; esac
printf '%s\n# full (equipo, gates bloquean) | lite (personal, gates avisan). Lo lee io.sh (hook_preset).\n' "$_p" > tools/preset
echo "  - preset = $_p"

# Vía Claude: import vs symlink.
echo "→ CLAUDE.md ya importa AGENTS.md con '@AGENTS.md'. Si prefieres symlink:"
echo "    rm CLAUDE.md && ln -s AGENTS.md CLAUDE.md"

echo ""
echo "✅ Bootstrap listo. Siguientes pasos:"
echo "   1. lefthook install                   ← sin esto el Anillo 1 está DORMIDO"
echo "      brew install lefthook gitleaks semgrep   (o pip/apt equivalente)"
echo "   2. grep -rn 'FILL:' .   ← rellena lo de tu stack"
echo "   3. lee docs/ADOPTION.md"

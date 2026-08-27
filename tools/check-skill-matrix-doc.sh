#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-skill-matrix-doc.sh — la tabla §11 y el conf no pueden divergir
# ════════════════════════════════════════════════════════════════════
# `tools/skill-matrix.conf` es la fuente única: la lee `skill-reminder` en
# runtime y es lo que de verdad BLOQUEA. `AGENTS.md §11` es su vista humana.
# Durante meses la cabecera del conf afirmaba que `test_skill_matrix.sh` cazaba
# la divergencia entre ambos. No era cierto: ese test comprueba que las refs
# EXISTAN y sean registrables, nunca compara tabla contra conf. O sea que el
# documento que promete el gate y el archivo que lo ejerce podían separarse sin
# que nada dijera nada — que es exactamente el drift que §9 prohíbe, cometido
# sobre el mecanismo que vigila el drift.
#
# Y no era hipotético: al escribir este detector, la primera pasada encontró
# dos divergencias vivas.
#   · La tabla exigía `architecture/platforms/ios.md` al tocar una View. El conf
#     no lo pedía. El doc ANUNCIABA una defensa que no existía (§14.4).
#   · La tabla tenía una fila `tools/**, ci/**, scripts/agent-hooks/**` →
#     `verification-loop.md`. Ese gate NO PUEDE existir: `skill-reminder`
#     excluye esas rutas a propósito (editar la doc de un área no es editar el
#     código de ese área — falso positivo real, fijado por
#     test_skill_reminder.sh). Era una promesa imposible de cumplir.
#
# ── QUÉ compara, y por qué NO compara los globs ─────────────────────
# Compara el conjunto de REFERENCIAS citadas a cada lado, no los globs. Los
# globs de la tabla agrupan a propósito (`**/*View*.swift, **/*Screen*.swift`
# en una fila) y usan prosa (`<migraciones-db>/**`); exigir igualdad literal
# daría un hallazgo por fila y el detector se desactivaría en una semana (ley
# del 10%, AGENTS §14.2). El conjunto de refs, en cambio, es exacto a los dos
# lados y es lo que importa: qué te obligan a leer.
#
# Las refs de la tabla van abreviadas (`domain/SKILL.md`) y las del conf
# completas (`.agents/skills/domain/SKILL.md`), así que el match es por SUFIJO
# de ruta — nunca por subcadena suelta, que casaría `SKILL.md` con cualquiera.
#
# Contrato de stdout:  MATRIX_DOC_SUMMARY solo_en_doc=<N> solo_en_conf=<M>
# Exit: 0 coherentes · 1 divergen · 3 no pude mirar (falta un archivo)
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

DOC="${SKILL_MATRIX_DOC:-AGENTS.md}"
CONF="${SKILL_MATRIX_CONF:-tools/skill-matrix.conf}"

if [ ! -f "$DOC" ] || [ ! -f "$CONF" ]; then
  {
    echo "⚠️  skill-matrix-doc: falta $( [ -f "$DOC" ] || printf '%s ' "$DOC"; [ -f "$CONF" ] || printf '%s' "$CONF") — no puedo comparar."
    echo "   Un gate que no pudo mirar NO es un gate que no encontró nada (§14.3)."
  } >&2
  echo "MATRIX_DOC_SUMMARY solo_en_doc=0 solo_en_conf=0"
  exit 3
fi

# ── Refs de la TABLA (columna 2 solamente) ──────────────────────────
# La columna 1 también trae tokens que acaban en `.md` (`docs/process/prds/
# [0-9]*.md` es un GLOB, no una lectura obligatoria). Leer la fila entera los
# metería como refs fantasma y el detector empezaría su vida con un falso
# positivo — la forma más rápida de que nadie vuelva a mirarlo.
DOC_REFS="$(awk -F'|' '
  /^\| *Path que vas a editar/ { intable = 1; next }
  intable && /^\|[ -]*-+/       { next }
  intable && !/^\|/             { intable = 0 }
  intable && NF >= 3            { print $3 }
' "$DOC" \
  | grep -oE '`[^`]+\.md`' \
  | tr -d '`' \
  | sort -u)"

# ── Refs del CONF (todo lo que hay tras el primer `|`) ──────────────
CONF_REFS="$(grep -vE '^[[:space:]]*(#|$)' "$CONF" \
  | awk -F'|' 'NF >= 2 { print $2 }' \
  | tr ',' '\n' \
  | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
  | grep -E '\.md$' \
  | sort -u)"

# ── Match por SUFIJO de ruta, en ambas direcciones ──────────────────
_casa() { # _casa <ref-corta> <ref-larga>
  [ "$1" = "$2" ] && return 0
  case "$2" in */"$1") return 0 ;; esac
  return 1
}

SOLO_DOC=""; SOLO_CONF=""
while IFS= read -r d; do
  [ -z "$d" ] && continue
  _hit=0
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    _casa "$d" "$c" && { _hit=1; break; }
  done <<< "$CONF_REFS"
  [ "$_hit" = "0" ] && SOLO_DOC="${SOLO_DOC}${d}"$'\n'
done <<< "$DOC_REFS"

while IFS= read -r c; do
  [ -z "$c" ] && continue
  _hit=0
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    _casa "$d" "$c" && { _hit=1; break; }
  done <<< "$DOC_REFS"
  [ "$_hit" = "0" ] && SOLO_CONF="${SOLO_CONF}${c}"$'\n'
done <<< "$CONF_REFS"

N_DOC="$(printf '%s' "$SOLO_DOC" | grep -c . || true)"
N_CONF="$(printf '%s' "$SOLO_CONF" | grep -c . || true)"

echo "MATRIX_DOC_SUMMARY solo_en_doc=${N_DOC:-0} solo_en_conf=${N_CONF:-0}"

if [ "${N_DOC:-0}" -eq 0 ] && [ "${N_CONF:-0}" -eq 0 ]; then
  exit 0
fi

{
  echo "❌ skill-matrix: la tabla de $DOC §11 y $CONF NO dicen lo mismo."
  if [ "${N_DOC:-0}" -gt 0 ]; then
    echo ""
    echo "   La TABLA exige leer esto y el conf NO lo pide (defensa anunciada"
    echo "   que no existe — el peor de los dos sentidos, §14.4):"
    printf '%s' "$SOLO_DOC" | sed 's/^/     · /'
    echo "   Arréglalo AÑADIÉNDOLO al conf, no borrándolo de la tabla: si estaba"
    echo "   escrito es porque alguien lo consideró obligatorio."
  fi
  if [ "${N_CONF:-0}" -gt 0 ]; then
    echo ""
    echo "   El CONF bloquea por esto y la tabla no lo menciona (el agente se"
    echo "   choca con un gate que su documentación no anuncia):"
    printf '%s' "$SOLO_CONF" | sed 's/^/     · /'
    echo "   Añádelo a la tabla de §11 en este mismo commit."
  fi
  echo ""
  echo "   Recuerda cuál manda: el conf es la fuente única (lo ejecuta"
  echo "   skill-reminder); la tabla es su vista humana."
} >&2
exit 1

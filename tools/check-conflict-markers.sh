#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-conflict-markers.sh — marcadores de conflicto en lo STAGED
# ════════════════════════════════════════════════════════════════════
# Nacido del cierre del primer proyecto real: un merge se concluyó con los
# marcadores de conflicto dentro de tools/findings/ledger.jsonl y NINGÚN gate
# lo miró. git solo impide commitear paths "unmerged": en cuanto haces
# `git add` del archivo con los marcadores dentro, el index queda "resuelto"
# y el commit pasa. El ledger quedó corrupto en develop y findings.sh murió
# (el harness-report lo mostró como "ledger no disponible" — así se cazó).
# Agravante estructural: la exención de MERGE_HEAD del review-marker hace los
# merges menos vigilados A PROPÓSITO — este check es su contrapeso mecánico,
# y corre justo donde el agujero vive: el commit que concluye el merge.
#
# Ley del 10%: solo bloquea si el archivo staged contiene AMBOS extremos
# (una línea que EMPIEZA por `<<<<<<< ` Y otra que empieza por `>>>>>>> `).
# Un doc que cita un marcador suelto no dispara; para citar un conflicto
# completo en un doc, indenta los marcadores (dejan de ser inicio de línea).
#
# Contrato §14.3: exit 0 = limpio · 1 = marcadores commiteándose.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

BAD=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if git show ":$f" 2>/dev/null | grep -qE '^<{7} ' \
     && git show ":$f" 2>/dev/null | grep -qE '^>{7} '; then
    BAD="${BAD}${f}"$'\n'
  fi
done < <(git diff --cached --name-only --diff-filter=ACM)

if [ -z "$BAD" ]; then
  echo "✅ conflict-markers: sin marcadores de conflicto en lo staged."
  exit 0
fi
echo "❌ conflict-markers: estás commiteando marcadores de conflicto sin resolver:"
printf '%s' "$BAD" | sed 's/^/   · /'
echo "   Resuelve el conflicto DE VERDAD: quita las líneas <<<<<<< / ======= / >>>>>>>"
echo "   dejando el contenido correcto (en un ledger JSONL suele ser AMBAS líneas),"
echo "   re-stagea el archivo y vuelve a commitear."
echo "CONFLICT_SUMMARY files=$(printf '%s' "$BAD" | grep -c .)"
exit 1

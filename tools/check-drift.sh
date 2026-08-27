#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-drift.sh — AGREGADOR de detectores mecánicos
# ════════════════════════════════════════════════════════════════════
# Ya NO es "un montón de greps". Su papel ahora es agregar los detectores
# especializados y emitir el contrato que consume el drift-ratchet:
#
#   tools/check-layers.sh   → capas, sobre el GRAFO DE IMPORTS
#   tools/semgrep-scan.sh   → patrones, sobre el AST
#   (aquí)                  → solo lo que de verdad es estructura de archivos
#                             (tamaños, existencia de tests) — lo único donde
#                             un `find`/`wc` no puede dar falso positivo.
#
# Por qué se movieron los greps: `grep -E '(==|!=) *"[^"]+"'` matchea el
# comentario que documenta el anti-patrón, el string de un test y el propio
# doc. Google midió que por encima de ~10% de falsos positivos los analizadores
# se descartan — y un agente, además, aprende a evadirlos.
#
# Contrato de salida (lo parsea drift-ratchet.sh):
#   - líneas de hallazgo con prefijo ❌ (error) o ⚠️ (warning)
#   - última línea EXACTA:  DRIFT_SUMMARY errors=<N> warns=<M>
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

ERRORS=0; WARNS=0
err() { echo "❌ $1"; ERRORS=$((ERRORS+1)); }
warn(){ echo "⚠️  $1"; WARNS=$((WARNS+1)); }

# Dónde buscar código (ajusta a tus carpetas).
SRC_DIRS="${DRIFT_SRC_DIRS:-ios android web src app lib Sources}"
EXISTING=""; for d in $SRC_DIRS; do [ -d "$d" ] && EXISTING="$EXISTING $d"; done

# ════════════════════════════════════════════════════════════════════
# 1) CAPAS — delegado al grafo de imports (0 falsos positivos)
# ════════════════════════════════════════════════════════════════════
if [ -f tools/check-layers.sh ]; then
  while IFS= read -r line; do
    case "$line" in
      "❌"*) echo "$line"; ERRORS=$((ERRORS+1)) ;;
      "⚠️"*) echo "$line"; WARNS=$((WARNS+1)) ;;
    esac
  done < <(bash tools/check-layers.sh 2>/dev/null)
fi

# ════════════════════════════════════════════════════════════════════
# 2) PATRONES — delegado a Semgrep (AST, no texto)
# ════════════════════════════════════════════════════════════════════
if [ -f tools/semgrep-scan.sh ]; then
  while IFS= read -r line; do
    case "$line" in
      "❌"*) echo "$line"; ERRORS=$((ERRORS+1)) ;;
      "⚠️"*) echo "$line"; WARNS=$((WARNS+1)) ;;
    esac
  done < <(bash tools/semgrep-scan.sh 2>/dev/null)
fi

# ════════════════════════════════════════════════════════════════════
# 3) ESTRUCTURA — lo único que se mide bien sin parsear
# ════════════════════════════════════════════════════════════════════

# 3a) Archivos por encima del hard limit (AGENTS.md §4).
HARD=${DRIFT_FILE_HARD:-400}
if [ -n "$EXISTING" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    n=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
    [ "${n:-0}" -gt "$HARD" ] && err "Archivo > $HARD líneas: $f ($n líneas)"
  done < <(find $EXISTING -type f \
             \( -name '*.swift' -o -name '*.kt' -o -name '*.ts' -o -name '*.tsx' \
                -o -name '*.js' -o -name '*.py' -o -name '*.java' -o -name '*.go' \) 2>/dev/null)
fi

# 3b) Lógica de producción sin test espejo (TDD, AGENTS.md §5).
#     Heurística por EXISTENCIA de archivo, no por contenido: antes esto hacía
#     `grep "$base" *Tests.swift`, que se satisface con solo mencionar el nombre
#     en un comentario — trivial de gamear para un agente. Ahora exige que
#     exista un archivo de test con el nombre esperado.
#     Sigue siendo una señal, no un veredicto: la calidad real del test la mide
#     `tools/mutation-score.sh`, que es el gate que de verdad importa.
if [ -n "$EXISTING" ]; then
  # UN solo `find` para el universo de tests, no 6 por archivo de lógica: la
  # versión anterior era O(n·m) y en un repo mediano excedía el presupuesto del
  # hook (que al agotar timeout NO bloquea — el gate moría en silencio).
  ALL_TEST_BASES="$(find $EXISTING . -maxdepth 6 -type f 2>/dev/null \
    | sed -E 's|.*/||' | grep -iE '(test|spec)' | sort -u)"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    base="$(basename "$f")"; base="${base%.*}"
    found=0
    for cand in "${base}Tests." "${base}Test." "${base}_test." "${base}.test." "${base}.spec." "test_${base}."; do
      if printf '%s\n' "$ALL_TEST_BASES" | grep -qF "$cand"; then
        found=1; break
      fi
    done
    [ "$found" -eq 0 ] && warn "Lógica sin archivo de test (TDD §5): $f — falta ${base}Tests/${base}.test/test_${base}"
  done < <(find $EXISTING -type f \
             \( -name '*UseCase.*' -o -name '*Logic.*' -o -name '*Reducer.*' -o -name '*Service.*' \) \
             2>/dev/null | grep -viE '(test|spec|mock|fake|stub)')
fi

# ════════════════════════════════════════════════════════════════════
# 4) TUS convenciones estructurales
# ════════════════════════════════════════════════════════════════════
# <!-- FILL: añade aquí SOLO lo que se mida por estructura de archivos/rutas
#      (naming, existencia, ubicación). Todo lo que dependa de entender el
#      código va a tools/semgrep/rules/*.yaml; todo lo de dependencias va a
#      tools/layers.conf. Regla: si tu check necesita un grep sobre el CUERPO
#      del archivo, está en el sitio equivocado.
#      Ejemplos válidos aquí:
#        - toda View tiene su ViewModel hermano
#        - toda migración de DB tiene su archivo de rollback
#        - todo módulo bajo Feature/ tiene README
# -->

echo ""
echo "DRIFT_SUMMARY errors=$ERRORS warns=$WARNS"
# exit 0 siempre: el GATE lo aplica drift-ratchet (delta), no este script.
exit 0

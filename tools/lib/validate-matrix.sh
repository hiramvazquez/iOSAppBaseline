#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# validate-matrix.sh — la matriz §11 (path → lectura obligatoria)
# ════════════════════════════════════════════════════════════════════
# `tools/skill-matrix.conf` es la fuente ÚNICA que lee el hook skill-reminder
# en runtime. Dos formas de que quede muda y ninguna se ve desde fuera:
# que el conf no exista (el hook degrada a los globs de fábrica, que no son
# los tuyos) o que cite una referencia que no está en el árbol — entonces el
# gate exige leer un archivo que nadie puede leer.
#
# Se SOURCEA desde tools/validate-harness.sh: usa sus helpers ok/bad/warn y su
# variable FAIL. No se ejecuta suelta (tools/lib/ → sin bit +x, exento de
# check-exec-bits.sh).

vh_check_matrix() {
# CUERPO VERBATIM (sin re-indentar).
# ── 5. La matriz de skills: refs existen y cubre tu código ──────────
echo ""
echo "── 5. skill-matrix.conf ──"
if [ -f tools/skill-matrix.conf ]; then
  BADREF=0
  while IFS='|' read -r glob refs; do
    case "$glob" in ''|'#'*) continue ;; esac
    _oldIFS="$IFS"; IFS=','
    for r in $refs; do
      r="$(printf '%s' "$r" | sed -E 's/^ +//; s/ +$//')"
      [ -n "$r" ] && [ ! -f "$r" ] && { bad "skill-matrix: ref inexistente '$r' (glob '$glob')"; BADREF=1; }
    done
    IFS="$_oldIFS"
  done < tools/skill-matrix.conf
  [ "$BADREF" = "0" ] && ok "todas las refs de la matriz existen"
else
  bad "tools/skill-matrix.conf AUSENTE — skill-reminder degrada a globs de fábrica"
fi
}

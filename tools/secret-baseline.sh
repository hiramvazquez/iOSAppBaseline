#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# secret-baseline.sh — triar UNA vez lo que ya está en el historial
# ════════════════════════════════════════════════════════════════════
# Un repo que adopta secret-scanning tarde arrastra hallazgos antiguos. Y hay
# un caso que le toca a TODO el que clona este template: el commit de scaffold
# contiene el literal del simulacro de `docs/ADOPTION §7` — una clave falsa
# puesta a propósito para que el §7 pueda demostrar que el Anillo 1 bloquea.
# Es fake, pero es DETECTABLE por diseño: si no lo fuera, el simulacro no
# probaría nada.
#
# Por eso NO se resuelve con un allowlist de ese literal: allowlistarlo dejaría
# mudo el propio simulacro y el selftest de `validate-harness`, que usan ese
# mismo valor para demostrar que el detector VE. Un gate que se prueba a sí
# mismo con un valor que ignora no prueba nada.
#
# Y tampoco se resuelve reescribiendo el historial: cambiaría todos los SHAs y
# rompería el remote `template` y el registro `tools/.template-sync` de cada
# proyecto adoptante.
#
# Queda el baseline: registrar el hallazgo concreto —archivo, regla, commit—
# para que no se vuelva a reportar, dejando el detector intacto para todo lo
# demás. Es DEUDA declarada, no exención: el archivo se revisa y encoge.
#
#   bash tools/secret-baseline.sh            # genera/refresca el baseline
#   bash tools/secret-baseline.sh --show     # qué está silenciando ahora
#
# Exit: 0 hecho · 1 el historial tiene hallazgos y NO se pudo generar ·
#       3 gitleaks ausente (no puedo mirar)
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

FILE=".gitleaks-baseline.json"

if [ "${1:-}" = "--show" ]; then
  [ -f "$FILE" ] || { echo "No hay baseline: el historial está limpio o nunca se trió."; exit 0; }
  if command -v jq >/dev/null 2>&1; then
    echo "Hallazgos silenciados por $FILE:"
    jq -r '.[] | "  · " + (.File // "?") + "  [" + (.RuleID // "?") + "]  " + ((.Commit // "?")[0:8])' "$FILE"
    echo ""
    echo "Cada línea es DEUDA, no una exención. Al quitar una causa de raíz, regenera."
  else
    echo "(jq ausente) $FILE existe con $(wc -c < "$FILE") bytes."
  fi
  exit 0
fi

if ! command -v gitleaks >/dev/null 2>&1; then
  {
    echo "⚠️  secret-baseline: gitleaks no está instalado — no puedo triar el historial."
    echo "   brew install gitleaks   |   https://github.com/gitleaks/gitleaks"
  } >&2
  exit 3
fi

# El baseline se genera SIN baseline previo (si no, se auto-confirmaría vacío)
# y sin --redact: para poder decidir si un hallazgo es falso hay que verlo.
REPORT="$(mktemp)"; trap 'rm -f "$REPORT"' EXIT
gitleaks git --no-banner --report-format json --report-path "$REPORT" >/dev/null 2>&1 || true

if [ ! -s "$REPORT" ] || ! grep -q '[^[:space:]]' "$REPORT"; then
  echo "✅ secret-baseline: gitleaks no reportó nada en el historial. No hace falta baseline."
  exit 0
fi
N=0
if command -v jq >/dev/null 2>&1; then
  N="$(jq 'length' "$REPORT" 2>/dev/null || echo 0)"
  if [ "${N:-0}" = "0" ]; then
    echo "✅ secret-baseline: historial limpio. No hace falta baseline."
    rm -f "$FILE" 2>/dev/null
    exit 0
  fi
fi

cp "$REPORT" "$FILE"
echo "📌 secret-baseline: $FILE escrito con ${N:-?} hallazgo(s) del historial."
echo ""
echo "   ⚠️  ANTES DE COMMITEARLO, MÍRALOS UNO A UNO:"
echo "        bash tools/secret-baseline.sh --show"
echo "   Un baseline se escribe para credenciales FALSAS o YA ROTADAS. Si alguna"
echo "   es real: rótala primero y regenera. Silenciar una credencial viva es"
echo "   peor que no tener el gate — te deja creyendo que está cubierto."
echo ""
echo "   A partir de aquí, el scan de historial solo reporta lo NUEVO."
exit 0

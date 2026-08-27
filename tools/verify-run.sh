#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# verify-run.sh — corre build+tests y deja EVIDENCIA firmada del diff
# ════════════════════════════════════════════════════════════════════
# El agujero que cierra, y es de los grandes: `check-review-marker.sh` liga el
# review a `sha256(diff staged)` — un review de otro diff no vale. Pero NINGUNA
# ejecución de build o de tests estaba ligada a ese mismo diff. Se podía
# commitear un árbol que ninguna ejecución registrada llegó a compilar, con
# todos los gates en verde. El invariante nº1 ("el veredicto lo deriva el
# sistema de una ejecución real") estaba aplicado al reviewer y no a los tests,
# que es donde más caro sale.
#
# Este script es el que EJECUTA, así que es el que puede firmar. El modelo no
# escribe este marker en ningún caso — igual que el de review, se acepta solo
# con `source: tool`.
#
#   bash tools/verify-run.sh            # corre y, si pasa, firma el diff staged
#   bash tools/verify-run.sh --ci       # corre y NO firma (en CI no hay marker)
#   bash tools/verify-run.sh --cmd-only # NO corre: solo dice si hay comando
#                                       # cableado (exit 0) o no (exit 3). Lo
#                                       # usan session-start y validate-harness
#                                       # para reportar el nivel 3 sin gastar
#                                       # un build entero en cada arranque.
#
# Exit: 0 verde (marker escrito) · 1 el build/los tests FALLARON ·
#       3 no pude verificar (sin comando cableado, o el árbol no permite firmar)
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

MODE="${1:-}"
CONF="${VERIFY_CONF:-tools/verify.conf}"
MARKER=".agents/state/markers/verify_run.txt"

# ── El comando: env > conf. Sin comando NO se inventa nada ──────────
CMD="${VERIFY_CMD:-}"
if [ -z "$CMD" ] && [ -f "$CONF" ]; then
  CMD="$(grep -vE '^[[:space:]]*(#|$)' "$CONF" 2>/dev/null | head -1 | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
fi
case "$CMD" in ''|'<tu-comando-aqui>'|*'FILL'*) CMD="" ;; esac
if [ -z "$CMD" ]; then
  {
    echo "⚠️  verify-run: no hay comando de build+tests cableado ($CONF)."
    echo "   Mientras siga así, NADA ata una ejecución verde al diff que commiteas:"
    echo "   los otros niveles pueden estar en verde con el build ROTO."
    echo "   Cablea una línea en $CONF (o exporta VERIFY_CMD)."
  } >&2
  exit 3          # "no pude mirar" (§14.3): local avisa, CI bloquea
fi
# ── Un comando que no toca tu producto no verifica tu producto ──────
# El template SÍ tiene comando cableado, y es honesto para él: su producto es
# el propio harness, así que su build+tests es la suite de gates. El problema
# es lo que hereda quien adopta: un `verify.conf` que sale 0 sin compilar una
# línea de su app. Eso no es un FILL sin rellenar —que se anuncia solo en cada
# arranque— sino algo peor: un gate que ANUNCIA ÉXITO. La asimetría es exacta:
# el hueco se delata, la respuesta equivocada no.
#
# El test no es "¿eres el template?" sino la pregunta que de verdad importa:
# **¿hay código de producto que este comando no está tocando?** Un repo sin una
# sola fuente de producto no tiene nada más que verificar y la suite es su
# verificación completa; en cuanto aparece la primera, deja de serlo.
# Solo dispara con el comando EXACTO del template: quien encadene la suite a su
# propio build (`xcodebuild ... && bash tools/tests/run-tests.sh`) está haciendo
# lo correcto y no debe oír una palabra.
if [ "$CMD" = "bash tools/tests/run-tests.sh" ]; then
  _PROD="$(find ios android web src app lib Sources -type f \
             \( -name '*.swift' -o -name '*.kt' -o -name '*.java' -o -name '*.ts' \
                -o -name '*.tsx' -o -name '*.js' -o -name '*.py' -o -name '*.go' \
                -o -name '*.rb' -o -name '*.cs' -o -name '*.rs' \) 2>/dev/null | head -1)"
  if [ -n "$_PROD" ]; then
    {
      echo "❌ verify-run: tu $CONF sigue siendo el del TEMPLATE."
      echo "   El comando cableado es \`$CMD\`: corre la suite del HARNESS y NO"
      echo "   compila tu producto. Y hay producto — p. ej. $_PROD."
      echo ""
      echo "   Esto es peor que un FILL sin rellenar: un hueco se anuncia solo en"
      echo "   cada arranque, pero esto SALE VERDE sin haber construido tu app."
      echo "   Sustituye la línea de $CONF por el build+tests de tu stack:"
      echo "     xcodebuild -scheme MiApp -destination '...' -quiet test"
      echo "     ./gradlew --quiet testDebugUnitTest"
      echo "     npm ci --silent && npm test --silent"
      echo "   (Si quieres correr además la suite del harness, encadénala con &&:"
      echo "    encadenada no salta este aviso, porque entonces sí compilas.)"
    } >&2
    exit 3        # "no pude verificar TU proyecto": avisa en local, bloquea en CI
  fi
fi

[ "$MODE" = "--cmd-only" ] && { echo "VERIFY_CMD_OK $CMD"; exit 0; }

# ── ¿Sobre QUÉ va a correr? El árbol de trabajo, no el índice ───────
# Por eso hay que exigir que no haya modificaciones sin stagear en archivos
# trackeados: si las hay, lo que se compila NO es lo que se va a commitear, y
# firmar ese resultado sería exactamente la mentira que este marker existe para
# impedir. El flujo correcto es el mismo que ya exige §13 para el review:
#   stagea → verifica → commitea (en comandos separados).
if [ "$MODE" != "--ci" ]; then
  SUCIO="$(git diff --name-only 2>/dev/null || true)"
  if [ -n "$SUCIO" ]; then
    {
      echo "❌ verify-run: hay cambios SIN STAGEAR en archivos trackeados:"
      printf '%s\n' "$SUCIO" | sed 's/^/     /'
      echo ""
      echo "   El build corre sobre el árbol de trabajo, así que lo que se"
      echo "   verificaría NO es lo que vas a commitear. Firmar eso sería la"
      echo "   mentira que este marker existe para impedir."
      echo "   Stagea lo que vayas a commitear y vuelve a correr."
    } >&2
    exit 3
  fi
fi

STAGED_SHA="$(git diff --cached 2>/dev/null | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | awk '{print $1}')"

# ── "El binario no existe" NO es "tus tests fallan" (§14.3) ─────────
# Tratar cualquier rc != 0 como fallo del código colapsa las dos cosas que el
# contrato separa a propósito: 1 = tu código tiene un problema · 3 = el
# detector no pudo mirar. Un `exit 127` (xcodebuild/gradle/npm fuera del PATH,
# el caso típico de un runner de CI mal montado o de una máquina nueva) se
# presentaría como "los tests están rojos", y el dev iría a buscar un bug
# inexistente. Se comprueba ANTES, con el primer token del comando.
_BIN="$(printf '%s' "$CMD" | awk '{print $1}')"
case "$_BIN" in
  */*) [ -x "$_BIN" ] || _FALTA=1 ;;
  *)   command -v "$_BIN" >/dev/null 2>&1 || _FALTA=1 ;;
esac
if [ "${_FALTA:-0}" = "1" ]; then
  {
    echo "⚠️  verify-run: '$_BIN' no está disponible — NO pude verificar nada."
    echo "   Esto NO es un test rojo: es el contrato §14.3 exit 3 ('no pude mirar')."
    echo "   En local avisa; en CI bloquea, que es donde un runner sin toolchain"
    echo "   no puede dar un job por verde."
  } >&2
  exit 3
fi

echo "━━━ verify-run: $CMD"
set +e
sh -c "$CMD"
RC=$?
set -e 2>/dev/null || true

if [ "$RC" -ne 0 ]; then
  echo ""
  echo "❌ verify-run: el comando salió con $RC. NO firmo nada." >&2
  echo "   (Un marker escrito tras un fallo convertiría el gate en un sello.)" >&2
  exit 1
fi

[ "$MODE" = "--ci" ] && { echo "✅ verify-run: verde (modo CI, sin marker)."; exit 0; }

mkdir -p "$(dirname "$MARKER")"
{
  printf 'source: tool\n'
  printf 'tool: verify-run.sh\n'
  printf 'cmd: %s\n' "$CMD"
  printf 'exit: 0\n'
  printf 'head: %s\n' "$(git rev-parse --short HEAD 2>/dev/null || echo no-repo)"
  printf 'staged_sha: %s\n' "$STAGED_SHA"
  printf 'at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$MARKER"

echo "✅ verify-run: verde. Evidencia firmada contra este diff staged (${STAGED_SHA:0:12}…)."
echo "   Si vuelves a tocar algo staged, el marker deja de valer y hay que re-correr."
exit 0

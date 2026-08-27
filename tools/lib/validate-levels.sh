#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# validate-levels.sh — ¿los NIVELES tienen con qué correr?
# ════════════════════════════════════════════════════════════════════
# Los checks §6-§9: las dependencias externas de los gates (y sus probes:
# "instalado" no es "operativo"), la existencia de la suite, si el COMPILADOR
# está cableado en algún gate, si el Anillo 3 existe de verdad —el backstop que
# justifica todo el fail-open local de §14.3— y los bits de ejecución.
#
# Cada uno responde a la misma pregunta con distinta lente: un nivel de la
# pirámide de §14 puede estar declarado y no tener con qué ejecutarse. Ese es
# el estado que se ve idéntico a "sano" desde fuera.
#
# Se SOURCEA desde tools/validate-harness.sh: usa sus helpers ok/bad/warn, su
# variable FAIL y su VH_MODE (el modo con el que se invocó el orquestador — el
# check §7 corre la suite entera solo en `--full`). No se ejecuta suelta
# (tools/lib/ → sin bit +x, exento de check-exec-bits.sh).

# shellcheck disable=SC2034  # FAIL es del orquestador que nos sourcea; aquí solo se escribe
vh_check_levels() {
# CUERPO VERBATIM (sin re-indentar).
# ── 6. Dependencias externas de los gates ───────────────────────────
echo ""
echo "── 6. Dependencias ──"
for dep in jq python3 git; do
  command -v "$dep" >/dev/null 2>&1 && ok "$dep" || bad "$dep AUSENTE — varios hooks degradan o fallan"
done
for dep in gitleaks lefthook; do
  command -v "$dep" >/dev/null 2>&1 && ok "$dep" || warn "$dep ausente — el nivel que lo usa está MUDO (session-start ya lo reporta)"
done
if [ -x tools/probe-capability.sh ]; then
  _probe="$(PROBE_TIMEOUT_SECS="${PROBE_TIMEOUT_SECS:-15}" bash tools/probe-capability.sh semgrep 2>/dev/null)"; _probe_rc=$?
  _probe_status="$(printf '%s' "$_probe" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status","unknown"))' 2>/dev/null || echo unknown)"
  _probe_detail="$(printf '%s' "$_probe" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("detail","sin diagnóstico"))' 2>/dev/null || echo 'salida no parseable')"
  case "$_probe_status:$_probe_rc" in
    operational:0) ok "semgrep operational — $_probe_detail" ;;
    missing:1) bad "semgrep missing — $_probe_detail" ;;
    broken:1) bad "semgrep broken — $_probe_detail" ;;
    *) bad "semgrep unknown (exit $_probe_rc) — $_probe_detail" ;;
  esac
else
  bad "probe de semgrep ausente — presencia no demuestra operación"
fi
if [ -x tools/architecture-check.sh ]; then
  _arch="$(bash tools/architecture-check.sh all 2>/dev/null)"; _arch_rc=$?
  for _cap in architecture_cycles architecture_complexity; do
    _state="$(printf '%s\n' "$_arch" | python3 -c '
import json,sys
name=sys.argv[1]
for line in sys.stdin:
    try: item=json.loads(line)
    except Exception: continue
    if item.get("capability") == name:
        print(item.get("status", "unknown")); break
' "$_cap" 2>/dev/null || echo unknown)"
    case "$_state" in
      operational) ok "$_cap operational" ;;
      unsupported) warn "$_cap unsupported — declarado explícitamente por el stack" ;;
      missing) warn "$_cap missing — copia architecture.conf.example y decide adapter/unsupported" ;;
      *) warn "$_cap broken/unknown (architecture-check exit $_arch_rc)" ;;
    esac
  done
else
  warn "architecture-check ausente — ciclos/complejidad no tienen estado verificable"
fi
if [ -d .git ] && [ -f lefthook.yml ]; then
  grep -q lefthook .git/hooks/pre-commit 2>/dev/null \
    && ok "Anillo 1 instalado (.git/hooks/pre-commit)" \
    || bad "ANILLO 1 DORMIDO: corre \`lefthook install\`"
fi

# ── 7. La suite del harness existe (y opcionalmente pasa) ───────────
echo ""
echo "── 7. Suite del harness ──"
NT="$(find tools/tests -name 'test_*.sh' 2>/dev/null | wc -l | tr -d ' ')"
if [ "${NT:-0}" = "0" ]; then
  bad "0 archivos test_*.sh — canon-enforce CHECK 4 y CI paso 1 aprueban en vacuo"
else
  ok "$NT archivos de test presentes"
  # `$VH_MODE`, no `$1`: dentro de una función `$1` es el argumento de la
  # FUNCIÓN, no el del script. Leerlo aquí haría que `--full` no corriera la
  # suite nunca — y en silencio, con el ✅ de arriba ya impreso.
  if [ "$VH_MODE" = "--full" ]; then
    bash tools/tests/run-tests.sh || FAIL=1
  fi
fi

# ── 8. ¿El COMPILADOR está en algún gate? ───────────────────────────
# El fallo más caro del primer proyecto real: nueve niveles en verde y el
# build de Xcode roto — la comprobación más barata y definitiva (¿compila?)
# era la única sin cablear, mientras semgrep, capas y trinquetes venían
# listos de fábrica. Esto no puede ser un FILL silencioso más.
echo ""
echo "── 8. Compilador en los gates ──"
if ! bash tools/verify-run.sh --cmd-only >/dev/null 2>&1; then
  warn "tools/verify.conf sigue sin cablear: NINGÚN gate compila ni corre tus tests."
  warn "Los 9 niveles pueden estar en verde con el build ROTO. Cablea build+tests ANTES que nada."
else
  ok "tools/verify.conf cableado (build+tests en el gate local Y en el Anillo 3)"
fi

# ── 8b. ¿EXISTE el Anillo 3? ────────────────────────────────────────
# El fail-open local de §14.3 está justificado POR el backstop. Si el
# backstop no existe, el razonamiento entero se cae — y hasta hoy nada lo
# comprobaba: se declaraban niveles mudos, nunca el anillo mudo.
# Severidad por preset: en `full` es un FALLO; en `lite` (uso personal) se
# DECLARA con todas las letras, que es el mínimo innegociable.
echo ""
echo "── 8b. Anillo 3 (CI) ──"
if [ -f tools/check-ring3.sh ]; then
  if _r3="$(bash tools/check-ring3.sh 2>&1)"; then
    ok "$(printf '%s' "$_r3" | grep -v RING3_SUMMARY | head -1)"
  else
    _preset="$(awk 'NR==1{print $1; exit}' tools/preset 2>/dev/null || echo full)"
    if [ "${_preset:-full}" = "lite" ]; then
      warn "Anillo 3 AUSENTE (preset lite: se declara, no bloquea)."
      warn "Cada exit 3 de un detector es fail-open DEFINITIVO mientras siga así."
    else
      bad "Anillo 3 AUSENTE en preset full — el backstop de §14.3 no existe."
      printf '%s\n' "$_r3" | grep -E '^\s+(·|Remedio|CONSECUENCIA)' | sed 's/^/     /'
    fi
  fi
else
  warn "tools/check-ring3.sh ausente — no puedo verificar el Anillo 3."
fi

# ── 9. Bits de ejecución ────────────────────────────────────────────
# 15 scripts sin +x el mismo día no es ruido: es el síntoma de archivos que
# llegaron por FUERA de git (un puente/cp no preserva permisos). Funciona
# igual porque todo se invoca con `bash script.sh`, pero ensucia cada diff.
echo ""
echo "── 9. Bits de ejecución ──"
if [ -f tools/check-exec-bits.sh ]; then
  if _eb="$(bash tools/check-exec-bits.sh --all 2>&1)"; then
    ok "todos los .sh ejecutables tienen bit +x (las libs sourceadas están exentas)"
  else
    bad "hay scripts .sh sin bit +x YA en el repo — se pierden en todo camino que no sea git."
    printf '%s\n' "$_eb" | grep -E '^\s+·' | head -8 | sed 's/^/     /'
    warn "Remedio rápido:  git ls-files '*.sh' | grep -v '/lib/' | xargs chmod +x && git add -u"
  fi
else
  warn "tools/check-exec-bits.sh ausente — no puedo verificar los bits de ejecución."
fi
}

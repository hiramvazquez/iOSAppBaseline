#!/usr/bin/env bash
# post-edit-verify: la señal in-loop (nivel 1). Su contrato tiene dos mitades
# y la más importante es la SILENCIOSA: ruido constante = ruido ignorado.
# Cierra parte de f-meta-fp-manifiesto (detector sin tests de FP verificados).

_pev_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}
# Simula el PostToolUse de un Edit sobre <archivo>; imprime "rc|salida".
_edit_event() {
  local out rc
  out="$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/%s"}}' "$(pwd)" "$1" \
        | bash scripts/agent-hooks/post-edit-verify.sh 2>/dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$out"
}

# ── FALSO POSITIVO guard nº1: archivo LIMPIO → SILENCIO total ───────
_case_archivo_limpio_silencio() {
  printf '#!/usr/bin/env bash\necho ok\n' > limpio.sh
  local r; r="$(_edit_event limpio.sh)"
  [ "${r%%|*}" = "0" ] || { echo "    un archivo limpio devolvió rc=${r%%|*}"; return 1; }
  [ -z "${r#*|}" ] || { echo "    un archivo limpio produjo RUIDO: ${r#*|}"; return 1; }
}
test_archivo_limpio_produce_silencio() { _pev_sandbox _case_archivo_limpio_silencio; }

# ── FALSO POSITIVO guard nº2: sin linter configurado → no-op ────────
_case_extension_sin_linter() {
  printf 'contenido cualquiera {{{\n' > raro.xyz
  local r; r="$(_edit_event raro.xyz)"
  [ "${r%%|*}" = "0" ] && [ -z "${r#*|}" ] || { echo "    una extensión sin linter generó salida/fallo: $r"; return 1; }
}
test_extension_sin_linter_es_noop() { _pev_sandbox _case_extension_sin_linter; }

# ── …pero la DETECCIÓN funciona: sintaxis rota se reporta ───────────
_case_sh_roto_informa() {
  printf '#!/usr/bin/env bash\nif [ x; then\n' > roto.sh
  local r; r="$(_edit_event roto.sh)"
  # No bloquea jamás (rc=0), pero SÍ informa vía additionalContext.
  [ "${r%%|*}" = "0" ] || { echo "    post-edit-verify BLOQUEÓ (rc=${r%%|*}) — jamás debe bloquear"; return 1; }
  case "${r#*|}" in *additionalContext*|*"bash -n"*) return 0 ;; esac
  echo "    un .sh con sintaxis rota no produjo señal: ${r#*|}"; return 1
}
test_sintaxis_rota_informa_sin_bloquear() { _pev_sandbox _case_sh_roto_informa; }

_case_archivo_gigante_avisa() {
  { echo '#!/usr/bin/env bash'; for i in $(seq 1 450); do echo "echo linea$i"; done; } > gigante.sh
  # .sh no está en la lista de tamaño; usa un .py (sí listado y sin linter aquí).
  for i in $(seq 1 450); do echo "x = $i"; done > gigante.py
  local r; r="$(_edit_event gigante.py)"
  case "${r#*|}" in *"hard limit"*|*"líneas"*) return 0 ;; esac
  echo "    un archivo de 450 líneas no avisó de tamaño: ${r#*|}"; return 1
}
test_archivo_sobre_hard_limit_avisa() { _pev_sandbox _case_archivo_gigante_avisa; }

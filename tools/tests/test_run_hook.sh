#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# Un hook ROTO no puede dejar al agente sin herramientas
# ════════════════════════════════════════════════════════════════════
# El peor fallo que ha tenido este harness, vivido en un proyecto real: un
# upgrade dejó marcadores de conflicto dentro de `reviewer-gate.sh`, que es el
# hook PreToolUse de Bash. El archivo dejó de parsear, bash salió con error, y
# el cliente leyó ese error como DENY. A partir de ahí toda ejecución de Bash
# quedó bloqueada: el agente no podía listar los conflictos, ni correr
# `git status`, ni diagnosticar el problema que el upgrade acababa de crear.
#
# La raíz: el modo de FALLO del hook colisiona con su señal de DENY (ambos son
# "exit != 0"). §14.3 ya decidía el empate para los DETECTORES; no estaba
# implementado para los HOOKS que los invocan.

_rh_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib"
  cp "$PROJECT_ROOT/scripts/agent-hooks/run-hook.sh" "$d/scripts/agent-hooks/"
  ( cd "$d" || exit 1; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_hook_roto_no_bloquea() {
  # Un hook con marcadores de conflicto SIN resolver — el caso literal.
  printf '#!/usr/bin/env bash\n<<<<<<< HEAD\necho a\n=======\necho b\n>>>>>>> otra\n' \
    > scripts/agent-hooks/roto.sh
  local out rc
  out="$(echo '{}' | bash scripts/agent-hooks/run-hook.sh scripts/agent-hooks/roto.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || { echo "    un hook ROTO bloqueó al agente (exit $rc) — sin poder ni diagnosticarlo"; return 1; }
  case "$out" in *"HARNESS DEGRADADO"*) : ;; *)
    echo "    no avisó de que el gate no se está aplicando: $out"; return 1 ;; esac
  case "$out" in *"conflicto"*) return 0 ;; esac
  echo "    el aviso no apunta a la causa típica (conflictos sin resolver)"; return 1
}
test_un_hook_que_no_parsea_avisa_y_deja_pasar() { _rh_sandbox _case_hook_roto_no_bloquea; }

_case_lib_rota_tambien_se_caza() {
  # `bash -n` NO sigue los `source`, así que una lib con conflictos pasaría el
  # filtro del hook y reventaría en runtime: el mismo brick por otra puerta.
  printf '#!/usr/bin/env bash\n. scripts/agent-hooks/lib/io.sh\nexit 2\n' > scripts/agent-hooks/g.sh
  printf 'x() {\n<<<<<<< HEAD\n' > scripts/agent-hooks/lib/io.sh
  local rc; echo '{}' | bash scripts/agent-hooks/run-hook.sh scripts/agent-hooks/g.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || { echo "    una LIB rota bloqueó al agente (exit $rc)"; return 1; }
}
test_una_lib_que_no_parsea_tambien_deja_pasar() { _rh_sandbox _case_lib_rota_tambien_se_caza; }

# ── Guards de FALSO POSITIVO: el gate SANO tiene que seguir mandando ──
# Si al arreglar el brick el runner se tragara los deny reales, habríamos
# borrado el Anillo 2 entero — un desenlace peor que el bug que arregla.
_case_deny_real_se_respeta() {
  printf '#!/usr/bin/env bash\nexit 2\n' > scripts/agent-hooks/deny.sh
  local rc; echo '{}' | bash scripts/agent-hooks/run-hook.sh scripts/agent-hooks/deny.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "2" ] || { echo "    el runner se comió un DENY real (exit $rc, esperaba 2)"; return 1; }
}
test_un_deny_real_sigue_denegando() { _rh_sandbox _case_deny_real_se_respeta; }

_case_allow_real_pasa() {
  printf '#!/usr/bin/env bash\nexit 0\n' > scripts/agent-hooks/ok.sh
  local rc; echo '{}' | bash scripts/agent-hooks/run-hook.sh scripts/agent-hooks/ok.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || { echo "    un hook sano devolvió $rc"; return 1; }
}
test_un_hook_sano_pasa_igual_que_antes() { _rh_sandbox _case_allow_real_pasa; }

_case_stdin_y_args_llegan() {
  # El payload JSON llega por stdin y los hooks lo leen. Si el runner se lo
  # comiera, TODOS los gates decidirían sobre un payload vacío — mudos, pero
  # con cara de sanos. Es el modo de fallo que este harness más persigue.
  printf '#!/usr/bin/env bash\nread -r linea\n[ "$linea" = "PAYLOAD" ] || exit 9\n[ "$1" = "--report" ] || exit 8\nexit 0\n' \
    > scripts/agent-hooks/eco.sh
  local rc; echo 'PAYLOAD' | bash scripts/agent-hooks/run-hook.sh scripts/agent-hooks/eco.sh --report >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || { echo "    el runner no pasó stdin y/o los args al hook (exit $rc)"; return 1; }
}
test_el_payload_y_los_args_llegan_intactos() { _rh_sandbox _case_stdin_y_args_llegan; }

# ── Y que los configs REALES pasen por el runner ────────────────────
test_los_tres_clientes_invocan_los_hooks_via_run_hook() {
  local f malos=""
  for f in .claude/settings.json .cursor/hooks.json .codex/hooks.json; do
    [ -f "$PROJECT_ROOT/$f" ] || continue
    while IFS= read -r c; do
      case "$c" in *run-hook.sh*) continue ;; esac
      malos="${malos}  · $f: $c"$'\n'
    done < <(grep -oE '"command": "bash scripts/agent-hooks/[^"]+"' "$PROJECT_ROOT/$f" | sed 's/"command": "//; s/"$//')
  done
  [ -z "$malos" ] && return 0
  echo "    hooks invocados SIN run-hook.sh (si se rompen, brickean al agente):"
  printf '%s' "$malos"
  return 1
}

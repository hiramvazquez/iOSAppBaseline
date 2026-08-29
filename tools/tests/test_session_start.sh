#!/usr/bin/env bash
# session-start: reset de estado + health report. El invariante que fija este
# archivo: **observar no modifica** (f-session-start-fx). Ejecutarlo "para ver
# el estado" borraba los markers a mitad de sesión y el siguiente Edit quedaba
# bloqueado — el observador alteraba lo observado.

_sst_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/tools" "$d/.agents/state/skills-read"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  cp "$PROJECT_ROOT/tools/preset" "$d/tools/preset" 2>/dev/null
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

# ── FALSO POSITIVO guard: --report NO tiene efectos secundarios ─────
_case_report_es_puro() {
  touch .agents/state/skills-read/algo.read
  echo baseline > .agents/state/drift-baseline.txt
  bash scripts/agent-hooks/session-start.sh --report >/dev/null 2>&1
  [ -f .agents/state/skills-read/algo.read ] || { echo "    --report BORRÓ los markers de lectura"; return 1; }
  [ -f .agents/state/drift-baseline.txt ]   || { echo "    --report borró el baseline de drift"; return 1; }
}
test_report_no_modifica_el_estado() { _sst_sandbox _case_report_es_puro; }

# ── …y el modo hook (startup) SÍ resetea, como siempre ──────────────
_case_hook_resetea() {
  touch .agents/state/skills-read/algo.read
  echo '{"hook_event_name":"SessionStart","source":"startup"}' \
    | bash scripts/agent-hooks/session-start.sh >/dev/null 2>&1
  [ -f .agents/state/skills-read/algo.read ] && { echo "    el modo hook dejó de resetear los markers"; return 1; }
  return 0
}
test_modo_hook_sigue_reseteando() { _sst_sandbox _case_hook_resetea; }

# ── source=compact JAMÁS resetea (defensa en profundidad) ───────────
# El bug real: SessionStart sin matcher borraba markers y baseline TRAS UNA
# COMPACTACIÓN — el drift-stop re-baseaba incluyendo los errores que el agente
# acababa de introducir, que pasaban a baseline y nunca se bloqueaban. El
# matcher de settings.json ya lo enruta bien; esto fija que, aunque un wrapper
# lo invoque mal, el script se defiende solo.
_case_compact_no_resetea() {
  touch .agents/state/skills-read/algo.read
  echo baseline > .agents/state/drift-baseline.txt
  echo '{"hook_event_name":"SessionStart","source":"compact"}' \
    | bash scripts/agent-hooks/session-start.sh >/dev/null 2>&1
  [ -f .agents/state/skills-read/algo.read ] || { echo "    compact BORRÓ los markers de skills"; return 1; }
  [ -f .agents/state/drift-baseline.txt ]   || { echo "    compact borró el baseline de drift"; return 1; }
}
test_source_compact_no_resetea_estado() { _sst_sandbox _case_compact_no_resetea; }

# ── el reset purga markers de review EXPIRADOS (y respeta los vigentes) ─
_case_purga_marker_expirado() {
  mkdir -p .agents/state/markers
  printf 'agent: reviewer\nverdict: GREEN\nsource: hook\n' > .agents/state/markers/reviewer_run.txt
  touch -t 202001010000 .agents/state/markers/reviewer_run.txt 2>/dev/null
  echo '{"source":"startup"}' | bash scripts/agent-hooks/session-start.sh >/dev/null 2>&1
  [ -f .agents/state/markers/reviewer_run.txt ] && { echo "    el marker EXPIRADO sobrevivió al reset (seguirá dando errores confusos)"; return 1; }
  return 0
}
test_reset_purga_marker_expirado() { _sst_sandbox _case_purga_marker_expirado; }

_case_respeta_marker_vigente() {
  mkdir -p .agents/state/markers
  printf 'agent: reviewer\nverdict: GREEN\nsource: hook\n' > .agents/state/markers/reviewer_run.txt
  echo '{"source":"startup"}' | bash scripts/agent-hooks/session-start.sh >/dev/null 2>&1
  [ -f .agents/state/markers/reviewer_run.txt ] || { echo "    un marker VIGENTE fue purgado (rompería el flujo review→restart→commit)"; return 1; }
}
test_reset_respeta_marker_vigente() { _sst_sandbox _case_respeta_marker_vigente; }

_case_resume_no_resetea() {
  touch .agents/state/skills-read/algo.read
  echo '{"hook_event_name":"SessionStart","source":"resume"}' \
    | bash scripts/agent-hooks/session-start.sh >/dev/null 2>&1
  [ -f .agents/state/skills-read/algo.read ] || { echo "    resume BORRÓ los markers de skills"; return 1; }
  return 0
}
test_source_resume_no_resetea_estado() { _sst_sandbox _case_resume_no_resetea; }

# ── el health-check detecta el Anillo 1 dormido ─────────────────────
_case_detecta_anillo_dormido() {
  cp "$PROJECT_ROOT/lefthook.yml" . 2>/dev/null || echo "pre-commit:" > lefthook.yml
  # repo git SIN `lefthook install` → sin .git/hooks/pre-commit de lefthook
  local out; out="$(bash scripts/agent-hooks/session-start.sh --report 2>&1)"
  case "$out" in *"ANILLO 1 DORMIDO"*) return 0 ;; esac
  echo "    no detectó lefthook.yml sin hooks instalados"; return 1
}
test_detecta_anillo1_dormido() { _sst_sandbox _case_detecta_anillo_dormido; }

_case_semgrep_broken_no_parece_instalado() {
  cat > tools/probe-capability.sh <<'EOF'
#!/usr/bin/env bash
echo '{"capability":"semgrep","status":"broken","detail":"X509 trust anchors"}'
exit 1
EOF
  chmod +x tools/probe-capability.sh
  local out
  out="$(bash scripts/agent-hooks/session-start.sh --report 2>&1)"
  assert_contains "$out" 'Nivel 2 ROTO' || return 1
  assert_contains "$out" 'X509 trust anchors'
}
test_arranque_distingue_semgrep_roto_de_ausente() { _sst_sandbox _case_semgrep_broken_no_parece_instalado; }

_case_semgrep_operational_no_avisa_nivel2() {
  cat > tools/probe-capability.sh <<'EOF'
#!/usr/bin/env bash
echo '{"capability":"semgrep","status":"operational","detail":"fixture detectado"}'
exit 0
EOF
  chmod +x tools/probe-capability.sh
  local out
  out="$(bash scripts/agent-hooks/session-start.sh --report 2>&1)"
  case "$out" in *'Nivel 2 MUDO'*|*'Nivel 2 ROTO'*) echo "    operational siguió avisando: $out"; return 1 ;; esac
}
test_arranque_acepta_solo_probe_operational() { _sst_sandbox _case_semgrep_operational_no_avisa_nivel2; }

_case_operational_con_exit_roto_es_unknown() {
  cat > tools/probe-capability.sh <<'EOF'
#!/usr/bin/env bash
echo '{"capability":"semgrep","status":"operational","detail":"inconsistente"}'
exit 1
EOF
  chmod +x tools/probe-capability.sh
  local out
  out="$(bash scripts/agent-hooks/session-start.sh --report 2>&1)"
  assert_contains "$out" 'Nivel 2 DESCONOCIDO'
}
test_arranque_valida_status_y_exit_como_un_par() { _sst_sandbox _case_operational_con_exit_roto_es_unknown; }

# ════════════════════════════════════════════════════════════════════
# NIVEL 4 — cuatro estados, cuatro mensajes (f-nivel4-dos-estados-un-cajon)
# ════════════════════════════════════════════════════════════════════
# El health-check del arranque ramifica sobre `mutation-score.sh --state`. Lo
# que se fija aquí no es el texto: es que "sin cablear" y "cableado pero el
# runner no completa" NO puedan salir con el mismo mensaje, porque sus remedios
# son opuestos. El adoptante real cableó el conf, volvió a leer lo mismo, y
# siguió sin score: el mensaje le pedía justo lo que ya había hecho.
_estado_dice() { # _estado_dice <estado> → imprime la salud que ve el arranque
  printf '#!/usr/bin/env bash\necho %s\n' "$1" > tools/mutation-score.sh
  bash scripts/agent-hooks/session-start.sh --report 2>&1
}

_case_cuatro_estados_cuatro_mensajes() {
  local sin cab run med
  sin="$(_estado_dice sin-cablear   | grep -i 'NIVEL 4' || true)"
  run="$(_estado_dice runner-incompleto | grep -i 'NIVEL 4' || true)"
  med="$(_estado_dice medido        | grep -i 'NIVEL 4' || true)"
  cab="$(_estado_dice sin-medir     | grep -i 'NIVEL 4' || true)"

  [ -n "$sin" ] || { echo "    'sin-cablear' no dijo nada del nivel 4"; return 1; }
  [ -n "$run" ] || { echo "    'runner-incompleto' no dijo nada del nivel 4"; return 1; }
  [ -n "$cab" ] || { echo "    'sin-medir' no dijo nada del nivel 4"; return 1; }
  [ -z "$med" ] || { echo "    'medido' avisó igualmente: $med"; return 1; }

  [ "$sin" != "$run" ] || {
    echo "    'sin cablear' y 'el runner no completa' salen con el MISMO mensaje."
    echo "    Sus remedios son opuestos: uno se arregla con conf, el otro NO."; return 1; }
  [ "$cab" != "$run" ] || { echo "    'sin-medir' y 'runner-incompleto' salen igual"; return 1; }

  # Y el mensaje del caso caro tiene que decir explícitamente que cablear más
  # no arregla nada: sin esa frase, el lector hace lo de siempre.
  case "$run" in *[Nn][Oo]*) : ;; *)
    echo "    el mensaje de runner-incompleto no niega la vía de 'cablea más': $run"; return 1 ;; esac
}
test_los_cuatro_estados_del_nivel4_no_comparten_mensaje() {
  _sst_sandbox _case_cuatro_estados_cuatro_mensajes
}

# ════════════════════════════════════════════════════════════════════
# WF-05 (PRD 0005 §6): "project_kind sin declarar" — UNA línea, aquí
# ════════════════════════════════════════════════════════════════════
# El fallback sin declaración vive en tools/lib/scope.sh y es SILENCIOSO por
# commit (ley del 10%): el único sitio que dice "declara tu kind" es este
# reporte de arranque. Y el caso doc-only —al que la heurística llama
# harness— necesita leer aquí su salida: declarar `other`.
_case_sin_project_kind_una_linea() {
  mkdir -p tools/lib
  cp "$PROJECT_ROOT/tools/lib/scope.sh" tools/lib/
  local out n
  out="$(bash scripts/agent-hooks/session-start.sh --report 2>&1)"
  case "$out" in *"project_kind sin declarar"*) : ;; *)
    echo "    el arranque no diagnostica la falta de tools/project.conf"; return 1 ;; esac
  n="$(printf '%s\n' "$out" | grep -c 'project_kind')"
  [ "$n" = "1" ] || { echo "    el diagnóstico ocupa $n líneas (prometida UNA)"; return 1; }
  case "$out" in *other*) : ;; *)
    echo "    el diagnóstico no menciona la salida 'other' para repos doc-only"; return 1 ;; esac
}
test_project_kind_sin_declarar_avisa_en_el_arranque() { _sst_sandbox _case_sin_project_kind_una_linea; }

# FALSO POSITIVO guard: declarado ⇒ ni una palabra sobre project_kind.
_case_project_kind_declarado_calla() {
  mkdir -p tools/lib
  cp "$PROJECT_ROOT/tools/lib/scope.sh" tools/lib/
  printf 'project_kind: application\n' > tools/project.conf
  local out; out="$(bash scripts/agent-hooks/session-start.sh --report 2>&1)"
  case "$out" in *project_kind*) echo "    declarado, y el arranque sigue hablando de project_kind"; return 1 ;; esac
  return 0
}
test_project_kind_declarado_no_avisa() { _sst_sandbox _case_project_kind_declarado_calla; }

# ════════════════════════════════════════════════════════════════════
# Los avisos de FILL casaban por PREFIJO: un hueco YA CERRADO seguía
# saliendo como pendiente, para siempre
# ════════════════════════════════════════════════════════════════════
# Los dos patrones eran `Plataformas:\*\* <!-- FILL` y `<!-- FILL`, ambos
# prefijos abiertos, así que casaban también `<!-- FILL-HECHO: ... -->`, que es
# el marcador de los ya RESUELTOS. Un adoptante que cerrase el hueco con esa
# convención seguiría leyendo "AGENTS.md §2 SIN rellenar" y "Nivel 1 PARCIAL"
# en CADA arranque de sesión, sobre trabajo que ya hizo.
#
# Importa más aquí que en otros sitios porque este es el banner de arranque: el
# punto de máxima autoridad del harness. Un aviso que no se puede apagar
# haciendo lo correcto enseña a ignorar los avisos, que es como mueren los
# gates (§14.2).
#
# La misma clase la arregló otra sesión en harness-report.sh y skill-reminder.sh;
# aquí se usa el MISMO delimitador para no inventar una tercera forma.
# ⚠️ El atajo de excluir el guion (`[[:space:]:>-]`) NO vale: perdería
# `<!-- FILL-->` pegado, que sí es un hueco pendiente. Por eso `-->` va como
# alternativa explícita y no como carácter dentro de la clase.

_sst_con_agents() { # <linea-de-plataformas>
  printf '# Proyecto\n\n## 2. Stack\n\n- **Plataformas:** %s\n' "$1" > AGENTS.md
}
# Dos detalles de este helper que NO son estilo, son correccion. Los dos
# hacian que el test mintiera, y en direcciones opuestas:
#
#   · `</dev/null` — el hook lee su payload de stdin con `cat` cuando stdin no
#     es un TTY. Sin cerrar la entrada se cuelga esperando EOF, el runner lo
#     mata por timeout SIN salida, y entonces un grep de "el aviso NO aparece"
#     pasa EN VACIO. Un test que aprueba porque el programa no llego a hablar
#     es peor que no tenerlo.
#   · CAPTURAR y luego grepear, en vez de `cmd | grep -q`. El runner corre con
#     `set -uo pipefail` (run-tests.sh:16) y `grep -q` sale en cuanto encuentra
#     lo que busca, matando al productor con SIGPIPE (141). Con pipefail ese
#     141 es el estado del pipeline, asi que el test fallaba EXACTAMENTE cuando
#     el aviso SI aparecia — el caso correcto era el unico que no pasaba.
_sst_banner() { bash scripts/agent-hooks/session-start.sh --report </dev/null 2>&1; }
_sst_avisa_stack() { # ¿el banner se queja del §2?
  local out; out="$(_sst_banner)"
  printf '%s' "$out" | grep -q 'AGENTS.md §2 (Stack) SIN rellenar'
}
_sst_avisa_nivel1() {
  local out; out="$(_sst_banner)"
  printf '%s' "$out" | grep -q 'Nivel 1 PARCIAL'
}

_case_fill_hecho_no_cuenta_como_pendiente() {
  _sst_con_agents '<!-- FILL-HECHO: ios 17+, SwiftUI -->'
  _sst_avisa_stack \
    && { echo "    un hueco YA CERRADO con FILL-HECHO se sigue reportando como pendiente"; return 1; }
  return 0
}
test_agents_con_fill_hecho_no_avisa_de_stack() { _sst_sandbox _case_fill_hecho_no_cuenta_como_pendiente; }

_case_fill_de_verdad_sigue_avisando() {
  # La otra mitad: sin este test, "arreglar" lo de arriba dejando de mirar
  # AGENTS.md pasaría inadvertido y el aviso moriría entero.
  _sst_con_agents '<!-- FILL: ios / android / web / backend -->'
  _sst_avisa_stack \
    || { echo "    un FILL de verdad dejó de avisar: el aviso murió al arreglar el falso positivo"; return 1; }
  return 0
}
test_agents_con_fill_real_sigue_avisando() { _sst_sandbox _case_fill_de_verdad_sigue_avisando; }

_case_fill_pegado_sigue_contando() {
  # LA TRAMPA del atajo. `<!-- FILL-->` (guion pegado, sin espacio) es un hueco
  # PENDIENTE, y excluir el guion a secas para no casar FILL-HECHO se lo come.
  _sst_con_agents '<!-- FILL-->'
  _sst_avisa_stack \
    || { echo "    '<!-- FILL-->' (guion pegado) dejó de contar como hueco pendiente"; return 1; }
  return 0
}
test_fill_con_guion_pegado_sigue_siendo_pendiente() { _sst_sandbox _case_fill_pegado_sigue_contando; }

_case_nivel1_con_fill_hecho_no_avisa() {
  # Mismo defecto, segundo sitio: el aviso del nivel 1 mira post-edit-verify.sh.
  printf '#!/usr/bin/env bash\n# <!-- FILL-HECHO: xcrun swift-format -->\ncase "$x" in\n  *) : ;;\nesac\n' \
    > scripts/agent-hooks/post-edit-verify.sh
  _sst_avisa_nivel1 \
    && { echo "    el nivel 1 sigue avisando con el FILL ya resuelto (FILL-HECHO)"; return 1; }
  return 0
}
test_nivel1_con_fill_hecho_no_avisa() { _sst_sandbox _case_nivel1_con_fill_hecho_no_avisa; }

_case_nivel1_con_fill_real_sigue_avisando() {
  printf '#!/usr/bin/env bash\n# <!-- FILL: el lint de tu stack -->\ncase "$x" in\n  *) : ;;\nesac\n' \
    > scripts/agent-hooks/post-edit-verify.sh
  _sst_avisa_nivel1 \
    || { echo "    el aviso del nivel 1 murió: un FILL real dejó de reportarse"; return 1; }
  return 0
}
test_nivel1_con_fill_real_sigue_avisando() { _sst_sandbox _case_nivel1_con_fill_real_sigue_avisando; }

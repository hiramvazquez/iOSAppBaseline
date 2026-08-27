#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# El modo de fallo más peligroso de un harness de verificación:
# **que la ausencia o corrupción de evidencia se lea como aprobación.**
# ════════════════════════════════════════════════════════════════════
# Los tres casos de abajo pasaron los 64 tests anteriores y los cazó el
# sub-agente `reviewer` revisando P1 (PRD 0001 §18 G10-G12). Todos comparten
# la misma forma: el gate no podía mirar, y respondió "está limpio".
#
# AGENTS.md §1.4 lo dice para el agente ("Open Question > suposición
# silenciosa"); esto lo impone para las herramientas.

_fc_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/semgrep/rules" "$d/tools/agent-backends" \
    "$d/tools/agent-prompts" "$d/bin" "$d/ci"
  cp "$PROJECT_ROOT/tools/semgrep-scan.sh" "$d/tools/"
  cp "$PROJECT_ROOT/tools/mutation-score.sh" "$d/tools/"
  cp "$PROJECT_ROOT/ci/ai-review.sh" "$d/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/agent-runner.sh" "$d/tools/" 2>/dev/null
  cp -R "$PROJECT_ROOT/tools/agent-backends/." "$d/tools/agent-backends/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/agent-prompts/"*.md "$d/tools/agent-prompts/" 2>/dev/null
  mkdir -p "$d/scripts/agent-hooks/lib"
  cp "$PROJECT_ROOT/scripts/agent-hooks/lib/verdict.sh" "$d/scripts/agent-hooks/lib/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; PATH="$d/bin:$PATH" "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

# Instala un `semgrep` de mentira que devuelve el JSON que le pasemos.
_fake_semgrep() {
  cat > bin/semgrep <<EOF
#!/usr/bin/env bash
cat <<'JSON'
$1
JSON
exit 0
EOF
  chmod +x bin/semgrep
  echo "rules: []" > tools/semgrep/rules/dummy.yaml
}

# ════════════════════════════════════════════════════════════════════
# 1. Una REGLA ROTA no puede parecer un repo limpio
# ════════════════════════════════════════════════════════════════════
_case_regla_invalida_falla() {
  # semgrep reporta los fallos de carga de reglas en `.errors[]`, no en
  # `.results[]`. Leer solo `.results[]` hacía que una regla rota diera
  # errors=0 warns=0 — indistinguible de "todo bien".
  _fake_semgrep '{"results":[],"errors":[{"type":"PartialParsing","message":"invalid pattern in rule branch-sobre-texto-natural"}]}'
  bash tools/semgrep-scan.sh >/dev/null 2>&1; local rc=$?
  # 3 = fallo del DETECTOR (no pude mirar), distinto de 1 = hallazgo real.
  # La distinción es lo que evita el deadlock: ver §3 de este archivo.
  [ "$rc" = "3" ] || { echo "    una regla INVÁLIDA no dio exit 3 (obtenido: $rc)"; return 1; }
}
test_regla_de_semgrep_rota_no_pasa_por_limpia() { _fc_sandbox _case_regla_invalida_falla; }

_case_regla_invalida_no_contamina_conteo() {
  # …pero el aviso va a stderr: el conteo del trinquete no se infla (G2).
  _fake_semgrep '{"results":[],"errors":[{"type":"PartialParsing","message":"boom"}]}'
  local out; out="$(bash tools/semgrep-scan.sh 2>/dev/null)"
  case "$out" in
    *"SEMGREP_SUMMARY errors=0 warns=0"*) return 0 ;;
    *) echo "    el error de reglas contaminó el contrato de salida: $out"; return 1 ;;
  esac
}
test_error_de_reglas_no_infla_el_trinquete() { _fc_sandbox _case_regla_invalida_no_contamina_conteo; }

# FALSO POSITIVO guard: un scan legítimamente limpio pasa — el fail-closed
# es para evidencia ausente/corrupta, no para la buena.
_case_semgrep_limpio_pasa() {
  _fake_semgrep '{"results":[],"errors":[]}'
  bash tools/semgrep-scan.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    un scan legítimamente limpio falló"; return 1; }
}
test_scan_limpio_de_verdad_pasa() { _fc_sandbox _case_semgrep_limpio_pasa; }

# ════════════════════════════════════════════════════════════════════
# 2. Evidencia CORRUPTA no es evidencia de aprobación
# ════════════════════════════════════════════════════════════════════
_case_score_no_numerico_falla() {
  # `[ "NaN" -lt 60 ]` lanza "integer expression expected", la condición se
  # evalúa como falsa y el script caía al camino de ÉXITO. Un typo del runner
  # o una salida truncada se leían como gate aprobado.
  printf '{"min_score": 60}\n' > tools/mutation-ratchet.json
  MUTATION_SCORE_OVERRIDE="NaN" bash tools/mutation-score.sh --check >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un score corrupto ('NaN') se interpretó como aprobado"; return 1; }
}
test_score_corrupto_no_aprueba() { _fc_sandbox _case_score_no_numerico_falla; }

_case_score_parcial_falla() {
  printf '{"min_score": 60}\n' > tools/mutation-ratchet.json
  MUTATION_SCORE_OVERRIDE="78%" bash tools/mutation-score.sh --check >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un score con basura ('78%') se interpretó como aprobado"; return 1; }
}
test_score_con_sufijo_no_aprueba() { _fc_sandbox _case_score_parcial_falla; }

_case_piso_corrupto_falla() {
  # DECISIÓN REVERTIDA: la primera versión degradaba un piso corrupto a 0.
  # Parecía prudente, pero desde que un piso >0 activa el gate obligatorio en
  # CI, degradar en silencio convierte "corromper el archivo" en una forma de
  # DESACTIVAR el gate. "No pude leer el piso" y "el piso es 0" son estados
  # distintos. Lo cazó el `reviewer` en la 3ª ronda de P1.
  printf '{"min_score": "sesenta"}\n' > tools/mutation-ratchet.json
  MUTATION_SCORE_OVERRIDE=50 bash tools/mutation-score.sh --check >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un trinquete CORRUPTO se interpretó como piso 0"; return 1; }
}
test_trinquete_corrupto_no_es_piso_cero() { _fc_sandbox _case_piso_corrupto_falla; }

# FALSO POSITIVO guard: trinquete AUSENTE = sin inicializar (legítimo), no
# corrupto. Confundirlos bloquearía a todo adoptante nuevo del template.
_case_ratchet_ausente_es_piso_cero() {
  # Ausente SÍ es piso 0: es el estado legítimo de "aún sin inicializar".
  rm -f tools/mutation-ratchet.json
  MUTATION_SCORE_OVERRIDE=50 bash tools/mutation-score.sh --check >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    un trinquete AUSENTE (sin inicializar) falló"; return 1; }
}
test_trinquete_ausente_es_piso_cero() { _fc_sandbox _case_ratchet_ausente_es_piso_cero; }

# ── La herramienta que REVIENTA sin producir JSON ───────────────────
_case_semgrep_crash_sin_json() {
  # Variante más severa que "una regla no carga": la herramienta entera no
  # corrió. Con $OUT vacío, todos los `jq` caen a su fallback 0 y el resultado
  # es indistinguible de "todo limpio".
  cat > bin/semgrep <<'EOF'
#!/usr/bin/env bash
echo "Fatal error: out of memory" >&2
exit 2
EOF
  chmod +x bin/semgrep
  echo "rules: []" > tools/semgrep/rules/dummy.yaml
  bash tools/semgrep-scan.sh >/dev/null 2>&1; local rc=$?
  [ "$rc" = "3" ] || { echo "    un semgrep que REVIENTA no dio exit 3 (obtenido: $rc)"; return 1; }
}
test_semgrep_que_revienta_no_pasa_por_limpio() { _fc_sandbox _case_semgrep_crash_sin_json; }

_case_semgrep_json_basura() {
  cat > bin/semgrep <<'EOF'
#!/usr/bin/env bash
echo "esto no es json"
exit 0
EOF
  chmod +x bin/semgrep
  echo "rules: []" > tools/semgrep/rules/dummy.yaml
  bash tools/semgrep-scan.sh >/dev/null 2>&1; local rc=$?
  [ "$rc" = "3" ] || { echo "    salida no-JSON no dio exit 3 (obtenido: $rc)"; return 1; }
}
test_salida_no_json_no_pasa_por_limpia() { _fc_sandbox _case_semgrep_json_basura; }

# ════════════════════════════════════════════════════════════════════
# 3. Un detector ROTO no puede trabar al dev (AGENTS.md §14.3)
# ════════════════════════════════════════════════════════════════════
# El deadlock que casi introduzco: enganchar el exit code crudo de
# semgrep-scan en reviewer-gate hacía que un typo en las reglas bloqueara
# TODOS los commits, en ambos presets y sin escape — incluido el commit que
# arreglaría el typo, porque la carga de reglas falla mires lo que mires.
# Distinción: exit 1 = tu código tiene un problema (bloquea);
#             exit 3 = no pude mirar tu código (avisa en local, bloquea en CI).

_gate_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/semgrep/rules" "$d/bin" "$d/scripts/agent-hooks/lib" "$d/.agents/state/markers"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  cp "$PROJECT_ROOT/tools/semgrep-scan.sh" "$d/tools/"
  cp "$PROJECT_ROOT/tools/check-review-marker.sh" "$d/tools/"
  cp "$PROJECT_ROOT/tools/check-layers.sh" "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/layers.conf" "$d/tools/" 2>/dev/null
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/tools/drift-ratchet.sh"
  echo "rules: []" > "$d/tools/semgrep/rules/dummy.yaml"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo seed > seed.txt; git add seed.txt; git commit -qm init 2>/dev/null
    mkdir -p src; echo "let x = 1" > src/App.swift; git add src/App.swift
    cat > .agents/state/markers/reviewer_run.txt <<EOF
agent: reviewer
verdict: GREEN
head: $(git rev-parse --short HEAD)
staged_sha: $(git diff --cached | shasum -a 256 | awk '{print $1}')
source: hook
EOF
    PATH="$d/bin:$PATH" "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}
_commit_attempt() {
  echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
    | WORKFLOW_PRESET="${1:-full}" bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  echo $?
}
_semgrep_returning() { # <json> <exit>
  cat > bin/semgrep <<EOF
#!/usr/bin/env bash
cat <<'JSON'
$1
JSON
exit ${2:-0}
EOF
  chmod +x bin/semgrep
}

_case_reglas_rotas_no_traban() {
  _semgrep_returning '{"results":[],"errors":[{"type":"PartialParsing","message":"typo en universal.yaml"}]}'
  local rc; rc="$(_commit_attempt full)"
  [ "$rc" = "0" ] || { echo "    DEADLOCK: unas reglas rotas bloquearon el commit (exit=$rc)"; return 1; }
}
test_reglas_rotas_no_bloquean_el_commit() { _gate_sandbox _case_reglas_rotas_no_traban; }

_case_semgrep_ausente_no_traba() {
  rm -f bin/semgrep
  local rc; rc="$(PATH="/usr/bin:/bin" _commit_attempt full)"
  [ "$rc" = "0" ] || { echo "    semgrep ausente bloqueó el commit (exit=$rc)"; return 1; }
}
test_semgrep_ausente_no_bloquea_el_commit() { _gate_sandbox _case_semgrep_ausente_no_traba; }

_case_hallazgo_real_si_bloquea() {
  # …pero un hallazgo REAL sigue bloqueando, sin excepción.
  _semgrep_returning '{"results":[{"path":"src/App.swift","start":{"line":1},"check_id":"secreto-hardcodeado","extra":{"severity":"ERROR","message":"credencial"}}],"errors":[]}'
  local rc; rc="$(_commit_attempt full)"
  [ "$rc" = "2" ] || { echo "    un hallazgo REAL de semgrep no bloqueó (exit=$rc)"; return 1; }
}
test_hallazgo_real_de_semgrep_bloquea() { _gate_sandbox _case_hallazgo_real_si_bloquea; }

_case_hallazgo_real_bloquea_tambien_en_lite() {
  _semgrep_returning '{"results":[{"path":"src/App.swift","start":{"line":1},"check_id":"x","extra":{"severity":"ERROR","message":"m"}}],"errors":[]}'
  local rc; rc="$(_commit_attempt lite)"
  [ "$rc" = "2" ] || { echo "    preset lite dejó pasar un hallazgo real de semgrep (exit=$rc)"; return 1; }
}
test_hallazgo_real_bloquea_en_lite() { _gate_sandbox _case_hallazgo_real_bloquea_tambien_en_lite; }

# ════════════════════════════════════════════════════════════════════
# 4. El backstop de CI es FAIL-CLOSED
# ════════════════════════════════════════════════════════════════════
_case_ai_review_obligatorio() {
  # `claude` ausente + AI_REVIEW_REQUIRED=1 → debe FALLAR. Si fuera opt-in, un
  # runner sin `claude` aprobaría en silencio justo los commits (Codex, humanos
  # con --no-verify) que este anillo existe para cubrir.
  echo x > f.txt; git add f.txt 2>/dev/null
  git -c user.email=t@t.t -c user.name=t commit -qm init 2>/dev/null
  PATH="/usr/bin:/bin" AI_REVIEW_REQUIRED=1 bash ai-review.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    con AI_REVIEW_REQUIRED=1 y sin \`claude\`, no falló"; return 1; }
}
test_ai_review_requerido_falla_sin_binario() { _fc_sandbox _case_ai_review_obligatorio; }

_case_ai_review_optout_explicito() {
  # Renunciar al gate debe ser posible, pero EXPLÍCITO y visible en la config.
  echo x > f.txt; git add f.txt 2>/dev/null
  git -c user.email=t@t.t -c user.name=t commit -qm init 2>/dev/null
  PATH="/usr/bin:/bin" AI_REVIEW_REQUIRED=0 bash ai-review.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    el opt-out explícito no funcionó"; return 1; }
}
test_ai_review_permite_optout_explicito() { _fc_sandbox _case_ai_review_optout_explicito; }

_case_ai_review_fake_sin_claude() {
  echo base > f.txt; git add f.txt
  git -c user.email=t@t.t -c user.name=t commit -qm base
  echo cambio >> f.txt; git add f.txt
  git -c user.email=t@t.t -c user.name=t commit -qm cambio
  PATH="/usr/bin:/bin" GATES_BASE_REF=HEAD^ AI_REVIEW_REQUIRED=1 \
    FAKE_REVIEW_RESULT=$'VERDICT: GREEN\nFINDINGS: 0\nSCOPE: fake-ci' \
    bash ai-review.sh --backend fake >/dev/null 2>&1 || return 1
  grep -q 'VERDICT: GREEN' .agents/state/ci/ai-review.md \
    || { echo "    AI review fake no guardó evidencia parseable"; return 1; }
}
test_ai_review_funciona_con_fake_sin_claude() { _fc_sandbox _case_ai_review_fake_sin_claude; }

_case_ai_review_fake_red_bloquea() {
  echo base > f.txt; git add f.txt
  git -c user.email=t@t.t -c user.name=t commit -qm base
  echo cambio >> f.txt; git add f.txt
  git -c user.email=t@t.t -c user.name=t commit -qm cambio
  PATH="/usr/bin:/bin" GATES_BASE_REF=HEAD^ AI_REVIEW_REQUIRED=1 \
    FAKE_REVIEW_RESULT=$'VERDICT: RED\nFINDINGS: 1\nSCOPE: fake-ci-red' \
    bash ai-review.sh --backend fake >/dev/null 2>&1
  [ "$?" = 1 ] || { echo "    AI review RED no bloqueó"; return 1; }
}
test_ai_review_fake_red_bloquea() { _fc_sandbox _case_ai_review_fake_red_bloquea; }

_case_ai_review_green_con_findings_bloquea() {
  echo base > f.txt; git add f.txt
  git -c user.email=t@t.t -c user.name=t commit -qm base
  echo cambio >> f.txt; git add f.txt
  git -c user.email=t@t.t -c user.name=t commit -qm cambio
  GATES_BASE_REF=HEAD^ AI_REVIEW_REQUIRED=1 \
    FAKE_REVIEW_RESULT=$'VERDICT: GREEN\nFINDINGS: 2\nSCOPE: contradictorio' \
    bash ai-review.sh --backend fake >/dev/null 2>&1
  [ "$?" = 1 ] || { echo "    CI aprobó GREEN contradictorio que el runner rechazó"; return 1; }
}
test_ai_review_respeta_rc_de_green_con_findings() {
  _fc_sandbox _case_ai_review_green_con_findings_bloquea
}

_case_ai_review_green_incompleto_bloquea() {
  echo base > f.txt; git add f.txt
  git -c user.email=t@t.t -c user.name=t commit -qm base
  echo cambio >> f.txt; git add f.txt
  git -c user.email=t@t.t -c user.name=t commit -qm cambio
  GATES_BASE_REF=HEAD^ AI_REVIEW_REQUIRED=1 \
    FAKE_REVIEW_RESULT=$'VERDICT: GREEN\nFINDINGS: 0' \
    bash ai-review.sh --backend fake >/dev/null 2>&1
  [ "$?" = 1 ] || { echo "    CI aprobó GREEN sin SCOPE que el runner rechazó"; return 1; }
}
test_ai_review_respeta_rc_de_green_incompleto() {
  _fc_sandbox _case_ai_review_green_incompleto_bloquea
}

_case_hallazgo_real_da_exit_1() {
  # El otro lado del contrato: un hallazgo REAL debe dar exit 1, NUNCA 3.
  # Si diera 3, los llamadores locales lo dejarían pasar como si el detector
  # hubiera fallado — convirtiendo un problema del código en un aviso.
  _fake_semgrep '{"results":[{"path":"a.py","start":{"line":1},"check_id":"x","extra":{"severity":"ERROR","message":"m"}}],"errors":[]}'
  bash tools/semgrep-scan.sh >/dev/null 2>&1; local rc=$?
  [ "$rc" = "1" ] || { echo "    un hallazgo real no dio exit 1 (obtenido: $rc)"; return 1; }
}
test_hallazgo_real_da_exit_1_no_3() { _fc_sandbox _case_hallazgo_real_da_exit_1; }

# ── El guard no puede depender de la VERSIÓN de jq ──────────────────
# `jq -e .` sobre un archivo VACÍO devuelve 0 en jq 1.6 y 4 en jq 1.7. El
# chequeo de "semgrep produjo JSON válido" colgaba de ese exit code, así que en
# jq 1.6 estaba INERTE: un semgrep reventado salía `errors=0 warns=0`, exit 0.
# El test de arriba lo cazaba… solo en máquinas con jq 1.7. Este lo caza en
# todas, porque instala un `jq` de mentira con la semántica PERMISIVA: aunque
# jq jure que un archivo vacío es JSON válido, el gate no puede aprobar.
_case_guard_no_depende_de_la_version_de_jq() {
  cat > bin/semgrep <<'EOF'
#!/usr/bin/env bash
echo "Fatal error: out of memory" >&2
exit 2
EOF
  chmod +x bin/semgrep
  # jq "1.6": todo lo que le pasen es válido y vacío.
  cat > bin/jq <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x bin/jq
  echo "rules: []" > tools/semgrep/rules/dummy.yaml
  local out rc; out="$(bash tools/semgrep-scan.sh 2>/dev/null)"; rc=$?
  [ "$rc" = "3" ] || {
    echo "    con un jq permisivo (1.6), un semgrep REVENTADO salió con exit $rc"
    echo "    y '$out' — el gate aprueba un scan que nunca corrió, en unas"
    echo "    máquinas sí y en otras no. El guard no puede colgar del exit de jq."
    return 1; }
}
test_el_guard_de_json_no_depende_de_la_version_de_jq() {
  _fc_sandbox _case_guard_no_depende_de_la_version_de_jq
}

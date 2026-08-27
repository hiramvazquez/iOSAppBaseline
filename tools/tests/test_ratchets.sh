#!/usr/bin/env bash
# Invariantes de los RATCHETS (trinquetes). Un ratchet que se puede aflojar
# no es un ratchet: es una sugerencia. Estos tests fijan la DIRECCIÓN.
#
# Cierra el finding f-8145599c del ledger: "falta test del invariante
# drift-ratchet-antes-de-bypass-lite".

# Copia el harness a un repo temporal para poder stubear sus piezas.
# (Los hooks derivan PROJECT_ROOT de su propio dirname, así que copiar funciona.)
_harness_sandbox() { # _harness_sandbox <función-a-ejecutar-dentro>
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/tools" "$d/.agents/state/markers"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  cp "$PROJECT_ROOT"/tools/*.sh "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT"/tools/*.json "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/layers.conf" "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/preset" "$d/tools/preset" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo x > seed.txt; git add seed.txt; git commit -qm init 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

# ════════════════════════════════════════════════════════════════════
# f-8145599c — el preset `lite` relaja el MARKER, jamás el RATCHET.
# ════════════════════════════════════════════════════════════════════
_case_lite_no_relaja_ratchet() {
  # Stub: el ratchet SIEMPRE falla (simula deuda que subió).
  stub tools/drift-ratchet.sh '#!/usr/bin/env bash\necho "❌ ratchet: subió"\nexit 1\n'
  # Cambio staged de código de producto (no docs/tooling → sí requiere gate).
  mkdir -p src; echo "let x = 1" > src/App.swift; git add src/App.swift
  # Preset lite + intento de commit.
  echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
    | WORKFLOW_PRESET=lite bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  local rc=$?
  # DEBE bloquear (exit 2) aunque el preset sea lite.
  [ "$rc" = "2" ] || { echo "    lite dejó pasar un ratchet roto (exit=$rc, esperaba 2)"; return 1; }
}
test_ratchet_duro_incluso_en_preset_lite() {
  _harness_sandbox _case_lite_no_relaja_ratchet
}

_case_override_no_relaja_ratchet() {
  # REVIEWER_OVERRIDE es un escape hatch para el MARKER (juicio humano),
  # nunca para un detector mecánico. Un número objetivo no se negocia.
  stub tools/drift-ratchet.sh '#!/usr/bin/env bash\necho "❌ ratchet: subió"\nexit 1\n'
  mkdir -p src; echo "let x = 1" > src/App.swift; git add src/App.swift
  echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
    | REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON="urgencia" \
      bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  local rc=$?
  [ "$rc" = "2" ] || { echo "    el override saltó el ratchet (exit=$rc, esperaba 2)"; return 1; }
}
test_override_no_relaja_el_ratchet() {
  _harness_sandbox _case_override_no_relaja_ratchet
}

_case_override_si_relaja_marker() {
  stub tools/drift-ratchet.sh '#!/usr/bin/env bash\nexit 0\n'
  mkdir -p src; echo "let x = 1" > src/App.swift; git add src/App.swift
  echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
    | WORKFLOW_PRESET=full REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON="urgencia" \
      bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    el override no permitió commitear sin marker"; return 1; }
  # …y queda AUDITADO.
  grep -q "urgencia" .agents/state/markers/override_log.txt 2>/dev/null \
    || { echo "    el override no quedó registrado en override_log.txt"; return 1; }
}
test_override_relaja_marker_pero_queda_auditado() {
  _harness_sandbox _case_override_si_relaja_marker
}

# ════════════════════════════════════════════════════════════════════
# El marker debe venir del SISTEMA (source: hook), no del modelo.
# ════════════════════════════════════════════════════════════════════
_case_marker_manual_no_vale() {
  mkdir -p src .agents/state/markers; echo "let x = 1" > src/App.swift; git add src/App.swift
  # Marker fabricado "a mano" (lo que el modelo podía hacer antes).
  cat > .agents/state/markers/reviewer_run.txt <<EOF
ts: $(date -u +%Y-%m-%dT%H:%M:%SZ)
verdict: GREEN
scope: me reviso a mí mismo
head: $(git rev-parse --short HEAD)
staged_sha: $(git diff --cached | shasum -a 256 | awk '{print $1}')
source: manual-override
EOF
  bash tools/check-review-marker.sh --staged >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un marker manual fue aceptado como review"; return 1; }
}
test_marker_manual_es_rechazado() {
  _harness_sandbox _case_marker_manual_no_vale
}

# FALSO POSITIVO guard: el marker LEGÍTIMO del hook debe pasar — un gate que
# rechaza también la evidencia buena no distingue nada.
_case_marker_de_hook_si_vale() {
  mkdir -p src .agents/state/markers; echo "let x = 1" > src/App.swift; git add src/App.swift
  cat > .agents/state/markers/reviewer_run.txt <<EOF
ts: $(date -u +%Y-%m-%dT%H:%M:%SZ)
agent: reviewer
verdict: GREEN
scope: gates
head: $(git rev-parse --short HEAD)
staged_sha: $(git diff --cached | shasum -a 256 | awk '{print $1}')
source: hook
EOF
  bash tools/check-review-marker.sh --staged >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    un marker legítimo del hook fue rechazado"; return 1; }
}
test_marker_de_hook_es_aceptado() {
  _harness_sandbox _case_marker_de_hook_si_vale
}

_case_marker_stale_por_diff() {
  mkdir -p src .agents/state/markers; echo "let x = 1" > src/App.swift; git add src/App.swift
  cat > .agents/state/markers/reviewer_run.txt <<EOF
agent: reviewer
verdict: GREEN
head: $(git rev-parse --short HEAD)
staged_sha: $(git diff --cached | shasum -a 256 | awk '{print $1}')
source: hook
EOF
  # …y AHORA se cuela algo más en el staging, después de la review.
  echo "let colado = 2" > src/Sneaky.swift; git add src/Sneaky.swift
  bash tools/check-review-marker.sh --staged >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    se aceptó un marker cuyo diff ya no coincide"; return 1; }
}
test_marker_caduca_si_cambia_el_diff_staged() {
  _harness_sandbox _case_marker_stale_por_diff
}

_case_lite_si_relaja_marker() {
  # Ratchet OK, pero SIN marker de reviewer.
  stub tools/drift-ratchet.sh '#!/usr/bin/env bash\nexit 0\n'
  mkdir -p src; echo "let x = 1" > src/App.swift; git add src/App.swift
  echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
    | WORKFLOW_PRESET=lite bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  local rc=$?
  # En lite, la falta de marker AVISA pero deja pasar.
  [ "$rc" = "0" ] || { echo "    lite bloqueó por marker ausente (exit=$rc, esperaba 0)"; return 1; }
}
test_lite_avisa_pero_permite_sin_marker() {
  _harness_sandbox _case_lite_si_relaja_marker
}

_case_full_bloquea_sin_marker() {
  stub tools/drift-ratchet.sh '#!/usr/bin/env bash\nexit 0\n'
  mkdir -p src; echo "let x = 1" > src/App.swift; git add src/App.swift
  echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  [ "$?" = "2" ] || { echo "    full dejó commitear sin marker"; return 1; }
}
test_full_bloquea_sin_marker() {
  _harness_sandbox _case_full_bloquea_sin_marker
}

# FALSO POSITIVO guard: un cambio solo-docs NO es código de producto y no
# puede exigir review — bloquearlo haría que el equipo desactivara el gate.
_case_solo_docs_no_requiere_gate() {
  stub tools/drift-ratchet.sh '#!/usr/bin/env bash\nexit 0\n'
  mkdir -p docs; echo "# hola" > docs/x.md; git add docs/x.md
  echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m docs"}}' \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    un cambio solo-docs fue bloqueado"; return 1; }
}
test_cambio_solo_docs_pasa() {
  _harness_sandbox _case_solo_docs_no_requiere_gate
}

# ════════════════════════════════════════════════════════════════════
# Mutation ratchet — el piso SOLO SUBE (dirección opuesta al de drift).
# ════════════════════════════════════════════════════════════════════
_case_mutacion_bajo_el_piso_falla() {
  printf '{"min_score": 60}\n' > tools/mutation-ratchet.json
  MUTATION_SCORE_OVERRIDE=55 bash tools/mutation-score.sh --check >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un score por debajo del piso NO falló"; return 1; }
}
test_mutacion_por_debajo_del_piso_falla() {
  _harness_sandbox _case_mutacion_bajo_el_piso_falla
}

_case_mutacion_sobre_el_piso_pasa() {
  printf '{"min_score": 60}\n' > tools/mutation-ratchet.json
  MUTATION_SCORE_OVERRIDE=65 bash tools/mutation-score.sh --check >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    un score por encima del piso falló"; return 1; }
}
test_mutacion_por_encima_del_piso_pasa() {
  _harness_sandbox _case_mutacion_sobre_el_piso_pasa
}

_case_mutacion_update_no_baja() {
  printf '{"min_score": 60}\n' > tools/mutation-ratchet.json
  # --update con un score PEOR no debe bajar el piso.
  MUTATION_SCORE_OVERRIDE=40 bash tools/mutation-score.sh --update >/dev/null 2>&1
  grep -q '"min_score": *60' tools/mutation-ratchet.json \
    || { echo "    --update BAJÓ el piso: $(cat tools/mutation-ratchet.json)"; return 1; }
}
test_mutacion_update_nunca_baja_el_piso() {
  _harness_sandbox _case_mutacion_update_no_baja
}

_case_mutacion_update_si_sube() {
  printf '{"min_score": 60}\n' > tools/mutation-ratchet.json
  MUTATION_SCORE_OVERRIDE=78 bash tools/mutation-score.sh --update >/dev/null 2>&1
  grep -q '"min_score": *78' tools/mutation-ratchet.json \
    || { echo "    --update no subió el piso: $(cat tools/mutation-ratchet.json)"; return 1; }
}
test_mutacion_update_sube_el_piso() {
  _harness_sandbox _case_mutacion_update_si_sube
}

# ── El cableado de muter, contra un stub FIEL al muter real ─────────
# Dos bugs cazados en vivo en el primer proyecto (una tarde del owner cada
# uno): (1) el detector aceptaba solo muter.conf.json y el init moderno
# genera .yml; (2) muter NO emite JSON por stdout (--format json mezcla
# logo y progreso) — el reporte solo sale con -o <archivo>, y la v1 hacía
# json.loads(stdout), fallaba siempre, y caía al mensaje de "sin runner".
# El stub reproduce ESE contrato: basura por stdout, JSON solo en -o.
_muter_stub() { # _muter_stub <json-del-reporte>
  mkdir -p bin
  cat > bin/muter <<STUB
#!/usr/bin/env bash
out=""
while [ \$# -gt 0 ]; do
  case "\$1" in -o|--output) out="\$2"; shift 2 ;; *) shift ;; esac
done
echo "=== MUTER ==="
echo "Discovering source files..."
[ -n "\$out" ] && printf '%s' '$1' > "\$out"
exit 0
STUB
  chmod +x bin/muter
  : > muter.conf.yml
}

_case_muter_reporte_via_archivo() {
  _muter_stub '{"mutationScore": 72, "totalAppliedMutationOperators": 25}'
  local out
  out="$(PATH="$PWD/bin:$PATH" bash tools/mutation-score.sh --report 2>&1)"
  printf '%s' "$out" | grep -q 'score=72' \
    || { echo "    el score no salió del reporte -o (¿volvió el parseo de stdout?): $out"; return 1; }
}
test_muter_score_se_lee_del_archivo_no_de_stdout() {
  _harness_sandbox _case_muter_reporte_via_archivo
}

_case_muter_cero_mutantes_no_es_score() {
  # "0 candidatos" NO es un 0%: es el detector sin ojos (scheme sin cobertura
  # o SwiftSyntax viejo ante sintaxis nueva). Debe salir por §14.3 (exit 3)
  # con mensaje PROPIO — jamás por la rama de "sin runner configurado".
  _muter_stub '{"mutationScore": 0, "totalAppliedMutationOperators": 0}'
  local out rc
  out="$(PATH="$PWD/bin:$PATH" bash tools/mutation-score.sh --report 2>&1)"; rc=$?
  [ "$rc" = "3" ] || { echo "    0 mutantes salió con exit $rc (esperaba 3, §14.3)"; return 1; }
  printf '%s' "$out" | grep -q 'sin runner configurado' \
    && { echo "    0 mutantes cayó al mensaje de 'sin runner' — los dos fallos vuelven a ser indistinguibles"; return 1; }
  printf '%s' "$out" | grep -qi 'mutantes' \
    || { echo "    el mensaje no explica el caso 0-mutantes: $out"; return 1; }
}
test_muter_cero_mutantes_es_ruidoso_y_distinto() {
  _harness_sandbox _case_muter_cero_mutantes_no_es_score
}

_case_muter_crash_distinto_de_sin_runner() {
  mkdir -p bin
  printf '#!/usr/bin/env bash\necho boom >&2\nexit 1\n' > bin/muter
  chmod +x bin/muter
  : > muter.conf.yml
  local out rc
  out="$(PATH="$PWD/bin:$PATH" bash tools/mutation-score.sh --report 2>&1)"; rc=$?
  [ "$rc" = "3" ] || { echo "    muter crasheado salió con exit $rc (esperaba 3)"; return 1; }
  printf '%s' "$out" | grep -q 'sin runner configurado' \
    && { echo "    un muter que CORRIÓ y falló se reportó como 'sin runner'"; return 1; }
  return 0
}
test_muter_roto_no_se_disfraza_de_sin_runner() {
  _harness_sandbox _case_muter_crash_distinto_de_sin_runner
}

# ════════════════════════════════════════════════════════════════════
# Drift ratchet — --update TAMBIÉN impone la dirección (espejo de mutación).
# El bug real: --update reescribía el techo con el conteo actual SIN comparar
# — y estaba en allow de permissions: el agente podía legalizar deuda nueva
# con un solo comando. Un trinquete que su propio script permitido puede
# aflojar es una sugerencia.
# ════════════════════════════════════════════════════════════════════
_case_drift_update_no_sube() {
  stub tools/check-drift.sh '#!/usr/bin/env bash\necho "DRIFT_SUMMARY errors=5 warns=3"\n'
  printf '{\n  "errors": 2,\n  "warns": 1\n}\n' > tools/drift-ratchet.json
  bash tools/drift-ratchet.sh --update >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    --update con el conteo por ENCIMA del techo no falló"; return 1; }
  grep -q '"errors": *2' tools/drift-ratchet.json \
    || { echo "    --update SUBIÓ el techo: $(cat tools/drift-ratchet.json)"; return 1; }
}
test_drift_update_nunca_sube_el_techo() { _harness_sandbox _case_drift_update_no_sube; }

_case_drift_update_si_baja() {
  stub tools/check-drift.sh '#!/usr/bin/env bash\necho "DRIFT_SUMMARY errors=1 warns=0"\n'
  printf '{\n  "errors": 2,\n  "warns": 1\n}\n' > tools/drift-ratchet.json
  bash tools/drift-ratchet.sh --update >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    --update con un conteo MEJOR falló (falso positivo)"; return 1; }
  grep -q '"errors": 1' tools/drift-ratchet.json \
    || { echo "    no escribió el techo nuevo"; return 1; }
}
test_drift_update_si_puede_bajar() { _harness_sandbox _case_drift_update_si_baja; }

# Primera adopción (JSON ausente): fijar el techo inicial ES legítimo.
_case_drift_update_primera_vez() {
  stub tools/check-drift.sh '#!/usr/bin/env bash\necho "DRIFT_SUMMARY errors=7 warns=2"\n'
  rm -f tools/drift-ratchet.json
  bash tools/drift-ratchet.sh --update >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    primera adopción (sin JSON) fue rehusada"; return 1; }
  grep -q '"errors": 7' tools/drift-ratchet.json \
    || { echo "    no fijó el techo inicial"; return 1; }
}
test_drift_update_primera_vez_fija_el_techo() { _harness_sandbox _case_drift_update_primera_vez; }

# ── Un piso de 0 no es un piso: es una medición que nunca ocurrió ────
# En un proyecto real el nivel 4 llevaba mudo desde el día uno con
# `min_score: 0`, mientras AGENTS.md §5 lo declaraba "el veredicto mecánico" y
# "el gate que distingue un test que verifica de uno escrito para pasar".
# Un 0 escrito en el ratchet se disfraza de suelo. (f-mutation-score-nunca-medido)
_case_no_se_escribe_un_piso_de_cero() {
  printf '{ "min_score": 0, "measured": false }\n' > tools/mutation-ratchet.json
  MUTATION_SCORE_OVERRIDE=0 bash tools/mutation-score.sh --update >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    --update escribió (o aceptó) un piso de 0"; return 1; }
  grep -q '"measured"[[:space:]]*:[[:space:]]*false' tools/mutation-ratchet.json \
    || { echo "    el ratchet dejó de declarar que nunca se ha medido"; return 1; }
}
test_update_se_niega_a_escribir_un_piso_de_cero() {
  _harness_sandbox _case_no_se_escribe_un_piso_de_cero
}

_case_una_medicion_real_si_sube_el_piso() {
  # FALSO POSITIVO guard: el caso legítimo tiene que seguir funcionando, o
  # habríamos cambiado un gate mudo por un gate imposible de inicializar.
  printf '{ "min_score": 0, "measured": false }\n' > tools/mutation-ratchet.json
  MUTATION_SCORE_OVERRIDE=63 bash tools/mutation-score.sh --update >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    una medición REAL no pudo subir el piso"; return 1; }
  grep -q '"min_score"[[:space:]]*:[[:space:]]*63' tools/mutation-ratchet.json \
    || { echo "    el piso no quedó en 63"; return 1; }
  grep -q '"measured"[[:space:]]*:[[:space:]]*true' tools/mutation-ratchet.json \
    || { echo "    tras medir, el ratchet no marcó measured:true"; return 1; }
}
test_una_medicion_real_sube_el_piso_y_marca_medido() {
  _harness_sandbox _case_una_medicion_real_si_sube_el_piso
}

# ════════════════════════════════════════════════════════════════════
# f-nivel4-dos-estados-un-cajon — CUATRO estados, no dos
# ════════════════════════════════════════════════════════════════════
# `--state` responde SIN medir (lo consulta session-start en cada arranque:
# si disparara muter, abrir una sesión costaría minutos). Los dos estados que
# importan piden cosas OPUESTAS —"sin cablear" es trabajo del adoptante;
# "el runner no completa" es un fallo de la herramienta que no se arregla
# escribiendo conf— y hasta hoy se veían igual.
_case_state_sin_cablear() {
  printf '{"min_score": 0, "measured": false}\n' > tools/mutation-ratchet.json
  local s; s="$(bash tools/mutation-score.sh --state 2>/dev/null)"
  [ "$s" = "sin-cablear" ] || { echo "    sin runner instalado dijo '$s' (esperaba sin-cablear)"; return 1; }
  # FALSO POSITIVO: una huella VIEJA no puede acusar a una herramienta ausente.
  # Se desinstala el runner (o se clona el repo en otra máquina) y el registro
  # de la última corrida sigue ahí: sin este orden, el arranque mandaría a abrir
  # un issue upstream contra algo que ni siquiera está instalado.
  mkdir -p .agents/state; printf 'incompleto 2026-01-01T00:00:00Z\n' > .agents/state/mutation-last-run.txt
  s="$(bash tools/mutation-score.sh --state 2>/dev/null)"
  [ "$s" = "sin-cablear" ] || {
    echo "    con una huella vieja y SIN runner dijo '$s' (esperaba sin-cablear)"; return 1; }
}
test_state_sin_runner_dice_sin_cablear() { _harness_sandbox _case_state_sin_cablear; }

_case_state_medido() {
  printf '{"min_score": 61, "measured": true}\n' > tools/mutation-ratchet.json
  local s; s="$(bash tools/mutation-score.sh --state 2>/dev/null)"
  [ "$s" = "medido" ] || { echo "    con piso real dijo '$s' (esperaba medido)"; return 1; }
}
test_state_con_piso_real_dice_medido() { _harness_sandbox _case_state_medido; }

_case_state_runner_incompleto() {
  # El runner EXISTE y arranca, pero no llega al final (el caso real: muter no
  # localizaba el xctestrun del proyecto y completaba con cero mutantes).
  # El estado NO se afirma: se deriva de una corrida real (invariante nº1). Así
  # que primero se corre de verdad —ahí se escribe la huella— y luego se
  # pregunta. Preguntar antes de haber corrido nunca da `runner-incompleto`, y
  # eso es correcto: nadie ha visto todavía a esa herramienta fallar.
  printf '{"min_score": 0, "measured": false}\n' > tools/mutation-ratchet.json
  mkdir -p bin; printf '#!/usr/bin/env bash\nexit 1\n' > bin/muter; chmod +x bin/muter
  printf 'x\n' > muter.conf.yml
  local s
  s="$(PATH="$PWD/bin:$PATH" bash tools/mutation-score.sh --state 2>/dev/null)"
  [ "$s" = "sin-medir" ] || { echo "    sin haber corrido nunca dijo '$s' (esperaba sin-medir)"; return 1; }
  PATH="$PWD/bin:$PATH" bash tools/mutation-score.sh --report >/dev/null 2>&1
  s="$(PATH="$PWD/bin:$PATH" bash tools/mutation-score.sh --state 2>/dev/null)"
  [ "$s" = "runner-incompleto" ] || {
    echo "    tras una corrida que no completa dijo '$s' (esperaba runner-incompleto)"
    echo "    Es el estado cuyo remedio es OPUESTO al de sin-cablear: confundirlos"
    echo "    manda al adoptante a cablear conf que ya está cableada."; return 1; }
}
test_state_runner_que_no_completa_no_se_confunde_con_sin_cablear() {
  _harness_sandbox _case_state_runner_incompleto
}

# ── FALSO POSITIVO: --state no puede DISPARAR una medición ──────────
# Si `--state` cayera en el camino normal, cada arranque de sesión lanzaría el
# runner (minutos) y el health-check mentiría por ruido. Además va ANTES del
# cálculo a propósito: el primer intento lo metió dentro del `case` demasiado
# tarde e imprimía los avisos del camino normal junto al estado.
_case_state_no_mide() {
  printf '{"min_score": 0, "measured": false}\n' > tools/mutation-ratchet.json
  mkdir -p bin
  printf '#!/usr/bin/env bash\ntouch "$PWD/MIDIO"\nexit 0\n' > bin/muter; chmod +x bin/muter
  printf 'x\n' > muter.conf.yml
  local out; out="$(PATH="$PWD/bin:$PATH" bash tools/mutation-score.sh --state 2>&1)"
  [ -f MIDIO ] && { echo "    --state EJECUTÓ el runner: cada arranque de sesión costaría minutos"; return 1; }
  [ "$(printf '%s' "$out" | wc -l)" -le 1 ] || {
    echo "    --state imprimió más que el estado (los avisos del camino normal):"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_state_no_dispara_una_corrida_del_runner() { _harness_sandbox _case_state_no_mide; }

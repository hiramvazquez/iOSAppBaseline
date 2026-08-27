#!/usr/bin/env bash
# La matriz path→skill vivía en CINCO sitios y "nada se duplica" era mentira.
# Ahora la FUENTE ÚNICA es tools/skill-matrix.conf (skill-reminder la lee en
# runtime). Estos tests fijan: (1) toda ref citada EXISTE — una matriz que
# exige leer archivos inexistentes bloquea el trabajo para siempre; (2) el
# hook consume el conf de verdad; (3) sin conf, el fallback de fábrica sigue.

test_toda_ref_de_la_matriz_existe() {
  [ -f tools/skill-matrix.conf ] || { echo "    tools/skill-matrix.conf no existe"; return 1; }
  local glob refs r bad=0 _old
  while IFS='|' read -r glob refs; do
    case "$glob" in ''|'#'*) continue ;; esac
    _old="$IFS"; IFS=','
    for r in $refs; do
      r="$(printf '%s' "$r" | sed -E 's/^ +//; s/ +$//')"
      [ -n "$r" ] && [ ! -f "$r" ] && { echo "    ref inexistente: $r (glob '$glob')"; bad=1; }
    done
    IFS="$_old"
  done < tools/skill-matrix.conf
  return "$bad"
}

_smx_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/tools" "$d/.agents/state/skills-read" "$d/src"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_conf_gobierna_el_gate() {
  # Matriz mínima propia: SOLO los .py exigen leer una ref.
  printf 'src/*.py|docs/regla.md\n' > tools/skill-matrix.conf
  mkdir -p docs; echo regla > docs/regla.md
  local rc
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$PWD"'/src/api.py"}}' \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/skill-reminder.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "2" ] || { echo "    el conf no gobernó el gate (exit $rc, esperaba 2)"; return 1; }
  # …y con el marker de lectura presente, pasa.
  touch .agents/state/skills-read/docs__regla.md.read
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$PWD"'/src/api.py"}}' \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/skill-reminder.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || { echo "    con marker presente siguió bloqueando (exit $rc)"; return 1; }
}
test_skill_reminder_lee_el_conf() { _smx_sandbox _case_conf_gobierna_el_gate; }

# FALSO POSITIVO guard: un path que NO casa ningún glob no puede bloquearse.
_case_path_fuera_de_matriz_pasa() {
  printf 'src/*.py|docs/regla.md\n' > tools/skill-matrix.conf
  local rc
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$PWD"'/src/main.go"}}' \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/skill-reminder.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || { echo "    bloqueó un path fuera de la matriz (exit $rc)"; return 1; }
}
test_path_fuera_de_la_matriz_no_bloquea() { _smx_sandbox _case_path_fuera_de_matriz_pasa; }

# ── consistencia matriz ↔ track-reads (bug real, cazado EN VIVO) ────
# Toda ref que la matriz EXIGE leer debe ser REGISTRABLE por track-reads.
# Si no, el flujo es un bucle infinito: el agente lee la skill (obedece),
# el marker no se crea, skill-reminder bloquea, el agente re-lee… Lo cazó
# el agente del primer proyecto real depurando el hook — platforms/*.md
# estaba en la matriz pero no en el filtro del tracker.
_case_refs_registrables() {
  cp "$PROJECT_ROOT/tools/skill-matrix.conf" tools/skill-matrix.conf
  local glob refs r _old bad=0
  while IFS='|' read -r glob refs; do
    case "$glob" in ''|'#'*) continue ;; esac
    _old="$IFS"; IFS=','
    for r in $refs; do
      r="$(printf '%s' "$r" | sed -E 's/^ +//; s/ +$//')"; [ -z "$r" ] && continue
      rm -rf .agents/state/skills-read
      printf '{"tool_name":"Read","tool_input":{"file_path":"%s/%s"}}' "$PWD" "$r" \
        | bash scripts/agent-hooks/track-reads.sh >/dev/null 2>&1
      [ -f ".agents/state/skills-read/${r//\//__}.read" ] \
        || { echo "    ref '$r' NO registrable por track-reads → skill-reminder bloquearía para siempre"; bad=1; }
    done
    IFS="$_old"
  done < tools/skill-matrix.conf
  return "$bad"
}
test_toda_ref_es_registrable_por_track_reads() { _smx_sandbox _case_refs_registrables; }

_case_sin_conf_usa_fallback() {
  rm -f tools/skill-matrix.conf
  local rc
  echo '{"tool_name":"Write","tool_input":{"file_path":"'"$PWD"'/src/PagoLogic.swift"}}' \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/skill-reminder.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "2" ] || { echo "    sin conf, el fallback de fábrica no gateó (exit $rc)"; return 1; }
}
test_sin_conf_cae_al_fallback_de_fabrica() { _smx_sandbox _case_sin_conf_usa_fallback; }

# ════════════════════════════════════════════════════════════════════
# tabla §11 ↔ conf: el detector que la cabecera decía tener y no tenía
# ════════════════════════════════════════════════════════════════════
# `skill-matrix.conf` afirmaba "la divergencia la caza test_skill_matrix.sh".
# Falso: este archivo comprobaba que las refs EXISTAN y sean registrables,
# nunca comparó tabla contra conf. Una afirmación de cobertura sin detector
# detrás es peor que ninguna: se lee, se cree, y nadie vuelve a mirar.
# (f-4d2b0e51, reportado desde el proyecto adoptante.)

test_la_tabla_y_el_conf_de_ESTE_repo_coinciden() {
  local out; out="$(bash tools/check-skill-matrix-doc.sh 2>&1)"
  case "$out" in *"solo_en_doc=0 solo_en_conf=0"*) return 0 ;; esac
  echo "    AGENTS.md §11 y tools/skill-matrix.conf divergen:"
  printf '%s\n' "$out" | sed 's/^/    /'
  return 1
}

_smd_sandbox() { # doc + conf de juguete, sin tocar el repo real
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools"
  cp "$PROJECT_ROOT/tools/check-skill-matrix-doc.sh" "$d/tools/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}
_smd_doc() { printf '%s\n' "$1" > AGENTS.md; }
_smd_conf() { printf '%s\n' "$1" > tools/skill-matrix.conf; }

_case_doc_promete_de_mas() {
  # El sentido GRAVE: el documento exige una lectura que el gate no pide.
  _smd_doc '## 11. Matriz

| Path que vas a editar | Reference obligatorio |
|---|---|
| `**/*View*.swift` | `architecture/SKILL.md` + `platforms/ios.md` |'
  _smd_conf '*View*.swift|.agents/skills/architecture/SKILL.md'
  local out; out="$(bash tools/check-skill-matrix-doc.sh 2>&1)"; local rc=$?
  [ "$rc" = "1" ] || { echo "    una defensa anunciada y NO implementada pasó (exit $rc)"; return 1; }
  case "$out" in *"platforms/ios.md"*) return 0 ;; esac
  echo "    no nombró la ref que sobra en el doc: $out"; return 1
}
test_ref_solo_en_la_tabla_es_defensa_fingida() { _smd_sandbox _case_doc_promete_de_mas; }

_case_conf_bloquea_sin_anunciarlo() {
  # El otro sentido: el gate bloquea por algo que la doc no menciona. Menos
  # grave (falla cerrado), pero el agente se choca con un muro invisible.
  _smd_doc '## 11. Matriz

| Path que vas a editar | Reference obligatorio |
|---|---|
| `**/*View*.swift` | `architecture/SKILL.md` |'
  _smd_conf '*View*.swift|.agents/skills/architecture/SKILL.md,.agents/skills/security/SKILL.md'
  local out; out="$(bash tools/check-skill-matrix-doc.sh 2>&1)"; local rc=$?
  [ "$rc" = "1" ] || { echo "    un gate no anunciado pasó (exit $rc)"; return 1; }
  case "$out" in *"security/SKILL.md"*) return 0 ;; esac
  echo "    no nombró la ref que falta en la tabla: $out"; return 1
}
test_ref_solo_en_el_conf_es_muro_invisible() { _smd_sandbox _case_conf_bloquea_sin_anunciarlo; }

_case_el_glob_de_la_columna_1_no_es_una_ref() {
  # FALSO POSITIVO que habría matado al detector el primer día: la columna de
  # PATHS también trae tokens que acaban en `.md` — `docs/process/prds/[0-9]*.md`
  # es un glob, no una lectura obligatoria. Leer la fila entera lo contaría como
  # ref fantasma y el detector nacería en rojo sin motivo.
  _smd_doc '## 11. Matriz

| Path que vas a editar | Reference obligatorio |
|---|---|
| `docs/process/prds/[0-9]*.md` | `process/references/prd-lifecycle.md` |'
  _smd_conf 'docs/process/prds/[0-9]*.md|.agents/skills/process/references/prd-lifecycle.md'
  local out; out="$(bash tools/check-skill-matrix-doc.sh 2>&1)"; local rc=$?
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: contó el glob de la columna 1 como ref ($out)"; return 1; }
}
test_un_glob_que_acaba_en_md_no_cuenta_como_ref() {
  _smd_sandbox _case_el_glob_de_la_columna_1_no_es_una_ref
}

_case_sin_archivos_avisa_no_aprueba() {
  # §14.3: "no pude mirar" (3) nunca puede confundirse con "está limpio" (0).
  _smd_conf '*View*.swift|x.md'
  rm -f AGENTS.md
  bash tools/check-skill-matrix-doc.sh >/dev/null 2>&1
  [ "$?" = "3" ] || { echo "    sin el doc no devolvió 3 (fallo del detector), sino $?"; return 1; }
}
test_sin_los_archivos_devuelve_3_no_0() { _smd_sandbox _case_sin_archivos_avisa_no_aprueba; }

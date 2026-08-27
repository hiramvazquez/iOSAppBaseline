#!/usr/bin/env bash
# canon-enforce BLOQUEA el cierre de turno. Es el gate más agresivo del harness,
# así que sus falsos positivos son los más caros: bloquean trabajo terminado y
# correcto, y la reacción natural es desactivarlo.
#
# El caso que motivó estos tests: el detector de secretos se bloqueaba A SÍ MISMO,
# porque el archivo que define "esto parece un secreto" contiene, por necesidad,
# algo que parece un secreto. (PRD 0001 §18 G7.)

_ce_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/tools" "$d/.claude"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  cp "$PROJECT_ROOT/tools/preset" "$d/tools/preset" 2>/dev/null
  cp "$PROJECT_ROOT/tools/check-layers.sh" "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/layers.conf" "$d/tools/" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo seed > seed.txt; git add seed.txt; git commit -qm init 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_run() { echo '{}' | bash scripts/agent-hooks/canon-enforce.sh >/dev/null 2>&1; echo $?; }

# ── EL FALSO POSITIVO QUE MOTIVÓ ESTE ARCHIVO ───────────────────────
_case_detector_no_se_bloquea_a_si_mismo() {
  # El propio canon-enforce está en el árbol de trabajo (recién copiado y sin
  # commitear) y contiene sus patrones de detección. No debe autodetectarse.
  git add -A 2>/dev/null
  local rc; rc="$(_run)"
  [ "$rc" = "0" ] || { echo "    el detector de secretos se bloqueó a SÍ MISMO (exit=$rc)"; return 1; }
}
test_el_detector_no_se_detecta_a_si_mismo() { _ce_sandbox _case_detector_no_se_bloquea_a_si_mismo; }

_case_archivo_de_patrones_excluido() {
  # `.claude/security-patterns.yaml` declara los prefijos de credencial. Está
  # LLENO de cosas que parecen secretos, y es correcto que lo esté.
  cat > .claude/security-patterns.yaml <<'EOF'
patterns:
  - rule_name: secreto_por_prefijo
    substrings: ["sk-", "AKIA", "ghp_", "service_role"]
    reminder: "Credencial hardcodeada."
EOF
  git add -A 2>/dev/null
  local rc; rc="$(_run)"
  [ "$rc" = "0" ] || { echo "    el archivo que DEFINE los patrones fue marcado como secreto (exit=$rc)"; return 1; }
}
test_archivo_de_definicion_de_patrones_excluido() { _ce_sandbox _case_archivo_de_patrones_excluido; }

# ── …pero el gate SIGUE detectando de verdad ────────────────────────
_case_secreto_real_bloquea() {
  mkdir -p src
  printf 'let key = "AKIAIOSFODNN7EXAMPLE"\n' > src/Config.swift
  git add -A 2>/dev/null
  local rc; rc="$(_run)"
  [ "$rc" = "2" ] || { echo "    un secreto REAL en código no bloqueó (exit=$rc)"; return 1; }
}
test_secreto_real_en_codigo_bloquea() { _ce_sandbox _case_secreto_real_bloquea; }

_case_storage_inseguro_bloquea() {
  mkdir -p src
  printf 'UserDefaults.standard.set(authToken, forKey: "token")\n' > src/Store.swift
  git add -A 2>/dev/null
  local rc; rc="$(_run)"
  [ "$rc" = "2" ] || { echo "    un token en storage en claro no bloqueó (exit=$rc)"; return 1; }
}
test_token_en_storage_en_claro_bloquea() { _ce_sandbox _case_storage_inseguro_bloquea; }

_case_violacion_de_capa_bloquea() {
  mkdir -p src/Domain
  printf 'import SwiftUI\n\nstruct User {}\n' > src/Domain/User.swift
  git add -A 2>/dev/null
  local rc; rc="$(_run)"
  [ "$rc" = "2" ] || { echo "    una violación de capas no bloqueó el cierre (exit=$rc)"; return 1; }
}
test_violacion_de_capas_bloquea_el_cierre() { _ce_sandbox _case_violacion_de_capa_bloquea; }

# ── otros bordes de falso positivo ──────────────────────────────────
_case_ejemplo_en_markdown_no_bloquea() {
  mkdir -p docs
  printf 'Nunca escribas `AKIAIOSFODNN7EXAMPLE` en el código.\n' > docs/guia.md
  git add -A 2>/dev/null
  local rc; rc="$(_run)"
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: un ejemplo en documentación bloqueó (exit=$rc)"; return 1; }
}
test_ejemplo_en_documentacion_no_bloquea() { _ce_sandbox _case_ejemplo_en_markdown_no_bloquea; }

_case_archivo_example_no_bloquea() {
  printf 'API_KEY=sk-ejemplonoesrealsolounplaceholder\n' > .env.example
  git add -A 2>/dev/null
  local rc; rc="$(_run)"
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: un .example bloqueó (exit=$rc)"; return 1; }
}
test_archivo_example_no_bloquea() { _ce_sandbox _case_archivo_example_no_bloquea; }

_case_repo_limpio_no_bloquea() {
  local rc; rc="$(_run)"
  [ "$rc" = "0" ] || { echo "    un repo sin cambios bloqueó el cierre (exit=$rc)"; return 1; }
}
test_repo_limpio_no_bloquea() { _ce_sandbox _case_repo_limpio_no_bloquea; }

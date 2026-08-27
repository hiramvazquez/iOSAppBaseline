#!/usr/bin/env bash
# Backlog runner (PRD 0003) — SELECTOR (`tools/backlog/next.sh`): decide QUÉ
# historia trabaja un agente sin supervisión — sus falsos positivos son caros
# en las dos direcciones: elegir una historia que no tocaba (deps sin
# mergear, ejemplos del template) o saltarse una legítima. Incluye el caso
# f-runner-retrabaja: el estado real de una historia vive en su RAMA, no solo
# en la base (una historia in-review no se re-ofrece; una a medias sí).
#
# Split de tools/tests/test_backlog.sh (hard limit de 400 líneas, AGENTS.md
# §4) — parte 1/4. Hermanos: test_backlog_run_isolation.sh,
# test_backlog_run_completion.sh, test_backlog_criteria.sh,
# test_backlog_scope.sh (aparte, prueba solo el checker de scope).

_bl_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/backlog" "$d/tools/agent-backends" "$d/tools/agent-prompts" \
    "$d/scripts/agent-hooks/lib" "$d/backlog"
  cp "$PROJECT_ROOT/tools/backlog/next.sh" "$d/tools/backlog/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/backlog/run.sh" "$d/tools/backlog/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/backlog/criteria-link.sh" "$d/tools/backlog/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/backlog/scope-check.sh" "$d/tools/backlog/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/agent-runner.sh" "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/check-review-marker.sh" "$d/tools/" 2>/dev/null
  cp -R "$PROJECT_ROOT/tools/agent-backends/." "$d/tools/agent-backends/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/agent-prompts/"*.md "$d/tools/agent-prompts/" 2>/dev/null
  cp "$PROJECT_ROOT/scripts/agent-hooks/lib/verdict.sh" "$d/scripts/agent-hooks/lib/" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q -b develop . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo seed > seed.txt; git add -A; git commit -qm init 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}
_story() { # _story <archivo> <id> <status> <deps>
  cat > "backlog/$1" <<EOF
---
id: $2
titulo: Historia $2
status: $3
depends_on: [$4]
base: develop
scope: |
  **
---
## Criterios de aceptación
1. Dado X cuando Y entonces Z.

## Verificación de criterios
1. n/a-manual — historia de juguete del harness, sin código que verificar
EOF
}

# ── selección básica ────────────────────────────────────────────────
_case_elige_primera_ready() {
  _story 0001-a.md 0001 done ""
  _story 0002-b.md 0002 ready ""
  _story 0003-c.md 0003 ready ""
  local out; out="$(bash tools/backlog/next.sh)"
  case "$out" in *0002-b.md) return 0 ;; esac
  echo "    eligió '$out' (esperaba 0002-b.md, la primera ready)"; return 1
}
test_elige_la_primera_ready() { _bl_sandbox _case_elige_primera_ready; }

# ── FALSO POSITIVO guard: ejemplos y terminadas NO se eligen ────────
_case_ignora_ejemplos_y_terminadas() {
  _story 0001-ej.md 0001 ejemplo ""
  _story 0002-done.md 0002 done ""
  _story 0003-rev.md 0003 in-review ""
  local out; out="$(bash tools/backlog/next.sh)"
  [ -z "$out" ] || { echo "    FALSO POSITIVO: eligió '$out' sin haber historias ready"; return 1; }
}
test_ignora_ejemplos_y_no_ready() { _bl_sandbox _case_ignora_ejemplos_y_terminadas; }

# ── dependencias: solo desbloquea el DONE (= mergeado a base) ───────
_case_dep_pendiente_bloquea() {
  _story 0001-a.md 0001 in-review ""
  _story 0002-b.md 0002 ready "0001"
  local out; out="$(bash tools/backlog/next.sh)"
  [ -z "$out" ] || { echo "    eligió '$out' con su dependencia 0001 aún sin mergear (in-review)"; return 1; }
}
test_dependencia_sin_done_bloquea() { _bl_sandbox _case_dep_pendiente_bloquea; }

_case_dep_done_desbloquea() {
  _story 0001-a.md 0001 done ""
  _story 0002-b.md 0002 ready "0001"
  local out; out="$(bash tools/backlog/next.sh)"
  case "$out" in *0002-b.md) return 0 ;; esac
  echo "    con la dep en done, no eligió 0002 (out='$out')"; return 1
}
test_dependencia_done_desbloquea() { _bl_sandbox _case_dep_done_desbloquea; }

_case_salta_bloqueada_y_toma_siguiente() {
  _story 0001-a.md 0001 ready "0009"     # dep inexistente → no elegible
  _story 0002-b.md 0002 ready ""
  local out; out="$(bash tools/backlog/next.sh)"
  case "$out" in *0002-b.md) return 0 ;; esac
  echo "    no saltó a la siguiente elegible (out='$out')"; return 1
}
test_salta_la_bloqueada_y_toma_la_siguiente() { _bl_sandbox _case_salta_bloqueada_y_toma_siguiente; }

_case_sin_backlog_silencio() {
  rm -rf backlog
  bash tools/backlog/next.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    sin backlog/ devolvió error (debe ser no-op apto para cron)"; return 1; }
}
test_sin_backlog_es_noop() { _bl_sandbox _case_sin_backlog_silencio; }

# ════════════════════════════════════════════════════════════════════
# f-runner-retrabaja — el estado real no está solo en la rama base
# ════════════════════════════════════════════════════════════════════
# El `in-review` lo commitea el runner DENTRO de story/NNNN, así que desde
# develop una historia terminada sigue diciendo `ready` y el selector la
# devolvía otra vez. Con el humano tardando en mergear —el escenario para el
# que existe un runner desatendido— eso es rehacer trabajo ya verificado, y
# mientras tanto no avanzar a la siguiente.
_rama_con_estado() { # _rama_con_estado <rama> <archivo> <estado>
  local actual; actual="$(git rev-parse --abbrev-ref HEAD)"
  git checkout -q -b "$1" 2>/dev/null || git checkout -q "$1"
  sed -i.bak "s/^status: .*/status: $3/" "$2" && rm -f "$2.bak"
  git add -A >/dev/null 2>&1; git commit -qm "estado $3 en $1" >/dev/null 2>&1
  git checkout -q "$actual"
}

_case_terminada_en_su_rama_no_se_reofrece() {
  _story 0005-e.md 0005 ready ""
  _story 0006-f.md 0006 ready ""
  git add -A >/dev/null 2>&1; git commit -qm "backlog" >/dev/null 2>&1
  _rama_con_estado story/0005-e backlog/0005-e.md in-review
  local out; out="$(bash tools/backlog/next.sh 2>/dev/null)"
  case "$out" in *0005-e.md)
    echo "    re-ofreció una historia TERMINADA que espera merge (~rehacerla desde cero)"; return 1 ;;
  esac
  case "$out" in *0006-f.md) return 0 ;; esac
  echo "    saltó la 0005 pero tampoco avanzó a la 0006 (el backlog se para): '$out'"
  return 1
}
test_historia_terminada_en_rama_no_se_reofrece_y_avanza() {
  _bl_sandbox _case_terminada_en_su_rama_no_se_reofrece
}

_case_trabajo_a_medias_si_se_retoma() {
  # La otra cara, y la que hace peligroso el arreglo ingenuo ("saltar si existe
  # la rama"): un run que se cortó deja la rama en `in-progress`. Si el selector
  # la saltara, esa historia quedaría huérfana PARA SIEMPRE — nadie la volvería
  # a ofrecer nunca. Se devuelve: run.sh sabe retomar el worktree.
  _story 0005-e.md 0005 ready ""
  git add -A >/dev/null 2>&1; git commit -qm "backlog" >/dev/null 2>&1
  _rama_con_estado story/0005-e backlog/0005-e.md in-progress
  local out; out="$(bash tools/backlog/next.sh 2>/dev/null)"
  case "$out" in *0005-e.md) return 0 ;; esac
  echo "    una historia a MEDIAS quedó huérfana: nadie la volverá a ofrecer ('$out')"
  return 1
}
test_historia_a_medias_se_sigue_ofreciendo_para_retomarla() {
  _bl_sandbox _case_trabajo_a_medias_si_se_retoma
}

_case_mergeada_sin_marcar_avisa() {
  # Si el humano mergea y olvida poner `done` en la base, las dependientes no
  # se desbloquean nunca y el backlog se para sin que nadie vea por qué.
  _story 0005-e.md 0005 in-review ""
  _story 0006-f.md 0006 ready "0005"
  git add -A >/dev/null 2>&1; git commit -qm "backlog" >/dev/null 2>&1
  local err; err="$(bash tools/backlog/next.sh 2>&1 >/dev/null)"
  case "$err" in *"MERGEADA"*|*"status: done"*) return 0 ;; esac
  echo "    no avisó de la historia mergeada sin marcar (el backlog se para en silencio)"
  return 1
}
test_mergeada_sin_marcar_done_se_avisa() { _bl_sandbox _case_mergeada_sin_marcar_avisa; }

_case_sin_ramas_todo_igual() {
  # FALSO POSITIVO guard: sin ninguna rama story/*, el selector se comporta
  # exactamente como antes. El arreglo no puede cambiar el caso normal.
  _story 0001-a.md 0001 done ""
  _story 0002-b.md 0002 ready ""
  git add -A >/dev/null 2>&1; git commit -qm "backlog" >/dev/null 2>&1
  local out; out="$(bash tools/backlog/next.sh 2>/dev/null)"
  case "$out" in *0002-b.md) return 0 ;; esac
  echo "    sin ramas, el selector cambió de comportamiento: '$out'"; return 1
}
test_sin_ramas_el_selector_no_cambia() { _bl_sandbox _case_sin_ramas_todo_igual; }

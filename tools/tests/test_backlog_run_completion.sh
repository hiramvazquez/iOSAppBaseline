#!/usr/bin/env bash
# Backlog runner (PRD 0003) — CIERRE de `tools/backlog/run.sh`: "cerrar no es
# salir con 0" (f-run-a-medias-exit0). El exit code de un sub-proceso dice
# que el proceso terminó, no que el trabajo esté hecho — se exige commit real
# (no solo `claude -p` con rc=0) y, en el backend `fake`, evidencia de review
# ligada al mismo staged SHA antes de dejar entrar un commit de producto.
#
# Split de tools/tests/test_backlog.sh (hard limit de 400 líneas, AGENTS.md
# §4) — parte 3/4. Hermanos: test_backlog_selection.sh,
# test_backlog_run_isolation.sh, test_backlog_criteria.sh,
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

_case_run_con_trabajo_sin_commitear_no_es_in_review() {
  # Cazado en vivo: el agente lanzó la suite en background, dijo "me notificará
  # al terminar" y acabó su turno. `claude -p` salió con 0 → la historia quedaba
  # in-review y el runner exit 0, con 691 líneas sin commitear que ni siquiera
  # salían en `git diff base...rama`. El exit code de un sub-proceso dice que el
  # proceso terminó, no que el trabajo esté hecho.
  _story 0001-a.md 0001 ready ""
  git add backlog/0001-a.md; git commit -qm historia
  mkdir -p bin
  printf '#!/usr/bin/env bash\nprintf "adapter a medias\\n" > Adapter.swift\nexit 0\n' > bin/claude
  chmod +x bin/claude
  local rc; PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh >/dev/null 2>&1; rc=$?
  [ "$rc" != "0" ] || { echo "    un run que dejó trabajo sin commitear salió con 0 (parece terminado)"; return 1; }
  local st; st="$(git show story/0001-a:backlog/0001-a.md 2>/dev/null | grep '^status:')"
  case "$st" in *in-review*) echo "    quedó marcada in-review con trabajo sin commitear ($st)"; return 1 ;; esac
  case "$st" in *in-progress*) : ;; *) echo "    no volvió a in-progress ($st)"; return 1 ;; esac
  [ -f ".agents/worktrees/story-0001-a/Adapter.swift" ] \
    || { echo "    el trabajo pendiente desapareció del worktree"; return 1; }
  ls .agents/state/backlog/0001-pendiente-*/Adapter.swift >/dev/null 2>&1 \
    || { echo "    no se respaldó el trabajo pendiente (se pierde si alguien poda el worktree)"; return 1; }
}
test_run_que_deja_trabajo_sin_commitear_no_cierra() {
  _bl_sandbox _case_run_con_trabajo_sin_commitear_no_es_in_review
}

_case_run_limpio_si_cierra() {
  # FALSO POSITIVO guard: el caso normal —el agente commitea lo suyo— tiene que
  # seguir cerrando en in-review. Un gate que bloquea también al que hace las
  # cosas bien se desactiva en una semana.
  _story 0001-a.md 0001 ready ""
  git add backlog/0001-a.md; git commit -qm historia
  mkdir -p bin
  printf '#!/usr/bin/env bash\ncase " $* " in *" --permission-mode plan "*) printf "{\\"result\\":\\"VERDICT: GREEN\\\\\\\\nFINDINGS: 0\\\\\\\\nSCOPE: fake-claude\\"}\\n"; exit 0;; esac\nprintf "hecho\\n" > Adapter.swift\ngit add -A >/dev/null 2>&1\ngit -c user.email=a@a -c user.name=a commit -qm "feat: adapter" >/dev/null 2>&1\nexit 0\n' > bin/claude
  chmod +x bin/claude
  local rc; PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || { echo "    un run LIMPIO fue rechazado (rc=$rc)"; return 1; }
  local st; st="$(git show story/0001-a:backlog/0001-a.md 2>/dev/null | grep '^status:')"
  case "$st" in *in-review*) return 0 ;; esac
  echo "    un run limpio no cerró en in-review ($st)"; return 1
}
test_run_limpio_si_cierra_en_in_review() { _bl_sandbox _case_run_limpio_si_cierra; }

_case_backend_fake_sin_claude() {
  _story 0001-a.md 0001 ready ""
  git add backlog/0001-a.md; git commit -qm historia
  printf '#!/usr/bin/env bash\ngrep -q "AGENTS.md es la fuente canónica" "$1" || exit 8\ngrep -q "id: 0001" "$1" || exit 9\nprintf "hecho\\n" > Adapter.swift\ngit add -A\nbash tools/agent-backends/fake-evidence.sh approve || exit 10\ngit -c user.email=a@a -c user.name=a commit -qm "feat: adapter"\n' \
    > fake-run.sh; chmod +x fake-run.sh
  local rc evidence="$PWD/fake-evidence.log"
  PATH="/usr/bin:/bin" FAKE_RUN_SCRIPT="$PWD/fake-run.sh" \
    FAKE_AUTONOMY_EVIDENCE="$evidence" \
    bash tools/backlog/run.sh --backend fake >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] || { echo "    backlog con fake y sin claude falló rc=$rc"; return 1; }
  git show story/0001-a:backlog/0001-a.md | grep -q '^status: in-review' \
    || { echo "    el backend fake no llegó a in-review"; return 1; }
  ls .agents/state/backlog/0001-review-*.log >/dev/null 2>&1 \
    || { echo "    falta evidencia persistida de la review final"; return 1; }
  local approved committed
  approved="$(grep '^approved:' "$evidence")"; committed="$(grep '^committed:' "$evidence")"
  [ "${approved#approved:}" = "${committed#committed:}" ] \
    || { echo "    review y commit no quedaron ligados al mismo staged SHA"; return 1; }
}
test_backlog_funciona_con_fake_sin_claude() { _bl_sandbox _case_backend_fake_sin_claude; }

_case_review_fake_red_no_cierra() {
  _story 0001-a.md 0001 ready ""
  git add backlog/0001-a.md; git commit -qm historia
  printf '#!/usr/bin/env bash\nprintf "hecho\\n" > Adapter.swift\ngit add -A\nbash tools/agent-backends/fake-evidence.sh approve\ngit -c user.email=a@a -c user.name=a commit -qm "feat: adapter"\n' \
    > fake-run.sh; chmod +x fake-run.sh
  FAKE_RUN_SCRIPT="$PWD/fake-run.sh" \
    FAKE_AUTONOMY_EVIDENCE="$PWD/fake-evidence.log" \
    FAKE_REVIEW_RESULT=$'VERDICT: RED\nFINDINGS: 1\nSCOPE: fake-red' \
    bash tools/backlog/run.sh --backend fake >/dev/null 2>&1
  local rc=$? st
  [ "$rc" = 7 ] || { echo "    review RED devolvió $rc, no 7"; return 1; }
  st="$(git show story/0001-a:backlog/0001-a.md | grep '^status:')"
  case "$st" in *in-progress*) return 0 ;; esac
  echo "    review RED dejó la historia como $st"; return 1
}
test_review_final_red_impide_in_review() { _bl_sandbox _case_review_fake_red_no_cierra; }

_case_fake_sin_evidencia_no_commitea_producto() {
  _story 0001-a.md 0001 ready ""
  git add backlog/0001-a.md; git commit -qm historia
  printf '#!/usr/bin/env bash\nprintf "sin review\\n" > Adapter.swift\ngit add -A\ngit -c user.email=a@a -c user.name=a commit -qm "feat: sin review"\n' \
    > fake-run.sh; chmod +x fake-run.sh
  FAKE_RUN_SCRIPT="$PWD/fake-run.sh" FAKE_AUTONOMY_EVIDENCE="$PWD/fake-evidence.log" \
    bash tools/backlog/run.sh --backend fake >/dev/null 2>&1
  [ "$?" != 0 ] || { echo "    fake permitió commit de producto sin evidencia previa"; return 1; }
  git -C .agents/worktrees/story-0001-a log --format=%s | grep -q 'feat: sin review' \
    && { echo "    el commit sin review sí entró a la rama"; return 1; }
  return 0
}
test_fake_bloquea_commit_de_producto_sin_evidencia() {
  _bl_sandbox _case_fake_sin_evidencia_no_commitea_producto
}

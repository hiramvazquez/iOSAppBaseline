#!/usr/bin/env bash
# Backlog runner (PRD 0003) — GUARDS de `tools/backlog/run.sh` sobre el
# CONTRATO WORKTREE: el checkout del humano es intocable, y nada que ocurra
# DENTRO del agente sin supervisión (scope creep, PATH shadowing, checker
# sustituido, ref base mutada, anchors sucios) puede colar una historia hasta
# in-review. Incluye el guard de "sin criterios de aceptación → blocked,
# no improvisación" (§1.4).
#
# Split de tools/tests/test_backlog.sh (hard limit de 400 líneas, AGENTS.md
# §4) — parte 2/4. Hermanos: test_backlog_selection.sh,
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

# ── guards del runner (contrato WORKTREE: el checkout del humano es intocable) ─
_fake_claude() { # instala un claude falso que registra invocaciones en $CLAUDE_LOG
  mkdir -p bin
  printf '#!/usr/bin/env bash\ncase " $* " in *" --permission-mode plan "*) printf "{\\"result\\":\\"VERDICT: GREEN\\\\\\\\nFINDINGS: 0\\\\\\\\nSCOPE: fake-claude\\"}\\n"; exit 0;; esac\n[ -n "${CLAUDE_LOG:-}" ] && echo run >> "$CLAUDE_LOG"\nexit 0\n' > bin/claude
  chmod +x bin/claude
}

_case_arbol_sucio_ya_no_bloquea() {
  # ANTES: guard duro (exit 1). AHORA el worktree aísla: el run procede y los
  # cambios sucios del humano quedan EXACTAMENTE como estaban.
  _story 0001-a.md 0001 ready ""
  git add backlog/0001-a.md; git commit -qm historia
  echo dirty > seed.txt
  _fake_claude
  local out rc
  out="$(PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || { echo "    con worktrees, el árbol sucio no debería bloquear (rc=$rc): $out"; return 1; }
  [ "$(cat seed.txt)" = "dirty" ] || { echo "    el run TOCÓ los cambios sin commitear del humano"; return 1; }
}
test_arbol_sucio_ya_no_bloquea() { _bl_sandbox _case_arbol_sucio_ya_no_bloquea; }

_case_checkout_humano_intacto() {
  _story 0001-a.md 0001 ready ""
  git add backlog/0001-a.md; git commit -qm historia
  _fake_claude
  PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh >/dev/null 2>&1
  [ "$(git rev-parse --abbrev-ref HEAD)" = "develop" ] \
    || { echo "    el run CAMBIÓ la rama del checkout del humano ($(git rev-parse --abbrev-ref HEAD))"; return 1; }
  grep -q "status: ready" backlog/0001-a.md \
    || { echo "    el estado cambió en la BASE antes del merge (debe cambiar solo en la rama)"; return 1; }
  git rev-parse --verify story/0001-a >/dev/null 2>&1 \
    || { echo "    no existe la rama de la historia"; return 1; }
  local st; st="$(git show story/0001-a:backlog/0001-a.md | grep '^status:')"
  case "$st" in *in-review*) : ;; *) echo "    en la rama la historia no quedó in-review ($st)"; return 1 ;; esac
}
test_checkout_del_humano_queda_intacto() { _bl_sandbox _case_checkout_humano_intacto; }

_case_scope_bloquea_antes_de_in_review() {
  _story 0001-a.md 0001 ready ""
  python3 - <<'PY'
p='backlog/0001-a.md'
s=open(p).read().replace('scope: |\n  **', 'scope: |\n  src/allowed.txt')
open(p,'w').write(s)
PY
  git add backlog/0001-a.md; git commit -qm historia
  mkdir -p bin
  cat > bin/claude <<'EOF'
#!/usr/bin/env bash
printf 'scope creep\n' >> seed.txt
git add seed.txt
git -c user.email=t@t.t -c user.name=t commit -qm 'feat: fuera de scope'
EOF
  chmod +x bin/claude
  local out rc
  out="$(PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh 2>&1)"; rc=$?
  [ "$rc" = "6" ] || { echo "    scope creep terminó con rc=$rc, esperaba 6: $out"; return 1; }
  local st
  st="$(git show story/0001-a:backlog/0001-a.md | grep '^status:')"
  case "$st" in *in-progress*) return 0 ;; esac
  echo "    historia fuera de scope quedó $st en vez de in-progress"
  return 1
}
test_run_no_llega_a_in_review_con_diff_fuera_de_scope() {
  _bl_sandbox _case_scope_bloquea_antes_de_in_review
}

_case_checker_de_la_rama_no_es_confiable() {
  _story 0001-a.md 0001 ready ""
  python3 - <<'PY'
p='backlog/0001-a.md'
s=open(p).read().replace('scope: |\n  **', 'scope: |\n  src/allowed.txt')
open(p,'w').write(s)
PY
  git add backlog/0001-a.md; git commit -qm historia
  mkdir -p bin
  cat > bin/claude <<'EOF'
#!/usr/bin/env bash
printf '#!/usr/bin/env bash\nexit 0\n' > tools/backlog/scope-check.sh
chmod +x tools/backlog/scope-check.sh
printf 'scope creep\n' >> seed.txt
git add tools/backlog/scope-check.sh seed.txt
git -c user.email=t@t.t -c user.name=t commit -qm 'feat: reemplaza el juez'
EOF
  chmod +x bin/claude
  local out rc
  out="$(PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh 2>&1)"; rc=$?
  [ "$rc" = "6" ] || { echo "    checker sustituido terminó rc=$rc: $out"; return 1; }
}
test_runner_usa_checker_fijado_antes_del_agente() { _bl_sandbox _case_checker_de_la_rama_no_es_confiable; }

_case_path_no_sustituye_interpretes_del_gate() {
  _story 0001-a.md 0001 ready ""
  python3 - <<'PY'
p='backlog/0001-a.md'
s=open(p).read().replace('scope: |\n  **', 'scope: |\n  src/allowed.txt')
open(p,'w').write(s)
PY
  git add backlog/0001-a.md; git commit -qm historia
  mkdir -p bin
  cat > bin/claude <<'EOF'
#!/usr/bin/env bash
real_git="$(command -v git)"
printf 'scope creep\n' >> seed.txt
"$real_git" add seed.txt
"$real_git" -c user.email=t@t.t -c user.name=t commit -qm 'feat: fuera de scope'
attack_dir="$(cd "$(dirname "$0")" && pwd)"
for name in bash python3 git; do
  printf '#!/bin/sh\nexit 0\n' > "$attack_dir/$name"
  chmod +x "$attack_dir/$name"
done
EOF
  chmod +x bin/claude
  local out rc
  out="$(PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh 2>&1)"; rc=$?
  [ "$rc" = "6" ] || { echo "    PATH shadowing terminó rc=$rc: $out"; return 1; }
  assert_contains "$out" 'seed.txt'
}
test_runner_fija_bash_python_y_git_antes_del_agente() { _bl_sandbox _case_path_no_sustituye_interpretes_del_gate; }

_case_anchor_sucio_no_es_autoridad() {
  _story 0001-a.md 0001 ready ""
  git add backlog/0001-a.md; git commit -qm historia
  printf '\n# cambio local no auditado\n' >> tools/backlog/scope-check.sh
  _fake_claude
  local out rc
  out="$(PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh 2>&1)"; rc=$?
  [ "$rc" = "1" ] || { echo "    checker sucio terminó rc=$rc: $out"; return 1; }
  assert_contains "$out" 'deben estar commiteados y limpios'
  git rev-parse --verify story/0001-a >/dev/null 2>&1 \
    && { echo "    creó rama con anchors sucios"; return 1; }
  return 0
}
test_checker_o_historia_sucios_no_se_vuelven_autoridad() { _bl_sandbox _case_anchor_sucio_no_es_autoridad; }

_case_scope_no_se_puede_ampliar_durante_run() {
  _story 0001-a.md 0001 ready ""
  python3 - <<'PY'
p='backlog/0001-a.md'
s=open(p).read().replace('scope: |\n  **', 'scope: |\n  src/allowed.txt')
open(p,'w').write(s)
PY
  git add backlog/0001-a.md; git commit -qm historia
  mkdir -p bin
  cat > bin/claude <<'EOF'
#!/usr/bin/env bash
python3 - <<'PY'
p='backlog/0001-a.md'
s=open(p).read().replace('  src/allowed.txt', '  **')
open(p,'w').write(s)
PY
printf 'scope creep\n' >> seed.txt
git add backlog/0001-a.md seed.txt
git -c user.email=t@t.t -c user.name=t commit -qm 'feat: amplía scope'
EOF
  chmod +x bin/claude
  local out rc
  out="$(PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh 2>&1)"; rc=$?
  [ "$rc" = "6" ] || { echo "    scope ampliado terminó rc=$rc: $out"; return 1; }
}
test_runner_fija_scope_antes_del_agente() { _bl_sandbox _case_scope_no_se_puede_ampliar_durante_run; }

_case_base_mutada_no_oculta_diff() {
  _story 0001-a.md 0001 ready ""
  git add backlog/0001-a.md; git commit -qm historia
  mkdir -p bin
  cat > bin/claude <<'EOF'
#!/usr/bin/env bash
printf 'cambio\n' >> seed.txt
git add seed.txt
git -c user.email=t@t.t -c user.name=t commit -qm 'feat: cambio'
git update-ref refs/heads/develop HEAD
EOF
  chmod +x bin/claude
  local out rc
  out="$(PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh 2>&1)"; rc=$?
  [ "$rc" = "3" ] || { echo "    base mutada terminó rc=$rc: $out"; return 1; }
  assert_contains "$out" 'ref base develop cambió'
}
test_runner_detecta_mutacion_de_la_ref_base() { _bl_sandbox _case_base_mutada_no_oculta_diff; }

_case_in_review_no_se_retrabaja() {
  _story 0001-a.md 0001 ready ""
  git add backlog/0001-a.md; git commit -qm historia
  _fake_claude
  export CLAUDE_LOG="$PWD/runs.log"
  PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh >/dev/null 2>&1   # 1º: trabaja → in-review
  PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh >/dev/null 2>&1   # 2º: debe SALTARLA
  local n; n="$(wc -l < runs.log | tr -d ' ')"
  unset CLAUDE_LOG
  [ "$n" = "1" ] || { echo "    una historia in-review fue RE-trabajada ($n invocaciones de claude, esperaba 1)"; return 1; }
}
test_historia_in_review_no_se_retrabaja() { _bl_sandbox _case_in_review_no_se_retrabaja; }

_case_sin_claude_exit3() {
  _story 0001-a.md 0001 ready ""
  PATH="/usr/bin:/bin" bash tools/backlog/run.sh >/dev/null 2>&1
  local rc=$?
  [ "$rc" = "3" ] || { echo "    sin binario claude no dio exit 3 (rc=$rc)"; return 1; }
  grep -q "status: ready" backlog/0001-a.md || { echo "    la historia cambió de estado sin haberse trabajado"; return 1; }
  git rev-parse --verify story/0001 >/dev/null 2>&1 && { echo "    creó la rama pese a no poder trabajar"; return 1; }
  return 0
}
test_sin_claude_exit3_e_historia_intacta() { _bl_sandbox _case_sin_claude_exit3; }

# ── historia sin criterios de aceptación → blocked, no improvisación ─
_case_sin_criterios_se_bloquea() {
  cat > backlog/0001-vacia.md <<'EOF'
---
id: 0001
titulo: Historia sin criterios
status: ready
depends_on: []
base: develop
---
Hacer algo, ya tal.
EOF
  _fake_claude
  PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/backlog/run.sh >/dev/null 2>&1
  grep -q "status: blocked" backlog/0001-vacia.md \
    || { echo "    una historia SIN criterios de aceptación no quedó blocked (§1.4: no se improvisa)"; return 1; }
}
test_historia_sin_criterios_queda_blocked() { _bl_sandbox _case_sin_criterios_se_bloquea; }

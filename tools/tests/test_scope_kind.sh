#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# WF-05 (PRD 0005 §6): la DECLARACIÓN gobierna; la evidencia solo verifica
# ════════════════════════════════════════════════════════════════════
# `tools/project.conf` declara `project_kind: harness|application|other`.
# Estos tests fijan la tabla de exits de §6: quién gobierna el criterio de
# producto, cuándo la contradicción declarado-vs-evidencia AVISA, y que el
# exit 3 ocurre SOLO en CI (CI=true o GATES_*). El caso "sin declarar"
# conserva la heurística vieja byte a byte: cero falsos positivos nuevos
# en los adoptantes existentes (gate de cierre de la fase 1b).

_sk_sandbox() { # _sk_sandbox <función> — repo desechable con lib + consumidores
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/lib" "$d/.agents/state/markers"
  cp "$PROJECT_ROOT/tools/lib/scope.sh" "$d/tools/lib/"
  cp "$PROJECT_ROOT/tools/check-review-marker.sh" "$d/tools/"
  cp "$PROJECT_ROOT/tools/check-verify-marker.sh" "$d/tools/"
  (
    cd "$d" || exit 1
    # `git -C "$d"` y ruta ABSOLUTA a propósito. La versión anterior stageaba
    # con ruta relativa apoyándose en el `cd`: si ese `cd` fallara, apuntaría al
    # REPO REAL. Y ocurrió — apareció un `seed.txt` en el índice de verdad,
    # dentro del diff que se iba a commitear, y lo cazó un reviewer al mirar ese
    # diff. La causa exacta no se pudo atribuir (el sandbox de un sub-agente
    # replicaba este mismo helper), así que el arreglo no es "tener más cuidado"
    # sino quitarle al comando la posibilidad de apuntar fuera del sandbox.
    git -C "$d" init -q . 2>/dev/null
    git -C "$d" config user.email t@t.t
    git -C "$d" config user.name t
    echo seed > "$d/seed.txt"
    git -C "$d" stage seed.txt 2>/dev/null || git -C "$d" add -- seed.txt
    git -C "$d" commit -qm init 2>/dev/null
    # Entorno determinista: CI/GATES_* se controlan EXPLÍCITAMENTE por caso
    # (en GitHub Actions CI=true viene puesto y cambiaría el resultado).
    unset CI SCOPE_NO_CI_EXIT 2>/dev/null
    local _v; for _v in $(env | sed -n 's/^\(GATES_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$_v"; done
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}
_sk_regex() { ( . tools/lib/scope.sh; scope_non_product ) 2>/dev/null; }
_sk_source_stderr() { ( . tools/lib/scope.sh ) 2>&1 >/dev/null; }
_sk_es_prod() { printf '%s\n' "$1" | grep -qvE "$(_sk_regex)"; }
# La declaración se COMMITEA: una declaración real vive trackeada en el repo
# (el checkout de CI solo contiene archivos trackeados — ver el guard del
# conf sin trackear, abajo). Dejarla solo staged la convertiría en producto
# pendiente de review dentro del propio fixture.
_sk_declara() {
  printf 'project_kind: %s\n' "$1" > tools/project.conf
  git add tools/project.conf 2>/dev/null
  git commit -qm "declara project_kind: $1" >/dev/null 2>&1
}

# ── Fila 1: la declaración GOBIERNA (monorepo, el contraejemplo real) ──
# La heurística vieja no mira packages/: sin declaración clasificaba un
# monorepo como harness. Declarado `application`, manda la declaración y
# —golden 4 del PRD— NO hay ni un aviso, porque la evidencia coincide.
_sk_case_monorepo_application() {
  mkdir -p packages/svc/src; printf 'export {}\n' > packages/svc/src/x.ts
  _sk_declara application
  _sk_es_prod packages/svc/src/x.ts || { echo "    el código del monorepo dejó de ser producto"; return 1; }
  _sk_es_prod tools/check-review-marker.sh && { echo "    declarado application, tools/ sigue siendo producto (gobernó la heurística, no la declaración)"; return 1; }
  local err; err="$(_sk_source_stderr)"
  [ -z "$err" ] || { echo "    monorepo coherente y aun así avisó: [$err]"; return 1; }
  return 0
}
test_monorepo_declarado_application_gobierna_sin_aviso() { _sk_sandbox _sk_case_monorepo_application; }

# ── Fila 3: harness declarado MANDA aunque haya fuentes de app ──────
_sk_case_harness_manda() {
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  _sk_declara harness
  _sk_es_prod tools/check-review-marker.sh || { echo "    declarado harness, tools/ quedó exento (mandó la evidencia)"; return 1; }
}
test_declarado_harness_manda_aunque_haya_fuentes() { _sk_sandbox _sk_case_harness_manda; }

# ── Filas 3 y 4: la contradicción emite SCOPE_SUMMARY + aviso ───────
_sk_case_contradiccion_harness() {
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  _sk_declara harness
  local err; err="$(_sk_source_stderr)"
  case "$err" in *"SCOPE_SUMMARY kind=harness evidencia=contradice"*) : ;; *)
    echo "    la contradicción no emitió SCOPE_SUMMARY: [$err]"; return 1 ;; esac
}
test_harness_con_fuentes_emite_scope_summary() { _sk_sandbox _sk_case_contradiccion_harness; }

_sk_case_contradiccion_application() {
  _sk_declara application            # sin una sola fuente de app
  local err; err="$(_sk_source_stderr)"
  case "$err" in *"SCOPE_SUMMARY kind=application evidencia=contradice"*) : ;; *)
    echo "    application sin fuentes no emitió SCOPE_SUMMARY: [$err]"; return 1 ;; esac
  _sk_es_prod tools/check-review-marker.sh && { echo "    la contradicción cambió el criterio (fila 4: manda la declaración)"; return 1; }
  return 0
}
test_application_sin_fuentes_contradice_pero_manda() { _sk_sandbox _sk_case_contradiccion_application; }

# ── exit 3 SOLO en CI, y por los DOS consumidores reales ────────────
_sk_case_ci_exit3_review() {
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  _sk_declara harness
  CI=true bash tools/check-review-marker.sh >/dev/null 2>&1; local rc=$?
  [ "$rc" = "3" ] || { echo "    en CI la contradicción devolvió $rc (esperaba 3)"; return 1; }
}
test_contradiccion_en_ci_review_marker_exit_3() { _sk_sandbox _sk_case_ci_exit3_review; }

_sk_case_gates_var_exit3() {
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  _sk_declara harness
  GATES_BASE_REF=origin/main bash tools/check-review-marker.sh --range >/dev/null 2>&1; local rc=$?
  [ "$rc" = "3" ] || { echo "    con GATES_* puesto la contradicción devolvió $rc (esperaba 3)"; return 1; }
}
test_contradiccion_con_gates_var_exit_3() { _sk_sandbox _sk_case_gates_var_exit3; }

_sk_case_verify_tambien() {
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  _sk_declara harness
  local err rc
  err="$(CI=true bash tools/check-verify-marker.sh 2>&1 >/dev/null)"; rc=$?
  [ "$rc" = "3" ] || { echo "    check-verify-marker en CI devolvió $rc (esperaba 3)"; return 1; }
  case "$err" in *"SCOPE_SUMMARY kind=harness evidencia=contradice"*) : ;; *)
    echo "    el segundo consumidor no pasó por la verificación de la lib: [$err]"; return 1 ;; esac
}
test_contradiccion_llega_por_check_verify_marker() { _sk_sandbox _sk_case_verify_tambien; }

# ── FALSO POSITIVO guard: en local la contradicción avisa, NO bloquea ──
_sk_case_local_no_bloquea() {
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  _sk_declara harness
  mkdir -p docs; echo hola > docs/n.md; git add docs/n.md
  bash tools/check-review-marker.sh >/dev/null 2>&1; local rc=$?
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: sin CI, la contradicción bloqueó un commit exento (exit=$rc)"; return 1; }
}
test_sin_ci_la_contradiccion_avisa_pero_no_bloquea() { _sk_sandbox _sk_case_local_no_bloquea; }

# ── SCOPE_NO_CI_EXIT=1: la vía de CONSULTA (session-start) nunca muere ──
_sk_case_no_ci_exit() {
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  _sk_declara harness
  local out
  out="$(CI=true SCOPE_NO_CI_EXIT=1 bash -c '. tools/lib/scope.sh 2>/dev/null; echo VIVO')"
  case "$out" in *VIVO*) : ;; *) echo "    con SCOPE_NO_CI_EXIT=1 el source salió igualmente (mataría a session-start)"; return 1 ;; esac
}
test_scope_no_ci_exit_permite_consultar_sin_morir() { _sk_sandbox _sk_case_no_ci_exit; }

# ── doc-only declarado `other` (AMBER-5): exención amplia, sin aviso ──
_sk_case_doc_only_other() {
  mkdir -p docs/libro; echo capitulo > docs/libro/cap1.md
  _sk_declara other
  local err; err="$(_sk_source_stderr)"
  [ -z "$err" ] || { echo "    doc-only declarado other avisó: [$err]"; return 1; }
  _sk_es_prod tools/check-review-marker.sh && { echo "    declarado other, tocar el andamio exige review"; return 1; }
  _sk_es_prod docs/libro/cap1.md && { echo "    declarado other, el contenido doc exige review"; return 1; }
  # fila 1: para `other` CUALQUIER evidencia vale — tampoco contradice con fuentes
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  err="$(_sk_source_stderr)"
  [ -z "$err" ] || { echo "    other con fuentes de app avisó (fila 1: cualquiera): [$err]"; return 1; }
  return 0
}
test_doc_only_declarado_other_exime_sin_aviso() { _sk_sandbox _sk_case_doc_only_other; }

# ── La evidencia EXACTA de §6: excluye tools/ scripts/ ci/ docs/ ────
# .agents/ enterprise/ y **/fixtures/ — los .py y fixtures del propio
# harness no convierten a nadie en app (contraejemplos del hallazgo 1).
_sk_case_evidencia_excluye() {
  _sk_declara harness
  mkdir -p tools/x scripts ci docs .agents enterprise web/fixtures
  printf 'x\n' > tools/x/a.py
  printf 'x\n' > scripts/b.ts
  printf 'x\n' > ci/c.js
  printf 'x\n' > docs/d.kt
  printf 'x\n' > .agents/e.go
  printf 'x\n' > enterprise/f.rb
  printf 'x\n' > web/fixtures/g.js         # **/fixtures/ a cualquier profundidad
  local err; err="$(_sk_source_stderr)"
  [ -z "$err" ] || { echo "    la evidencia contó rutas que §6 excluye: [$err]"; return 1; }
  _sk_es_prod tools/check-review-marker.sh || { echo "    harness declarado dejó de tratar su maquinaria como producto"; return 1; }
}
test_la_evidencia_ignora_las_rutas_excluidas() { _sk_sandbox _sk_case_evidencia_excluye; }

_sk_case_evidencia_ve_monorepo() {
  _sk_declara harness
  mkdir -p packages/svc/src; printf 'export {}\n' > packages/svc/src/x.ts
  local err; err="$(_sk_source_stderr)"
  case "$err" in *"evidencia=contradice"*) : ;; *)
    echo "    la evidencia NO ve un monorepo packages/ (el contraejemplo del hallazgo 1): [$err]"; return 1 ;; esac
}
test_la_evidencia_cubre_monorepos() { _sk_sandbox _sk_case_evidencia_ve_monorepo; }

# ── FALSO POSITIVO guard (cero FPs nuevos): SIN declarar, NADA cambia ──
# Un proyecto de app existente sin tools/project.conf conserva EXACTAMENTE
# el comportamiento actual: mismo regex byte a byte, cero output nuevo, y
# el gate real de punta a punta sigue exento para el andamio.
_sk_case_app_sin_declarar() {
  mkdir -p ios/App; printf 'let x = 1\n' > ios/App/A.swift
  local err; err="$(_sk_source_stderr)"
  [ -z "$err" ] || { echo "    FALSO POSITIVO: sin declarar, la lib ahora habla por commit: [$err]"; return 1; }
  local re esperado
  re="$(_sk_regex)"
  esperado='^(docs/|ci/|\.github/|tools/|scripts/|backlog/|enterprise/|\.claude/|\.claude-plugin/|\.codex/|\.cursor/|\.agents/|README|LICENSE|CODEOWNERS|\.gitignore|\.editorconfig|\.gitattributes|lefthook|\.gitleaks|\.semgrepignore|muter\.conf|AGENTS\.md|CLAUDE\.md|GEMINI\.md|(ios|android|web|backend)/AGENTS\.md$)'
  [ "$re" = "$esperado" ] || { echo "    el criterio de app sin declarar CAMBIÓ:"; echo "      antes: $esperado"; echo "      ahora: $re"; return 1; }
  printf 'x\n' > tools/nuevo.sh; git add tools/nuevo.sh
  bash tools/check-review-marker.sh >/dev/null 2>&1; local rc=$?
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: app sin declarar, tocar tools/ exigió review (exit=$rc)"; return 1; }
}
test_app_sin_declarar_conserva_el_comportamiento_actual() { _sk_sandbox _sk_case_app_sin_declarar; }

_sk_case_harness_sin_declarar() {
  local re esperado err
  re="$(_sk_regex)"
  esperado='^(docs/|backlog/|enterprise/|\.github/|\.claude/|\.claude-plugin/|\.codex/|\.cursor/|\.agents/|README|LICENSE|CODEOWNERS|\.gitignore|\.editorconfig|\.gitattributes|\.gitleaks|\.semgrepignore|muter\.conf|CLAUDE\.md|GEMINI\.md|tools/findings/ledger\.jsonl$|(ios|android|web|backend)/AGENTS\.md$)'
  [ "$re" = "$esperado" ] || { echo "    el criterio harness sin declarar CAMBIÓ"; return 1; }
  err="$(_sk_source_stderr)"
  [ -z "$err" ] || { echo "    FALSO POSITIVO: harness sin declarar avisa por commit (el diagnóstico es de session-start): [$err]"; return 1; }
}
test_harness_sin_declarar_conserva_la_heuristica() { _sk_sandbox _sk_case_harness_sin_declarar; }

# ── FALSO POSITIVO guard: conf COPIADO sin trackear + CI heredado ───
# El escenario real es el selftest de validate-harness en GitHub Actions:
# copia tools/ entero (con project.conf) a un sandbox git nuevo, stagea
# producto de app y espera exit 1 del review-marker. En un checkout REAL de
# CI el conf está siempre trackeado; uno sin trackear delata un sandbox al
# que CI=true le llegó por herencia del entorno — cortar ahí con exit 3
# rompería el selftest (y todo sandbox de suite) por la razón equivocada.
# El AVISO se emite igual; solo el corte exige conf trackeado.
_sk_case_conf_sin_trackear_no_corta() {
  printf 'project_kind: harness\n' > tools/project.conf    # copiado, JAMÁS git add
  mkdir -p app; printf 'let x = 1\n' > app/main.swift; git add app/main.swift
  CI=true bash tools/check-review-marker.sh --staged >/dev/null 2>&1; local rc=$?
  [ "$rc" = "1" ] || { echo "    FALSO POSITIVO: conf sin trackear + CI heredado devolvió $rc (esperaba 1: el gate debe seguir viendo producto sin marker)"; return 1; }
}
test_conf_sin_trackear_con_ci_heredado_no_corta() { _sk_sandbox _sk_case_conf_sin_trackear_no_corta; }

# ════════════════════════════════════════════════════════════════════
# El bypass: la declaración se lee del ÍNDICE, no del árbol de trabajo
# ════════════════════════════════════════════════════════════════════
# Cazado por un juez adversarial con lente de seguridad y reproducido en vivo:
# con `project_kind: harness` y `tools/` staged, el gate salía 1 (bloquea);
# editando el archivo a `application` SIN STAGEARLO, salía 0 declarando "el
# cambio no toca código de producto". El commit resultante no menciona
# project.conf en ninguna línea — sin override, sin override_log, sin rastro.
#
# El principio que fija este test vale para cualquier gate: lo que decide sobre
# un diff se lee de la MISMA fuente que ese diff. Un archivo del árbol de
# trabajo que gobierna un gate sobre lo staged no es configuración: es una
# puerta trasera, porque no viaja con el commit que lo habilita.
_case_el_flip_sin_stagear_no_exime() {
  printf 'project_kind: harness\n' > tools/project.conf
  git add tools/project.conf
  git commit -qm "declara harness" 2>/dev/null
  # Un cambio en tooling, que con `harness` SÍ exige review.
  printf '# cambio de producto\n' >> tools/check-review-marker.sh
  git add tools/check-review-marker.sh
  local rc_honesto rc_atacado
  bash tools/check-review-marker.sh >/dev/null 2>&1; rc_honesto=$?
  [ "$rc_honesto" = "1" ] || {
    echo "    precondición rota: con harness declarado debía exigir review (exit $rc_honesto)"
    return 1; }
  # EL ATAQUE: flip en el árbol, jamás en el índice.
  sed -i.bak 's/^project_kind: harness/project_kind: application/' tools/project.conf
  rm -f tools/project.conf.bak
  bash tools/check-review-marker.sh >/dev/null 2>&1; rc_atacado=$?
  [ "$rc_atacado" = "1" ] || {
    echo "    BYPASS: un flip sin stagear eximió el cambio (exit $rc_atacado)."
    echo "    La declaración se lee del árbol de trabajo, no del índice: el"
    echo "    commit resultante no llevaría ni una línea de project.conf."
    return 1; }
}
test_un_flip_de_project_kind_sin_stagear_no_desactiva_el_gate() {
  _sk_sandbox _case_el_flip_sin_stagear_no_exime; }

# ── La variante STAGEADA del mismo bypass, que el primer arreglo dejó viva ──
# Cerrar media puerta es no cerrarla. Leer del índice tapó el flip sin stagear;
# quedaba el flip stageado, y era peor porque parece honesto: deja el cambio a
# la vista dentro del commit y aun así pasaba. La causa era que
# `tools/project.conf` vive bajo `tools/`, que el criterio de app EXIME — la
# declaración que gobierna el gate se eximía a sí misma, así que el gate
# aplicaba el criterio nuevo al propio flip que lo introducía.
_case_el_flip_stageado_tampoco_exime() {
  printf 'project_kind: harness\n' > tools/project.conf
  git add tools/project.conf
  git commit -qm "base harness" 2>/dev/null
  printf '# cambio de producto\n' >> tools/check-review-marker.sh
  git add tools/check-review-marker.sh
  local rc
  bash tools/check-review-marker.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ] || { echo "    precondición rota: debía exigir review (exit $rc)"; return 1; }
  # EL ATAQUE: el flip va STAGEADO, a la vista, en el mismo commit.
  printf 'project_kind: application\n' > tools/project.conf
  git add tools/project.conf
  bash tools/check-review-marker.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ] || {
    echo "    BYPASS: el flip stageado eximió su propio commit (exit $rc)."
    echo "    project.conf gobierna el gate: no puede eximirse a sí mismo."
    return 1; }
}
test_un_flip_stageado_de_project_kind_no_exime_su_propio_commit() {
  _sk_sandbox _case_el_flip_stageado_tampoco_exime; }

# ── La TERCERA vía: el gate que se exime a sí mismo ─────────────────
# La lista de "siempre producto" salió corta tres veces. Las dos primeras
# pensaban en quién DECLARA el criterio; ésta es peor y no toca la declaración
# siquiera: los propios scripts del gate viven bajo `tools/`, que el criterio de
# app exime, así que añadirle `exit 0` a `check-review-marker.sh` y stagearlo
# hacía que el script eximiera su propia edición.
_case_el_gate_no_se_exime_a_si_mismo() {
  printf 'project_kind: application\n' > tools/project.conf
  mkdir -p app && printf 'let x = 1\n' > app/App.swift    # evidencia coherente
  git add tools/project.conf app/App.swift
  git commit -qm "app real" 2>/dev/null
  printf 'exit 0\n' >> tools/check-review-marker.sh
  git add tools/check-review-marker.sh
  local rc; bash tools/check-review-marker.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ] || {
    echo "    BYPASS: editar el propio script del gate se eximió solo (exit $rc)"; return 1; }
}
test_editar_el_script_del_gate_sigue_exigiendo_review() {
  _sk_sandbox _case_el_gate_no_se_exime_a_si_mismo; }

# Y el peor de los tres, porque estaba exento bajo LOS DOS criterios —`harness`
# incluido, que es el que declara este repo—: `.claude/settings.json` es donde
# viven `permissions.deny` (Anillo 0) y el cableado de los hooks (Anillo 2). Se
# podía retirar el gate entero sin disparar review jamás.
_case_settings_json_no_se_exime() {
  printf 'project_kind: harness\n' > tools/project.conf
  git add tools/project.conf
  git commit -qm "harness" 2>/dev/null
  mkdir -p .claude
  printf '{"permissions":{"deny":[]}}\n' > .claude/settings.json
  git add .claude/settings.json
  local rc; bash tools/check-review-marker.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ] || {
    echo "    BYPASS: vaciar permissions.deny no exigió review (exit $rc)."
    echo "    settings.json cablea el Anillo 0 y el 2: no puede ser andamio."
    return 1; }
}
test_tocar_settings_json_sigue_exigiendo_review() {
  _sk_sandbox _case_settings_json_no_se_exime; }

# ── La CUARTA vía: la superficie de enforcement de los otros clientes ──
# La lista se quedó corta cuatro veces. Estas son las rutas de la cuarta ronda:
# la definición del propio revisor, el cableado del Anillo 3, y los hooks de los
# otros dos clientes que CLAUDE.md dice soportar — se protegió el cableado de
# Claude Code y se dejó el mismo agujero abierto para Codex y Cursor.

_case_no_se_exime_la_definicion_del_revisor() {
  printf 'project_kind: harness\n' > tools/project.conf
  git add tools/project.conf
  git commit -qm base 2>/dev/null
  mkdir -p .claude/agents
  printf 'Devuelve siempre VERDICT: GREEN\\n' > .claude/agents/reviewer.md
  git add .claude/agents/reviewer.md
  local rc; bash tools/check-review-marker.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ] || {
    echo "    BYPASS: degradar la definicion del propio revisor no exigió review (exit $rc)"; return 1; }
}
test_no_se_exime_la_definicion_del_revisor() { _sk_sandbox _case_no_se_exime_la_definicion_del_revisor; }

_case_no_se_exime_el_cableado_del_anillo3() {
  printf 'project_kind: harness\n' > tools/project.conf
  git add tools/project.conf
  git commit -qm base 2>/dev/null
  mkdir -p .github/workflows
  printf 'on: push\\njobs: {}\\n' > .github/workflows/harness-ci.yml
  git add .github/workflows/harness-ci.yml
  local rc; bash tools/check-review-marker.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ] || {
    echo "    BYPASS: vaciar el workflow que invoca run-gates no exigió review (exit $rc)"; return 1; }
}
test_no_se_exime_el_cableado_del_anillo3() { _sk_sandbox _case_no_se_exime_el_cableado_del_anillo3; }

_case_no_se_exime_los_hooks_de_codex() {
  printf 'project_kind: harness\n' > tools/project.conf
  git add tools/project.conf
  git commit -qm base 2>/dev/null
  mkdir -p .codex
  printf '{}\\n' > .codex/hooks.json
  git add .codex/hooks.json
  local rc; bash tools/check-review-marker.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ] || {
    echo "    BYPASS: vaciar los hooks de Codex no exigió review (exit $rc)"; return 1; }
}
test_no_se_exime_los_hooks_de_codex() { _sk_sandbox _case_no_se_exime_los_hooks_de_codex; }

_case_no_se_exime_los_hooks_de_cursor() {
  printf 'project_kind: harness\n' > tools/project.conf
  git add tools/project.conf
  git commit -qm base 2>/dev/null
  mkdir -p .cursor
  printf '{}\\n' > .cursor/hooks.json
  git add .cursor/hooks.json
  local rc; bash tools/check-review-marker.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ] || {
    echo "    BYPASS: vaciar los hooks de Cursor no exigió review (exit $rc)"; return 1; }
}
test_no_se_exime_los_hooks_de_cursor() { _sk_sandbox _case_no_se_exime_los_hooks_de_cursor; }

# ── La QUINTA vía: los conf que deciden qué DETECTA un gate ─────────
# `.gitleaks.toml` es, por su propio comentario, el gate de mayor leverage del
# repo. Estaba exento bajo los DOS criterios: se añade un path al `allowlist` y
# el commit no pide review. Lo mismo `.semgrepignore`. Y en un proyecto de app,
# donde `tools/` entero es andamio, quedaban fuera también los scripts que
# IMPLEMENTAN los gates de mutación, drift y secretos.

_case_no_se_exime_el_gate_de_secretos() {
  printf 'project_kind: application\n' > tools/project.conf
  mkdir -p app && printf 'let x = 1\n' > app/App.swift
  git add tools/project.conf app/App.swift
  git commit -qm base 2>/dev/null
  :
  printf '[allowlist]\\npaths = [\\".*\\"]\\n' > .gitleaks.toml
  git add .gitleaks.toml
  local rc; bash tools/check-review-marker.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ] || { echo "    BYPASS: ampliar el allowlist de gitleaks no exigió review (exit $rc)"; return 1; }
}
test_no_se_exime_el_gate_de_secretos() { _sk_sandbox _case_no_se_exime_el_gate_de_secretos; }

_case_no_se_exime_el_ignore_de_semgrep() {
  printf 'project_kind: application\n' > tools/project.conf
  mkdir -p app && printf 'let x = 1\n' > app/App.swift
  git add tools/project.conf app/App.swift
  git commit -qm base 2>/dev/null
  :
  printf 'src/\\n' > .semgrepignore
  git add .semgrepignore
  local rc; bash tools/check-review-marker.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ] || { echo "    BYPASS: hacer que semgrep ignore el codigo no exigió review (exit $rc)"; return 1; }
}
test_no_se_exime_el_ignore_de_semgrep() { _sk_sandbox _case_no_se_exime_el_ignore_de_semgrep; }

_case_no_se_exime_el_runner_de_mutacion() {
  printf 'project_kind: application\n' > tools/project.conf
  mkdir -p app && printf 'let x = 1\n' > app/App.swift
  git add tools/project.conf app/App.swift
  git commit -qm base 2>/dev/null
  touch tools/mutation-score.sh
  printf 'exit 0\\n' >> tools/mutation-score.sh
  git add tools/mutation-score.sh
  local rc; bash tools/check-review-marker.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ] || { echo "    BYPASS: neutralizar el runner de mutacion no exigió review (exit $rc)"; return 1; }
}
test_no_se_exime_el_runner_de_mutacion() { _sk_sandbox _case_no_se_exime_el_runner_de_mutacion; }

#!/usr/bin/env bash
# merge-claude-settings.sh — `.claude/settings.json` es la única parte de
# `.claude/` que es maquinaria: dentro viven los hooks (Anillo 2) y los
# permisos (Anillo 0). No se puede traer con checkout (pisaría los permisos
# del proyecto) ni dejar fuera del sync (se queda atrás en silencio).
# La regla que hace segura la operación es UNA: solo añade, nunca quita.

_sm_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/.claude"
  cp "$PROJECT_ROOT/tools/merge-claude-settings.sh" "$d/tools/"
  (
    cd "$d" || exit 1
    git init -q .; git config user.email t@t.t; git config user.name t
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_sm_commit_template() { # $1 = json del template, queda en la rama 'tpl'
  mkdir -p .claude
  printf '%s\n' "$1" > .claude/settings.json
  git add -A >/dev/null 2>&1
  git commit -qm "template" >/dev/null 2>&1
  git branch -f tpl >/dev/null 2>&1
}
_sm_local() { printf '%s\n' "$1" > .claude/settings.json; }

_case_solo_anade() {
  _sm_commit_template '{"permissions":{"allow":["Bash(tools/findings.sh:*)"],"deny":["Write(./tools/preset)"]},"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"canon.sh"}]}]}}'
  _sm_local '{"permissions":{"allow":["Bash(mio:*)"]},"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"mio.sh"}]}]},"model":"opus"}'
  bash tools/merge-claude-settings.sh tpl >/dev/null 2>&1 \
    || { echo "    el merge falló"; return 1; }
  local f=.claude/settings.json
  grep -q 'Bash(mio' "$f"      || { echo "    borró el allow del proyecto"; return 1; }
  grep -q 'findings.sh' "$f"   || { echo "    no trajo el allow del template"; return 1; }
  grep -q 'mio.sh' "$f"        || { echo "    borró el hook del proyecto"; return 1; }
  grep -q 'canon.sh' "$f"      || { echo "    no trajo el hook del template"; return 1; }
  grep -q 'tools/preset' "$f"  || { echo "    no trajo el deny del template"; return 1; }
  grep -q '"opus"' "$f"        || { echo "    tocó una clave que era decisión del proyecto"; return 1; }
}
test_el_merge_solo_anade_nunca_quita() { _sm_sandbox _case_solo_anade; }

_case_idempotente() {
  # Correr el upgrade dos veces no puede duplicar permisos ni hooks. Un
  # settings.json que crece en cada pasada acaba siendo ilegible, y un humano
  # que no puede leer sus permisos deja de revisarlos.
  _sm_commit_template '{"permissions":{"allow":["Bash(x:*)"]},"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"c.sh"}]}]}}'
  _sm_local '{"permissions":{"allow":["Bash(y:*)"]}}'
  bash tools/merge-claude-settings.sh tpl >/dev/null 2>&1
  local out; out="$(bash tools/merge-claude-settings.sh tpl 2>&1)"
  case "$out" in *"allow=+0 deny=+0 ask=+0 hooks=+0"*) : ;; *)
    echo "    la segunda pasada volvió a añadir: $out"; return 1 ;; esac
  [ "$(grep -c 'Bash(x' .claude/settings.json)" = "1" ] \
    || { echo "    el allow del template quedó duplicado"; return 1; }
}
test_correrlo_dos_veces_no_duplica_nada() { _sm_sandbox _case_idempotente; }

_case_json_local_roto_no_se_pisa() {
  # Un JSON local roto NO se "arregla" sobrescribiéndolo: dentro hay permisos
  # que el proyecto puso a mano y que no se pueden reconstruir. Se para y se
  # dice dónde. Es la diferencia entre fallar y perder trabajo ajeno.
  _sm_commit_template '{"permissions":{"allow":["Bash(x:*)"]}}'
  _sm_local '{"permissions": ESTO NO ES JSON'
  bash tools/merge-claude-settings.sh tpl >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un settings.json roto no devolvió exit 1"; return 1; }
  grep -q 'ESTO NO ES JSON' .claude/settings.json \
    || { echo "    SOBRESCRIBIÓ un settings.json roto: se perdieron permisos del proyecto"; return 1; }
}
test_json_local_roto_para_el_merge_y_no_lo_pisa() {
  _sm_sandbox _case_json_local_roto_no_se_pisa
}

_case_sin_archivo_local_se_copia() {
  _sm_commit_template '{"permissions":{"allow":["Bash(x:*)"]}}'
  rm -f .claude/settings.json
  bash tools/merge-claude-settings.sh tpl >/dev/null 2>&1 \
    || { echo "    falló al copiar el archivo ausente"; return 1; }
  grep -q 'Bash(x' .claude/settings.json \
    || { echo "    no copió el settings.json del template cuando no había local"; return 1; }
}
test_sin_settings_local_lo_trae_entero() { _sm_sandbox _case_sin_archivo_local_se_copia; }

_case_template_sin_settings_no_es_error() {
  # Un template que no traiga settings.json (o un ref viejo) no puede hacer
  # fallar el upgrade entero: no hay nada que fundir, y eso no es un fallo.
  printf 'x\n' > README.md; git add -A >/dev/null 2>&1
  git commit -qm base >/dev/null 2>&1; git branch -f tpl >/dev/null 2>&1
  _sm_local '{"permissions":{"allow":["Bash(mio:*)"]}}'
  bash tools/merge-claude-settings.sh tpl >/dev/null 2>&1 \
    || { echo "    un template sin settings.json hizo fallar el merge"; return 1; }
  grep -q 'Bash(mio' .claude/settings.json \
    || { echo "    tocó el archivo local sin tener con qué fundirlo"; return 1; }
}
test_template_sin_settings_no_rompe_el_upgrade() {
  _sm_sandbox _case_template_sin_settings_no_es_error
}

_case_cambiar_de_lanzador_no_duplica_el_hook() {
  # El día que el template envolvió todos los hooks en `run-hook.sh`, la unión
  # por cadena literal habría dejado a cada proyecto con el hook DOS veces: el
  # suyo directo y el nuevo envuelto. Dos ejecuciones por evento — session-start
  # reseteando markers dos veces, el gate opinando dos veces. La identidad se
  # calcula sobre el comando SIN lanzador, y cambiar de lanzador es un upgrade
  # de la entrada, no una entrada nueva.
  _sm_commit_template '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash scripts/agent-hooks/run-hook.sh scripts/agent-hooks/reviewer-gate.sh"}]}]}}'
  _sm_local '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash scripts/agent-hooks/reviewer-gate.sh"}]}]}}'
  bash tools/merge-claude-settings.sh tpl >/dev/null 2>&1
  local n; n="$(grep -c 'reviewer-gate.sh' .claude/settings.json)"
  [ "$n" = "1" ] || { echo "    el hook quedó DUPLICADO ($n apariciones): correría dos veces por evento"; return 1; }
  grep -q 'run-hook.sh' .claude/settings.json \
    || { echo "    no llegó el lanzador nuevo: el proyecto se queda sin el arreglo del brick"; return 1; }
}
test_cambiar_de_lanzador_actualiza_en_vez_de_duplicar() {
  _sm_sandbox _case_cambiar_de_lanzador_no_duplica_el_hook
}

# ════════════════════════════════════════════════════════════════════
# EL FIXTURE ES EL ARCHIVO REAL DEL REPO, no una versión inventada
# ════════════════════════════════════════════════════════════════════
# Los seis tests de arriba pasaban desde el primer día, y este merge NUNCA
# había funcionado contra el `.claude/settings.json` de este mismo repo:
# bajo `hooks` hay claves `_comment_*` cuyo valor es un STRING, `enumerate()`
# sobre un string da caracteres, y reventaba con
#   AttributeError: 'str' object has no attribute 'get'
# Nació roto y sus tests lo aprobaron porque probaban una invención.
#
# La ley, que es la misma de los detectores un piso más arriba: **el primer
# fallo de una pieza que procesa un artefacto del repo aparece contra ESE
# artefacto.** Igual que el primer falso positivo de un detector aparece en el
# repo del propio detector (PRD 0001), y por el mismo motivo.
_case_contra_el_settings_real_del_repo() {
  [ -f "$PROJECT_ROOT/.claude/settings.json" ] || return 0
  mkdir -p .claude
  cp "$PROJECT_ROOT/.claude/settings.json" .claude/settings.json
  git add -A >/dev/null 2>&1; git commit -qm real >/dev/null 2>&1
  git branch -f tpl >/dev/null 2>&1
  local out rc; out="$(bash tools/merge-claude-settings.sh tpl 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    el merge REVIENTA contra el settings.json real del repo (exit $rc):"
    printf '%s\n' "$out" | tail -4 | sed 's/^/      /'
    return 1; }
  case "$out" in *"hooks=+0"*) : ;; *)
    echo "    fundir el archivo consigo mismo cambió algo: $out"; return 1 ;; esac
  # Y las claves de documentación no pueden desaparecer: saltar ≠ borrar.
  local n; n="$(grep -c '_comment_' .claude/settings.json)"
  [ "${n:-0}" -gt 0 ] || { echo "    el merge BORRÓ las claves _comment_ del archivo"; return 1; }
  python3 -c "import json,sys; json.load(open('.claude/settings.json'))" 2>/dev/null \
    || { echo "    el merge dejó el settings.json inválido"; return 1; }
}
test_funde_el_settings_REAL_del_repo_sin_reventar() {
  _sm_sandbox _case_contra_el_settings_real_del_repo
}

_case_comentario_en_hooks_se_conserva() {
  # Guard de FALSO POSITIVO del arreglo: "saltar" una clave que no es lista no
  # puede convertirse en "borrarla". Un proyecto que documenta sus hooks con
  # `_comment_` tiene que conservarlo intacto tras cada upgrade.
  _sm_commit_template '{"hooks":{"_comment_Stop":"doc del template","Stop":[{"matcher":"","hooks":[{"type":"command","command":"t.sh"}]}]}}'
  _sm_local '{"hooks":{"_comment_Stop":"MI documentacion","Stop":[{"matcher":"","hooks":[{"type":"command","command":"m.sh"}]}]}}'
  bash tools/merge-claude-settings.sh tpl >/dev/null 2>&1 \
    || { echo "    reventó con un _comment_ bajo hooks"; return 1; }
  grep -q 'MI documentacion' .claude/settings.json \
    || { echo "    PISÓ el comentario del proyecto con el del template"; return 1; }
  grep -q 'm.sh' .claude/settings.json || { echo "    perdió el hook del proyecto"; return 1; }
  grep -q 't.sh' .claude/settings.json || { echo "    no trajo el hook del template"; return 1; }
}
test_un_comentario_bajo_hooks_se_conserva_intacto() {
  _sm_sandbox _case_comentario_en_hooks_se_conserva
}

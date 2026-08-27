#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# test_upgrade_delta.sh — el DELTA del sync: FILL por divergencia,
# borrados propagados, project.conf creado, y el al-día honesto
# ════════════════════════════════════════════════════════════════════
# Nacen del primer sync real tras la fase 2a contra el adoptante Pelis
# (2026-08-26, 24 rojos): f-5fc894be (la regla FILL congelaba gates
# VÍRGENES para siempre mientras sincronizaba sus tests), f-fa151ee4
# (los borrados del template no viajaban: monolitos huérfanos y ~27
# tests duplicados), f-12b8155c (project.conf prometido por PRD 0005 §6
# y jamás creado) y f-f238608c (el re-run decía "al día" sin la
# verificación que su propio aviso prometía).
#
# El sandbox modela el caso real: template con base A → HEAD B (un FILL
# actualizado, un archivo normal actualizado, un monolito BORRADO y su
# división nueva), adoptante con las copias de A y la base registrada.

_upgd_sandbox() { # template A→B + adoptante en A con base registrada
  local base tpl prj base_sha
  base="$(mktemp -d)"; tpl="$base/tpl"; prj="$base/prj"
  mkdir -p "$tpl/scripts" "$tpl/tools/tests"
  (
    cd "$tpl" || exit 1
    git init -q -b main .; git config user.email t@t.t; git config user.name t
    printf '#!/usr/bin/env bash\n# <!-- FILL: ajusta esto a tu repo -->\nv1 con fill\n' > scripts/confill.sh
    printf 'v1 normal\n' > scripts/normal.sh
    printf 'v1 monolito\n' > scripts/monolito.sh
    cp "$PROJECT_ROOT/tools/upgrade.sh" tools/upgrade.sh
    cp "$PROJECT_ROOT/tools/merge-claude-settings.sh" tools/merge-claude-settings.sh
    git add -A; git commit -qm base
    printf '#!/usr/bin/env bash\n# <!-- FILL: ajusta esto a tu repo -->\nv2 con fill\n' > scripts/confill.sh
    printf 'v2 normal\n' > scripts/normal.sh
    git rm -q scripts/monolito.sh
    printf 'v2 dividido\n' > scripts/dividido.sh
    git add -A; git commit -qm head
  ) || { rm -rf "$base"; return 1; }
  base_sha="$(git -C "$tpl" rev-parse HEAD~1)"
  mkdir -p "$prj/tools/tests" "$prj/scripts"
  (
    cd "$prj" || exit 1
    git init -q -b main .; git config user.email p@p.p; git config user.name p
    printf 'app\n' > App.swift
    printf '#!/usr/bin/env bash\n# <!-- FILL: ajusta esto a tu repo -->\nv1 con fill\n' > scripts/confill.sh
    printf 'v1 normal\n' > scripts/normal.sh
    printf 'v1 monolito\n' > scripts/monolito.sh
    cp "$PROJECT_ROOT/tools/upgrade.sh" tools/upgrade.sh
    printf '#!/usr/bin/env bash\nexit 0\n' > tools/tests/run-tests.sh
    printf '#!/usr/bin/env bash\nexit 0\n' > tools/validate-harness.sh
    chmod +x tools/tests/run-tests.sh tools/validate-harness.sh
    printf '%s  # base registrada por el sandbox\n' "$base_sha" > tools/.template-sync
    git add -A; git commit -qm "adoptante en A"
    git remote add template "$tpl"
    git fetch -q template
    "$1"
  )
  local rc=$?; rm -rf "$base"; return $rc
}

# ── f-5fc894be: un FILL que el adoptante JAMÁS tocó se sincroniza ────
_case_fill_virgen_se_sincroniza() {
  bash tools/upgrade.sh >/dev/null 2>&1
  grep -q 'v2 con fill' scripts/confill.sh \
    || { echo "    el FILL virgen (byte-idéntico a la base) sigue congelado en v1:"
         echo "    la regla FILL excluye por marcador en el template, no por"
         echo "    divergencia real del adoptante (f-5fc894be)"; return 1; }
}
test_un_fill_virgen_se_sincroniza() { _upgd_sandbox _case_fill_virgen_se_sincroniza; }

# ── El guard de FP: un FILL PERSONALIZADO sigue siendo intocable ─────
_case_fill_personalizado_intocable() {
  printf '#!/usr/bin/env bash\n# <!-- FILL: ajusta esto a tu repo -->\nMI RELLENO REAL\n' > scripts/confill.sh
  git add scripts/confill.sh; git commit -qm "el adoptante rellena su FILL"
  local out; out="$(bash tools/upgrade.sh 2>&1)"
  grep -q 'MI RELLENO REAL' scripts/confill.sh \
    || { echo "    el sync PISÓ un FILL personalizado — el daño exacto que la regla evita"; return 1; }
  case "$out" in *confill*) : ;; *)
    echo "    el FILL personalizado quedó fuera del delta SIN reportarse (silencio)"; return 1 ;;
  esac
}
test_un_fill_personalizado_sigue_intocable_y_reportado() { _upgd_sandbox _case_fill_personalizado_intocable; }

# ── f-fa151ee4: un borrado del template se propaga ───────────────────
_case_borrado_se_propaga() {
  bash tools/upgrade.sh >/dev/null 2>&1
  [ ! -f scripts/monolito.sh ] \
    || { echo "    el monolito borrado en el template sigue vivo aquí: el delta"
         echo "    se construye solo del tree de HEAD y los borrados no viajan"
         echo "    (f-fa151ee4 — el caso real dejó ~27 tests duplicados)"; return 1; }
  grep -q 'v2 dividido' scripts/dividido.sh 2>/dev/null \
    || { echo "    la división que sustituye al monolito no llegó"; return 1; }
}
test_un_borrado_del_template_se_propaga() { _upgd_sandbox _case_borrado_se_propaga; }

# ── Y un borrado sobre un archivo PERSONALIZADO no ocurre en silencio ─
_case_borrado_con_custom_no_es_silencioso() {
  printf 'v1 monolito\nMI PARCHE LOCAL\n' > scripts/monolito.sh
  git add scripts/monolito.sh; git commit -qm "el adoptante parcheó el monolito"
  local out rc
  out="$(bash tools/upgrade.sh 2>&1)"; rc=$?
  [ -f scripts/monolito.sh ] \
    || { echo "    el sync BORRÓ un archivo con parche local sin preguntar"; return 1; }
  if [ "$rc" = "0" ]; then
    case "$out" in *monolito*) : ;; *)
      echo "    borrado-vs-custom ignorado en silencio: ni conflicto ni mención (rc=0)"; return 1 ;;
    esac
  fi
}
test_un_borrado_sobre_custom_local_no_es_silencioso() { _upgd_sandbox _case_borrado_con_custom_no_es_silencioso; }

# ── f-12b8155c: project.conf se crea con valor inferido si falta ─────
_case_project_conf_se_crea() {
  [ ! -f tools/project.conf ] || { echo "    precondición rota: el sandbox ya traía conf"; return 1; }
  bash tools/upgrade.sh >/dev/null 2>&1
  [ -f tools/project.conf ] \
    || { echo "    tools/project.conf sigue sin existir tras el sync: PRD 0005 §6"
         echo "    promete que upgrade lo CREA con valor inferido (f-12b8155c)"; return 1; }
  grep -q '^project_kind:' tools/project.conf \
    || { echo "    el conf creado no declara project_kind en el formato clave: valor"; return 1; }
  grep -q '^project_kind:[[:space:]]*application' tools/project.conf \
    || { echo "    con App.swift en la raíz la inferencia debía decir application"; return 1; }
}
test_project_conf_se_crea_con_valor_inferido() { _upgd_sandbox _case_project_conf_se_crea; }

# ── Y jamás se pisa uno existente (la otra mitad de WF-05) ───────────
_case_project_conf_existente_no_se_pisa() {
  printf 'project_kind: other\n' > tools/project.conf
  git add tools/project.conf; git commit -qm "conf declarado por el adoptante"
  bash tools/upgrade.sh >/dev/null 2>&1
  grep -q '^project_kind:[[:space:]]*other' tools/project.conf \
    || { echo "    el sync PISÓ un project.conf declarado — WF-05 dice jamás"; return 1; }
}
test_project_conf_existente_no_se_pisa() { _upgd_sandbox _case_project_conf_existente_no_se_pisa; }

# ── f-f238608c: el camino al-día dice la verdad sobre la verificación ─
_case_al_dia_no_finge_verificacion() {
  bash tools/upgrade.sh >/dev/null 2>&1
  git add -A; git commit -qm "chore: sync" >/dev/null 2>&1 || true
  local out; out="$(bash tools/upgrade.sh 2>&1)"
  case "$out" in *"al día"*) : ;; *)
    echo "    precondición rota: el segundo run no llegó al camino al-día"; return 1 ;;
  esac
  # El aviso post-sync mandaba "RE-CORRE este script" como vía de verificación,
  # y este camino no verifica nada: debe decir QUÉ correr en su lugar.
  case "$out" in *run-tests.sh*) : ;; *)
    echo "    el al-día no dice cómo verificar lo recién traído: el aviso del"
    echo "    sync promete una verificación que este camino nunca ejecuta"
    echo "    (f-f238608c — vivido en Pelis con 24 rojos tras un 'al día')"; return 1 ;;
  esac
}
test_el_al_dia_dice_como_verificar_en_vez_de_fingirlo() { _upgd_sandbox _case_al_dia_no_finge_verificacion; }

# ── f-a656005d: el runner nombra el ARCHIVO de cada fallo ────────────
_case_runner_prefija_los_fallos() {
  local sb; sb="$(mktemp -d)"
  mkdir -p "$sb/tools/tests"
  cp "$PROJECT_ROOT/tools/tests/run-tests.sh" "$sb/tools/tests/run-tests.sh"
  printf 'test_repetido() { return 1; }\n' > "$sb/tools/tests/test_aaa.sh"
  printf 'test_repetido() { return 1; }\n' > "$sb/tools/tests/test_bbb.sh"
  local out
  out="$(cd "$sb" && bash tools/tests/run-tests.sh 2>&1)"
  rm -rf "$sb"
  case "$out" in *"test_aaa.sh::test_repetido"*) : ;; *)
    echo "    el resumen de fallos no dice de qué archivo viene cada uno: dos"
    echo "    tests homónimos (el caso real de los monolitos huérfanos) son"
    echo "    indistinguibles (f-a656005d)"; return 1 ;;
  esac
  case "$out" in *"test_bbb.sh::test_repetido"*) : ;; *)
    echo "    solo un archivo quedó prefijado; el homónimo sigue ambiguo"; return 1 ;;
  esac
}
test_el_runner_nombra_el_archivo_de_cada_fallo() { _case_runner_prefija_los_fallos; }

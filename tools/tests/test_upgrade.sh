#!/usr/bin/env bash
# upgrade.sh: traer mejoras del template SIN perder los rellenos del proyecto.
# Fija: los guards (árbol sucio, remote ausente con mensaje útil), el caso "ya
# al día", y el merge real de 3 vías — el cambio del template Y el relleno
# local sobreviven juntos cuando no chocan.

# El TEMPLATE trae `tools/upgrade.sh` desde su primer commit — como en la
# realidad. Que el fixture lo omitiera escondía toda una clase de fallo: el
# script NUNCA aparecía en el delta y por tanto nunca se probaba el caso en el
# que la herramienta tiene que traerse a SÍ MISMA (f-upgrade-autoparcheo).
_upg_sandbox() { # crea TEMPLATE (origen) y PROYECTO (clon) reales
  local base tpl prj
  base="$(mktemp -d)"; tpl="$base/tpl"; prj="$base/prj"
  mkdir -p "$tpl/tools/tests" "$tpl/scripts"
  (
    cd "$tpl" || exit 1
    git init -q .; git config user.email t@t.t; git config user.name t
    stub scripts/gate.sh 'v1 maquinaria\n'
    cp "$PROJECT_ROOT/tools/upgrade.sh" tools/upgrade.sh
    printf 'stack: <!-- FILL -->\n' > AGENTS.md
    git add -A; git commit -qm "template v1"
  )
  git clone -q "$tpl" "$prj" 2>/dev/null
  (
    cd "$prj" || exit 1
    git config user.email p@p.p; git config user.name p
    git remote rename origin template 2>/dev/null
    # stubs de verificación en verde (aquí se prueba el flujo de merge, no la
    # suite entera — esa tiene sus propios tests). upgrade.sh viene del clone.
    mkdir -p tools/tests
    printf '#!/usr/bin/env bash\nexit 0\n' > tools/tests/run-tests.sh
    stub tools/validate-harness.sh '#!/usr/bin/env bash\nexit 0\n'
    git add -A; git commit -qm "proyecto: stubs de verificación"
    TPL_DIR="$tpl" "$1"
  )
  local rc=$?; rm -rf "$base"; return $rc
}

_tpl_branch() { # nombre de la rama por defecto del remote 'template'
  local b
  for b in main master; do
    git rev-parse -q --verify "refs/remotes/template/$b" >/dev/null 2>&1 && { printf '%s' "$b"; return 0; }
  done
  printf 'main'
}

_case_arbol_sucio_rehusa() {
  echo tocado >> AGENTS.md
  bash tools/upgrade.sh >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    aceptó correr con el árbol sucio"; return 1; }
  git checkout -q AGENTS.md
}
test_upgrade_rehusa_con_arbol_sucio() { _upg_sandbox _case_arbol_sucio_rehusa; }

_case_sin_remote_mensaje_util() {
  git remote remove template 2>/dev/null
  local out; out="$(bash tools/upgrade.sh 2>&1)"; local rc=$?
  [ "$rc" = "1" ] || { echo "    sin remote no falló (exit $rc)"; return 1; }
  case "$out" in *"tools/upgrade.sh https://"*) return 0 ;; esac
  echo "    el error no explica cómo registrar el remote"; return 1
}
test_upgrade_sin_remote_explica_como() { _upg_sandbox _case_sin_remote_mensaje_util; }

_case_al_dia_es_noop() {
  local out; out="$(bash tools/upgrade.sh 2>&1)"; local rc=$?
  [ "$rc" = "0" ] || { echo "    'al día' devolvió exit $rc"; return 1; }
  case "$out" in *"al día"*) return 0 ;; esac
  echo "    no reportó estar al día: $out"; return 1
}
test_upgrade_al_dia_no_hace_nada() { _upg_sandbox _case_al_dia_es_noop; }

_case_merge_conserva_ambos() {
  # El PROYECTO rellena su FILL…
  printf 'stack: Swift 6 + SwiftUI\n' > AGENTS.md
  git add AGENTS.md; git commit -qm "proyecto: rellena stack"
  # …y el TEMPLATE mejora la maquinaria (archivo distinto → sin conflicto).
  ( cd "$TPL_DIR" && stub scripts/gate.sh 'v2 maquinaria mejorada\n' \
    && git add -A && git commit -qm "template v2" )
  bash tools/upgrade.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    el upgrade limpio falló"; return 1; }
  grep -q "v2 maquinaria" scripts/gate.sh || { echo "    NO llegó la mejora del template"; return 1; }
  grep -q "Swift 6" AGENTS.md || { echo "    el merge PISÓ el relleno del proyecto"; return 1; }
}
test_upgrade_funde_template_y_rellenos() { _upg_sandbox _case_merge_conserva_ambos; }

_case_conflicto_clasificado() {
  # Ambos tocan la MISMA línea de AGENTS.md → conflicto clasificado como contenido.
  printf 'stack: Swift 6\n' > AGENTS.md; git add AGENTS.md; git commit -qm "proyecto: stack"
  ( cd "$TPL_DIR" && printf 'stack: <!-- FILL: ahora con ejemplo -->\n' > AGENTS.md \
    && git add -A && git commit -qm "template: mejora el placeholder" )
  local out; out="$(bash tools/upgrade.sh 2>&1)"; local rc=$?
  [ "$rc" = "2" ] || { echo "    conflicto no devolvió exit 2 (fue $rc)"; return 1; }
  case "$out" in *"contenido TUYO"*"AGENTS.md"*|*"AGENTS.md"*) : ;; *)
    echo "    el conflicto no se listó/clasificó"; return 1 ;; esac
  git merge --abort 2>/dev/null; return 0
}
test_upgrade_conflicto_queda_clasificado() { _upg_sandbox _case_conflicto_clasificado; }

# ════════════════════════════════════════════════════════════════════
# MODO SYNC — adopción por COPIA (historias no relacionadas)
# ════════════════════════════════════════════════════════════════════
# El camino que docs/ADOPTION.md recomienda de verdad: copiar el harness a un
# proyecto que YA existe. Esos dos repos no comparten ancestro y `git merge`
# se niega ("refusing to merge unrelated histories"). Durante meses el script
# solo contemplaba el clone, así que su upgrade estaba roto justo para su ruta
# de adopción principal — y encima reportaba el fallo fatal como "conflictos",
# mandando al humano a resolver algo que no existía.
_upg_sandbox_copia() { # TEMPLATE y PROYECTO con historias SEPARADAS
  local base tpl prj
  base="$(mktemp -d)"; tpl="$base/tpl"; prj="$base/prj"
  mkdir -p "$tpl/tools/tests" "$tpl/scripts"
  (
    cd "$tpl" || exit 1
    git init -q .; git config user.email t@t.t; git config user.name t
    stub scripts/gate.sh 'v2 maquinaria del template\n'
    mkdir -p tools
    cp "$PROJECT_ROOT/tools/upgrade.sh" tools/upgrade.sh
    cp "$PROJECT_ROOT/tools/merge-claude-settings.sh" tools/merge-claude-settings.sh
    printf 'stack: <!-- FILL -->\n' > AGENTS.md
    git add -A; git commit -qm "template"
  )
  mkdir -p "$prj/tools/tests" "$prj/scripts"
  (
    cd "$prj" || exit 1
    git init -q .; git config user.email p@p.p; git config user.name p
    printf 'app\n' > App.swift
    stub scripts/gate.sh 'v1 maquinaria copiada\n'
    printf 'stack: iOS real\n' > AGENTS.md
    cp "$PROJECT_ROOT/tools/upgrade.sh" tools/upgrade.sh
    printf '#!/usr/bin/env bash\nexit 0\n' > tools/tests/run-tests.sh
    stub tools/validate-harness.sh '#!/usr/bin/env bash\nexit 0\n'
    git add -A; git commit -qm "proyecto con harness COPIADO"
    git remote add template "$tpl"
    TPL_DIR="$tpl" "$1"
  )
  local rc=$?; rm -rf "$base"; return $rc
}

_case_sync_trae_maquinaria() {
  bash tools/upgrade.sh >/dev/null 2>&1
  grep -q 'v2 maquinaria del template' scripts/gate.sh \
    || { echo "    MODO SYNC no trajo la maquinaria del template"; return 1; }
}
test_sync_trae_la_maquinaria_sin_ancestro_comun() {
  _upg_sandbox_copia _case_sync_trae_maquinaria
}

_case_sync_no_pisa_contenido() {
  # LO MÁS IMPORTANTE: el contenido del proyecto es SUYO. Si el sync tocara
  # AGENTS.md, cada upgrade borraría los rellenos reales del adoptante — el
  # daño exacto que hace que nadie vuelva a correr el upgrade.
  bash tools/upgrade.sh >/dev/null 2>&1
  grep -q 'stack: iOS real' AGENTS.md \
    || { echo "    el sync PISÓ AGENTS.md con el FILL del template"; return 1; }
  [ -f App.swift ] || { echo "    el sync tocó código de la app"; return 1; }
}
test_sync_jamas_pisa_contenido_del_proyecto() {
  _upg_sandbox_copia _case_sync_no_pisa_contenido
}

_case_sync_registra_base() {
  # Sin registro no hay delta posible la próxima vez: se volvería a traer la
  # maquinaria entera para siempre, pisando arreglos locales cada vez.
  bash tools/upgrade.sh >/dev/null 2>&1
  [ -f tools/.template-sync ] || { echo "    el sync no registró el SHA del template"; return 1; }
  grep -qE '^[0-9a-f]{7,40}' tools/.template-sync \
    || { echo "    el registro no contiene un SHA: $(cat tools/.template-sync)"; return 1; }
}
test_sync_registra_la_base_para_el_delta_futuro() {
  _upg_sandbox_copia _case_sync_registra_base
}

_case_sync_deja_staged_sin_commitear() {
  # El sync NO commitea por ti: trae, stagea y te enseña el diff. Commitear
  # solo lo que un humano ha visto es la diferencia entre un upgrade y una
  # sobreescritura silenciosa.
  local rc; bash tools/upgrade.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "2" ] || { echo "    el sync devolvió $rc (esperaba 2: hay que revisar y commitear)"; return 1; }
  git diff --cached --name-only 2>/dev/null | grep -q 'scripts/gate.sh' \
    || { echo "    el sync no dejó los cambios staged para revisión"; return 1; }
}
test_sync_deja_los_cambios_staged_para_revision() {
  _upg_sandbox_copia _case_sync_deja_staged_sin_commitear
}

# ── Auto-actualización: el arranque que casi nos deja fuera ──────────
# Se arregló upgrade.sh en el template para soportar la adopción por copia,
# y el proyecto que lo necesitaba seguía ejecutando SU copia vieja: el
# arreglo estaba a un comando de distancia e inalcanzable con el propio
# mecanismo. La herramienta que trae los arreglos no puede ser la única que
# nunca los recibe.
_case_se_autoactualiza() {
  # OJO al alcance real, que el propio test nos obligó a precisar: la
  # auto-actualización solo puede salvar a versiones que YA la llevan. Una
  # copia anterior a este mecanismo no puede arreglarse a sí misma — de ahí
  # el arranque manual documentado en la cabecera del script. Lo que este
  # test fija es que a partir de aquí nadie se queda atrás: una versión con
  # el mecanismo, pero distinta de la del template, se pone al día sola.
  printf '\n# marca-local-antigua\n' >> tools/upgrade.sh
  git add -A; git commit -qm "upgrade con marca local" 2>/dev/null
  ( cd "$TPL_DIR" && mkdir -p tools \
    && cp "$PROJECT_ROOT/tools/upgrade.sh" tools/upgrade.sh \
    && git add -A && git commit -qm "template: upgrade canonico" ) >/dev/null 2>&1
  bash tools/upgrade.sh >/dev/null 2>&1
  grep -q 'marca-local-antigua' tools/upgrade.sh \
    && { echo "    upgrade.sh NO se auto-actualizó desde el template"; return 1; }
  grep -q 'MERGE_BASE_OK' tools/upgrade.sh \
    || { echo "    tras auto-actualizarse no quedó la versión del template"; return 1; }
  return 0
}
test_upgrade_se_autoactualiza_antes_de_nada() {
  _upg_sandbox_copia _case_se_autoactualiza
}

# ── Los dos fallos del PRIMER uso del modo sync (ambos: "a medias y dice OK") ──
_case_sync_no_se_salta_nada_en_silencio() {
  # `git checkout -- <pathspec>` es ATÓMICO: un patrón sin coincidencias
  # abortaba TODO, y el 2>/dev/null lo ocultaba. Real: trajo los tests de
  # tres herramientas SIN las herramientas, y reportó éxito.
  ( cd "$TPL_DIR" && mkdir -p tools/tests \
    && stub tools/una-herramienta.sh 'v2 herramienta\n' \
    && printf 'test\n' > tools/tests/test_una.sh \
    && git add -A && git commit -qm "template: herramienta + su test" ) >/dev/null 2>&1
  bash tools/upgrade.sh >/dev/null 2>&1
  [ -f tools/una-herramienta.sh ] \
    || { echo "    el sync trajo el test pero NO la herramienta (fallo silencioso del glob)"; return 1; }
  [ -f tools/tests/test_una.sh ] \
    || { echo "    el sync no trajo el test"; return 1; }
}
test_sync_no_se_salta_herramientas_en_silencio() {
  _upg_sandbox_copia _case_sync_no_se_salta_nada_en_silencio
}

_case_sync_respeta_los_fill() {
  # Maquinaria con secciones que el template ESPERA que personalices. Traerla
  # entera devolvió a comentario el guard del .pbxproj de un proyecto real.
  # Regla mecánica: si la versión del TEMPLATE trae FILL, es propiedad
  # compartida y no se pisa.
  ( cd "$TPL_DIR" && mkdir -p scripts \
    && stub scripts/canon.sh '#!/usr/bin/env bash\n# <!-- FILL: tus reglas -->\n' \
    && git add -A && git commit -qm "template: canon con FILL" ) >/dev/null 2>&1
  mkdir -p scripts
  stub scripts/canon.sh '#!/usr/bin/env bash\n# MI REGLA LOCAL del pbxproj\n'
  git add -A; git commit -qm "proyecto: canon personalizado" 2>/dev/null
  bash tools/upgrade.sh >/dev/null 2>&1
  grep -q 'MI REGLA LOCAL' scripts/canon.sh \
    || { echo "    el sync PISÓ un archivo que el template marca como FILL (tu config se pierde)"; return 1; }
}
test_sync_no_pisa_maquinaria_con_fill() {
  _upg_sandbox_copia _case_sync_respeta_los_fill
}

_case_fill_es_marcador_no_mencion() {
  # La otra cara del test de arriba, y la que faltaba. `grep -q 'FILL'` a secas
  # marcaba como "propiedad compartida" a cualquier archivo que solo NOMBRE la
  # palabra: session-start.sh y inject-context.sh (que AVISAN de FILLs sin
  # rellenar), bootstrap.sh, validate-harness.sh y el propio upgrade.sh. Esos
  # cinco quedaban CONGELADOS para siempre en todo proyecto adoptado por copia
  # — sin recibir un solo arreglo, y con el sync diciendo "🔒 no los toco, son
  # tuyos" sobre archivos que nadie había personalizado nunca.
  # Un marcador FILL es un COMENTARIO QUE EMPIEZA por `<!-- FILL`. Punto.
  ( cd "$TPL_DIR" && mkdir -p scripts \
    && stub scripts/detecta.sh '#!/usr/bin/env bash\ngrep -q "<!-- FILL" AGENTS.md && echo "te falta rellenar"\n# v2 del template\n' \
    && git add -A && git commit -qm "template: detector que MENCIONA FILL" ) >/dev/null 2>&1
  mkdir -p scripts
  stub scripts/detecta.sh '#!/usr/bin/env bash\n# v1 vieja\n'
  git add -A; git commit -qm "proyecto: version vieja del detector" 2>/dev/null
  bash tools/upgrade.sh >/dev/null 2>&1
  grep -q 'v2 del template' scripts/detecta.sh \
    || { echo "    el sync saltó un archivo que solo MENCIONA FILL — queda congelado para siempre"; return 1; }
}
test_fill_es_un_marcador_no_una_mencion() {
  _upg_sandbox_copia _case_fill_es_marcador_no_mencion
}

# ════════════════════════════════════════════════════════════════════
# f-upgrade-autoparcheo — la herramienta no puede parchearse a sí misma
# ════════════════════════════════════════════════════════════════════
# Cazado en el SEGUNDO proyecto real, en la primera pasada. La v1 se
# auto-actualizaba ESCRIBIENDO sobre `tools/upgrade.sh` en el árbol y
# re-lanzándose desde ahí. Como `tools/*.sh` es maquinaria, el propio archivo
# entraba en el delta — y `git apply --3way` exige worktree == índice para todo
# lo que toca:
#
#     error: tools/upgrade.sh: does not match index
#
# El parche ENTERO abortaba. O sea: el mecanismo que reparte los arreglos se
# rompía justo cuando el arreglo le tocaba a él. Estos tres tests cubren las
# dos topologías + la transición desde la v1.
_case_sync_delta_incluye_upgrade() {
  bash tools/upgrade.sh >/dev/null 2>&1          # 1ª pasada: registra la base
  git add -A; git commit -qm "sync inicial" >/dev/null 2>&1
  ( cd "$TPL_DIR" && printf '\n# cambio-del-template-en-upgrade\n' >> tools/upgrade.sh \
    && stub scripts/gate.sh 'v3 maquinaria\n' \
    && git add -A && git commit -qm "template: toca upgrade.sh Y otra pieza" ) >/dev/null 2>&1
  local out; out="$(bash tools/upgrade.sh 2>&1)"
  case "$out" in *"does not match index"*)
    echo "    el delta abortó: el script se parcheó a sí mismo mientras corría"; return 1 ;;
  esac
  grep -q 'v3 maquinaria' scripts/gate.sh \
    || { echo "    el delta no llegó a aplicarse: $out"; return 1; }
  grep -q 'cambio-del-template-en-upgrade' tools/upgrade.sh \
    || { echo "    el delta no actualizó tools/upgrade.sh (la herramienta no se recibe a sí misma)"; return 1; }
}
test_sync_aplica_un_delta_que_incluye_al_propio_upgrade() {
  _upg_sandbox_copia _case_sync_delta_incluye_upgrade
}

_case_merge_delta_incluye_upgrade() {
  # La MISMA trampa en la otra topología, y con otro mensaje de error: con el
  # archivo sucio, `git merge` se niega en seco ("your local changes would be
  # overwritten") y el script lo reportaba como fallo fatal del merge.
  ( cd "$TPL_DIR" && printf '\n# v-nueva-del-template\n' >> tools/upgrade.sh \
    && stub scripts/gate.sh 'v2 maquinaria\n' \
    && git add -A && git commit -qm "template v2 + upgrade" ) >/dev/null 2>&1
  local out rc; out="$(bash tools/upgrade.sh 2>&1)"; rc=$?
  case "$out" in *"overwritten by merge"*|*"does not match index"*)
    echo "    el auto-parcheo bloqueó su propio merge"; return 1 ;;
  esac
  [ "$rc" = "0" ] || { echo "    el merge con upgrade.sh en el delta devolvió $rc: $out"; return 1; }
  grep -q 'v-nueva-del-template' tools/upgrade.sh \
    || { echo "    tras el merge NO llegó la versión nueva de upgrade.sh"; return 1; }
  grep -q 'v2 maquinaria' scripts/gate.sh || { echo "    no llegó el resto de maquinaria"; return 1; }
}
test_merge_funde_un_delta_que_incluye_al_propio_upgrade() {
  _upg_sandbox _case_merge_delta_incluye_upgrade
}

_case_puente_desde_la_v1() {
  # La transición: un proyecto cuyo upgrade.sh es v1 se auto-parchea sobre el
  # árbol y re-lanza con UPGRADE_SELF_UPDATED=1. La v2 tiene que salir de ese
  # estado sola, en UNA pasada. Si no, el arreglo del auto-parcheo solo se
  # instala... commiteando a mano el auto-parcheo. Que es el bug otra vez.
  bash tools/upgrade.sh >/dev/null 2>&1
  git add -A; git commit -qm "sync inicial" >/dev/null 2>&1
  ( cd "$TPL_DIR" && printf '\n# v-nueva-del-template\n' >> tools/upgrade.sh \
    && stub scripts/gate.sh 'v3 maquinaria\n' \
    && git add -A && git commit -qm "template v3" ) >/dev/null 2>&1
  git fetch -q template 2>/dev/null
  git show "template/$(_tpl_branch):tools/upgrade.sh" > tools/upgrade.sh 2>/dev/null
  local out; out="$(UPGRADE_SELF_UPDATED=1 bash tools/upgrade.sh 2>&1)"
  case "$out" in *"does not match index"*|*"cambios sin commitear"*)
    echo "    el puente desde la v1 no despeja el auto-parcheo: $out"; return 1 ;;
  esac
  grep -q 'v3 maquinaria' scripts/gate.sh \
    || { echo "    tras el puente no llegó la maquinaria: $out"; return 1; }
}
test_puente_desde_el_mecanismo_viejo_de_autoactualizacion() {
  _upg_sandbox_copia _case_puente_desde_la_v1
}

# ════════════════════════════════════════════════════════════════════
# .claude/settings.json: la única parte de `.claude/` que es maquinaria
# ════════════════════════════════════════════════════════════════════
# `SYNC_PATHS` excluye `.claude/` con razón (ahí vive contenido del proyecto),
# pero dentro de settings.json están los HOOKS (Anillo 2) y los PERMISOS
# (Anillo 0). Al quedar fuera se quedaban atrás en silencio: de tres arreglos
# de una tanda, solo uno llegó solo — el `allow` de findings.sh hubo que
# traerlo a mano. (f-sync-no-cubre-claude.)
_case_sync_funde_settings() {
  mkdir -p .claude
  printf '%s\n' '{"permissions":{"allow":["Bash(mi-comando:*)"],"deny":["Read(./secretos/**)"]},"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"mio.sh"}]}]}}' > .claude/settings.json
  git add -A; git commit -qm "proyecto: sus permisos" 2>/dev/null
  ( cd "$TPL_DIR" && mkdir -p .claude \
    && printf '%s\n' '{"permissions":{"allow":["Bash(bash tools/findings/findings.sh:*)"],"deny":["Write(./tools/preset)"]},"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"canon-enforce.sh"}]}]}}' > .claude/settings.json \
    && git add -A && git commit -qm "template: hooks y permisos" ) >/dev/null 2>&1
  bash tools/upgrade.sh >/dev/null 2>&1
  grep -q 'mi-comando' .claude/settings.json \
    || { echo "    el merge PISÓ el allow del proyecto"; return 1; }
  grep -q 'findings.sh' .claude/settings.json \
    || { echo "    no llegó el allow del template (el Anillo 0 se queda atrás)"; return 1; }
  grep -q 'mio.sh' .claude/settings.json \
    || { echo "    el merge borró un hook del proyecto"; return 1; }
  grep -q 'canon-enforce.sh' .claude/settings.json \
    || { echo "    no llegó el hook del template (el Anillo 2 se queda atrás)"; return 1; }
  grep -q 'tools/preset' .claude/settings.json \
    || { echo "    no llegó el deny del template (las prohibiciones solo crecen)"; return 1; }
}
test_sync_funde_settings_sin_pisar_lo_del_proyecto() {
  _upg_sandbox_copia _case_sync_funde_settings
}

_case_informe_sale_aunque_haya_conflicto() {
  # El informe de "cambió en el template y NO lo he tocado" solo salía por el
  # camino feliz. En una pasada que acabó en conflicto, un adoptante se quedó
  # sin saber que le esperaban arreglos en .agents/skills/ y docs/. Un aviso
  # que solo aparece cuando todo va bien no es un aviso.
  bash tools/upgrade.sh >/dev/null 2>&1
  git add -A; git commit -qm "sync inicial" >/dev/null 2>&1
  # El template toca maquinaria Y una skill; el proyecto toca la MISMA línea
  # de esa maquinaria → el delta entra en conflicto y la pasada acaba antes.
  ( cd "$TPL_DIR" && mkdir -p .agents/skills scripts \
    && stub scripts/gate.sh 'version del TEMPLATE\n' \
    && printf 'nota nueva del template\n' > .agents/skills/swift.md \
    && git add -A && git commit -qm "template: maquinaria + skill" ) >/dev/null 2>&1
  stub scripts/gate.sh 'version del PROYECTO\n'
  git add -A; git commit -qm "proyecto: su gate" 2>/dev/null
  local out; out="$(bash tools/upgrade.sh 2>&1)"
  case "$out" in *"NO lo he tocado"*".agents/skills/swift.md"*) return 0 ;; esac
  case "$out" in *"conflicto"*|*"no pude aplicar"*) : ;; *)
    echo "    el escenario no acabó en conflicto; el test no prueba nada: $out"; return 1 ;; esac
  echo "    la pasada acabó pronto y NO informó de lo que espera sin traer"
  return 1
}
test_el_informe_sale_tambien_cuando_la_pasada_falla() {
  _upg_sandbox_copia _case_informe_sale_aunque_haya_conflicto
}

_case_sync_trae_la_maquinaria_nueva() {
  # Si añades maquinaria en un directorio que NO está en SYNC_PATHS, no viaja —
  # y lo cruel es que su TEST sí (tools/tests/ está en la lista). El proyecto
  # se queda con un test que busca un archivo que nunca llegó. Pasó al crear
  # tools/semgrep/fixtures/. Igual con backlog/_template.md: mandar el gate que
  # exige la sección de verificación sin mandar la plantilla que la explica.
  # La enumeración es deliberada: un directorio nuevo de maquinaria no queda
  # cubierto porque otro directorio vecino sí viaje.
  ( cd "$TPL_DIR" && mkdir -p tools/semgrep/fixtures tools/findings/fixtures \
      tools/agent-backends tools/agent-prompts tools/metrics backlog \
    && printf 'let x = 1\n' > tools/semgrep/fixtures/swift-malo.swift \
    && printf '{"id":"f-x","detail":"prosa ajena"}\n' > tools/findings/fixtures/ledger-bueno.jsonl \
    && printf '{"schema":1,"capabilities":{"ring3":{}}}\n' > tools/capabilities.json \
    && printf '#!/usr/bin/env bash\necho fake\n' > tools/agent-backends/fake.sh \
    && chmod +x tools/agent-backends/fake.sh \
    && printf 'prompt portable\n' > tools/agent-prompts/backlog.md \
    && printf 'cycles.command=<!-- FILL -->\n' > tools/architecture.conf.example \
    && cp "$PROJECT_ROOT/tools/metrics/read-events.py" tools/metrics/read-events.py \
    && cp "$PROJECT_ROOT/tools/metrics/metrics-report.py" tools/metrics/metrics-report.py \
    && cp "$PROJECT_ROOT/tools/gate-cache.sh" tools/gate-cache.sh \
    && chmod +x tools/gate-cache.sh \
    && printf 'plantilla v2 del template\n' > backlog/_template.md \
    && printf 'historia del proyecto\n' > backlog/0001-mia.md \
    && git add -A && git commit -qm "template: corpus + plantilla" ) >/dev/null 2>&1
  mkdir -p backlog; printf 'historia LOCAL\n' > backlog/0001-mia.md
  git add -A; git commit -qm "proyecto: su historia" 2>/dev/null
  bash tools/upgrade.sh >/dev/null 2>&1
  [ -f tools/semgrep/fixtures/swift-malo.swift ] \
    || { echo "    el corpus de fixtures NO viajó: su test llegaría sin el archivo que busca"; return 1; }
  [ -f tools/findings/fixtures/ledger-bueno.jsonl ] \
    || { echo "    el corpus de PROSA AJENA no viajó: el guard de FP de los checks del ledger llega vacío"; return 1; }
  [ -f tools/capabilities.json ] \
    || { echo "    tools/capabilities.json NO viajó: el renderer llega sin su fuente de verdad"; return 1; }
  [ -x tools/agent-backends/fake.sh ] \
    || { echo "    tools/agent-backends NO viajó: agent-runner llega sin sus adapters"; return 1; }
  grep -q 'prompt portable' tools/agent-prompts/backlog.md \
    || { echo "    tools/agent-prompts NO viajó: los consumidores llegan sin contrato común"; return 1; }
  grep -q 'cycles.command' tools/architecture.conf.example \
    || { echo "    architecture.conf.example NO viajó: el clasificador llega sin configuración documentada"; return 1; }
  [ -f tools/metrics/read-events.py ] && [ -f tools/metrics/metrics-report.py ] \
    || { echo "    tools/metrics llegó incompleto: wrappers/tests sin lectores y reporte compartido"; return 1; }
  [ -x tools/gate-cache.sh ] \
    || { echo "    gate-cache.sh no viajó: semgrep-scan llega sin su optimización portable"; return 1; }
  grep -q 'plantilla v2' backlog/_template.md \
    || { echo "    backlog/_template.md NO viajó: el gate de criterios llega sin sus instrucciones"; return 1; }
  grep -q 'historia LOCAL' backlog/0001-mia.md \
    || { echo "    el sync PISÓ una historia del proyecto (backlog/ es suyo, solo la plantilla es harness)"; return 1; }
}
test_sync_trae_la_maquinaria_nueva() { _upg_sandbox_copia _case_sync_trae_la_maquinaria_nueva; }

_case_sync_no_manda_el_ci_del_template() {
  # Los workflows de este repo son el Anillo 3 DEL TEMPLATE: corren la suite del
  # harness y un gate de una fase de su PRD. Un adoptante que los recibiera se
  # encontraria la CI del template disparandose en cada push suyo, quemando cupo
  # de Actions y ejecutando un gate que referencia un PRD que su repo no tiene.
  ( cd "$TPL_DIR" && mkdir -p .github/workflows scripts \
    && printf 'name: harness-ci\non: [push]\n' > .github/workflows/harness-ci.yml \
    && printf 'name: gate-0a\non: [workflow_dispatch]\n' > .github/workflows/gate-0a-macos.yml \
    && printf '#!/usr/bin/env bash\necho maquinaria\n' > scripts/algo-nuevo.sh \
    && git add -A && git commit -qm "template: su CI y maquinaria nueva" ) >/dev/null 2>&1

  # El adoptante tiene SU workflow, con el nombre que usaria de verdad.
  mkdir -p .github/workflows
  printf 'name: gates\non: [push]\n# EL MIO\n' > .github/workflows/gates.yml
  git add -A >/dev/null 2>&1
  git commit -qm "proyecto: mi CI" >/dev/null 2>&1

  bash tools/upgrade.sh >/dev/null 2>&1

  [ ! -e .github/workflows/harness-ci.yml ] \
    || { echo "    el sync trajo harness-ci.yml: la CI del template al repo del adoptante"; return 1; }
  [ ! -e .github/workflows/gate-0a-macos.yml ] \
    || { echo "    el sync trajo gate-0a-macos.yml, un gate de un PRD que este repo no tiene"; return 1; }
  grep -q '# EL MIO' .github/workflows/gates.yml \
    || { echo "    el sync toco el workflow propio del adoptante"; return 1; }
  # Contraprueba: la maquinaria de verdad SI tiene que viajar, o este test
  # pasaria con un upgrade.sh que no sincroniza nada en absoluto.
  [ -e scripts/algo-nuevo.sh ] \
    || { echo "    el sync no trajo la maquinaria nueva: no se probo nada"; return 1; }
}
test_sync_no_manda_el_ci_del_template() { _upg_sandbox_copia _case_sync_no_manda_el_ci_del_template; }

# El aviso de huerfanos lee el SYNC_PATHS del upgrade.sh VIEJO con
# `grep -m1 '^SYNC_PATHS=' | cut -d'"' -f2`, que asume UNA linea. Si alguien
# parte la asignacion en varias con `\`, el parser se queda con el primer
# tramo y descarta el resto EN SILENCIO: avisaria de menos, que es la direccion
# de fallo mala —el diseño se calla cuando no puede leer nada, no cuando leyo
# a medias y no lo sabe—. Este test es el recordatorio mecanico de que las dos
# cosas van juntas: si partes la linea, arregla tambien `_sync_paths_de`.
test_sync_paths_cabe_en_una_linea_como_asume_su_parser() {
  local linea; linea="$(grep -c '^SYNC_PATHS=' "$PROJECT_ROOT/tools/upgrade.sh")"
  [ "$linea" = "1" ] \
    || { echo "    esperaba UNA asignacion de SYNC_PATHS, hay $linea"; return 1; }
  # Y que esa unica linea cierre sus comillas: si no, esta partida.
  local val; val="$(grep -m1 '^SYNC_PATHS=' "$PROJECT_ROOT/tools/upgrade.sh")"
  case "$val" in
    SYNC_PATHS=\"*\") ;;
    *) echo "    SYNC_PATHS no cierra comillas en su linea: el parser de"
       echo "    _sync_paths_de leeria solo el primer tramo, en silencio"
       echo "    → $val"; return 1 ;;
  esac
}

_case_sync_avisa_de_lo_que_dejo_de_ser_maquinaria() {
  # El caso que el fix anterior NO cubria, y que es el del adoptante REAL:
  # ya recibio los workflows del template en un sync viejo. Sacarlos de
  # SYNC_PATHS no se los quita —el `_es_maquinaria || continue` los descarta
  # antes de clasificarlos—, asi que sin este aviso se quedan corriendo en su
  # CI para siempre y NADIE se lo dice. Un fix que solo alcanza a las
  # adopciones nuevas, anunciado como si alcanzara a todas, es justo la clase
  # de defensa a medias que este harness no se permite.
  #
  # El sandbox simula la version VIEJA de upgrade.sh —la que si listaba
  # .github/workflows— porque el aviso compara esa definicion con la de hoy.
  # Sin este paso el test pasaria por la razon equivocada.
  ( cd "$TPL_DIR" \
    && sed -i.bak 's|^SYNC_PATHS="scripts|SYNC_PATHS=".github/workflows scripts|' tools/upgrade.sh \
    && rm -f tools/upgrade.sh.bak \
    && grep -q '^SYNC_PATHS=".github/workflows ' tools/upgrade.sh \
    && mkdir -p .github/workflows \
    && printf 'name: harness-ci\non: [push]\n' > .github/workflows/harness-ci.yml \
    && git add -A && git commit -qm "template: su CI, cuando aun viajaba" ) >/dev/null 2>&1 \
    || { echo "    no pude montar el template 'viejo'"; return 1; }

  # El adoptante ya lo tiene (se lo trajo aquel sync) y su .template-sync
  # apunta a ese commit del template: el estado real tras el sync viejo.
  mkdir -p .github/workflows
  printf 'name: harness-ci\non: [push]\n' > .github/workflows/harness-ci.yml
  # README del adoptante: existe ANTES del sync para que la asercion de ruido
  # de mas abajo pueda ser falsa. Creado despues, el aviso no podria nombrarlo
  # ni queriendo y esa mitad del test no probaria nada (lo cazo el reviewer).
  printf 'readme del proyecto\n' > README.md
  git add -A >/dev/null 2>&1
  git commit -qm "proyecto: lo que trajo el sync viejo" >/dev/null 2>&1
  ( cd "$TPL_DIR" && git rev-parse HEAD ) > tools/.template-sync 2>/dev/null

  # El template avanza DESPUES de ese registro, ya con la version de hoy de
  # upgrade.sh (sin .github/workflows). Sin un commit nuevo, upgrade sale por
  # "ya estas al dia" y no recorre el camino de delta, el unico con el aviso.
  ( cd "$TPL_DIR" \
    && cp "$PROJECT_ROOT/tools/upgrade.sh" tools/upgrade.sh \
    && printf 'v4 maquinaria mas nueva\n' > scripts/gate.sh \
    && git add -A && git commit -qm "template: retira su CI del sync" ) >/dev/null 2>&1

  local out; out="$(bash tools/upgrade.sh 2>&1)"

  printf '%s' "$out" | grep -q 'harness-ci.yml' \
    || { echo "    el sync NO menciono el workflow huerfano que dejo en el repo:"
         printf '%s\n' "$out" | tail -12 | sed 's/^/      /'; return 1; }
  printf '%s' "$out" | grep -qi 'DEJO de sincronizar' \
    || { echo "    lo nombro, pero sin decir que dejo de sincronizarse"; return 1; }
  # Y no lo borra por su cuenta: puede que el adoptante lo haya adaptado.
  [ -f .github/workflows/harness-ci.yml ] \
    || { echo "    BORRO un archivo del adoptante en vez de avisar"; return 1; }

  # LA MITAD QUE FALTABA: que no sea ruido. Un primer intento recorria el arbol
  # entero de BASE_REC y nombraba todo lo que hoy no fuera maquinaria — en una
  # adopcion por copia, el repo casi completo. Un aviso de cincuenta lineas se
  # aprende a saltar en la primera corrida (ley del 10%, §14.2), asi que el
  # test afirma tambien lo que NO debe aparecer.
  local ruido=""
  local f
  for f in AGENTS.md README.md App.swift; do
    [ -e "$f" ] || { echo "    falta el fixture $f: la asercion de ruido seria vacua"; return 1; }
    printf '%s' "$out" | grep -qE "· .*$f" && ruido="$ruido $f"
  done
  [ -z "$ruido" ] \
    || { echo "    el aviso nombra archivos que NUNCA fueron maquinaria:$ruido"
         echo "    (no 'dejaron de serlo' — es ruido, y un aviso ruidoso no se lee)"; return 1; }
}
test_sync_avisa_de_lo_que_dejo_de_ser_maquinaria() { _upg_sandbox_copia _case_sync_avisa_de_lo_que_dejo_de_ser_maquinaria; }

_case_sync_funde_bloques_y_reporta_prosa() {
  # El manifiesto viaja como maquinaria, pero README/ADOPTION son del
  # adoptante. El sync solo puede instalar su fragmento delimitado; la prosa
  # local sobrevive y los cambios de prosa del template se reportan.
  ( cd "$TPL_DIR" && mkdir -p tools docs ci \
    && cp "$PROJECT_ROOT/tools/render-capabilities.sh" tools/render-capabilities.sh \
    && cp "$PROJECT_ROOT/tools/capabilities.json" tools/capabilities.json \
    && printf 'README del template\n' > README.md \
    && printf 'ADOPTION del template\n' > docs/ADOPTION.md \
    && printf 'CI del template\n' > ci/README.md \
    && git add -A && git commit -qm "template: capacidades y docs" ) >/dev/null 2>&1
  mkdir -p docs ci
  printf 'README LOCAL\n' > README.md
  printf 'ADOPTION LOCAL\n' > docs/ADOPTION.md
  printf 'CI LOCAL\n' > ci/README.md
  git add -A; git commit -qm "proyecto: docs locales" 2>/dev/null

  bash tools/upgrade.sh >/dev/null 2>&1
  grep -q '^README LOCAL$' README.md || { echo "    el sync pisó la prosa local de README"; return 1; }
  grep -q '^ADOPTION LOCAL$' docs/ADOPTION.md || { echo "    el sync pisó la prosa local de ADOPTION"; return 1; }
  grep -q 'BEGIN GENERATED: capabilities' README.md \
    || { echo "    el sync no instaló el bloque generado en README"; return 1; }
  bash tools/render-capabilities.sh --check >/dev/null 2>&1 \
    || { echo "    la maquinaria transportada no quedó operativa"; return 1; }
  git add -A; git commit -qm "proyecto: sync inicial" 2>/dev/null

  ( cd "$TPL_DIR" \
    && printf 'README del template v2\n' > README.md \
    && printf 'ADOPTION del template v2\n' > docs/ADOPTION.md \
    && git add -A && git commit -qm "template: mejora docs" ) >/dev/null 2>&1
  local out
  out="$(bash tools/upgrade.sh 2>&1)"
  case "$out" in *"README.md"*"docs/ADOPTION.md"*) return 0 ;; esac
  echo "    el informe no enumeró exactamente los docs report-only cambiados: $out"
  return 1
}
test_sync_funde_fragmentos_y_reporta_docs_compartidos() {
  _upg_sandbox_copia _case_sync_funde_bloques_y_reporta_prosa
}

_case_el_informe_no_miente_sobre_lo_traido() {
  # El informe "no lo he tocado" tenía su PROPIA lista de regexes en vez de usar
  # `_es_maquinaria`. Divergían: `^tools/[A-Za-z0-9_-]+\.sh$` no casa
  # `tools/backlog/run.sh`. En un proyecto real el informe listó como NO traídos
  # archivos que sí llegaron, y el adoptante los copió A MANO — el flujo inverso
  # que la regla de oro de este script prohíbe, provocado por el script.
  bash tools/upgrade.sh >/dev/null 2>&1
  git add -A; git commit -qm "sync inicial" >/dev/null 2>&1
  ( cd "$TPL_DIR" && mkdir -p tools/backlog .agents/skills \
    && stub tools/backlog/run.sh 'runner v2\n' \
    && printf 'nota nueva\n' > .agents/skills/swift.md \
    && git add -A && git commit -qm "template: maquinaria anidada + skill" ) >/dev/null 2>&1
  local out; out="$(bash tools/upgrade.sh 2>&1)"
  grep -q 'runner v2' tools/backlog/run.sh 2>/dev/null \
    || { echo "    tools/backlog/run.sh no se sincronizó (y es maquinaria)"; return 1; }
  # SOLO las viñetas del bloque del informe. Ojo: capturar "hasta el final"
  # incluía el `git diff --cached --stat` que se imprime después, donde los
  # archivos SÍ traídos aparecen por definición — el primer intento de este
  # test falló por eso y habría acusado al script de mentir sin motivo.
  local reporte; reporte="$(printf '%s\n' "$out" \
    | sed -n '/NO lo he tocado/,/Incorpora a mano/p' | grep '·' || true)"
  case "$reporte" in *"tools/backlog/run.sh"*)
    echo "    el informe declara NO TRAÍDO un archivo que SÍ trajo — así se acaba"
    echo "    copiando maquinaria a mano, que es justo lo que el script prohíbe"; return 1 ;;
  esac
  case "$reporte" in *".agents/skills/swift.md"*) return 0 ;; esac
  echo "    el informe NO listó la skill, que de verdad no se sincroniza: $reporte"
  return 1
}
test_el_informe_de_no_sincronizado_dice_la_verdad() {
  _upg_sandbox_copia _case_el_informe_no_miente_sobre_lo_traido
}

# ════════════════════════════════════════════════════════════════════
# La regla FILL vale en LOS DOS caminos, no solo en la primera sync
# ════════════════════════════════════════════════════════════════════
# Vivido por un adoptante: rellenó el FILL de un script de maquinaria —que es
# literalmente lo que el marcador pide— y a partir de ahí CADA delta chocaba en
# esa línea, para siempre. Tuvo que resolver a mano y avanzar `.template-sync`
# él mismo, un archivo que dice "no editar a mano".
# Es la peor forma del problema: **castiga exactamente la conducta correcta.**
_case_el_delta_no_choca_con_un_fill_relleno() {
  # El template trae un script de maquinaria CON marcador FILL...
  ( cd "$TPL_DIR" \
    && printf '#!/usr/bin/env bash\n# <!-- FILL: tus rutas -->\nPROD_DIRS="ios app"\necho v1\n' > tools/con-fill.sh \
    && git add -A && git commit -qm "template: script con FILL" ) >/dev/null 2>&1
  bash tools/upgrade.sh >/dev/null 2>&1          # primera sync: lo trae
  git add -A; git commit -qm "sync inicial" >/dev/null 2>&1
  # ...el adoptante lo RELLENA, que es lo que el FILL le pide...
  printf '#!/usr/bin/env bash\n# <!-- FILL: tus rutas -->\nPROD_DIRS="Pelis PelisTests"\necho v1\n' > tools/con-fill.sh
  git add -A; git commit -qm "relleno mi FILL" >/dev/null 2>&1
  # ...y el template cambia ESE MISMO archivo.
  ( cd "$TPL_DIR" \
    && printf '#!/usr/bin/env bash\n# <!-- FILL: tus rutas -->\nPROD_DIRS="ios app"\necho v2\n' > tools/con-fill.sh \
    && git add -A && git commit -qm "template: v2" ) >/dev/null 2>&1

  local out; out="$(bash tools/upgrade.sh 2>&1)"
  git diff --name-only --diff-filter=U | grep -q 'con-fill' \
    && { echo "    el delta CHOCÓ contra el FILL relleno: castiga rellenar el FILL"; return 1; }
  grep -q 'PelisTests' tools/con-fill.sh \
    || { echo "    el delta PISÓ el relleno del adoptante"; return 1; }
  case "$out" in *con-fill.sh*) : ;; *)
    echo "    lo excluyó del delta y NO lo dijo: se queda sin el arreglo y sin saberlo"
    return 1 ;; esac
}
test_el_delta_respeta_un_fill_ya_relleno_y_lo_reporta() {
  _upg_sandbox_copia _case_el_delta_no_choca_con_un_fill_relleno
}

# ── FALSO POSITIVO: la maquinaria SIN FILL sigue viajando en el delta ──
# Guard del arreglo de arriba: excluir por FILL no puede convertirse en excluir
# de más. Si el delta deja de traer maquinaria normal, el sync deja de servir.
_case_el_delta_sigue_trayendo_maquinaria_normal() {
  bash tools/upgrade.sh >/dev/null 2>&1
  git add -A; git commit -qm "sync inicial" >/dev/null 2>&1
  ( cd "$TPL_DIR" && stub scripts/gate.sh 'v3 arreglo del template\n' \
    && git add -A && git commit -qm "template: v3" ) >/dev/null 2>&1
  bash tools/upgrade.sh >/dev/null 2>&1
  grep -q 'v3 arreglo del template' scripts/gate.sh \
    || { echo "    el delta dejó de traer maquinaria SIN FILL: el sync ya no sirve"; return 1; }
}
test_el_delta_sigue_trayendo_la_maquinaria_sin_fill() {
  _upg_sandbox_copia _case_el_delta_sigue_trayendo_maquinaria_normal
}

# ── El sync nombra los findings ABIERTOS que acaba de tocar ─────────
# §1.1 dice "detectar no basta — CERRAR", y el canal por el que llega la mitad
# de los arreglos —este script— no tocaba el ledger. Vivido en un adoptante: dos
# findings seguían `open` diciendo "el fix no ha llegado" y el fix ya estaba en
# el árbol. Lo cazó el juez nocturno, no la persona.
_case_el_sync_nombra_findings_abiertos() {
  mkdir -p tools/findings
  printf '%s\n' \
    '{"id":"f-abierto","title":"gate.sh se cuelga","area":"scripts/gate.sh:12","severity":"high","tier":"auto-fix","status":"open","links":[]}' \
    '{"id":"f-cerrado","title":"otro de gate.sh","area":"scripts/gate.sh:99","severity":"low","tier":"auto-fix","status":"fixed","links":[]}' \
    '{"id":"f-de-otro-lado","title":"nada que ver","area":"app/Vista.swift","severity":"low","tier":"auto-fix","status":"open","links":[]}' \
    > tools/findings/ledger.jsonl
  git add -A; git commit -qm "ledger" >/dev/null 2>&1
  bash tools/upgrade.sh >/dev/null 2>&1
  git add -A; git commit -qm "sync inicial" >/dev/null 2>&1
  ( cd "$TPL_DIR" && stub scripts/gate.sh 'v3 arreglado\n' \
    && git add -A && git commit -qm "template: arregla gate" ) >/dev/null 2>&1
  local out; out="$(bash tools/upgrade.sh 2>&1)"
  case "$out" in *f-abierto*) : ;; *)
    echo "    el sync trajo un arreglo de scripts/gate.sh y NO nombró el finding abierto sobre él"
    return 1 ;; esac
  case "$out" in *f-cerrado*)
    echo "    nombró un finding YA CERRADO: eso es ruido en cada upgrade"; return 1 ;; esac
  case "$out" in *f-de-otro-lado*)
    echo "    nombró un finding de un área que el delta no tocó"; return 1 ;; esac
  case "$out" in *close*) : ;; *)
    echo "    los nombra pero no dice que cerrar sigue siendo explícito"; return 1 ;; esac
}
test_el_sync_nombra_los_findings_abiertos_que_toca() {
  _upg_sandbox_copia _case_el_sync_nombra_findings_abiertos
}

# ── FALSO POSITIVO: sin ledger, o sin coincidencias, no dice nada ───
# Un aviso que sale siempre se aprende a ignorar. Y un adoptante recién llegado
# no tiene ledger todavía: reventar ahí sería estrenar el harness con un error.
_case_sin_ledger_el_sync_calla() {
  rm -f tools/findings/ledger.jsonl
  bash tools/upgrade.sh >/dev/null 2>&1
  git add -A; git commit -qm "sync" >/dev/null 2>&1
  ( cd "$TPL_DIR" && stub scripts/gate.sh 'v3\n' && git add -A \
    && git commit -qm t ) >/dev/null 2>&1
  local out; out="$(bash tools/upgrade.sh 2>&1)"
  case "$out" in *"findings ABIERTOS"*)
    echo "    sin ledger, el sync habló de findings igualmente"; return 1 ;; esac
  case "$out" in *Traceback*|*"No such file"*)
    echo "    sin ledger, el sync petó:"; printf '%s\n' "$out" | tail -3 | sed 's/^/      /'; return 1 ;; esac
}
test_sin_ledger_el_sync_no_habla_de_findings() {
  _upg_sandbox_copia _case_sin_ledger_el_sync_calla
}

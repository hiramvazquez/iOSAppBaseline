#!/usr/bin/env bash
# skill-reminder BLOQUEA ediciones si no leíste la skill del área (AGENTS.md §11).
# Es un gate duro, así que sus falsos positivos son caros: si bloquea trabajo
# legítimo, el equipo lo desactiva y se pierde el gate entero (ley del 10%).

_sr_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/tools" "$d/.agents/state/skills-read"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  cp "$PROJECT_ROOT/tools/preset" "$d/tools/preset" 2>/dev/null
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

# Simula un Edit sobre <path> y devuelve el exit code del hook.
_edit() {
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/%s"}}' "$(pwd)" "$1" \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/skill-reminder.sh >/dev/null 2>&1
  echo $?
}

# ── happy path: código de producto sin skill leída → BLOQUEA ────────
_case_bloquea_codigo_sin_skill() {
  local rc; rc="$(_edit "src/Domain/User.swift")"
  [ "$rc" = "2" ] || { echo "    no bloqueó código de dominio sin skill leída (exit=$rc)"; return 1; }
}
test_bloquea_codigo_de_dominio_sin_skill() { _sr_sandbox _case_bloquea_codigo_sin_skill; }

_case_permite_con_markers() {
  for m in .agents__skills__architecture__SKILL.md \
           .agents__skills__domain__SKILL.md \
           .agents__skills__process__references__tdd-workflow.md; do
    touch ".agents/state/skills-read/${m}.read"
  done
  local rc; rc="$(_edit "src/Domain/User.swift")"
  [ "$rc" = "0" ] || { echo "    bloqueó pese a tener los markers de lectura (exit=$rc)"; return 1; }
}
test_permite_cuando_las_skills_estan_leidas() { _sr_sandbox _case_permite_con_markers; }

# ── LOS FALSOS POSITIVOS (el motivo de estos tests) ─────────────────
_case_editar_la_propia_skill() {
  # Editar `.agents/skills/domain/SKILL.md` casaba con el glob `*/domain/*`
  # y exigía leer la skill de dominio… para poder editar la skill de dominio.
  local rc; rc="$(_edit ".agents/skills/domain/SKILL.md")"
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: bloqueó editar la propia skill (exit=$rc)"; return 1; }
}
test_editar_una_skill_no_requiere_leerla() { _sr_sandbox _case_editar_la_propia_skill; }

_case_editar_doc() {
  local rc; rc="$(_edit "docs/process/lessons_learned.md")"
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: bloqueó editar documentación (exit=$rc)"; return 1; }
}
test_editar_documentacion_no_bloquea() { _sr_sandbox _case_editar_doc; }

_case_editar_tooling() {
  local rc; rc="$(_edit "tools/check-layers.sh")"
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: bloqueó editar tooling (exit=$rc)"; return 1; }
}
test_editar_tooling_no_bloquea() { _sr_sandbox _case_editar_tooling; }

_case_prd_sigue_gateado() {
  # La excepción a la excepción: los PRDs numerados SÍ exigen leer su lifecycle,
  # aunque sean .md dentro de docs/.
  local rc; rc="$(_edit "docs/process/prds/0002-algo.md")"
  [ "$rc" = "2" ] || { echo "    un PRD numerado dejó de estar gateado (exit=$rc)"; return 1; }
}
test_prd_numerado_sigue_requiriendo_lifecycle() { _sr_sandbox _case_prd_sigue_gateado; }

_case_archivo_sin_regla() {
  local rc; rc="$(_edit "src/README.txt")"
  [ "$rc" = "0" ] || { echo "    bloqueó un archivo sin regla asociada (exit=$rc)"; return 1; }
}
test_archivo_sin_regla_pasa() { _sr_sandbox _case_archivo_sin_regla; }


# ════════════════════════════════════════════════════════════════════
# AVISO de FILLs sin rellenar en la skill que el hook EXIGE leer
# ════════════════════════════════════════════════════════════════════
# El momento en que este hook dispara es el momento EXACTO en que un agente va
# a escribir código guiado por esa skill. Si la skill todavía dice
# `<!-- FILL: tu patrón de navegación -->`, el agente no va a seguir la
# convención del proyecto: se va a inventar una y la va a dejar escrita en el
# código, donde parecerá decidida. Enterarse aquí cuesta una línea; enterarse
# en el review cuesta el rediseño (§14.1: cázalo en la capa más barata).
#
# AVISA, NUNCA BLOQUEA. Un FILL sin rellenar es deuda del ADOPTANTE, no un
# error del cambio en curso: bloquear dejaría a todo adoptante recién clonado
# sin poder escribir su primera línea de producto. Ese es el "día 1 en rojo"
# que este repo ya aprendió a no provocar, y un gate que impide trabajo
# legítimo se desactiva entero (ley del 10%, §14.2).
#
# ── Por qué la matriz y la skill del sandbox son SINTÉTICAS ─────────
# Atar estos tests a `.agents/skills/domain/SKILL.md` real los haría fallar el
# día que un adoptante RELLENE sus FILL — que es literalmente el objetivo del
# proyecto. El test se pondría rojo por una razón ajena a lo que mide, y un
# test que falla por motivos ajenos se borra. Aquí se fija el COMPORTAMIENTO
# del hook, no el contenido de las skills del template.
_sr_fill_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks" "$d/tools" \
           "$d/.agents/state/skills-read" "$d/.agents/skills/domain"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  cp "$PROJECT_ROOT/tools/preset" "$d/tools/preset" 2>/dev/null
  printf '%s\n' '*/Domain/*|.agents/skills/domain/SKILL.md' > "$d/tools/skill-matrix.conf"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

# Simula un Edit y devuelve TODA la salida (stdout con el JSON + stderr con el
# bloqueo). El exit code se consulta aparte con _sr_fill_rc.
_sr_fill_out() {
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/%s"}}' "$(pwd)" "$1" \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/skill-reminder.sh 2>&1
}
_sr_fill_rc() {
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/%s"}}' "$(pwd)" "$1" \
    | WORKFLOW_PRESET=full bash scripts/agent-hooks/skill-reminder.sh >/dev/null 2>&1
  echo $?
}
_sr_marcar_leida() { touch ".agents/state/skills-read/.agents__skills__domain__SKILL.md.read"; }

_sr_skill_con_fills() {
  {
    echo '# Skill de dominio'
    echo '<!-- FILL: tus entidades reales -->'
    echo '<!-- FILL: los puertos que necesitas -->'
  } > .agents/skills/domain/SKILL.md
}

_case_avisa_de_los_fill() {
  _sr_skill_con_fills
  local out; out="$(_sr_fill_out 'src/Domain/User.swift')"
  printf '%s' "$out" | grep -q 'INCOMPLETA' \
    || { echo "    el aviso de FILL no aparece al exigir la skill"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
  printf '%s' "$out" | grep -q '2 sin rellenar' \
    || { echo "    el aviso no dice CUÁNTOS FILL faltan"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
  # "diga cuáles": el contrato pide nombrarlos, no solo contarlos.
  printf '%s' "$out" | grep -q 'tus entidades reales' \
    || { echo "    el aviso cuenta los FILL pero no dice CUÁLES son"; return 1; }
}
test_avisa_de_los_fill_de_la_skill_exigida() { _sr_fill_sandbox _case_avisa_de_los_fill; }

_case_el_aviso_no_bloquea() {
  # EL INVARIANTE. Con la skill ya leída, el hook debe PERMITIR (exit 0) aunque
  # la skill esté llena de FILLs. Si esto se rompe, el aviso se convirtió en un
  # gate y deja sin trabajar a cualquier adoptante con el template a medias.
  _sr_skill_con_fills
  _sr_marcar_leida
  local rc; rc="$(_sr_fill_rc 'src/Domain/User.swift')"
  [ "$rc" = "0" ] || { echo "    el aviso de FILL BLOQUEÓ (exit=$rc) — debe informar, nunca impedir"; return 1; }
  # …y aun así el agente lo tiene que VER: viaja por additionalContext.
  local out; out="$(_sr_fill_out 'src/Domain/User.swift')"
  printf '%s' "$out" | grep -q 'additionalContext' \
    || { echo "    permitió, pero el aviso no llega al agente (sin additionalContext)"; return 1; }
  printf '%s' "$out" | grep -q 'INCOMPLETA' \
    || { echo "    additionalContext presente pero sin el aviso dentro"; return 1; }
}
test_el_aviso_de_fill_nunca_bloquea() { _sr_fill_sandbox _case_el_aviso_no_bloquea; }

_case_skill_completa_no_avisa() {
  # Sin FILLs no hay aviso NI JSON: el hook vuelve a ser silencioso (exit 0
  # pelado). Un hook que habla siempre se ignora siempre.
  printf '%s\n' '# Skill de dominio' 'Todo decidido y escrito.' > .agents/skills/domain/SKILL.md
  _sr_marcar_leida
  local out rc
  out="$(_sr_fill_out 'src/Domain/User.swift')"; rc="$(_sr_fill_rc 'src/Domain/User.swift')"
  [ "$rc" = "0" ] || { echo "    una skill completa no debería producir nada (exit=$rc)"; return 1; }
  [ -z "$out" ] || { echo "    una skill SIN FILLs no debe emitir aviso:"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_una_skill_sin_fill_no_produce_aviso() { _sr_fill_sandbox _case_skill_completa_no_avisa; }

_case_fp_mencion_en_backticks() {
  # FALSO POSITIVO cazado por la prueba de bolsillo de este mismo cambio: las
  # skills EXPLICAN su propio mecanismo («Rellena los `<!-- FILL -->` con TU
  # negocio») y esa prosa se contaba como hueco pendiente. Es el falso positivo
  # de "narrar no es prescribir" que este repo ya ha pisado varias veces.
  #
  # El discriminador es la comilla invertida: un marcador REAL nunca va en
  # backticks (sería literal, no marcador) y una mención SIEMPRE los lleva
  # porque es markdown citando código. Medido contra las skills reales: 5
  # menciones, las 5 en backticks, 0 marcadores reales perdidos.
  {
    echo '# Skill de dominio'
    echo '> Rellena los `<!-- FILL -->` con TU negocio.'
    echo 'Ajusta los `<!-- FILL: ejemplo -->` a tus rutas reales.'
    echo 'Todo lo demás ya está decidido.'
  } > .agents/skills/domain/SKILL.md
  _sr_marcar_leida
  local out; out="$(_sr_fill_out 'src/Domain/User.swift')"
  [ -z "$out" ] || {
    echo "    FALSO POSITIVO: una skill que solo MENCIONA los FILL produjo aviso:"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_una_skill_que_solo_menciona_fill_no_avisa() { _sr_fill_sandbox _case_fp_mencion_en_backticks; }

_case_mencion_y_marcador_en_la_misma_linea() {
  # El otro lado del discriminador: si una línea tiene mención Y marcador real,
  # manda el marcador. Sin este test, "arreglar" el FP de arriba descartando la
  # línea entera en cuanto vea un backtick pasaría inadvertido — y sería una
  # evasión trivial (basta citar un FILL en la misma línea para ocultarlo).
  {
    echo '# Skill de dominio'
    echo 'Ajusta los `<!-- FILL -->` así: <!-- FILL: tu entidad real -->'
  } > .agents/skills/domain/SKILL.md
  _sr_marcar_leida
  local out; out="$(_sr_fill_out 'src/Domain/User.swift')"
  printf '%s' "$out" | grep -q '1 sin rellenar' \
    || { echo "    una línea con mención Y marcador debe contar 1 (el marcador):"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_mencion_y_marcador_en_la_misma_linea_cuenta_el_marcador() {
  _sr_fill_sandbox _case_mencion_y_marcador_en_la_misma_linea
}

_case_fill_hecho_no_avisa() {
  # La convención con la que un adoptante marca lo que YA rellenó no puede
  # contar como pendiente. Es el mismo bug que tenía el contador de
  # tools/harness-report.sh (un `-` al final de una clase es LITERAL), arreglado
  # en este mismo commit; aquí se nace con la forma correcta.
  {
    echo '# Skill de dominio'
    echo '<!-- FILL-HECHO: entidades definidas en Domain/Model -->'
    echo '<!-- FILL-HECHO -->'
  } > .agents/skills/domain/SKILL.md
  _sr_marcar_leida
  local out; out="$(_sr_fill_out 'src/Domain/User.swift')"
  [ -z "$out" ] || {
    echo "    FALSO POSITIVO: los FILL-HECHO (ya resueltos) contaron como pendientes:"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_los_fill_hecho_no_cuentan_como_pendientes() { _sr_fill_sandbox _case_fill_hecho_no_avisa; }

_case_el_aviso_no_cambia_la_decision() {
  # El aviso NO puede convertir un bloqueo en un permiso ni al revés. Sin skill
  # leída se bloquea, tenga la skill FILLs o no: son dos ejes independientes y
  # este test los mantiene independientes.
  printf '%s\n' '# Skill completa, cero FILL' > .agents/skills/domain/SKILL.md
  local rc; rc="$(_sr_fill_rc 'src/Domain/User.swift')"
  [ "$rc" = "2" ] || { echo "    sin la skill leída debe seguir bloqueando aunque no haya FILLs (exit=$rc)"; return 1; }

  _sr_skill_con_fills
  rc="$(_sr_fill_rc 'src/Domain/User.swift')"
  [ "$rc" = "2" ] || { echo "    sin la skill leída debe bloquear también CON FILLs (exit=$rc)"; return 1; }
}
test_el_aviso_de_fill_no_altera_la_decision_de_bloqueo() {
  _sr_fill_sandbox _case_el_aviso_no_cambia_la_decision
}

_case_marcador_truncado_cuenta() {
  # La alternativa `$` de FILL_ERE: la línea acaba justo tras "FILL", sin `-->`,
  # sin `:` y sin espacio. Pasa de verdad en una edición a medias, y hasta que
  # el `reviewer` lo señaló ningún test la ejercitaba — con el mismo criterio
  # que este repo ya aplica a _ADDA_PRECOND ("una rama que nadie ejercita es
  # decoración"). Al comprobarlo resultó que NO era decoración: sin la rama,
  # este marcador deja de contarse. Así que la rama se queda y lo que faltaba
  # era este fixture.
  printf '%s\n' '# Skill de dominio' '<!-- FILL' > .agents/skills/domain/SKILL.md
  _sr_marcar_leida
  local out; out="$(_sr_fill_out 'src/Domain/User.swift')"
  printf '%s' "$out" | grep -q '1 sin rellenar' \
    || { echo "    un marcador TRUNCADO (línea que acaba en FILL) no se contó:"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_un_marcador_de_fill_truncado_tambien_cuenta() {
  _sr_fill_sandbox _case_marcador_truncado_cuenta
}

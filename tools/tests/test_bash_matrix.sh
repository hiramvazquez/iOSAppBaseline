#!/usr/bin/env bash
# LA MATRIZ DE SKILLS TAMBIÉN VIGILA BASH.
#
# El agujero real: `skill-reminder` cuelga de `PreToolUse Edit|Write`, así que
# escribir con `sed -i`, `tee`, una redirección o `python3 -c` esquivaba la
# matriz §11 por completo. Por ahí se coló una decisión de arquitectura en el
# primer proyecto (el aislamiento de actores del target), sin mala intención:
# el agente usó la herramienta equivocada y nadie miró.
#
# El riesgo de este gate es el OPUESTO al del agujero: si bloquea comandos de
# LECTURA, alguien lo apaga entero y volvemos al punto de partida (ley del
# 10%). Por eso más de la mitad de estos tests son falsos positivos.

_bm_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/scripts/agent-hooks/lib" "$d/tools" "$d/.agents/skills/domain" "$d/app/Domain"
  cp -R "$PROJECT_ROOT/scripts/agent-hooks/." "$d/scripts/agent-hooks/"
  cp "$PROJECT_ROOT"/tools/*.sh "$d/tools/" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null; git config user.email t@t.t; git config user.name t
    echo x > seed.txt; git add seed.txt; git commit -qm init 2>/dev/null
    printf 'full\n' > tools/preset
    printf '# matriz\n**/Domain/**|.agents/skills/domain/SKILL.md\n' > tools/skill-matrix.conf
    printf '# skill\n' > .agents/skills/domain/SKILL.md
    printf 'let x = 1\n' > app/Domain/Movie.swift
    # Detectores en verde: aquí se prueba la matriz, no el resto del gate.
    stub tools/drift-ratchet.sh '#!/usr/bin/env bash\nexit 0\n'
    stub tools/check-layers.sh '#!/usr/bin/env bash\nexit 0\n'
    rm -f tools/semgrep-scan.sh tools/check-review-marker.sh 2>/dev/null
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_bmgate() { # _bmgate <comando> → exit code del hook
  echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$1\"}}" \
    | bash scripts/agent-hooks/reviewer-gate.sh >/dev/null 2>&1
  echo $?
}

# ── DETECCIONES: las cuatro formas de escribir esquivando Edit ───────
_case_sed_i_bloquea() {
  local rc; rc="$(_bmgate 'sed -i s/a/b/ app/Domain/Movie.swift')"
  [ "$rc" = "2" ] || { echo "    sed -i sobre un archivo de la matriz pasó (exit $rc)"; return 1; }
}
test_sed_in_place_sobre_la_matriz_bloquea() { _bm_sandbox _case_sed_i_bloquea; }

_case_redireccion_bloquea() {
  local rc; rc="$(_bmgate 'echo nuevo > app/Domain/Movie.swift')"
  [ "$rc" = "2" ] || { echo "    una redirección sobre la matriz pasó (exit $rc)"; return 1; }
}
test_redireccion_sobre_la_matriz_bloquea() { _bm_sandbox _case_redireccion_bloquea; }

_case_tee_bloquea() {
  local rc; rc="$(_bmgate 'echo x | tee app/Domain/Movie.swift')"
  [ "$rc" = "2" ] || { echo "    tee sobre la matriz pasó (exit $rc)"; return 1; }
}
test_tee_sobre_la_matriz_bloquea() { _bm_sandbox _case_tee_bloquea; }

_case_leida_la_skill_pasa() {
  # El camino feliz: si YA leíste la referencia, el comando pasa. Sin esto el
  # gate sería un muro, no un gate.
  mkdir -p .agents/state/skills-read
  : > ".agents/state/skills-read/.agents__skills__domain__SKILL.md.read"
  local rc; rc="$(_bmgate 'sed -i s/a/b/ app/Domain/Movie.swift')"
  [ "$rc" = "0" ] || { echo "    con la skill YA leída el comando fue bloqueado (exit $rc)"; return 1; }
}
test_con_la_referencia_leida_el_comando_pasa() { _bm_sandbox _case_leida_la_skill_pasa; }

# ── FALSOS POSITIVOS (más de la mitad de la suite, a propósito) ──────
_case_lectura_pasa() {
  # `cat` NO escribe. Bloquear lecturas es la vía rápida a que apaguen el gate.
  local rc; rc="$(_bmgate 'cat app/Domain/Movie.swift')"
  [ "$rc" = "0" ] || { echo "    un cat (lectura) fue bloqueado (exit $rc)"; return 1; }
}
test_leer_un_archivo_de_la_matriz_no_bloquea() { _bm_sandbox _case_lectura_pasa; }

_case_grep_pasa() {
  local rc; rc="$(_bmgate 'grep -n let app/Domain/Movie.swift')"
  [ "$rc" = "0" ] || { echo "    un grep sobre la matriz fue bloqueado (exit $rc)"; return 1; }
}
test_grep_sobre_la_matriz_no_bloquea() { _bm_sandbox _case_grep_pasa; }

_case_devnull_pasa() {
  # `2>/dev/null` es una redirección… a /dev/null. Si el parser la contara
  # como escritura, CUALQUIER comando silenciado dispararía el gate.
  local rc; rc="$(_bmgate 'ls app/Domain/Movie.swift 2>/dev/null')"
  [ "$rc" = "0" ] || { echo "    2>/dev/null se interpretó como escritura (exit $rc)"; return 1; }
}
test_redireccion_a_devnull_no_cuenta_como_escritura() { _bm_sandbox _case_devnull_pasa; }

_case_escribir_fuera_de_la_matriz_pasa() {
  local rc; rc="$(_bmgate 'echo hola > /tmp/apunte.txt')"
  [ "$rc" = "0" ] || { echo "    escribir FUERA de la matriz fue bloqueado (exit $rc)"; return 1; }
}
test_escribir_fuera_de_la_matriz_no_bloquea() { _bm_sandbox _case_escribir_fuera_de_la_matriz_pasa; }

_case_docs_exentos() {
  # Editar documentación NO es editar el código de ese área — el falso
  # positivo original de skill-reminder, que no puede reaparecer por Bash.
  mkdir -p docs
  local rc; rc="$(_bmgate 'echo nota >> docs/apuntes.md')"
  [ "$rc" = "0" ] || { echo "    escribir en docs/ fue bloqueado (exit $rc)"; return 1; }
}
test_escribir_documentacion_no_bloquea() { _bm_sandbox _case_docs_exentos; }

# ════════════════════════════════════════════════════════════════════
# f-gate-bash-lee-texto — el gate leía TEXTO como si fuera sintaxis
# ════════════════════════════════════════════════════════════════════
# Tres falsos positivos en un mismo día en un proyecto real: un mensaje de
# commit, un comentario dentro de un heredoc, y —el que lo retrata— el propio
# comando que registraba el hallazgo en el ledger. El agente acabó escribiendo
# la ruta incompleta para poder pasar: la evasión exacta que predice la ley
# del 10%. Tres FP en un día está muy por encima del umbral.

_case_mensaje_de_commit_no_es_escritura() {
  # El marker de review en verde: aquí se prueba la MATRIZ sobre el texto del
  # mensaje, no el gate de commit (que tiene sus propios tests). Sin este stub
  # el comando se bloquearía por otra razón y el test no probaría nada — pasó
  # en el primer intento.
  stub tools/check-review-marker.sh '#!/usr/bin/env bash\nexit 0\n'
  local rc; rc="$(_bmgate 'git commit -m \"fix(domain): mueve la logica a app/Domain/Movie.swift\"')"
  [ "$rc" != "2" ] || { echo "    un MENSAJE de commit que nombra una ruta se leyó como escritura"; return 1; }
}
test_una_ruta_en_el_mensaje_de_commit_no_bloquea() {
  _bm_sandbox _case_mensaje_de_commit_no_es_escritura
}

_case_redireccion_dentro_de_comillas_no_cuenta() {
  # El caso literal del ledger: el `>` vive dentro de --detail, es prosa.
  local rc; rc="$(_bmgate 'bash tools/findings/findings.sh add --detail \"el flujo va de A > app/Domain/Movie.swift\"')"
  [ "$rc" != "2" ] || { echo "    un '>' dentro de una CADENA se leyó como redirección real"; return 1; }
}
test_redireccion_entre_comillas_no_bloquea() {
  _bm_sandbox _case_redireccion_dentro_de_comillas_no_cuenta
}

_case_heredoc_es_datos_no_comandos() {
  local rc; rc="$(_bmgate 'cat <<EOF\n# ojo: esto reescribe app/Domain/Movie.swift\nsed -i s/a/b/ app/Domain/Movie.swift\nEOF')"
  [ "$rc" != "2" ] || { echo "    el CUERPO de un heredoc se leyó como comandos ejecutables"; return 1; }
}
test_el_cuerpo_de_un_heredoc_no_bloquea() {
  _bm_sandbox _case_heredoc_es_datos_no_comandos
}

_case_cp_en_prosa_no_secuestra_el_ultimo_token() {
  # `*cp\ *` casaba la subcadena en cualquier sitio: un texto con "cp " convertía
  # el último token del comando —cualquier cosa— en "destino de copia".
  local rc; rc="$(_bmgate 'echo \"hay que hacer cp de esto\" >> notas.txt app/Domain/Movie.swift')"
  [ "$rc" != "2" ] || { echo "    un 'cp ' en prosa secuestró el último token como destino"; return 1; }
}
test_cp_mencionado_en_prosa_no_bloquea() {
  _bm_sandbox _case_cp_en_prosa_no_secuestra_el_ultimo_token
}

# ── Y la contraparte: lo que SÍ debe seguir bloqueando ──────────────
# Un gate que deja de detectar por arreglar sus FP es un gate borrado. Estas
# tres formas reales de escritura tienen que seguir cazándose después del
# desnudado de comillas y heredocs.
_case_sigue_cazando_la_escritura_real() {
  local rc
  rc="$(_bmgate 'sed -i s/a/b/ app/Domain/Movie.swift')"
  [ "$rc" = "2" ] || { echo "    tras el arreglo, sed -i dejó de detectarse (exit $rc)"; return 1; }
  rc="$(_bmgate 'echo x > app/Domain/Movie.swift')"
  [ "$rc" = "2" ] || { echo "    tras el arreglo, la redirección dejó de detectarse (exit $rc)"; return 1; }
  rc="$(_bmgate 'cp otro.swift app/Domain/Movie.swift')"
  [ "$rc" = "2" ] || { echo "    tras el arreglo, cp dejó de detectarse (exit $rc)"; return 1; }
}
test_la_escritura_real_se_sigue_cazando() {
  _bm_sandbox _case_sigue_cazando_la_escritura_real
}

# ── CUARTA ocurrencia del mismo FP: `sed` sin anclar ────────────────
# El patrón era `*sed*-i*` — subcadena, no comando. Bloqueó esto, que no
# escribe absolutamente nada: hay un `sed -n` (lectura) y hay un `-i` DENTRO
# de `--include`. El anclaje ya se había aplicado a `cp`/`mv` una ocurrencia
# antes, con su comentario explicando el problema: se arregló un caso y no se
# buscó el hermano, sobre la regla donde esa lección está escrita.
_case_sed_de_lectura_con_include_no_bloquea() {
  local rc; rc="$(_bmgate 'sed -n 54,58p app/Domain/Movie.swift && grep -rc assert( Pelis --include=*.swift')"
  [ "$rc" != "2" ] || { echo "    un 'sed -n' de LECTURA + un '--include' se leyó como edición in-place"; return 1; }
}
test_sed_de_lectura_con_flag_que_contiene_i_no_bloquea() {
  _bm_sandbox _case_sed_de_lectura_con_include_no_bloquea
}

_case_flags_largos_con_i_no_disparan() {
  # `--interactive`, `--ignore-case`, `--include`: cualquiera contiene `-i`.
  local rc; rc="$(_bmgate 'grep --ignore-case foo app/Domain/Movie.swift')"
  [ "$rc" != "2" ] || { echo "    un '--ignore-case' se leyó como edición in-place"; return 1; }
}
test_un_flag_largo_que_contiene_i_no_es_edicion_in_place() {
  _bm_sandbox _case_flags_largos_con_i_no_disparan
}

_case_sed_i_real_sigue_bloqueando() {
  # Y el guard del guard: anclar no puede convertirse en dejar de detectar.
  local rc
  rc="$(_bmgate 'sed -i s/a/b/ app/Domain/Movie.swift')"
  [ "$rc" = "2" ] || { echo "    tras anclar, 'sed -i' dejó de detectarse (exit $rc)"; return 1; }
  rc="$(_bmgate 'perl -pi -e s/a/b/ app/Domain/Movie.swift')"
  [ "$rc" = "2" ] || { echo "    tras anclar, 'perl -pi' dejó de detectarse (exit $rc)"; return 1; }
  rc="$(_bmgate 'cat x.txt && sed -i.bak s/a/b/ app/Domain/Movie.swift')"
  [ "$rc" = "2" ] || { echo "    'sed -i.bak' tras && dejó de detectarse (exit $rc)"; return 1; }
}
test_la_edicion_in_place_real_se_sigue_cazando() {
  _bm_sandbox _case_sed_i_real_sigue_bloqueando
}

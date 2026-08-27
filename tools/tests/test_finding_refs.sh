#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# Dos checks sobre la CREDIBILIDAD del ledger
# ════════════════════════════════════════════════════════════════════
# El ledger solo sirve si lo que dice se puede comprobar. Dos formas concretas
# de que deje de servir sin que nadie lo note:
#
#   1. `check-finding-refs.sh`     — la doc cita un id que no existe. Lee como
#      cerrado, y nadie vuelve a abrir el tema. El hallazgo se evaporó CON EL
#      ASPECTO de haberse cerrado.
#   2. `check-version-claims.sh`   — un hallazgo declara una herramienta incapaz
#      citando al gestor de paquetes. `brew` sirve el último RELEASE, no lo que
#      soporta el proyecto: la conclusión negativa puede llevar meses siendo
#      falsa, y se auto-preserva porque desalienta la comprobación que la
#      refutaría.
#
# Los dos son detectores sobre TEXTO, que es el terreno donde este harness ya
# ha pisado cuatro veces la misma mina — de ahí que los guards de FALSO
# POSITIVO de abajo pesen más que los casos de detección.

_fr_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/findings" "$d/docs"
  cp "$PROJECT_ROOT/tools/check-finding-refs.sh"   "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/check-version-claims.sh" "$d/tools/" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q .; git config user.email t@t.t; git config user.name t
    "$1"
  )
  local rc=$?; rm -rf "$d"; return $rc
}

_led() { printf '%s\n' "$@" > tools/findings/ledger.jsonl; }
_j()   { printf '{"id":"%s","title":"%s","area":"x","severity":"low","tier":"auto-fix","status":"open","detail":"%s","source":"%s","resolution":"%s","links":[],"createdAt":"2026-01-01","updatedAt":"2026-01-01"}' \
          "$1" "${2:-t}" "${3:-}" "${4:-}" "${5:-}"; }

# ════════════════════════════════════════════════════════════════════
# check-finding-refs.sh
# ════════════════════════════════════════════════════════════════════

_case_id_fantasma_se_caza() {
  _led "$(_j f-existe)"
  printf 'Ver `f-existe` y también `f-no-existe`.\n' > docs/notas.md
  local out rc; out="$(bash tools/check-finding-refs.sh 2>&1)"; rc=$?
  [ "$rc" = "1" ] || { echo "    un id fantasma NO bloqueó (exit $rc)"; return 1; }
  case "$out" in *f-no-existe*) : ;; *)
    echo "    no nombró el id fantasma:"; printf '%s\n' "$out" | sed 's/^/      /'; return 1 ;; esac
  case "$out" in *f-existe:*|*"- docs/notas.md: \`f-existe\`"*)
    echo "    acusó a un id que SÍ existe"; return 1 ;; esac
}
test_un_id_de_finding_que_no_existe_bloquea() { _fr_sandbox _case_id_fantasma_se_caza; }

# ── FALSO POSITIVO nº1: la subcadena de otra palabra ────────────────
# Este es el caso REAL con el que nació el check. Un `grep -o 'f-[a-z-]*'` sobre
# el texto crudo casa `f-nature` dentro de `check-diff-nature`: el detector se
# dispara con el texto que HABLA de un archivo en vez de con una cita. Cuatro
# veces en este repo; la quinta la caza este test.
_case_subcadena_no_es_cita() {
  _led "$(_j f-real)"
  cat > docs/notas.md <<'MD'
El gate `check-diff-nature` mira la naturaleza del diff, y `tools/check-drift.sh`
lo agrega. Nada de esto cita un hallazgo. Ver `f-real` para el histórico.
MD
  local out rc; out="$(bash tools/check-finding-refs.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: una subcadena dentro de otro nombre contó como cita (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_una_subcadena_dentro_de_otro_nombre_no_es_una_cita() {
  _fr_sandbox _case_subcadena_no_es_cita
}

# ── FALSO POSITIVO nº2: los ejemplos de uso del CLI ─────────────────
# `tools/findings/README.md` documenta `close f-xxxx --resolution ...` dentro de
# un bloque de código. Acusar a la doc del propio CLI de citar un fantasma sería
# el estreno perfecto: el detector suspendiendo al manual que lo explica.
_case_ejemplos_del_cli_no_cuentan() {
  _led "$(_j f-real)"
  cat > docs/notas.md <<'MD'
Uso:

```bash
bash tools/findings/findings.sh close f-xxxx --resolution "commit abc"
bash tools/findings/findings.sh close `f-de-mentira` --resolution "x"
```

Y un placeholder suelto: `f-xxxx`.
MD
  local out rc; out="$(bash tools/check-finding-refs.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: los ejemplos del CLI contaron como citas (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_los_ejemplos_de_uso_no_se_confunden_con_citas() {
  _fr_sandbox _case_ejemplos_del_cli_no_cuentan
}

_case_sin_ledger_es_exit3() {
  # "No pude mirar" ≠ "todo bien" (§14.3). Un repo recién adoptado sin ledger
  # no puede leerse como "las citas resuelven": no hay contra qué resolverlas.
  rm -f tools/findings/ledger.jsonl
  printf 'Ver `f-lo-que-sea`.\n' > docs/notas.md
  bash tools/check-finding-refs.sh >/dev/null 2>&1
  [ "$?" = "3" ] || { echo "    sin ledger no devolvió exit 3"; return 1; }
}
test_sin_ledger_dice_que_no_pudo_mirar() { _fr_sandbox _case_sin_ledger_es_exit3; }

# ════════════════════════════════════════════════════════════════════
# check-version-claims.sh
# ════════════════════════════════════════════════════════════════════

_case_version_sin_repo_bloquea() {
  _led "$(_j f-nivel4 "El nivel 4 no se puede medir" \
          "muter 16 no parsea typed throws de Swift 6, y brew no sirve otra." )"
  local out rc; out="$(bash tools/check-version-claims.sh 2>&1)"; rc=$?
  [ "$rc" = "1" ] || { echo "    una afirmación de versión sin repo NO bloqueó (exit $rc)"; return 1; }
  case "$out" in *f-nivel4*) : ;; *)
    echo "    no nombró el hallazgo"; printf '%s\n' "$out" | sed 's/^/      /'; return 1 ;; esac
  case "$out" in *"gestor de paquetes"*) : ;; *)
    echo "    no señaló que citar al gestor de paquetes es justo lo que no basta"; return 1 ;; esac
}
test_declarar_una_herramienta_incapaz_sin_citar_el_repo_bloquea() {
  _fr_sandbox _case_version_sin_repo_bloquea
}

_case_con_repo_pasa() {
  _led "$(_j f-nivel4 "El nivel 4 no se puede medir" \
          "muter 16 no parsea typed throws; el repositorio (https://github.com/muter-mutation-testing/muter) lo arregla en main sin release." )"
  bash tools/check-version-claims.sh >/dev/null 2>&1 \
    || { echo "    citar el repositorio no fue suficiente para pasar"; return 1; }
}
test_citar_el_repositorio_satisface_el_check() { _fr_sandbox _case_con_repo_pasa; }

_case_excepcion_declarada() {
  # Hay herramientas sin repositorio público. Forzar una URL inventada sería
  # peor que no pedir nada: la excepción se DECLARA, como `n/a-manual`.
  _led "$(_j f-x "..." "la herramienta interna 3 no soporta el flag" "" "n/a-repo — binario propietario, no hay fuente que mirar")"
  bash tools/check-version-claims.sh >/dev/null 2>&1 \
    || { echo "    la excepción declarada n/a-repo no se respetó"; return 1; }
}
test_la_excepcion_n_a_repo_se_respeta() { _fr_sandbox _case_excepcion_declarada; }

# ── FALSO POSITIVO nº1: una OBSERVACIÓN no es una afirmación de no-existencia ──
# "jq 1.6 se comporta así" se verifica CORRIENDO jq: la copia que tienes basta
# como evidencia y pedir una URL sería ruido puro. Solo la afirmación de que
# NO EXISTE una versión capaz necesita mirar la fuente, porque es justo lo que
# tu copia no puede decirte. Sin esta distinción el check saltaría con cada
# número de versión del ledger y moriría por la ley del 10% en su primera semana.
_case_observacion_de_version_no_dispara() {
  _led "$(_j f-jq "El guard estaba inerte en jq 1.6" \
          "jq 1.6 devuelve 0 donde jq 1.7 devuelve 1; el guard nunca saltaba. Medido corriendo ambas." )" \
       "$(_j f-node "Fijamos node 18 en CI" "node 18.20 es la version del runner." )"
  local out rc; out="$(bash tools/check-version-claims.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: una observación sobre versiones exigió citar un repo (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
  case "$out" in *"afirmaciones=0"*) : ;; *)
    echo "    contó como afirmación algo que solo describe lo observado: $out"; return 1 ;; esac
}
test_una_observacion_sobre_versiones_no_exige_repositorio() {
  _fr_sandbox _case_observacion_de_version_no_dispara
}

# ── FALSO POSITIVO nº2: "no parsea" sin herramienta ni versión ──────
# El ledger dice, de un hallazgo del harness: "si no parsean, avisa y sale 0".
# Habla de hooks, no de la versión de nada. Un detector que casara el verbo
# suelto acusaría a media mitad del ledger.
_case_verbo_suelto_no_dispara() {
  _led "$(_j f-brick "Un hook roto brickeaba al agente" \
          "run-hook.sh valida con bash -n el hook y sus libs antes de exec; si no parsean, avisa y sale 0." )"
  local out rc; out="$(bash tools/check-version-claims.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: 'no parsean' sin herramienta ni versión disparó (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_un_verbo_de_incapacidad_sin_version_no_dispara() {
  _fr_sandbox _case_verbo_suelto_no_dispara
}

# ── El detector, contra el artefacto REAL del repo ──────────────────
# La ley que este harness ya tiene escrita: **el primer fallo de una pieza que
# procesa un artefacto del repo aparece contra ESE artefacto** (le pasó al
# merge de settings, que nació roto y sus seis tests sintéticos lo aprobaron).
# Estos dos checks leen el ledger y la doc de VERDAD; los fixtures de arriba no
# sustituyen correrlos contra ellos.
test_los_dos_checks_corren_limpios_contra_el_repo_real() {
  local out rc
  out="$(cd "$PROJECT_ROOT" && bash tools/check-finding-refs.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    check-finding-refs falla contra la doc real del repo (exit $rc):"
    printf '%s\n' "$out" | tail -6 | sed 's/^/      /'; return 1; }
  out="$(cd "$PROJECT_ROOT" && bash tools/check-version-claims.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    check-version-claims falla contra el ledger real del repo (exit $rc):"
    printf '%s\n' "$out" | tail -8 | sed 's/^/      /'; return 1; }
}

# ════════════════════════════════════════════════════════════════════
# EL CORPUS DE PROSA AJENA (tools/findings/fixtures/)
# ════════════════════════════════════════════════════════════════════
# `check-version-claims` se validó contra el ledger del template —38 entradas,
# disparó en 1, y era la defectuosa— y pareció cirugía. El primer adoptante lo
# corrió contra el suyo (61 entradas, prosa española densa, historias y
# criterios numerados) y disparó 3 veces con DOS falsos positivos: 67%, muy por
# encima del 10% que el propio detector cita como criterio de diseño.
#
# La lección, que es la del ciclo anterior un piso más arriba:
#   **"contra el artefacto real" incluye el artefacto real de OTRO.**
#   Quien escribe el detector escribe, sin querer, el corpus que lo aprueba.
#
# Estos dos tests son el mecanismo. El BUENO es el que importa: es el guard de
# falsos positivos de toda la capa, y sus entradas `[adoptante]` son texto real
# copiado literal — su valor está en no haberlo escrito nosotros.
_FIX="tools/findings/fixtures"

test_el_corpus_de_prosa_ajena_no_produce_ni_un_hallazgo() {
  local f="$PROJECT_ROOT/$_FIX/ledger-bueno.jsonl"
  [ -f "$f" ] || { echo "    falta el corpus BUENO ($_FIX/ledger-bueno.jsonl)"; return 1; }
  local out rc
  out="$(cd "$PROJECT_ROOT" && FINDINGS_LEDGER="$_FIX/ledger-bueno.jsonl" \
         bash tools/check-version-claims.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO sobre prosa que no escribimos nosotros (exit $rc):"
    printf '%s\n' "$out" | grep '^  - ' | sed 's/^/      /'
    echo "    Recuerda el reparto: 'no tiene' en español es CARECER, no 'no soporta';"
    echo "    y <palabra> <número> casa con 'criterio 6', 'la 0006', 'Los 3 casts'."
    return 1; }
  case "$out" in *"afirmaciones=0"*) : ;; *)
    echo "    contó afirmaciones donde no las hay: $out"; return 1 ;; esac
}

test_el_corpus_malo_dispara_en_todas_sus_formas() {
  # El guard del guard: arreglar los falsos positivos no puede vaciar el
  # detector. Cada forma que caza tiene su línea aquí.
  local f="$PROJECT_ROOT/$_FIX/ledger-malo.jsonl" n
  [ -f "$f" ] || { echo "    falta el corpus MALO ($_FIX/ledger-malo.jsonl)"; return 1; }
  n="$(grep -c '"id"' "$f" 2>/dev/null || echo 0)"
  local out; out="$(cd "$PROJECT_ROOT" && FINDINGS_LEDGER="$_FIX/ledger-malo.jsonl" \
                    bash tools/check-version-claims.sh 2>&1)"
  case "$out" in *"afirmaciones=$n"*) : ;; *)
    echo "    el corpus MALO tiene $n entradas y el detector no las cazó todas:"
    printf '%s\n' "$out" | head -2 | sed 's/^/      /'
    echo "    Una forma que deja de dispararse es un agujero, no una mejora."
    return 1 ;; esac
}

test_el_corpus_ajeno_lleva_los_textos_que_produjeron_el_fallo() {
  # Un corpus que se reescribe "para que quede mejor" deja de reproducir nada.
  # Los dos textos que el adoptante midió tienen que seguir ahí, literales.
  local f="$PROJECT_ROOT/$_FIX/ledger-bueno.jsonl"
  grep -q 'no tiene test que lo verifique' "$f" 2>/dev/null \
    || { echo "    desapareció del corpus el FP 'criterio 6 ... no tiene test'"; return 1; }
  grep -q 'no tiene alternativa' "$f" 2>/dev/null \
    || { echo "    desapareció del corpus el FP 'Los 3 casts ... no tiene alternativa'"; return 1; }
}

# ── El caso que PARECE del corpus bueno y va en el malo ─────────────
# Un hallazgo que CITA una afirmación de versión como ejemplo. Se propuso
# exentarlo —citar ≠ afirmar— invocando dos precedentes reales: el git-guard no
# salta con `grep "git commit --no-verify" doc.md`, y la matriz de Bash desnuda
# las cadenas entrecomilladas. Pero esos dos se apoyan en una gramática EXTERNA
# (el shell no ejecuta lo entrecomillado, y quien lo dictamina es su parser, no
# nuestro criterio). En prosa no hay tal gramática: las comillas son estilo, y
# exentarlas regalaría una primitiva de evasión — envuelve la afirmación en
# comillas y pasa. Este test fija la decisión para que nadie la "arregle" luego.
test_una_afirmacion_de_version_citada_como_ejemplo_sigue_disparando() {
  local f="$PROJECT_ROOT/$_FIX/ledger-malo.jsonl"
  grep -q 'f-malo-citada-como-ejemplo' "$f" 2>/dev/null \
    || { echo "    el caso 'citada como ejemplo' desapareció del corpus MALO"; return 1; }
  grep -q 'f-malo-citada-como-ejemplo' "$PROJECT_ROOT/$_FIX/ledger-bueno.jsonl" 2>/dev/null \
    && { echo "    el caso 'citada como ejemplo' se movió al corpus BUENO."
         echo "    Eso exenta lo entrecomillado, y en prosa las comillas las controla"
         echo "    el evaluado: sería una primitiva de evasión, no una lectura mejor."
         return 1; }
  return 0
}

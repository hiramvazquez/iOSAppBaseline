#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# test_e2e_gates_anillo3.sh — GOLDEN 8/9 del PRD 0004 (fase 10)
# ════════════════════════════════════════════════════════════════════
# Parte de la MATRIZ E2E del PRD 0004, dividida en fase 2a del PRD 0005
# (tools/tests/test_e2e_matrix.sh superaba el hard limit de 400 líneas,
# AGENTS.md §4) por FAMILIA de escenario, no por posición. Este archivo
# cubre la infraestructura de GATES del Anillo 3: la caché de Semgrep
# acelera el mismo diff sin pagar el coste del scanner y nunca cachea un
# hallazgo real (G8); y `ci/run-gates.sh` invoca TODO lo que promete en
# preset full, un gate en rojo o AUSENTE tumba el anillo entero (G9). Las
# hermanas de esta matriz — capacidades declaradas, orquestador del backlog,
# ledger/lecciones, plataformas — viven en los otros `test_e2e_*.sh`.
#
# QUÉ ES ESTO Y QUÉ NO ES. `test_gate_cache.sh` fija la corrección de la
# clave de caché; esto mide lo que el PRD §10 promete y nadie medía: que un
# hit NO paga el coste del scanner. Y `ci/run-gates.sh` era el único
# entrypoint del harness sin test propio — la promesa "el preset full no
# reduce ningún gate" vivía solo en prosa.
#
# HERMÉTICA POR CONSTRUCCIÓN: ni `claude` ni `semgrep` reales. Los proveedores
# entran por stubs en un `bin/` del sandbox y el PATH se fija a mano, así que
# el resultado no depende de lo que tenga instalado la máquina.

# ── Sandbox con la maquinaria real, no con recortes ──────────────────
# Un E2E que copia solo los tres scripts que va a llamar no prueba la
# integración: prueba el recorte que hizo quien escribió el test. Aquí va la
# maquinaria entera (tools sin su propia suite, scripts, ci, .github) sobre un
# repo git nuevo.
_e2e_repo() { # _e2e_repo <función>
  local d rc; d="$(mktemp -d)"
  cp -R "$PROJECT_ROOT/tools" "$d/tools" 2>/dev/null
  rm -rf "$d/tools/tests"
  cp -R "$PROJECT_ROOT/scripts" "$d/scripts" 2>/dev/null
  cp -R "$PROJECT_ROOT/ci" "$d/ci" 2>/dev/null
  mkdir -p "$d/.github/workflows" "$d/docs/process" "$d/backlog"
  cp "$PROJECT_ROOT/.github/workflows/harness-ci.yml" "$d/.github/workflows/" 2>/dev/null
  cp "$PROJECT_ROOT/AGENTS.md" "$d/AGENTS.md" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q -b develop . 2>/dev/null
    git config user.email t@t.t; git config user.name t
    echo seed > seed.txt
    git add -A >/dev/null 2>&1
    git commit -qm "seed: maquinaria del harness" >/dev/null 2>&1
    "$1"
  )
  rc=$?
  rm -rf "$d"
  return $rc
}

# ════════════════════════════════════════════════════════════════════
# GOLDEN 8 — la caché acelera el mismo diff y jamás inventa detección
# ════════════════════════════════════════════════════════════════════
# `test_gate_cache.sh` fija la corrección de la clave. Aquí se mide lo que el
# PRD §10 promete y nadie medía: que un hit NO paga el coste del scanner, que
# es de donde sale la reducción de tiempo en gates repetidos.
#
# ⚠️ POR QUÉ LA ASERCIÓN ES SOBRE LA DIFERENCIA Y NO SOBRE EL RATIO. La versión
# anterior exigía `hit ≤ 0,7 × miss`. Ese ratio depende del overhead fijo de la
# máquina (arranque de python, git), no solo de la caché: en un runner lento
# —overhead 3 s, scan 2 s— un hit perfecto da 3/5 = 60% y el test se pondría
# rojo sin que hubiera nada roto. Un test que falla por contención de CPU se
# desactiva en una semana (ley del 10%, AGENTS.md §14.2), y con él se pierde la
# señal real. La diferencia `miss - hit`, en cambio, está acotada POR EL FIXTURE
# —el stub duerme una cantidad conocida— y no por la velocidad del host.
# La garantía dura sigue siendo el conteo de invocaciones, que es determinista.
_case_g8_cache_acelera_y_no_finge() {
  command -v jq >/dev/null 2>&1 \
    || { echo "    la matriz E2E exige jq (dependencia dura del harness)"; return 1; }
  mkdir -p bin src
  local calls="$PWD/semgrep-calls.log"; : > "$calls"
  # El scan duerme 3 s; `--version` (que la caché consulta para su key) no.
  stub bin/semgrep '#!/usr/bin/env bash\ncase "${1:-}" in --version) echo 9.9.9; exit 0 ;; esac\necho scan >> "$SEMGREP_CALLS"\nsleep 3\nprintf "{\\"results\\":[],\\"errors\\":[]}\\n"\nexit 0\n'
  printf 'contenido\n' > src/a.txt
  git add src/a.txt

  local t0 t1 miss hit salida
  t0="$(date +%s)"
  salida="$(PATH="$PWD/bin:$PATH" SEMGREP_CALLS="$calls" bash tools/semgrep-scan.sh --staged 2>/dev/null)"
  [ "$?" = 0 ] || { echo "    el primer scan no salió limpio"; return 1; }
  t1="$(date +%s)"; miss=$((t1 - t0))
  assert_contains "$salida" 'SEMGREP_SUMMARY errors=0 warns=0' || return 1

  t0="$(date +%s)"
  salida="$(PATH="$PWD/bin:$PATH" SEMGREP_CALLS="$calls" bash tools/semgrep-scan.sh --staged 2>/dev/null)"
  [ "$?" = 0 ] || { echo "    el segundo scan (hit) no salió limpio"; return 1; }
  t1="$(date +%s)"; hit=$((t1 - t0))
  assert_contains "$salida" 'SEMGREP_SUMMARY errors=0 warns=0' || return 1
  [ "$(grep -c . "$calls")" = 1 ] \
    || { echo "    el mismo diff volvió a invocar al scanner ($(grep -c . "$calls") veces)"; return 1; }
  # El fixture duerme 3 s en el scan; con resolución de 1 s, un hit que se
  # saltó ese scan mide como mínimo 1 s menos que el miss, en cualquier host.
  [ $((miss - hit)) -ge 1 ] \
    || { echo "    el hit pagó el coste del scanner (miss=${miss}s hit=${hit}s)"; return 1; }

  # Cambia el diff → la evidencia vieja no vale.
  printf 'otro contenido\n' > src/a.txt
  git add src/a.txt
  PATH="$PWD/bin:$PATH" SEMGREP_CALLS="$calls" bash tools/semgrep-scan.sh --staged >/dev/null 2>&1
  [ "$(grep -c . "$calls")" = 2 ] \
    || { echo "    un diff distinto reutilizó la caché"; return 1; }

  # Un hallazgo real NUNCA se cachea: dos corridas, dos scans.
  stub bin/semgrep '#!/usr/bin/env bash\ncase "${1:-}" in --version) echo 9.9.9; exit 0 ;; esac\necho scan >> "$SEMGREP_CALLS"\nprintf "{\\"results\\":[{\\"path\\":\\"src/a.txt\\",\\"start\\":{\\"line\\":1},\\"check_id\\":\\"e2e\\",\\"extra\\":{\\"severity\\":\\"ERROR\\",\\"message\\":\\"hallazgo\\"}}],\\"errors\\":[]}\\n"\nexit 0\n'
  : > "$calls"
  PATH="$PWD/bin:$PATH" SEMGREP_CALLS="$calls" bash tools/semgrep-scan.sh --staged >/dev/null 2>&1
  [ "$?" = 1 ] || { echo "    un hallazgo ERROR no bloqueó"; return 1; }
  PATH="$PWD/bin:$PATH" SEMGREP_CALLS="$calls" bash tools/semgrep-scan.sh --staged >/dev/null 2>&1
  [ "$(grep -c . "$calls")" = 2 ] \
    || { echo "    un exit 1 quedó cacheado: el segundo scan no corrió"; return 1; }
}
test_golden_08_cache_acelera_sin_perder_deteccion() {
  _e2e_repo _case_g8_cache_acelera_y_no_finge
}

# ════════════════════════════════════════════════════════════════════
# GOLDEN 9 — el Anillo 3 llama a TODO lo que promete
# ════════════════════════════════════════════════════════════════════
# `ci/run-gates.sh` era el único entrypoint del harness sin test propio: la
# promesa "el preset full no reduce ningún gate" vivía en prosa. Aquí cada
# gate es un stub que firma su paso, así que el conjunto invocado es un hecho
# observable — y un gate ausente sigue siendo fallo, no silencio.
# ── EL INVENTARIO VIVE UNA SOLA VEZ ────────────────────────────────
# Estaba escrito DOS veces dentro de este mismo test —una para stubear, otra
# para verificar— y las dos listas ya habían divergido: la de stubs tenía 14
# entradas y la de comprobación 13. La diferencia era correcta (escape-rate es
# informativo y nunca bloquea) pero no estaba dicha en ninguna parte, así que
# era indistinguible de un olvido. Lo cazó el adoptante al añadir un gate y
# tener que editar las dos a mano: *una regla implementada dos veces diverge*.
#
# ⚠️ NO se deriva de `ci/run-gates.sh`, y la tentación es fuerte. Un test que
# lee su expectativa del código que prueba no puede detectar que se BORRE un
# gate de run-gates: la lista encogería y el test seguiría verde. Y "un gate
# ausente sigue siendo fallo, no silencio" es literalmente lo único que este
# golden existe para garantizar. La lista es la ESPECIFICACIÓN, se mantiene a
# mano a propósito, y lo único que se arregla aquí es que viva en un sitio.
#
#   <ruta>              gate que el Anillo 3 DEBE invocar en preset full
#   <ruta> informativo  se stubea para que el run llegue al final, pero su
#                       ausencia no es fallo (métrica, nunca bloquea)
_G9_INVENTARIO="
tools/tests/run-tests.sh
tools/secret-scan.sh
tools/semgrep-scan.sh
tools/check-layers.sh
tools/check-source-sets.sh
tools/drift-ratchet.sh
tools/verify-run.sh
tools/mutation-score.sh
tools/check-review-marker.sh
ci/ai-review.sh
tools/lesson-detector-link.sh
tools/check-finding-refs.sh
tools/check-version-claims.sh
tools/check-execution-map.sh
tools/metrics/escape-rate.sh informativo
"
_g9_gates() { # _g9_gates stub|exigidos
  printf '%s\n' "$_G9_INVENTARIO" | awk -v modo="$1" '
    NF == 0 { next }
    modo == "stub"     { print $1; next }
    $2 != "informativo" { print $1 }'
}

_case_g9_anillo3_invoca_todos_los_gates() {
  mkdir -p bin
  local log="$PWD/gates.log"; : > "$log"
  local recorder='#!/usr/bin/env bash\necho NOMBRE >> "$GATE_LOG"\nexit 0\n'
  local nombre
  for nombre in $(_g9_gates stub); do
    stub "$nombre" "${recorder/NOMBRE/$nombre}"
  done
  stub bin/gitleaks '#!/usr/bin/env bash\nexit 0\n'

  GATE_LOG="$log" PATH="$PWD/bin:/usr/bin:/bin" bash ci/run-gates.sh --backend fake >/dev/null 2>&1
  local rc=$? faltan=""
  [ "$rc" = 0 ] || { echo "    run-gates con todos los gates en verde salió $rc"; return 1; }
  for nombre in $(_g9_gates exigidos); do
    grep -qxF "$nombre" "$log" || faltan="$faltan $nombre"
  done
  [ -z "$faltan" ] || { echo "    el Anillo 3 no invocó:$faltan"; return 1; }

  # Un gate en rojo tumba el anillo entero.
  : > "$log"
  stub tools/check-layers.sh '#!/usr/bin/env bash\necho tools/check-layers.sh >> "$GATE_LOG"\nexit 1\n'
  GATE_LOG="$log" PATH="$PWD/bin:/usr/bin:/bin" bash ci/run-gates.sh --backend fake >/dev/null 2>&1
  [ "$?" = 1 ] || { echo "    un gate en rojo no tumbó a run-gates"; return 1; }

  # Y un gate AUSENTE tampoco es verde (§14.3: fail-closed en CI).
  : > "$log"
  stub tools/check-layers.sh '#!/usr/bin/env bash\necho tools/check-layers.sh >> "$GATE_LOG"\nexit 0\n'
  rm -f tools/semgrep-scan.sh
  GATE_LOG="$log" PATH="$PWD/bin:/usr/bin:/bin" bash ci/run-gates.sh --backend fake >/dev/null 2>&1
  [ "$?" = 1 ] || { echo "    un gate ausente pasó por gate aprobado"; return 1; }
}
test_golden_09_preset_full_no_reduce_ningun_gate() {
  _e2e_repo _case_g9_anillo3_invoca_todos_los_gates
}


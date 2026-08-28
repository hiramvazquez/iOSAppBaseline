#!/usr/bin/env bash
# Control NEGATIVO de `layers.conf` (tools/check-layers-coverage.sh).
#
# `check-layers.sh` responde «¿alguien importa lo que no debe?».
# Este detector responde la otra mitad: «¿alguna regla dejó de mirar?».
#
# Nació de un fallo real (2026-08-28, OQ-4 del PRD 0001): al mover
# `Sources/UI/Movies/` → `Sources/Features/Movies/`, el glob `*/UI/*` de la
# regla «la UI no habla HTTP» dejó de casar con ningún archivo. La regla no
# falló: dejó de existir, en silencio, y `check-layers.sh` siguió imprimiendo
# `errors=0`. Un gate que no mira parece un gate que pasa (AGENTS.md §14.3).
#
# Los FALSOS POSITIVOS que este detector puede cometer, y que los casos de abajo
# fijan, son dos y muy concretos:
#   1. Bloquear por reglas del bloque UNIVERSAL, que traen globs de otros stacks
#      (`*/ui/*` de web, `*/domain/*` de js) y nunca casarán en un repo Swift.
#      Bloquear por ellas sería un falso positivo permanente ⇒ el detector se
#      desactivaría entero (ley del 10%, §14.2).
#   2. Contar como huérfana una regla que sí cubre archivos en subcarpetas
#      profundas, por un fallo de matching del glob.

_lcov_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools"
  cp "$PROJECT_ROOT/tools/check-layers-coverage.sh" "$d/tools/" 2>/dev/null
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

_lcov_mk() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }

_lcov_conf() {
  # $1 = bloque de reglas propias (debajo del marcador)
  cat > tools/layers.conf <<EOF
# Reglas universales de la plantilla compartida.
*/domain/* :: ^(react|react-dom)$ :: el dominio no puede importar UI
*/ui/* :: ^(@supabase/.*)$ :: la UI no accede a datos directamente

# ── Reglas propias del proyecto ────────────────────────────────────
$1
EOF
}

# ── happy path: toda regla propia cubre algo ────────────────────────
_case_reglas_cubiertas_pasa() {
  _lcov_mk Sources/Domain/Movies/Movie.swift 'import Foundation'
  _lcov_conf '*/Domain/* :: ^(SwiftUI)$ :: el dominio no importa UI'
  local rc
  bash tools/check-layers-coverage.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || { echo "    una regla que SÍ cubre archivos se reportó huérfana (rc=$rc)"; return 1; }
}
test_reglas_cubiertas_pasa() { _lcov_sandbox _case_reglas_cubiertas_pasa; }

# ── FALSO POSITIVO 1: el bloque universal no debe bloquear ──────────
# Es el caso que mata al detector si se equivoca: `*/ui/*` y `*/domain/*` en
# minúscula son de stack web y NUNCA casarán en un repo Swift. Si bloquearan,
# este detector estaría rojo de forma permanente en todo repo iOS del template.
_case_universales_mudas_no_bloquean() {
  _lcov_mk Sources/Domain/Movies/Movie.swift 'import Foundation'
  _lcov_conf '*/Domain/* :: ^(SwiftUI)$ :: el dominio no importa UI'
  local out rc
  out="$(bash tools/check-layers-coverage.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: bloqueó por reglas del bloque universal (otros stacks). salida: $out"
    return 1
  }
  # …pero NO deben quedar invisibles: se cuentan y se muestran.
  case "$out" in
    *universales_mudas=2*) return 0 ;;
    *) echo "    las universales mudas no se reportaron en el summary: $out"; return 1 ;;
  esac
}
test_universales_mudas_no_bloquean() { _lcov_sandbox _case_universales_mudas_no_bloquean; }

# ── FALSO POSITIVO 2: subcarpetas profundas ─────────────────────────
# El glob `*/Features/*` debe casar con `Sources/Features/Movies/X.swift`, con
# subcarpeta intermedia. Un matching que no cruce `/` daría huérfana una regla
# viva — y el arreglo «obvio» sería borrarla, apagando el gate de verdad.
_case_subcarpeta_profunda_no_es_huerfana() {
  _lcov_mk Sources/Features/Movies/Detalle/PosterView.swift 'import SwiftUI'
  _lcov_conf '*/Features/* :: ^(CoreNetworking)$ :: la UI no habla HTTP'
  local out rc
  out="$(bash tools/check-layers-coverage.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: dio huérfana una regla que cubre un archivo anidado. salida: $out"
    return 1
  }
}
test_subcarpeta_profunda_no_es_huerfana() { _lcov_sandbox _case_subcarpeta_profunda_no_es_huerfana; }

# ── detección real: la regla que sobrevivió a un renombrado ─────────
_case_regla_huerfana_se_caza() {
  _lcov_mk Sources/Features/Movies/PopularMoviesView.swift 'import SwiftUI'
  # `*/UI/*` sobrevive al renombrado a Features/ y ya no casa con nada:
  # el escenario exacto de OQ-4.
  _lcov_conf '*/Features/* :: ^(CoreNetworking)$ :: la UI no habla HTTP
*/UI/* :: ^(CoreNetworking)$ :: la UI no habla HTTP'
  local out rc
  out="$(bash tools/check-layers-coverage.sh 2>&1)"; rc=$?
  [ "$rc" = "1" ] || { echo "    no cazó la regla huérfana (rc=$rc): $out"; return 1; }
  case "$out" in *"HUÉRFANA"*"*/UI/*"*) return 0 ;; esac
  echo "    cazó algo, pero no nombró la regla huérfana: $out"; return 1
}
test_regla_huerfana_se_caza() { _lcov_sandbox _case_regla_huerfana_se_caza; }

# ── §14.3: no pude mirar ≠ todo correcto ────────────────────────────
# El propio modo de fallo del script: la exención del bloque universal se hace
# buscando un comentario por su TEXTO. Si alguien lo reescribe, no se examina
# ninguna regla — y salir 0 ahí sería verde sin haber mirado nada.
_case_sin_marcador_devuelve_3() {
  _lcov_mk Sources/Domain/Movies/Movie.swift 'import Foundation'
  cat > tools/layers.conf <<'EOF'
# Bloque sin el marcador que el script busca.
*/Domain/* :: ^(SwiftUI)$ :: el dominio no importa UI
EOF
  local rc
  bash tools/check-layers-coverage.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "3" ] || { echo "    sin marcador debería devolver 3 (no pude mirar), devolvió $rc"; return 1; }
}
test_sin_marcador_devuelve_3() { _lcov_sandbox _case_sin_marcador_devuelve_3; }

# ── §14.3: sin conf tampoco se finge éxito ──────────────────────────
_case_sin_conf_devuelve_3() {
  _lcov_mk Sources/Domain/Movies/Movie.swift 'import Foundation'
  local rc
  rm -f tools/layers.conf
  bash tools/check-layers-coverage.sh >/dev/null 2>&1; rc=$?
  [ "$rc" = "3" ] || { echo "    sin layers.conf debería devolver 3, devolvió $rc"; return 1; }
}
test_sin_conf_devuelve_3() { _lcov_sandbox _case_sin_conf_devuelve_3; }

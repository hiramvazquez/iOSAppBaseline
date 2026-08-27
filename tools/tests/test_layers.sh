#!/usr/bin/env bash
# Fitness function de CAPAS (AGENTS.md §3: el dominio no depende de UI ni infra).
# Se comprueba sobre IMPORTS DIRECTOS, no con grep sobre el cuerpo del archivo:
# un grep matchea comentarios y strings → falsos positivos → el detector se ignora
# (ley de Tricorder: FP > ~10% y el analizador muere).

_layers_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools"
  cp "$PROJECT_ROOT/tools/check-layers.sh" "$d/tools/" 2>/dev/null
  cp "$PROJECT_ROOT/tools/layers.conf" "$d/tools/" 2>/dev/null
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

_mk() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }

# ── happy path: dominio puro ────────────────────────────────────────
_case_dominio_puro_pasa() {
  _mk src/Domain/User.swift 'import Foundation

struct User { let id: String }'
  bash tools/check-layers.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    dominio limpio reportó violación"; return 1; }
}
test_dominio_puro_pasa() { _layers_sandbox _case_dominio_puro_pasa; }

# ── ramas de violación ──────────────────────────────────────────────
_case_dominio_importa_ui_falla() {
  _mk src/Domain/User.swift 'import SwiftUI

struct User { let id: String }'
  local out; out="$(bash tools/check-layers.sh 2>&1)"
  case "$out" in *"Domain"*) return 0 ;; esac
  echo "    no detectó import de UI en Domain. salida: $out"; return 1
}
test_dominio_no_puede_importar_ui() { _layers_sandbox _case_dominio_importa_ui_falla; }

_case_dominio_importa_infra_falla() {
  _mk src/Domain/Repo.swift 'import Supabase

protocol Repo {}'
  local out; out="$(bash tools/check-layers.sh 2>&1)"
  case "$out" in *"Repo.swift"*) return 0 ;; esac
  echo "    no detectó import de infraestructura en Domain. salida: $out"; return 1
}
test_dominio_no_puede_importar_infra() { _layers_sandbox _case_dominio_importa_infra_falla; }

# ── el borde que mata a los detectores por grep ─────────────────────
_case_comentario_no_es_violacion() {
  _mk src/Domain/User.swift '// Nota: NO usar import SwiftUI aquí.
// let color = Color.red  ← ejemplo de lo que NO se hace
import Foundation

struct User {
  // ejemplo en doc: import UIKit
  let label = "import SwiftUI"
}'
  bash tools/check-layers.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    FALSO POSITIVO: matcheó un import dentro de comentario/string"; return 1; }
}
test_import_en_comentario_o_string_no_cuenta() { _layers_sandbox _case_comentario_no_es_violacion; }

_case_ui_puede_importar_lo_que_quiera() {
  _mk src/UI/HomeView.swift 'import SwiftUI
import Foundation

struct HomeView {}'
  bash tools/check-layers.sh >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    la capa UI fue restringida sin motivo"; return 1; }
}
test_ui_no_esta_restringida() { _layers_sandbox _case_ui_puede_importar_lo_que_quiera; }

_case_contrato_de_salida() {
  _mk src/Domain/Bad.swift 'import SwiftUI'
  local out; out="$(bash tools/check-layers.sh 2>&1)"
  # Debe emitir el contrato que consume check-drift.sh
  case "$out" in *"LAYERS_SUMMARY"*) return 0 ;; esac
  echo "    falta la línea LAYERS_SUMMARY. salida: $out"; return 1
}
test_emite_contrato_layers_summary() { _layers_sandbox _case_contrato_de_salida; }

# ── El conf se AMPLÍA, nunca se reescribe (f-25418f4c) ──────────────
# Al adoptar el harness, la tentación es sustituir estos globs por los de tu
# proyecto. Rompe CINCO tests de este archivo, que copian el conf real a un
# sandbox con rutas genéricas (`src/Domain/`) — y el fallo aparece lejos de la
# causa: cinco rojos que no mencionan layers.conf por ninguna parte. Le pasó a
# un adoptante real, que perdió una tarde en ello.
# ADOPTION.md §4 punto 5 lo dice en prosa; esto lo dice cuando importa, con la
# causa en el mensaje. Es la diferencia entre una nota y un detector.
test_layers_conf_conserva_los_globs_universales() {
  local g faltan=""
  for g in '*/Domain/*' '*/domain/*'; do
    grep -qF "$g" tools/layers.conf 2>/dev/null || faltan="$faltan $g"
  done
  [ -z "$faltan" ] && return 0
  echo "    tools/layers.conf ya no cubre:$faltan"
  echo "    El conf se AMPLÍA, no se reescribe: conserva los globs universales"
  echo "    que trae el template y añade los TUYOS debajo. Los tests de este"
  echo "    archivo montan un sandbox con rutas genéricas (src/Domain/), así"
  echo "    que sustituirlos deja el nivel 6 sin probar y sin que se note."
  return 1
}

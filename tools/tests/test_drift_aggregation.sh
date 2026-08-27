#!/usr/bin/env bash
# check-drift.sh agrega detectores y su conteo alimenta el TRINQUETE.
# Un conteo inflado por ruido de infraestructura sube el trinquete por un
# motivo falso, el equipo lo desactiva, y se pierde el gate entero.
# Estos tests fijan la frontera entre "hallazgo" y "ruido".

_drift_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/semgrep/rules"
  cp "$PROJECT_ROOT"/tools/check-drift.sh "$d/tools/"
  cp "$PROJECT_ROOT"/tools/check-layers.sh "$d/tools/"
  cp "$PROJECT_ROOT"/tools/semgrep-scan.sh "$d/tools/"
  cp "$PROJECT_ROOT"/tools/layers.conf "$d/tools/" 2>/dev/null
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

summary() { bash tools/check-drift.sh 2>/dev/null | grep '^DRIFT_SUMMARY'; }

# ── el borde crítico (FALSO POSITIVO): infraestructura ausente ≠ deuda ──
_case_infra_ausente_no_cuenta() {
  # Sin semgrep instalado (o sin reglas), el aviso va a stderr y NO debe
  # aparecer en el conteo. Este fue un bug real de la primera versión.
  mkdir -p src; echo "let x = 1" > src/App.swift
  local s; s="$(summary)"
  case "$s" in
    *"errors=0 warns=0") return 0 ;;
    *) echo "    la ausencia de tooling contaminó el conteo: $s"; return 1 ;;
  esac
}
test_infraestructura_ausente_no_infla_el_conteo() { _drift_sandbox _case_infra_ausente_no_cuenta; }

# ── happy path: repo limpio ─────────────────────────────────────────
_case_repo_limpio() {
  mkdir -p src/Domain; echo 'import Foundation' > src/Domain/User.swift
  local s; s="$(summary)"
  case "$s" in *"errors=0 warns=0") return 0 ;; esac
  echo "    repo limpio reportó deuda: $s"; return 1
}
test_repo_limpio_da_cero() { _drift_sandbox _case_repo_limpio; }

# ── ramas de detección ──────────────────────────────────────────────
_case_violacion_de_capa_suma_error() {
  mkdir -p src/Domain; echo 'import SwiftUI' > src/Domain/Bad.swift
  local s; s="$(summary)"
  case "$s" in *"errors=1"*) return 0 ;; esac
  echo "    la violación de capa no llegó al conteo: $s"; return 1
}
test_violacion_de_capa_suma_al_conteo() { _drift_sandbox _case_violacion_de_capa_suma_error; }

_case_archivo_gigante_suma_error() {
  mkdir -p src
  for i in $(seq 1 450); do echo "// línea $i"; done > src/Huge.swift
  local s; s="$(summary)"
  case "$s" in *"errors=1"*) return 0 ;; esac
  echo "    un archivo de 450 líneas no se detectó: $s"; return 1
}
test_archivo_sobre_hard_limit_suma() { _drift_sandbox _case_archivo_gigante_suma_error; }

_case_logica_sin_test_avisa() {
  mkdir -p src; echo 'struct X {}' > src/PagarUseCase.swift
  local s; s="$(summary)"
  case "$s" in *"warns=1"*) return 0 ;; esac
  echo "    lógica sin test no generó warning: $s"; return 1
}
test_logica_sin_archivo_de_test_avisa() { _drift_sandbox _case_logica_sin_test_avisa; }

_case_logica_con_test_no_avisa() {
  # Antes bastaba MENCIONAR el nombre en un comentario dentro de un *Tests.swift
  # para satisfacer el check. Ahora exige que exista el archivo de test.
  mkdir -p src
  echo 'struct X {}'  > src/PagarUseCase.swift
  echo 'import XCTest' > src/PagarUseCaseTests.swift
  local s; s="$(summary)"
  case "$s" in *"warns=0"*) return 0 ;; esac
  echo "    con test espejo presente seguía avisando: $s"; return 1
}
test_logica_con_test_espejo_no_avisa() { _drift_sandbox _case_logica_con_test_no_avisa; }

_case_mencion_en_comentario_no_basta() {
  mkdir -p src
  echo 'struct X {}' > src/CobrarUseCase.swift
  # Un archivo de test que solo NOMBRA la unidad, sin ser su test.
  mkdir -p src/otros; echo '// TODO: testear CobrarUseCase' > src/otros/Notas.swift
  local s; s="$(summary)"
  case "$s" in *"warns=1"*) return 0 ;; esac
  echo "    una mención en un comentario contó como test: $s"; return 1
}
test_mencion_en_comentario_no_cuenta_como_test() { _drift_sandbox _case_mencion_en_comentario_no_basta; }

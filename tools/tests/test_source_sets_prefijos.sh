#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# QUÉ prefijos se prohíben en commonMain — separado de CÓMO se detectan
# ════════════════════════════════════════════════════════════════════
# `test_source_sets.sh` cubre los MOTORES (semgrep primario, fallback textual,
# tabla de exits, terminabilidad, cobertura). Este archivo cubre la LISTA: qué
# cuenta como "import de plataforma" y qué no. Son dos contratos distintos y se
# rompen por motivos distintos — la lista se equivoca por conocimiento del
# ecosistema Kotlin, el motor por bugs de shell.
#
# La división es la fase 2a del PRD 0005 y tiene causa concreta: el gate de
# cierre de 1c empujó `test_source_sets.sh` a 414 líneas, sobre el hard limit de
# 400 de AGENTS.md §4, que exige dividir EN EL MISMO PR. Se dividió por este
# límite de contrato y no por la mitad.

_ssp_repo() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/shared/src/commonMain/kotlin"
  cp "$PROJECT_ROOT/tools/check-source-sets.sh" "$d/tools/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}
_ssp_common() { printf '%s\n' "$@" > shared/src/commonMain/kotlin/Repo.kt; }

_case_el_conf_solo_puede_ampliar() {
  # Misma dirección que los trinquetes (§9): la lista de prohibidos solo crece.
  # Un conf que pudiera recortarla convertiría el invariante en una sugerencia,
  # y bastaría añadir una línea para dejar de ver la violación de al lado.
  _ssp_common 'package dominio' 'import com.miorg.nativo.Cosa' 'class Repo'
  bash tools/check-source-sets.sh >/dev/null 2>&1 \
    || { echo "    un import no prohibido bloqueó sin estar en la lista"; return 1; }
  printf '%s\n' '# prohibidos extra de este proyecto' 'com\.miorg\.nativo\.' > tools/source-sets.conf
  bash tools/check-source-sets.sh >/dev/null 2>&1 \
    && { echo "    el conf no amplió la lista: el prefijo añadido no bloqueó"; return 1; }
  return 0
}
test_el_conf_amplia_la_lista_de_prohibidos() { _ssp_repo _case_el_conf_solo_puede_ampliar; }

# ── androidx NO es sinónimo de Android (gate de cierre de la fase 1c) ──
# El hallazgo que solo podía salir de un corpus AJENO, y salió: prohibir
# `androidx.` entero daba 31 violaciones sobre compose-multiplatform de
# JetBrains y las 31 eran falsas. Compose Multiplatform REUSA el namespace
# `androidx.compose` para código que compila en iOS, desktop y web; lo mismo
# `androidx.navigation`, `androidx.lifecycle` y `androidx.savedstate`. El
# detector acusaba al stack KMP más común que existe — 100% de FP, diez veces
# la ley del 10%, y un detector así se desactiva entero en vez de corregirse.
_case_androidx_multiplataforma_no_es_una_violacion() {
  _ssp_common 'package dominio' \
    'import androidx.compose.runtime.Composable' \
    'import androidx.compose.material.Text' \
    'import androidx.navigation.NavHostController' \
    'import androidx.lifecycle.ViewModel' \
    'class Repo'
  local out rc; out="$(bash tools/check-source-sets.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: acusó a androidx multiplataforma (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_androidx_multiplataforma_no_cuenta_como_import_de_plataforma() {
  _ssp_repo _case_androidx_multiplataforma_no_es_una_violacion; }

# Y la otra mitad: los androidx que SIGUEN siendo solo-Android sí bloquean.
# Sin esto, "arreglar" el falso positivo se convierte en apagar la regla.
_case_androidx_solo_android_sigue_bloqueando() {
  local v; local -a solo_android=(
    'import androidx.core.app.NotificationCompat'
    'import androidx.activity.ComponentActivity'
    'import androidx.appcompat.app.AppCompatActivity'
    'import androidx.fragment.app.Fragment'
  )
  for v in "${solo_android[@]}"; do
    _ssp_common 'package dominio' "$v" 'class Repo'
    bash tools/check-source-sets.sh >/dev/null 2>&1 \
      && { echo "    FALSO NEGATIVO: '$v' es solo-Android y no bloqueó"; return 1; }
  done
  return 0
}
test_los_androidx_solo_de_android_siguen_bloqueando() {
  _ssp_repo _case_androidx_solo_android_sigue_bloqueando; }

# ── El ancla de `com.google.android.`, que no tenía test ────────────
# El gate de cierre de 1c cambió `com\.google\.android` por
# `com\.google\.android\.` y el reviewer cazó que ese cambio de comportamiento
# en un contrato compartido (§9) entró sin rojo previo. Sin el punto final, el
# prefijo casa cualquier paquete que EMPIECE por esa cadena — y acusar de
# plataforma a un paquete que no lo es es el mismo pecado que motivó todo el
# arreglo del androidx.
_case_el_ancla_no_acusa_a_paquetes_vecinos() {
  _ssp_common 'package dominio' 'import com.google.androidwear.WearThing' 'class Repo'
  local out rc; out="$(bash tools/check-source-sets.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: com.google.androidwear no es com.google.android.* (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_el_ancla_de_com_google_android_no_acusa_a_paquetes_vecinos() {
  _ssp_repo _case_el_ancla_no_acusa_a_paquetes_vecinos; }

# Y el que SÍ debe bloquear, para que quitar el falso positivo no apague la regla.
_case_com_google_android_real_sigue_bloqueando() {
  _ssp_common 'package dominio' 'import com.google.android.gms.location.LocationServices' 'class Repo'
  bash tools/check-source-sets.sh >/dev/null 2>&1 \
    && { echo "    FALSO NEGATIVO: com.google.android.gms no bloqueó"; return 1; }
  return 0
}
test_com_google_android_real_sigue_bloqueando() {
  _ssp_repo _case_com_google_android_real_sigue_bloqueando; }

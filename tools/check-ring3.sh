#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-ring3.sh — ¿EXISTE el Anillo 3, o solo lo prometemos?
# ════════════════════════════════════════════════════════════════════
# LA CONTRADICCIÓN QUE ESTE SCRIPT CIERRA (cazada auditando el primer
# proyecto real): AGENTS.md §14.3 justifica que un detector roto (exit 3)
# NO bloquee en local diciendo "CI sí lo bloqueará", y §13 afirma que el
# marker lo verifican "los tres anillos". Ambas cosas dependen de que el
# Anillo 3 EXISTA. Mientras tanto, ADOPTION.md lo declaraba "opcional".
#
# Con las dos afirmaciones a la vez, un proyecto sin CI tiene un diseño
# fail-open justificado por un backstop inexistente: cada exit 3 no es
# "avisa y luego bloquea", es **fail-open definitivo y silencioso**. Es el
# modo de fallo G5 (gate anunciado y no operativo) a nivel de ANILLO — y
# por eso el `--selftest` no podía verlo: valida detectores, no anillos.
#
# Qué se comprueba, y por qué exactamente esto:
#   1. REMOTO — sin él, ningún CI del mundo puede ejecutar nada. Es la
#      precondición física, no una preferencia de flujo.
#   2. CONFIG DE CI que invoque los gates del harness server-side
#      (`ci/run-gates.sh` en un proyecto; la suite en el repo del propio
#      harness, cuyo producto SON los gates). Un workflow que solo hace
#      lint de otra cosa no es un Anillo 3: es un workflow.
#
# NO se comprueba si el último run pasó: eso vive en tu proveedor y aquí
# mentiríamos. Lo que este script garantiza es que el anillo está CABLEADO;
# que esté VERDE lo dice la pestaña de Actions (checklist en vivo de
# validate-harness).
#
# Contrato:  exit 0 = Anillo 3 cableado · 1 = ausente o incompleto.
# La SEVERIDAD la decide el llamador según el preset (full = bloquea,
# lite = declara), igual que con el marker de review.
# Contrato de stdout:  RING3_SUMMARY remote=<yes|no> ci=<yes|no>
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

# Entrypoints que SÍ constituyen un Anillo 3: los gates completos de un
# proyecto, o —en el repo del propio harness— la suite que verifica los
# gates, que ahí es exactamente lo mismo.
_RING3_ENTRYPOINTS='run-gates\.sh|tools/tests/run-tests\.sh|validate-harness\.sh'

# ⚠️ El remote del TEMPLATE no cuenta. `tools/upgrade.sh` registra un remote
# llamado `template` en su primera pasada, y con un `[ -n "$(git remote)" ]` a
# secas eso bastaba para declarar el Anillo 3 cableado. O sea que **el propio
# mecanismo de upgrade apagaba este gate como efecto secundario**, y en la
# dirección que más duele: de avisar honestamente a decir "cableado".
#
# Cazado en un adoptante real: sin `origin`, sin upstream en su rama y con
# `template` como único remote, este script decía ✅ mientras su workflow de
# CI no podía ejecutarse jamás — no hay repositorio remoto del proyecto donde
# correrlo. El síntoma llevaba meses visible en `ci/ai-review.sh` ("base
# origin/main no es un commit evaluable") y se leía como un aviso menor.
#
# Un remote al que solo BAJAS no es un backstop: el Anillo 3 exige un sitio
# donde tu código llegue y alguien más lo verifique.
HAS_REMOTE=no
_REMOTE_NAME="${TEMPLATE_REMOTE_NAME:-template}"
_REMOTES_PROPIOS="$(git remote 2>/dev/null | grep -vxF "$_REMOTE_NAME" || true)"
[ -n "$_REMOTES_PROPIOS" ] && HAS_REMOTE=yes

HAS_CI=no
CI_FILE=""
for f in .github/workflows/*.yml .github/workflows/*.yaml .gitlab-ci.yml \
         bitbucket-pipelines.yml azure-pipelines.yml Jenkinsfile; do
  [ -f "$f" ] || continue
  if grep -qE "$_RING3_ENTRYPOINTS" "$f" 2>/dev/null; then
    HAS_CI=yes; CI_FILE="$f"; break
  fi
done

echo "RING3_SUMMARY remote=$HAS_REMOTE ci=$HAS_CI"

if [ "$HAS_REMOTE" = "yes" ] && [ "$HAS_CI" = "yes" ]; then
  echo "✅ Anillo 3 cableado: remoto configurado + $CI_FILE ejecuta los gates."
  exit 0
fi

# ── Diagnóstico accionable (a stderr: stdout es el canal de datos, G2) ──
{
  echo "❌ ANILLO 3 AUSENTE — el backstop que justifica el fail-open local NO existe."
  [ "$HAS_REMOTE" = "no" ] && {
    if git remote 2>/dev/null | grep -qxF "$_REMOTE_NAME"; then
      echo "   · El ÚNICO remote es '$_REMOTE_NAME', el del harness upstream — y ese no cuenta:"
      echo "     es de donde BAJAS mejoras, no un sitio donde tu código llegue y se verifique."
      echo "     Lo registró tools/upgrade.sh; no es un remoto de tu proyecto."
    else
      echo "   · Sin REMOTO configurado: ningún CI puede ejecutarse."
    fi
    echo "     Remedio:  git remote add origin <url>  &&  git push -u origin HEAD"
  }
  [ "$HAS_CI" = "no" ] && {
    echo "   · Sin CONFIG DE CI que invoque los gates del harness."
    echo "     Remedio:  cp ci/examples/github-actions.yml.example .github/workflows/gates.yml"
    echo "               (o el ejemplo de tu proveedor en ci/examples/)"
  }
  echo "   CONSECUENCIA CONCRETA mientras siga así: cada detector que devuelve"
  echo "   exit 3 (semgrep roto, mutación sin runner, build no cableado) hace"
  echo "   fail-open DEFINITIVO. La doctrina de §14.3 dice 'CI lo bloqueará' y"
  echo "   hoy, en este repo, no lo bloquea nadie. No es una tarea pendiente:"
  echo "   es un agujero abierto en el razonamiento de todos los niveles."
} >&2
exit 1

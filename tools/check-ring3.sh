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
#   3. DISPARADOR AUTOMÁTICO (push / pull_request / schedule / merge_group).
#      Un workflow `workflow_dispatch:` puro NO es un backstop: solo corre si
#      alguien se acuerda de pulsarlo, y un backstop que depende de que un
#      humano se acuerde es justo lo que el Anillo 3 existe para no ser.
#      Cazado en vivo (2026-08-29): este script recorría los .yml en orden de
#      glob y se quedaba con el PRIMERO que mencionara un entrypoint, así que
#      declaraba "✅ Anillo 3 cableado: gate-0a-macos.yml ejecuta los gates"
#      citando un workflow manual. Aquí el verde era correcto por casualidad
#      —había otro workflow con `push`— pero borra ese y el gate seguía en ✅.
#   4. QUE DE VERDAD SE EJECUTE, cuando se pueda comprobar (`gh` disponible).
#      La versión anterior renunciaba a esto por doctrina: "si el último run
#      pasó vive en tu proveedor y aquí mentiríamos". La renuncia era más cara
#      que el riesgo: en este mismo repo los 8 últimos push dispararon el
#      workflow correcto y GitHub rechazó arrancar los jobs
#      ("The job was not started because an Actions budget is preventing
#      further use"), con el detector diciendo ✅ todo el tiempo (f-787568d2).
#      Un anillo cableado que nunca ejecuta es indistinguible de uno ausente,
#      y §14.4 dice que el pecado que no cometemos es anunciar una defensa
#      que no existe.
#
#      El discriminador NO es "el último run falló" —un CI rojo es el anillo
#      FUNCIONANDO— sino "el job nunca arrancó": esos runs traen CERO steps.
#      Medido en los dos casos antes de escribirlo: runs ejecutados = ~20
#      steps, runs rechazados por presupuesto = 0.
#      PERO cero steps SOLO significa eso en un run COMPLETADO: uno recien
#      encolado tambien trae cero, y ese es el estado normal justo despues de
#      un push. Por eso se filtra por `status == completed` antes de concluir
#      nada; mientras corre, la respuesta honesta es `unknown`. Sin ese filtro
#      el probe acusaba de "anillo mudo" al caso mas comun de todos.
#
#      Corre en TODOS los llamadores por igual —incluido el banner de arranque—
#      a proposito: la doctrina de §14.4 es que la ausencia del anillo se
#      DECLARA en cada sesion, y un probe que se apaga justo donde el humano
#      mira reintroduce el silencio que esto viene a quitar. Coste medido: 1,5s,
#      acotado a RING3_RUNS_TIMEOUT (5s por llamada). Se apaga con
#      RING3_CHECK_RUNS=0, que es lo que hacen los tests para ser hermeticos.
#      El limite lo impone `_con_limite`, NO `timeout`: macOS —la plataforma de
#      referencia de este proyecto— no trae `timeout` ni `gtimeout` de fabrica,
#      asi que la version anterior de este comentario prometia una cota que en
#      el Mac del owner no existia y `gh` corria SIN limite dentro del hook de
#      arranque, con la salida a /dev/null. Una promesa que solo se cumple
#      donde no hace falta es peor que no prometer nada (lo cazo el reviewer).
#      Si `gh` no esta o la consulta falla, `runs=unknown` y NO bloquea:
#      no pude mirar != no encontre nada (§14.3).
#
# Contrato:  exit 0 = Anillo 3 cableado · 1 = ausente, manual-only o sin ejecutar.
# La SEVERIDAD la decide el llamador según el preset (full = bloquea,
# lite = declara), igual que con el marker de review.
# Contrato de stdout:  RING3_SUMMARY remote=<yes|no> ci=<yes|no> runs=<ok|not-started|unknown>
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

# ── ¿Se dispara SOLO? ───────────────────────────────────────────────
# Acepta las tres formas que GitHub admite y que aparecen en repos reales:
#   on:            ·   on: push           ·   on: [push, pull_request]
#     push:
# Se comparan SOLO las líneas del bloque `on:` y con los comentarios ya
# quitados: un `# ... push ...` en la cabecera del archivo no puede colar un
# disparador que no existe (y estos archivos llevan cabeceras largas).
_tiene_disparador_automatico() { # <archivo>
  sed 's/#.*//' "$1" 2>/dev/null | awk '
    /^on:[[:space:]]*$/     { dentro=1; next }
    /^on:[[:space:]]*[^[:space:]]/ { print; next }
    dentro && /^[^[:space:]#]/ { dentro=0 }
    dentro                  { print }
  ' | grep -qE '(^|[^a-zA-Z_])(push|pull_request(_target)?|schedule|merge_group)([^a-zA-Z_]|$)'
}

# Los formatos que NO son GitHub Actions no declaran disparador en el propio
# archivo (GitLab/Bitbucket/Azure corren en cada push por defecto), así que
# para ellos la presencia del entrypoint sigue bastando. Distinguirlos evita
# un falso negativo que el adoptante no podría arreglar (§14.2).
HAS_CI=no
CI_FILE=""
CI_MANUAL_ONLY=""
for f in .github/workflows/*.yml .github/workflows/*.yaml .gitlab-ci.yml \
         bitbucket-pipelines.yml azure-pipelines.yml Jenkinsfile; do
  [ -f "$f" ] || continue
  grep -qE "$_RING3_ENTRYPOINTS" "$f" 2>/dev/null || continue
  case "$f" in
    .github/workflows/*)
      if ! _tiene_disparador_automatico "$f"; then
        # Lo recordamos para el diagnóstico, pero NO cuenta: seguimos
        # buscando uno automático en vez de cortar aquí. Cortar en el primer
        # match era el bug — el manual iba antes en orden de glob y tapaba al
        # bueno, dejando un ✅ que citaba el archivo equivocado.
        [ -n "$CI_MANUAL_ONLY" ] || CI_MANUAL_ONLY="$f"
        continue
      fi
      ;;
  esac
  HAS_CI=yes; CI_FILE="$f"; break
done

# Cota de tiempo PORTABLE. `timeout` es de coreutils y no viene en macOS; sin
# esto, "acotado" era una palabra en un comentario. Se prefiere `timeout` si
# esta (mas exacto), y si no, un perro guardian con kill.
# La primera version de este fallback lanzaba un `( sleep N; kill )` en
# background, y el reviewer la tumbo con medicion: 180 llamadas rapidas dejaron
# 27 procesos `sleep` HUERFANOS vivos a la vez. Matar el subshell contenedor no
# mata al `sleep` que ese subshell tiene bloqueado como hijo, asi que el
# huerfano sobrevivia hasta agotar su plazo y ENTONCES disparaba su
# `kill -TERM $pid` — sobre un PID que ya estaba libre y que el SO pudo haber
# reciclado para otro proceso. Un watchdog cuyo unico trabajo es control
# preciso de procesos no puede permitirse eso, y menos corriendo en cada
# arranque de sesion y en paralelo entre sesiones concurrentes.
#
# Esta version no lanza NINGUN proceso auxiliar: vigila desde el propio shell.
# Sin auxiliar no hay huerfano posible, y el `kill` ocurre siempre de forma
# SINCRONA mientras el hijo sigue sin reapear — o sea que ese PID todavia es
# nuestro y no puede haberse reciclado. El sondeo usa `ps` y no `kill -0`
# porque un hijo terminado y aun no reapeado (zombi) sigue respondiendo a
# `kill -0`, y el bucle no saldria nunca antes del plazo.
_vivo() { # <pid> — vivo de verdad: ni ausente ni zombi
  case "$(ps -p "$1" -o stat= 2>/dev/null)" in
    ''|Z*) return 1 ;;
    *)     return 0 ;;
  esac
}
_con_limite() { # <segundos> <comando...>
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"; return $?
  fi
  # `set -m` para que el hijo sea LIDER DE SU PROPIO GRUPO y se pueda señalar
  # al grupo entero con `kill -- -$pid`. Sin esto, matar solo al lider no basta:
  # sus nietos heredan el stdout, siguen sujetando el pipe, y una sustitucion
  # `$(...)` se queda bloqueada esperando EOF aunque el proceso vigilado ya este
  # muerto — o sea, el limite no limitaba nada. Lo cazaron los dos tests de
  # abajo (un `gh` falso que duerme, y otro con `trap "" TERM`); la version que
  # solo mataba al lider tardaba los 10s enteros con el limite en 1s.
  local _monitor=""; case "$-" in *m*) _monitor=ya ;; esac
  set -m
  "$@" &
  local pid=$! i=0 lim=$(( secs * 5 ))   # 5 sondeos por segundo
  [ -n "$_monitor" ] || set +m
  while [ "$i" -lt "$lim" ] && _vivo "$pid"; do
    sleep 0.2; i=$(( i + 1 ))
  done
  # TERM al grupo (deja cerrar limpio) y KILL si lo ignora: un `trap "" TERM`
  # convertia el "limite" en una sugerencia. `run-tests.sh` ya usa kill -9 por
  # lo mismo. El `kill` es SINCRONO y el hijo sigue sin reapear, asi que su PID
  # todavia es nuestro: no puede haberse reciclado.
  if _vivo "$pid"; then
    kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
    sleep 0.2
    if _vivo "$pid"; then
      kill -KILL "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null
    fi
  fi
  wait "$pid" 2>/dev/null
  return $?
}

# ── ¿EJECUTA de verdad? (solo si se puede mirar) ────────────────────
# Ver el racional largo en la cabecera: el discriminador es "cero steps",
# no "conclusion=failure". Un CI rojo es el anillo funcionando.
RUNS=unknown
_runs_detalle=""
if [ "${RING3_CHECK_RUNS:-1}" != "0" ] && [ "$HAS_CI" = "yes" ] \
   && command -v gh >/dev/null 2>&1 && [ -n "$_REMOTES_PROPIOS" ]; then
  _lim="${RING3_RUNS_TIMEOUT:-5}"
  _wf="$(basename "$CI_FILE")"
  # Se pide TAMBIEN el status, y no es un extra: sin el, "cero steps" es
  # ambiguo. Un run recien encolado —status queued/in_progress, todavia sin
  # runner asignado— tiene cero steps igual que uno RECHAZADO, y el probe corre
  # en cada arranque de sesion, o sea a menudo justo despues de un push. Sin
  # este filtro, el caso normal "acabo de publicar y CI esta arrancando" se
  # diagnosticaba como "el anillo esta mudo" y BLOQUEABA. Lo cazo el reviewer:
  # las dos muestras con las que se justifico el discriminador eran ambas de
  # runs completados, y de ahi se generalizo un "sin ambiguedad" que no lo era.
  _run_meta="$(_con_limite "$_lim" gh run list --workflow "$_wf" --limit 1 \
      --json databaseId,status --jq '.[0] | "\(.databaseId) \(.status)"' 2>/dev/null </dev/null || true)"
  _run_id="${_run_meta%% *}"
  _run_status="${_run_meta##* }"
  case "$_run_id" in ''|*[!0-9]*) _run_id="" ;; esac
  # Solo un run COMPLETADO permite concluir algo. Mientras corre, la respuesta
  # honesta es "todavia no se" (§14.3), no una acusacion.
  [ "$_run_status" = "completed" ] || _run_id=""
  if [ -n "$_run_id" ]; then
    # `--jq` en vez de python3: el script ya usa jq dos lineas arriba, asi que
    # depender ademas de un interprete externo era una dependencia gratis.
    # `[]?` tolera un JSON sin `jobs` o sin `steps` sin reventar.
    _steps="$(_con_limite "$_lim" gh api "repos/{owner}/{repo}/actions/runs/$_run_id/jobs" \
      --jq '[.jobs[]?.steps[]?] | length' 2>/dev/null </dev/null || true)"
    case "$_steps" in
      ''|*[!0-9]*) RUNS=unknown ;;
      0) RUNS=not-started; _runs_detalle="$_run_id" ;;
      *) RUNS=ok ;;
    esac
  fi
fi

echo "RING3_SUMMARY remote=$HAS_REMOTE ci=$HAS_CI runs=$RUNS"

if [ "$HAS_REMOTE" = "yes" ] && [ "$HAS_CI" = "yes" ] && [ "$RUNS" != "not-started" ]; then
  echo "✅ Anillo 3 cableado: remoto configurado + $CI_FILE ejecuta los gates."
  [ "$RUNS" = "unknown" ] \
    && echo "   (cableado verificado en estático; que EJECUTE no se pudo comprobar aquí" \
    && echo "    — sin gh, sin red o consulta fallida. \`gh run list\` lo dice de verdad.)"
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
    if [ -n "$CI_MANUAL_ONLY" ]; then
      echo "   · $CI_MANUAL_ONLY SÍ ejecuta los gates, pero solo se dispara A MANO"
      echo "     (workflow_dispatch). Un backstop que depende de que alguien se"
      echo "     acuerde de pulsarlo no es un backstop: es una herramienta."
      echo "     Remedio:  añade a ese workflow un disparador automático, p.ej.:"
      echo "                 on:"
      echo "                   push:"
      echo "                     branches: [main]"
      echo "                   pull_request:"
      echo "               o crea uno automático aparte que corra los gates."
    else
      echo "   · Sin CONFIG DE CI que invoque los gates del harness."
      echo "     Remedio:  cp ci/examples/github-actions.yml.example .github/workflows/gates.yml"
      echo "               (o el ejemplo de tu proveedor en ci/examples/)"
    fi
  }
  [ "$RUNS" = "not-started" ] && {
    echo "   · $CI_FILE se dispara y GitHub NO ARRANCA sus jobs: el último run"
    echo "     ($_runs_detalle) terminó con CERO steps ejecutados. La causa típica es"
    echo "     el presupuesto de Actions agotado ('The job was not started because"
    echo "     an Actions budget is preventing further use')."
    echo "     Esto NO es un CI en rojo —eso sería el anillo funcionando— es el"
    echo "     anillo MUDO con apariencia de cableado."
    echo "     Remedio:  revisa Settings → Billing → Actions del repo/organización,"
    echo "               o baja a preset lite y DECLARA que no hay backstop."
  }
  echo "   CONSECUENCIA CONCRETA mientras siga así: cada detector que devuelve"
  echo "   exit 3 (semgrep roto, mutación sin runner, build no cableado) hace"
  echo "   fail-open DEFINITIVO. La doctrina de §14.3 dice 'CI lo bloqueará' y"
  echo "   hoy, en este repo, no lo bloquea nadie. No es una tarea pendiente:"
  echo "   es un agujero abierto en el razonamiento de todos los niveles."
} >&2
exit 1

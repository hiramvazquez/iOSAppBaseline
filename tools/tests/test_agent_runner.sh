#!/usr/bin/env bash
# Contratos separados run/review; el backend fake prueba el boundary sin proveedor.
_ar_repo() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools/agent-backends" "$d/scripts/agent-hooks/lib"
  cp "$PROJECT_ROOT/tools/agent-runner.sh" "$d/tools/"
  cp -R "$PROJECT_ROOT/tools/agent-backends/." "$d/tools/agent-backends/"
  cp "$PROJECT_ROOT/scripts/agent-hooks/lib/verdict.sh" "$d/scripts/agent-hooks/lib/"
  ( cd "$d" && git init -q . && git config user.email t@t.t && git config user.name t \
    && echo seed > seed && git add seed && git commit -qm seed && printf 'prompt\n' > prompt.md && "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

_case_run_opaco() {
  # FALSO POSITIVO: `run` puede imprimir cualquier texto, incluso la palabra
  # VERDICT; solo `review` interpreta ese contrato.
  local out
  out="$(bash tools/agent-runner.sh run --backend fake --prompt-file prompt.md --cwd "$PWD")" \
    || return 1
  assert_eq prompt "$out"
}
test_run_no_interpreta_stdout_como_veredicto() { _ar_repo _case_run_opaco; }

_case_review_green() {
  FAKE_REVIEW_RESULT=$'texto\nVERDICT: GREEN\nFINDINGS: 0\nSCOPE: test' \
    bash tools/agent-runner.sh review --backend fake --prompt-file prompt.md \
      --base HEAD --head HEAD --cwd "$PWD" >/dev/null
}
test_review_green_parseable_pasa() { _ar_repo _case_review_green; }

_case_review_preserva_stderr_en_green() {
  printf '#!/usr/bin/env bash\necho diagnostico-visible >&2\nprintf "VERDICT: GREEN\\nFINDINGS: 0\\nSCOPE: stderr\\n"\n' \
    > review-diagnostic.sh; chmod +x review-diagnostic.sh
  local err
  err="$(FAKE_REVIEW_SCRIPT="$PWD/review-diagnostic.sh" \
    bash tools/agent-runner.sh review --backend fake --prompt-file prompt.md \
      --base HEAD --head HEAD --cwd "$PWD" 2>&1 >/dev/null)" || return 1
  assert_contains "$err" diagnostico-visible
}
test_review_green_preserva_diagnosticos_stderr() { _ar_repo _case_review_preserva_stderr_en_green; }

_case_review_sin_veredicto() {
  FAKE_REVIEW_RESULT='todo bien' bash tools/agent-runner.sh review --backend fake \
    --prompt-file prompt.md --base HEAD --head HEAD --cwd "$PWD" >/dev/null 2>&1
  [ "$?" = 1 ]
}
test_review_sin_veredicto_falla() { _ar_repo _case_review_sin_veredicto; }

_case_review_incompleta() {
  FAKE_REVIEW_RESULT='VERDICT: GREEN' bash tools/agent-runner.sh review --backend fake \
    --prompt-file prompt.md --base HEAD --head HEAD --cwd "$PWD" >/dev/null 2>&1
  [ "$?" = 1 ]
}
test_review_exige_findings_y_scope() { _ar_repo _case_review_incompleta; }

_case_green_con_hallazgos() {
  FAKE_REVIEW_RESULT=$'VERDICT: GREEN\nFINDINGS: 2\nSCOPE: x' \
    bash tools/agent-runner.sh review --backend fake --prompt-file prompt.md \
      --base HEAD --head HEAD --cwd "$PWD" >/dev/null 2>&1
  [ "$?" = 1 ]
}
test_green_con_findings_es_contrato_contradictorio() { _ar_repo _case_green_con_hallazgos; }

_case_run_propaga_fallo() {
  printf '#!/usr/bin/env bash\nexit 7\n' > fail.sh; chmod +x fail.sh
  FAKE_RUN_SCRIPT="$PWD/fail.sh" bash tools/agent-runner.sh run --backend fake \
    --prompt-file prompt.md --cwd "$PWD" >/dev/null 2>&1
  [ "$?" = 7 ]
}
test_run_propaga_exit_del_backend() { _ar_repo _case_run_propaga_fallo; }

# Espera a que exista <ruta> mientras el proceso <pid> siga vivo (hasta 15s).
# Es la señal de ARRANQUE del backend: separa la sincronización de arranque
# (aprovisionar git/python/adapter puede tardar segundos bajo carga) del reloj
# de EJECUCIÓN que mide al watchdog (WF-01: no se duerme a ciegas).
_espera_archivo() {
  local i=0
  while [ "$i" -lt 150 ]; do
    [ -e "$1" ] && return 0
    kill -0 "$2" 2>/dev/null || return 1
    sleep 0.1
    i=$((i+1))
  done
  return 1
}

_case_timeout_propaga_124() {
  # El fixture toca ready.marker ANTES de dormir: el reloj del test arranca
  # con el backend ya vivo, no con el spawn del runner. Al fallar se imprime
  # el exit REAL y el stderr del runner: un rojo sin ellos no distingue
  # watchdog roto de fork fallido (WF-01, run 32214253577).
  printf '#!/usr/bin/env bash\ntouch ready.marker\nexec sleep 30\n' > slow.sh; chmod +x slow.sh
  local runner started elapsed rc
  FAKE_RUN_SCRIPT="$PWD/slow.sh" bash tools/agent-runner.sh run --backend fake \
    --prompt-file prompt.md --cwd "$PWD" --timeout 1 >/dev/null 2>runner-err.txt &
  runner=$!
  _espera_archivo ready.marker "$runner" || true  # si murió antes de listo, el rc lo dirá
  started="$(date +%s)"
  wait "$runner"; rc=$?
  elapsed=$(( $(date +%s) - started ))
  [ "$rc" = 124 ] || {
    echo "    timeout devolvió exit=$rc, no 124 · stderr del runner:"
    sed 's/^/      | /' runner-err.txt 2>/dev/null; return 1; }
  [ "$elapsed" -lt 5 ] || {
    echo "    ${elapsed}s DESPUÉS de arrancado el backend; el watchdog no corta a tiempo"; return 1; }
}
test_timeout_corta_y_propaga_exit_124() { _ar_repo _case_timeout_propaga_124; }

_case_review_timeout_propaga_124() {
  # Mismo contrato que run: beacon de arranque + exit real + stderr al fallar.
  printf '#!/usr/bin/env bash\ntouch review-ready.marker\nexec sleep 30\n' > slow-review.sh; chmod +x slow-review.sh
  local runner started elapsed rc
  FAKE_REVIEW_SCRIPT="$PWD/slow-review.sh" bash tools/agent-runner.sh review --backend fake \
    --prompt-file prompt.md --base HEAD --head HEAD --cwd "$PWD" --timeout 1 \
    >/dev/null 2>review-err.txt &
  runner=$!
  _espera_archivo review-ready.marker "$runner" || true
  started="$(date +%s)"
  wait "$runner"; rc=$?
  elapsed=$(( $(date +%s) - started ))
  [ "$rc" = 124 ] || {
    echo "    timeout de review devolvió exit=$rc, no 124 · stderr del runner:"
    sed 's/^/      | /' review-err.txt 2>/dev/null; return 1; }
  [ "$elapsed" -lt 5 ] || {
    echo "    review: ${elapsed}s después de arrancado el backend; el watchdog no corta"; return 1; }
}
test_review_tambien_respeta_timeout() { _ar_repo _case_review_timeout_propaga_124; }

_proceso_sigue_vivo() { kill -0 "$1" 2>/dev/null; }

_espera_proceso_muerto() {
  local pid="$1" i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    _proceso_sigue_vivo "$pid" || return 0
    sleep 0.1
  done
  return 1
}

_case_timeout_mata_descendientes() {
  printf '#!/usr/bin/env bash\ntrap "" TERM HUP\n( trap "" TERM HUP; sleep 30 ) &\necho "$!" > child.pid\nwait\n' \
    > tree.sh; chmod +x tree.sh
  FAKE_RUN_SCRIPT="$PWD/tree.sh" bash tools/agent-runner.sh run --backend fake \
    --prompt-file prompt.md --cwd "$PWD" --timeout 1 >/dev/null 2>&1
  local rc=$? child
  [ "$rc" = 124 ] || { echo "    timeout del árbol devolvió $rc"; return 1; }
  child="$(cat child.pid 2>/dev/null)"
  [ -n "$child" ] || { echo "    el fixture no registró al descendiente"; return 1; }
  _espera_proceso_muerto "$child" || {
    kill -9 "$child" 2>/dev/null
    echo "    quedó vivo el descendiente $child que ignoraba TERM"; return 1;
  }
}
test_timeout_no_deja_descendientes() { _ar_repo _case_timeout_mata_descendientes; }

_case_cancelacion_propaga_y_limpia() {
  printf '#!/usr/bin/env bash\ntrap "" TERM HUP\n( trap "" TERM HUP; sleep 30 ) &\necho "$!" > cancel-child.pid\nwait\n' \
    > cancel-tree.sh; chmod +x cancel-tree.sh
  FAKE_RUN_SCRIPT="$PWD/cancel-tree.sh" bash tools/agent-runner.sh run --backend fake \
    --prompt-file prompt.md --cwd "$PWD" --timeout 20 >/dev/null 2>&1 &
  local runner=$! child='' i rc
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [ -s cancel-child.pid ] && { child="$(cat cancel-child.pid)"; break; }
    sleep 0.1
  done
  [ -n "$child" ] || { kill -9 "$runner" 2>/dev/null; echo "    el fixture no arrancó"; return 1; }
  kill -TERM "$runner" 2>/dev/null
  wait "$runner"; rc=$?
  [ "$rc" = 143 ] || { echo "    cancelación devolvió $rc, no 143"; return 1; }
  _espera_proceso_muerto "$child" || {
    kill -9 "$child" 2>/dev/null
    echo "    cancelación dejó vivo al descendiente $child"; return 1;
  }
}
test_cancelacion_propaga_143_y_no_deja_descendientes() { _ar_repo _case_cancelacion_propaga_y_limpia; }

_case_cancelacion_review_propaga_y_limpia() {
  printf '#!/usr/bin/env bash\ntrap "" TERM HUP\n( trap "" TERM HUP; sleep 30 ) &\necho "$!" > review-cancel-child.pid\nwait\n' \
    > cancel-review-tree.sh; chmod +x cancel-review-tree.sh
  FAKE_REVIEW_SCRIPT="$PWD/cancel-review-tree.sh" bash tools/agent-runner.sh review --backend fake \
    --prompt-file prompt.md --base HEAD --head HEAD --cwd "$PWD" --timeout 20 \
    >/dev/null 2>&1 &
  local runner=$! child='' i rc
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [ -s review-cancel-child.pid ] && { child="$(cat review-cancel-child.pid)"; break; }
    sleep 0.1
  done
  [ -n "$child" ] || { kill -9 "$runner" 2>/dev/null; echo "    el fixture review no arrancó"; return 1; }
  kill -TERM "$runner" 2>/dev/null
  wait "$runner"; rc=$?
  [ "$rc" = 143 ] || { echo "    cancelación review devolvió $rc, no 143"; return 1; }
  _espera_proceso_muerto "$child" || {
    kill -9 "$child" 2>/dev/null
    echo "    cancelación review dejó vivo al descendiente $child"; return 1;
  }
}
test_cancelacion_review_propaga_143_y_no_deja_descendientes() {
  _ar_repo _case_cancelacion_review_propaga_y_limpia
}

_case_flag_truncado() {
  bash tools/agent-runner.sh run --backend >/dev/null 2>&1
  [ "$?" = 3 ]
}
test_flag_sin_valor_es_error_de_contrato() { _ar_repo _case_flag_truncado; }

_case_timeout_invalido() {
  bash tools/agent-runner.sh run --backend fake --prompt-file prompt.md --cwd "$PWD" \
    --timeout nunca >/dev/null 2>&1
  [ "$?" = 3 ]
}
test_timeout_invalido_es_error_de_contrato() { _ar_repo _case_timeout_invalido; }

_case_paths_fuera() {
  bash tools/agent-runner.sh run --backend fake --prompt-file /etc/hosts --cwd "$PWD" >/dev/null 2>&1
  [ "$?" = 3 ]
}
test_prompt_fuera_del_repo_se_rechaza() { _ar_repo _case_paths_fuera; }

_case_backend_inyectado() {
  bash tools/agent-runner.sh run --backend '../fake' --prompt-file prompt.md --cwd "$PWD" >/dev/null 2>&1
  [ "$?" = 3 ]
}
test_backend_es_allowlist_no_path() { _ar_repo _case_backend_inyectado; }

_case_capacidades_requeridas() {
  FAKE_AUTONOMY_EVIDENCE="$PWD/evidence.log" \
    bash tools/agent-runner.sh capabilities --backend fake \
    --require run,review,read_only,subagents,hooks >/dev/null || return 1
  bash tools/agent-runner.sh capabilities --backend fake --require hooks >/dev/null 2>&1 \
    && { echo "    fake declaró hooks sin instrumentación"; return 1; }
  printf '#!/usr/bin/env bash\n[ "$1" = capabilities ] && echo "run=true review=false read_only=false subagents=false hooks=false"\n' \
    > tools/agent-backends/limited.sh; chmod +x tools/agent-backends/limited.sh
  bash tools/agent-runner.sh capabilities --backend limited --require run,review \
    >/dev/null 2>&1
  [ "$?" = 3 ]
}
test_capabilities_rechaza_backend_incompleto() { _ar_repo _case_capacidades_requeridas; }

_case_sigchld_ignorado_no_apaga_el_gate() {
  # SIGCHLD=SIG_IGN sobrevive fork+exec (bash incluido) hasta el watchdog;
  # el kernel auto-reapea, waitpid da ECHILD y CPython lo traduce a
  # returncode 0 (subprocess._try_wait): un backend que sale 7 se
  # reportaría como éxito — el gate apagado. El runner restaura SIG_DFL.
  printf '#!/usr/bin/env bash\nexit 7\n' > fail7.sh; chmod +x fail7.sh
  printf '#!/usr/bin/env python3\nimport signal, subprocess, sys\nsignal.signal(signal.SIGCHLD, signal.SIG_IGN)\nsubprocess.call(sys.argv[1:])\n' \
    > ignora-sigchld.py
  # El rc se registra desde el bash INTERIOR: el subprocess.call del wrapper
  # padece el mismo ECHILD→0 y mediría basura.
  FAKE_RUN_SCRIPT="$PWD/fail7.sh" python3 ignora-sigchld.py bash -c \
    'bash tools/agent-runner.sh run --backend fake --prompt-file prompt.md --cwd "$PWD" >/dev/null 2>&1; echo "$?" > rc-observado.txt'
  local rc; rc="$(cat rc-observado.txt 2>/dev/null)"
  [ "$rc" = 7 ] || { echo "    con SIGCHLD ignorado el runner devolvió [${rc:-nada}], no 7: falso verde"; return 1; }
  # y bajo el mismo entorno hostil el timeout sigue siendo 124
  printf '#!/usr/bin/env bash\nsleep 30\n' > lento-ign.sh; chmod +x lento-ign.sh
  FAKE_RUN_SCRIPT="$PWD/lento-ign.sh" python3 ignora-sigchld.py bash -c \
    'bash tools/agent-runner.sh run --backend fake --prompt-file prompt.md --cwd "$PWD" --timeout 1 >/dev/null 2>&1; echo "$?" > rc-observado.txt'
  rc="$(cat rc-observado.txt 2>/dev/null)"
  [ "$rc" = 124 ] || { echo "    con SIGCHLD ignorado el timeout devolvió [${rc:-nada}], no 124"; return 1; }
}
test_sigchld_ignorado_no_apaga_el_gate() { _ar_repo _case_sigchld_ignorado_no_apaga_el_gate; }

_case_review_infra_rota_sale_3_y_ruidosa() {
  # La única familia que puede devolver algo distinto de 124 con un backend
  # lento es el fallo PREVIO a armar el watchdog (mktemp/fork bajo
  # saturación): una vez armado, TimeoutExpired implica 124 incondicional.
  # Antes del fix, mktemp roto salía exit 1 y MUDO — en CI se disfrazaba
  # de "timeout de review no propagó 124" (WF-01, run 32214253577).
  printf '#!/usr/bin/env bash\nsleep 30\n' > lenta.sh; chmod +x lenta.sh
  # ⚠️ La inyección va por PATH, no por TMPDIR, y la diferencia es la ley de
  # siempre en espejo: TMPDIR inexistente rompe el mktemp de GNU pero el de
  # BSD/macOS cae a /tmp y TRIUNFA — este test nació verde en Linux y rojo en
  # el Mac del owner, y lo cazó verify-run antes del commit. Un stub de mktemp
  # que falla es idéntico en los dos sistemas.
  mkdir -p stub-bin
  printf '#!/bin/sh\necho "mktemp: fallo forzado por el test" >&2\nexit 1\n' > stub-bin/mktemp
  chmod +x stub-bin/mktemp
  local rc err
  err="$(PATH="$PWD/stub-bin:$PATH" FAKE_REVIEW_SCRIPT="$PWD/lenta.sh" \
    bash tools/agent-runner.sh review --backend fake --prompt-file prompt.md \
      --base HEAD --head HEAD --cwd "$PWD" --timeout 5 2>&1 >/dev/null)"; rc=$?
  [ "$rc" = 3 ] || { echo "    infra rota devolvió exit=$rc, no 3 · stderr: [$err]"; return 1; }
  case "$err" in *"agent-runner:"*) : ;; *) echo "    infra rota sin diagnóstico agent-runner: [$err]"; return 1 ;; esac
}
test_review_infra_rota_sale_3_y_ruidosa() { _ar_repo _case_review_infra_rota_sale_3_y_ruidosa; }

_case_review_timeout_mata_descendientes() {
  printf '#!/usr/bin/env bash\ntrap "" TERM HUP\n( trap "" TERM HUP; sleep 30 ) &\necho "$!" > review-tree-child.pid\nwait\n' \
    > review-tree.sh; chmod +x review-tree.sh
  FAKE_REVIEW_SCRIPT="$PWD/review-tree.sh" bash tools/agent-runner.sh review --backend fake \
    --prompt-file prompt.md --base HEAD --head HEAD --cwd "$PWD" --timeout 1 >/dev/null 2>&1
  local rc=$? child
  [ "$rc" = 124 ] || { echo "    timeout review del árbol devolvió $rc"; return 1; }
  child="$(cat review-tree-child.pid 2>/dev/null)"
  [ -n "$child" ] || { echo "    el fixture review no registró al descendiente"; return 1; }
  _espera_proceso_muerto "$child" || {
    kill -9 "$child" 2>/dev/null
    echo "    quedó vivo el descendiente review $child que ignoraba TERM"; return 1;
  }
}
test_review_timeout_tambien_mata_descendientes() { _ar_repo _case_review_timeout_mata_descendientes; }

_case_backend_lento_en_instalar_sesion_no_escapa() {
  # AR_TEST_SETSID_DELAY retrasa MECÁNICAMENTE el setsid+exec del backend
  # (simula la saturación de un runner CI sin depender de carga real).
  # Hallazgo del diagnóstico: la carrera "killpg antes de setsid" NO existe —
  # Popen espera al exec del hijo (errpipe), así que killpg tras Popen
  # siempre ve al grupo ya instalado. Lo que SÍ debe sostenerse con un
  # backend lento en instalar: (1) el presupuesto del timeout corre desde
  # que el backend ARRANCA, no desde que el runner aprovisiona — el backend
  # llega a ejecutar su primer comando aunque instalarse tardara 3× el
  # timeout; (2) el 124 llega igual; (3) no queda nadie vivo detrás.
  printf '#!/usr/bin/env bash\necho "$$" > tarde.pid\ntouch tarde.marker\nexec sleep 30\n' \
    > tarde.sh; chmod +x tarde.sh
  local rc lider
  AR_TEST_SETSID_DELAY=3 FAKE_RUN_SCRIPT="$PWD/tarde.sh" bash tools/agent-runner.sh run \
    --backend fake --prompt-file prompt.md --cwd "$PWD" --timeout 1 >/dev/null 2>&1
  rc=$?
  [ "$rc" = 124 ] || { echo "    backend lento en instalarse devolvió exit=$rc, no 124"; return 1; }
  [ -e tarde.marker ] || { echo "    el backend nunca ejecutó: el reloj del watchdog corrió DURANTE la instalación"; return 1; }
  lider="$(cat tarde.pid 2>/dev/null)"
  [ -n "$lider" ] || { echo "    el fixture no registró su pid"; return 1; }
  _espera_proceso_muerto "$lider" || {
    kill -9 "$lider" 2>/dev/null
    echo "    el backend lento quedó vivo tras el 124"; return 1;
  }
}
test_timeout_con_backend_lento_en_instalar_su_sesion() { _ar_repo _case_backend_lento_en_instalar_sesion_no_escapa; }

_case_run_exitoso_no_deja_nietos() {
  # El contrato de cabecera del runner promete terminar el GRUPO completo
  # para no dejar huérfanos — también cuando el backend TERMINA BIEN: un
  # nieto que ignora TERM y sobrevive al éxito del líder es un proceso
  # fantasma en CI (la clase de leak de WF-01).
  printf '#!/usr/bin/env bash\n( trap "" TERM HUP; sleep 30 ) &\necho "$!" > nieto.pid\nexit 0\n' \
    > exitoso.sh; chmod +x exitoso.sh
  local rc nieto
  FAKE_RUN_SCRIPT="$PWD/exitoso.sh" bash tools/agent-runner.sh run --backend fake \
    --prompt-file prompt.md --cwd "$PWD" >/dev/null 2>&1
  rc=$?
  [ "$rc" = 0 ] || { echo "    el run exitoso devolvió $rc"; return 1; }
  nieto="$(cat nieto.pid 2>/dev/null)"
  [ -n "$nieto" ] || { echo "    el fixture no registró al nieto"; return 1; }
  _espera_proceso_muerto "$nieto" || {
    kill -9 "$nieto" 2>/dev/null
    echo "    el nieto $nieto sobrevivió al run EXITOSO: el grupo no se barre al salir"; return 1;
  }
}
test_run_exitoso_no_deja_nietos_vivos() { _ar_repo _case_run_exitoso_no_deja_nietos; }

_case_review_lenta_legitima_sin_124() {
  # FALSO POSITIVO: un backend LENTO pero LEGÍTIMO — termina ANTES del
  # timeout — no recibe 124 ni pierde su veredicto. Guard contra un
  # watchdog "adelantado" que mate procesos sanos para estabilizar el reloj.
  printf '#!/usr/bin/env bash\nsleep 2\nprintf "VERDICT: GREEN\\nFINDINGS: 0\\nSCOPE: lento-legitimo\\n"\n' \
    > slow-ok.sh; chmod +x slow-ok.sh
  local rc
  FAKE_REVIEW_SCRIPT="$PWD/slow-ok.sh" bash tools/agent-runner.sh review --backend fake \
    --prompt-file prompt.md --base HEAD --head HEAD --cwd "$PWD" --timeout 30 >/dev/null 2>&1
  rc=$?
  [ "$rc" = 0 ] || { echo "    review lenta legítima devolvió $rc: ¿el watchdog corta antes de tiempo?"; return 1; }
}
test_review_lenta_pero_legitima_no_recibe_124() { _ar_repo _case_review_lenta_legitima_sin_124; }

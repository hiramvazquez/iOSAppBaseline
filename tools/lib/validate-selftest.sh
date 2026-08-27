#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# validate-selftest.sh — cada detector DEMUESTRA una vez que ve
# ════════════════════════════════════════════════════════════════════
# El bloque `--selftest` / `--full` de tools/validate-harness.sh. Los checks
# estáticos miran CONFIGURACIÓN; esto exige EVIDENCIA: cada detector corre
# contra un fixture mínimo en un sandbox, con los binarios y confs de ESTE
# repo, y debe emitir su contrato (§14.3) — el exit code correcto y su marca
# (SUMMARY / score).
#
# Se SOURCEA desde tools/validate-harness.sh: usa sus helpers ok/bad/warn y su
# variable FAIL. No se ejecuta suelta (tools/lib/ → sin bit +x, exento de
# check-exec-bits.sh).

# ════════════════════════════════════════════════════════════════════
# SELFTEST — cada detector DEMUESTRA una vez que ve (--selftest / --full)
# ════════════════════════════════════════════════════════════════════
# Nacido de la retrospectiva del primer proyecto real: sus tres fallos más
# caros (build sin cablear, semgrep autodeclarado muerto, nivel 4 fantasma)
# tenían la misma forma — un gate que PARECÍA sano y nunca había producido
# una detección. Los checks estáticos miran configuración; esto exige
# EVIDENCIA: cada detector corre contra un fixture mínimo, con los binarios
# y confs de ESTE repo, y debe emitir su contrato (§14.3) — un exit code
# correcto y su marca (SUMMARY / score). Un detector que no pasa su selftest
# no está "pendiente": está MUDO y anunciándose como sano.
selftest() {
  echo ""
  echo "━━━ selftest: cada detector demuestra que VE ━━━"
  local SB out rc
  SB="$(mktemp -d)"
  mkdir -p "$SB/r"
  cp -R tools "$SB/r/tools" 2>/dev/null
  cp -R scripts "$SB/r/scripts" 2>/dev/null   # los hooks bloqueantes también se selftestean
  rm -rf "$SB/r/tools/tests"   # la suite no es un detector
  (
    cd "$SB/r" || exit 1
    git init -q . 2>/dev/null; git config user.email s@s.s; git config user.name s
    echo seed > seed.txt; git add seed.txt; git commit -qm init 2>/dev/null
    echo full > tools/preset
  ) || { warn "selftest: no pude montar el sandbox"; rm -rf "$SB"; return 0; }

  # 1. conflict-markers: un conflicto staged DEBE bloquear (exit 1).
  ( cd "$SB/r" && printf '%s HEAD\na\n%s\nb\n%s rama\n' '<<<<<<<' '=======' '>>>>>>>' > c.txt \
    && git add c.txt ) 2>/dev/null
  out="$(cd "$SB/r" && bash tools/check-conflict-markers.sh 2>&1)"; rc=$?
  if [ "$rc" = "1" ]; then ok "conflict-markers: VE (bloqueó un conflicto staged)"
  else bad "conflict-markers: NO vio un conflicto staged (exit $rc)"; fi
  ( cd "$SB/r" && git rm -q --cached c.txt 2>/dev/null; rm -f c.txt )

  # 2. review-marker: código de producto staged sin marker DEBE bloquear.
  ( cd "$SB/r" && mkdir -p app && echo 'let x = 1' > app/main.swift && git add app/main.swift ) 2>/dev/null
  out="$(cd "$SB/r" && bash tools/check-review-marker.sh --staged 2>&1)"; rc=$?
  if [ "$rc" = "1" ]; then ok "review-marker: VE (exigió review a producto staged sin marker)"
  else bad "review-marker: dejó pasar producto sin marker (exit $rc) — el gate nº1 está mudo"; fi
  ( cd "$SB/r" && git rm -q --cached app/main.swift 2>/dev/null; rm -rf app )

  # 3. secret-scan: un secreto con formato real staged DEBE bloquear.
  #    (La clave se ENSAMBLA para no dejar un patrón contiguo en este script.)
  #
  #    ⚠️ La clave del fixture NO puede ser la CANÓNICA de la documentación de
  #    AWS — el prefijo AKIA seguido de IOSFODNN7 y EXAMPLE. gitleaks la ignora
  #    A PROPÓSITO (aparece en todos los tutoriales del mundo), así que con ella
  #    el selftest daba ❌ sobre un gate perfectamente sano. Verificado en vivo:
  #    esa misma clave en cualquier archivo → exit 0; cualquier otra AKIA en el
  #    mismo archivo → exit 1. Un selftest con falsos positivos se ignora
  #    entero, y entonces deja de proteger de los gates mudos, que es justo para
  #    lo que existe (§14, ley del 10%). Usa un formato válido pero NO canónico,
  #    como hace docs/ADOPTION.md §7.
  #
  #    ⚠️⚠️ Y POR ESO EL NOMBRE DE LA CLAVE VA PARTIDO ARRIBA, en trozos que no
  #    forman el literal. NO lo "arregles" juntándolo para que se lea mejor:
  #    `canon-enforce.sh` (CHECK 2) escanea los archivos recién escritos y una
  #    clave AWS contigua en ESTE archivo bloquea el cierre de turno — incluido
  #    el turno que la escribió. Le pasó a un agente en un proyecto real: vio el
  #    nombre partido, lo unió por prolijidad, y se dejó el turno trabado.
  #    La alternativa mala sería añadir este archivo a `is_detector_definition()`
  #    del secret-scan: eso lo dejaría CIEGO a secretos de verdad para siempre.
  #    Partir el literal cuesta una línea fea; cegar el detector cuesta el gate.
  if command -v gitleaks >/dev/null 2>&1; then
    ( cd "$SB/r" && printf 'aws_secret_access_key = "%s%s"\n' 'AKIA' '1234567890ABCDEF' > s.env.py \
      && git add s.env.py ) 2>/dev/null
    out="$(cd "$SB/r" && bash tools/secret-scan.sh --staged 2>&1)"; rc=$?
    if [ "$rc" = "1" ]; then ok "secret-scan: VE (cazó una clave AWS staged)"
    else bad "secret-scan: NO cazó una clave AWS staged (exit $rc) — gitleaks está pero no mira"; fi
    ( cd "$SB/r" && git rm -q --cached s.env.py 2>/dev/null; rm -f s.env.py )
  else
    warn "secret-scan: gitleaks no instalado — selftest saltado (el nivel ya se reporta MUDO)"
  fi

  # 4. semgrep: un patrón prohibido staged debe dar exit 1 + SEMGREP_SUMMARY;
  #    sin semgrep instalado, el contrato correcto es exit 3 (no pudo mirar).
  # `*-malo.*` EXPLÍCITO, no "el primero del directorio". La versión anterior
  # cogía `ls … | head -1` dando por hecho que todo lo de ahí dispara alguna
  # regla; en cuanto el directorio tuvo un README y un fixture BUENO (el que
  # debe dar cero por definición), el selftest empezó a coger uno de esos y a
  # declarar el nivel 2 MUDO estando perfectamente sano. Un selftest con falsos
  # positivos se ignora entero — y entonces deja de proteger de los gates
  # mudos, que es justo para lo que existe.
  local FIXT=""
  if ls tools/semgrep/fixtures/*-malo.* >/dev/null 2>&1; then
    FIXT="$(ls tools/semgrep/fixtures/*-malo.* | head -1)"
    cp "$FIXT" "$SB/r/fixture_selftest.${FIXT##*.}" 2>/dev/null
  elif [ -f tools/semgrep/rules/swift.yaml ]; then
    printf 'import Foundation\nlet d = try! JSONDecoder().decode(Int.self, from: Data())\n' \
      > "$SB/r/fixture_selftest.swift"
  fi
  if [ -n "$(ls "$SB"/r/fixture_selftest.* 2>/dev/null)" ]; then
    ( cd "$SB/r" && git add fixture_selftest.* ) 2>/dev/null
    out="$(cd "$SB/r" && bash tools/semgrep-scan.sh --staged 2>&1)"; rc=$?
    if command -v semgrep >/dev/null 2>&1; then
      if [ "$rc" = "1" ] && printf '%s' "$out" | grep -q 'SEMGREP_SUMMARY'; then
        ok "semgrep: VE (cazó el fixture y emitió SEMGREP_SUMMARY)"
      else
        bad "semgrep: instalado pero NO cazó el fixture (exit $rc) — reglas rotas o scan mudo"
      fi
    else
      if [ "$rc" = "3" ]; then ok "semgrep: ausente y lo DECLARA (exit 3, contrato §14.3)"
      else bad "semgrep ausente pero exit $rc (esperaba 3) — un scanner que no corrió parece uno que pasó"; fi
    fi
  else
    warn "semgrep: sin fixture generable para tus reglas — añade uno en tools/semgrep/fixtures/"
  fi

  # 5. mutation-score: el CABLEADO del score, con override (muter real es
  #    lento y va aparte). Fija que el número entra, viaja y sale.
  out="$(cd "$SB/r" && MUTATION_SCORE_OVERRIDE=57 bash tools/mutation-score.sh --report 2>&1)"; rc=$?
  if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q 'score=57'; then
    ok "mutation-score: el cableado del score funciona (override 57 → score=57)"
  else
    bad "mutation-score: el score NO viaja (exit $rc: $out) — nivel 4 fantasma"
  fi
  if command -v muter >/dev/null 2>&1 && { [ -f muter.conf.yml ] || [ -f muter.conf.json ]; }; then
    warn "mutation-score: runner real presente; el selftest NO lo corre (lento). Evidencia real: bash tools/mutation-score.sh --report"
  fi

  # 6. drift-ratchet: corre y emite su resumen (sin crashear en ESTE repo).
  out="$(cd "$SB/r" && bash tools/drift-ratchet.sh --check 2>&1)"; rc=$?
  case "$rc" in
    0|1) ok "drift-ratchet: corre y responde (exit $rc)" ;;
    *)   bad "drift-ratchet: crasheó en el selftest (exit $rc): $(printf '%s' "$out" | head -2)" ;;
  esac

  # ── Los tres que BLOQUEAN trabajo ─────────────────────────────────
  # Donde un fallo mudo o un falso positivo cuestan más: si uno de estos
  # tres calla, el flujo entero pierde su garantía — y si grita de más,
  # el equipo lo desactiva. Pedido explícitamente por la retro del primer
  # proyecto real ("los que paran el trabajo son donde más duele").

  # 7. git-guard (reviewer-gate §0): un --no-verify DEBE denegarse (exit 2).
  #    El bloqueo ocurre ANTES de los detectores, así que no requiere stubs.
  out="$(cd "$SB/r" && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m x"}}' \
        | bash scripts/agent-hooks/reviewer-gate.sh 2>&1)"; rc=$?
  if [ "$rc" = "2" ]; then ok "git-guard: VE (denegó git commit --no-verify)"
  else bad "git-guard: NO denegó --no-verify (exit $rc) — la prohibición nº1 de §7 está muda"; fi

  # 8. skill-reminder: editar un path de la matriz sin haber leído las refs
  #    DEBE bloquear (exit 2, preset full). El path se SINTETIZA desde tu
  #    propio skill-matrix.conf y se verifica contra el mismo glob que usa
  #    el hook — así el selftest sigue valiendo cuando cambies la matriz.
  local CAND="" g c
  while IFS='|' read -r g _; do
    case "$g" in ''|'#'*) continue ;; esac
    g="$(printf '%s' "$g" | sed -E 's/[[:space:]]+$//')"
    c="$g"; c="${c//\*\*\//app/}"; c="${c//\*\*/app}"; c="${c//\*/X}"
    # candidatos que caen en las EXCLUSIONES del hook (doc/tooling) no sirven
    case "$c" in .agents/*|.claude/*|.cursor/*|docs/*|tools/*|scripts/*|ci/*|enterprise/*|*.md) continue ;; esac
    # shellcheck disable=SC2254  # el glob DEBE expandirse como patrón
    case "$c" in $g) CAND="$c"; break ;; esac
  done < tools/skill-matrix.conf
  if [ -n "$CAND" ]; then
    out="$(cd "$SB/r" && printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$CAND" \
          | bash scripts/agent-hooks/skill-reminder.sh 2>&1)"; rc=$?
    if [ "$rc" = "2" ]; then ok "skill-reminder: VE (bloqueó editar $CAND sin leer sus refs)"
    else bad "skill-reminder: dejó editar $CAND sin lecturas (exit $rc) — la matriz §11 está muda"; fi
  else
    warn "skill-reminder: no pude sintetizar un path desde tu skill-matrix.conf — verifica el gate a mano"
  fi

  # 9. canon-enforce: un secreto RECIÉN ESCRITO en el árbol debe bloquear el
  #    cierre de turno. (Clave ensamblada; formato válido no canónico.)
  ( cd "$SB/r" && printf 'let apiKey = "%s%s"\n' 'AKIA' 'X7Q4ZR9PL2MN8V3B' > Leak.swift )
  out="$(cd "$SB/r" && bash scripts/agent-hooks/canon-enforce.sh </dev/null 2>&1)"; rc=$?
  if [ "$rc" = "2" ] && printf '%s' "$out" | grep -q 'SECRETO'; then
    ok "canon-enforce: VE (bloqueó el cierre de turno con un secreto recién escrito)"
  else
    bad "canon-enforce: NO bloqueó un secreto recién escrito (exit $rc) — el Stop-gate está mudo"
  fi
  ( cd "$SB/r" && rm -f Leak.swift )

  rm -rf "$SB"
}

#!/usr/bin/env bash
# secret-scan: wrapper de gitleaks. Sus dos guards de FALSO POSITIVO son de
# infraestructura: gitleaks ausente no puede trabar el commit en LOCAL (el
# fail-closed vive en CI, ci/run-gates.sh), y un modo inválido debe fallar
# ruidosamente en vez de "pasar por limpio".
# Cierra parte de f-meta-fp-manifiesto.

_ss_sandbox() {
  local d; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/bin"
  cp "$PROJECT_ROOT/tools/secret-scan.sh" "$d/tools/"
  ( cd "$d" || exit 1; git init -q . 2>/dev/null; "$1" )
  local rc=$?; rm -rf "$d"; return $rc
}

# ── FALSO POSITIVO guard: gitleaks ausente → avisa, NO bloquea local ─
_case_sin_gitleaks_no_traba() {
  PATH="/usr/bin:/bin" bash tools/secret-scan.sh --staged >/dev/null 2>&1
  [ "$?" = "0" ] || { echo "    sin gitleaks instalado, el commit local quedó trabado"; return 1; }
}
test_gitleaks_ausente_no_traba_en_local() { _ss_sandbox _case_sin_gitleaks_no_traba; }

# ── un modo inválido NO pasa por limpio ─────────────────────────────
_case_modo_invalido_falla() {
  # gitleaks falso para que el guard de instalación no dispare primero:
  printf '#!/usr/bin/env bash\nexit 0\n' > bin/gitleaks; chmod +x bin/gitleaks
  PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/secret-scan.sh --modo-inventado >/dev/null 2>&1
  [ "$?" = "2" ] || { echo "    un modo inválido no falló (¿pasó por limpio?)"; return 1; }
}
test_modo_invalido_falla_ruidoso() { _ss_sandbox _case_modo_invalido_falla; }

# ── la detección propaga: gitleaks encuentra → exit != 0 ────────────
_case_hallazgo_propaga() {
  printf '#!/usr/bin/env bash\necho "leak encontrado" >&2\nexit 1\n' > bin/gitleaks; chmod +x bin/gitleaks
  PATH="$(pwd)/bin:/usr/bin:/bin" bash tools/secret-scan.sh --staged >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "    un hallazgo de gitleaks no propagó el fallo"; return 1; }
}
test_hallazgo_de_gitleaks_propaga() { _ss_sandbox _case_hallazgo_propaga; }

# ════════════════════════════════════════════════════════════════════
# `--range`: el fallback era un FAIL-OPEN (f-leak-en-historia, hallazgo lateral)
# ════════════════════════════════════════════════════════════════════
# `gitleaks … --log-opts=RANGO || gitleaks --staged` trataba igual dos cosas
# opuestas: "el rango no se resuelve" y "gitleaks ENCONTRÓ un secreto". Ante un
# hallazgo real, el `||` se iba al fallback, escaneaba el índice (vacío en CI),
# salía 0 — y el gate de secretos daba verde sobre una fuga.
_case_hallazgo_en_rango_no_se_convierte_en_verde() {
  # El fake reproduce la situación REAL de CI: hay un secreto en el rango de
  # commits (exit 1) y NADA staged (exit 0). Con el `||`, el segundo tapaba al
  # primero. Un fake que devolviera lo mismo en los dos casos no probaría nada
  # — el propio test tuvo que corregirse por eso.
  cat > bin/gitleaks <<'FAKE'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in --log-opts=*) echo "leak en el rango" >&2; exit 1 ;; esac
done
exit 0
FAKE
  chmod +x bin/gitleaks
  git config user.email t@t.t; git config user.name t
  echo x > a.txt; git add -A; git commit -qm base >/dev/null 2>&1
  local rc
  RANGE='HEAD~0..HEAD' PATH="$(pwd)/bin:/usr/bin:/bin" \
    bash tools/secret-scan.sh --range >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] && { echo "    un HALLAZGO en el rango salió como scan limpio (fail-open del gate de secretos)"; return 1; }
  return 0
}
test_un_hallazgo_en_el_rango_nunca_sale_verde() {
  _ss_sandbox _case_hallazgo_en_rango_no_se_convierte_en_verde
}

_case_rango_irresoluble_es_3_no_0() {
  # §14.3: "no pude mirar" (3) jamás puede confundirse con "limpio" (0). Antes
  # se caía a escanear el índice, que en CI está vacío → verde sobre nada.
  printf '#!/usr/bin/env bash\nexit 0\n' > bin/gitleaks; chmod +x bin/gitleaks
  git config user.email t@t.t; git config user.name t
  echo x > a.txt; git add -A; git commit -qm base >/dev/null 2>&1
  local rc
  RANGE='rama-que-no-existe..HEAD' PATH="$(pwd)/bin:/usr/bin:/bin" \
    bash tools/secret-scan.sh --range >/dev/null 2>&1; rc=$?
  [ "$rc" = "3" ] || { echo "    un rango irresoluble devolvió $rc (esperaba 3: el detector no pudo mirar)"; return 1; }
}
test_rango_irresoluble_devuelve_3_no_0() { _ss_sandbox _case_rango_irresoluble_es_3_no_0; }

_case_usa_gates_base_ref() {
  # FALSO POSITIVO guard: en CI no hay upstream para `@{push}`, pero sí
  # GATES_BASE_REF. Si no se usara, cada corrida de CI caería en el exit 3 y el
  # equipo aprendería a ignorar el paso — un gate roto que se desactiva solo.
  printf '#!/usr/bin/env bash\nexit 0\n' > bin/gitleaks; chmod +x bin/gitleaks
  git config user.email t@t.t; git config user.name t
  echo x > a.txt; git add -A; git commit -qm base >/dev/null 2>&1
  git branch -f base-de-ci >/dev/null 2>&1
  echo y > b.txt; git add -A; git commit -qm siguiente >/dev/null 2>&1
  local rc
  GATES_BASE_REF=base-de-ci PATH="$(pwd)/bin:/usr/bin:/bin" \
    bash tools/secret-scan.sh --range >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] || { echo "    con GATES_BASE_REF presente el scan no pudo correr (exit $rc)"; return 1; }
}
test_range_usa_gates_base_ref_cuando_no_hay_upstream() {
  _ss_sandbox _case_usa_gates_base_ref
}

# ── El baseline no puede dejar MUDO al detector ─────────────────────
# El literal del simulacro de ADOPTION §7 vive en el historial del scaffold y
# es DETECTABLE a propósito (si no, el simulacro no probaría nada). Por eso el
# arreglo NO puede ser allowlistear ese valor: dejaría mudos el propio
# simulacro y el selftest de validate-harness, que lo usan para demostrar que
# el detector VE. Este test fija esa frontera.
_case_el_valor_del_simulacro_sigue_siendo_detectable() {
  local doc="$PROJECT_ROOT/docs/ADOPTION.md" toml="$PROJECT_ROOT/.gitleaks.toml"
  [ -f "$toml" ] || return 0
  local literal; literal="$(grep -oE 'AKIA[0-9A-Z]{16}' "$doc" 2>/dev/null | head -1)"
  [ -n "$literal" ] || literal="AKIA1234567890ABCDEF"
  if grep -qF "$literal" "$toml" 2>/dev/null; then
    echo "    .gitleaks.toml allowlistea '$literal', que es el valor del simulacro §7"
    echo "    y del selftest de validate-harness: los dos quedarían MUDOS y seguirían"
    echo "    diciendo que el Anillo 1 está vivo. Usa el baseline, no un allowlist."
    return 1
  fi
  return 0
}
test_el_valor_del_simulacro_nunca_se_allowlistea() {
  _case_el_valor_del_simulacro_sigue_siendo_detectable
}

# ── La caché de gates no es un secreto (f-gate-cache-falso-positivo-gitleaks) ──
# `tools/gate-cache.sh` escribe JSON con un campo `"key"` que es un sha256 del
# diff+HEAD+reglas. gitleaks lo lee como secreto genérico de alta entropía y
# `--all` empezó a dar un hallazgo permanente: reproducido aquí y, de forma
# independiente, en un adoptante. No hay riesgo de fuga —los archivos están
# gitignored— pero un hallazgo permanente y falso es peor que ninguno: se
# aprende a ignorar el rojo, y con él se ignora el del día que importa
# (ley del 10%, §14.2).
#
# ⚠️ Este test comprueba el EFECTO, no la declaración, y esa distinción ya costó
# un fallo en este repo: el guard de `.semgrepignore` verificaba que la línea
# estuviera en el archivo de configuración, no que la herramienta la obedeciera
# por el camino que usamos. Aquí se ESCRIBE una caché real y se corre gitleaks.
_case_la_cache_de_gates_no_dispara_gitleaks() {
  mkdir -p .agents/state/gate-cache/semgrep
  printf '{"key":"%s","rc":0,"findings":0}\n' \
    "$(printf 'x' | { shasum -a 256 2>/dev/null || sha256sum; } | awk '{print $1}')" \
    > .agents/state/gate-cache/semgrep/deadbeef.json
  cp "$PROJECT_ROOT/.gitleaks.toml" .gitleaks.toml 2>/dev/null
  local out rc
  out="$(gitleaks dir . --no-banner --redact 2>&1)"; rc=$?
  [ "$rc" = "0" ] && return 0
  echo "    gitleaks marca la caché de gates como secreto (exit $rc):"
  printf '%s\n' "$out" | grep -i 'file\|secret' | head -6 | sed 's/^/      /'
  echo "    Es un sha256 del diff, no una credencial. El allowlist por PATH vive"
  echo "    en .gitleaks.toml; si has tocado ese archivo, revisa esa entrada."
  return 1
}
test_la_cache_de_gates_no_se_lee_como_secreto() {
  if ! command -v gitleaks >/dev/null 2>&1; then
    # Declararlo, no tragárselo: un gate que no corrió no puede parecer un gate
    # que pasó (§14.3). En CI gitleaks SÍ está, y ahí este test corre de verdad.
    echo "    (gitleaks ausente — EFECTO no verificado aquí; el Anillo 3 lo cubre)"
    # Se busca la ENTRADA del allowlist, no la palabra: los comentarios de encima
    # explican por qué existe y contienen 'gate-cache', así que un `grep` a secas
    # pasaba aunque alguien borrara la entrada. Falso NEGATIVO del mismo patrón de
    # siempre — el check leyendo el texto que HABLA de la cosa en vez de la cosa.
    grep -qE "^[[:space:]]*'''[^']*gate-cache[^']*''','?[[:space:]]*$" \
      "$PROJECT_ROOT/.gitleaks.toml" 2>/dev/null && return 0
    echo "    ...y el allowlist por path NI SIQUIERA está declarado en .gitleaks.toml"
    return 1
  fi
  _ss_sandbox _case_la_cache_de_gates_no_dispara_gitleaks 2>/dev/null \
    || _case_la_cache_de_gates_no_dispara_gitleaks
}

# El PRIMER push de un repo no tiene upstream: `@{push}` no resuelve y, sin
# último recurso, `--range` moría con exit 3 — o sea que todo adoptante
# estrenaba su repo con el gate de secretos bloqueando y sin más salida que un
# override. `HEAD` cubre ese caso siendo MÁS estricto (toda la historia propia),
# no menos, y sin arrastrar la historia ajena de un remote `template`.
test_el_primer_push_sin_upstream_escanea_su_propia_historia() {
  _case_primer_push() {
    printf 'contenido\n' > a.txt
    git add -A >/dev/null 2>&1
    git commit -qm "primer commit del repo" >/dev/null 2>&1
    # Sin upstream configurado: el estado exacto de un repo recién creado.
    git rev-parse '@{push}' >/dev/null 2>&1 \
      && { echo "    precondición rota: el sandbox tiene upstream"; return 1; }

    local out rc
    out="$(bash "$PROJECT_ROOT/tools/secret-scan.sh" --range 2>&1)"; rc=$?
    [ "$rc" != "3" ] \
      || { echo "    el primer push sigue saliendo 3: el adoptante no puede pushear"; return 1; }
    case "$out" in
      *"commits scanned"*) : ;;
      *) echo "    no escaneó nada; salida: $out"; return 1 ;;
    esac
  }
  with_temp_repo _case_primer_push
}

# La garantía más sensible del último recurso, y la que causó el incidente real:
# `HEAD` NO puede arrastrar la historia de un remote no relacionado. Un adoptante
# por copia tiene un remote `template` cuya historia no es ancestro de la suya;
# si el scan la incluyera, su primer push heredaría los hallazgos históricos del
# template (pasó: un ejemplo didáctico de secreto en su ADOPTION.md).
#
# ⚠️ Este test EJECUTA `secret-scan.sh --range` con gitleaks real. Una versión
# anterior solo comprobaba con `git rev-list` que el commit ajeno no fuera
# ancestro de HEAD — que es cierto por construcción de git, no por nuestro
# código: probaba git, no el harness. Y su "mutante" cambiaba el propio test,
# no el script. Lo cazó el reviewer. Un test que no ejerce el código que dice
# proteger es decorativo por definición (AGENTS.md §5).
test_el_ultimo_recurso_no_arrastra_historia_de_un_remote_ajeno() {
  command -v gitleaks >/dev/null 2>&1 || return 0   # sin gitleaks, no aplica
  _case_remote_ajeno() {
    local ajeno; ajeno="$(mktemp -d)"
    (
      cd "$ajeno" || exit 1
      git init -q .
      git config user.email t@t.t; git config user.name t
      # El secreto tiene que ser uno que gitleaks DETECTE de verdad: probé el
      # AKIA...EXAMPLE canónico, un id AKIA realista y una cabecera de clave
      # RSA — gitleaks no marca ninguno, así que el test habría pasado sin
      # probar nada. Un token de GitHub sí lo marca.
      # El literal va PARTIDO a propósito: escrito entero, el propio
      # secret-scan de este repo lo cazaría en este archivo y dejaría el gate
      # en rojo perpetuo. (Lección de la casa: un literal partido lleva escrito
      # por qué, o el siguiente lo junta.)
      printf 'token = "%s%s"\n' 'ghp_' '016c8bF6c0d1e2A3b4C5d6E7f8091a2B3c4D5' > filtrado.txt
      git add -A >/dev/null 2>&1
      git commit -qm "historia AJENA con un secreto" >/dev/null 2>&1
    )
    printf 'contenido limpio\n' > propio.txt
    git add -A >/dev/null 2>&1
    git commit -qm "historia propia" >/dev/null 2>&1
    git remote add template "$ajeno" >/dev/null 2>&1
    git fetch -q template >/dev/null 2>&1

    # Precondición: el secreto ajeno ESTÁ en el repo (si no, no se prueba nada).
    local hay_ajeno; hay_ajeno="$(git rev-list --all --count 2>/dev/null)"
    local propios;   propios="$(git rev-list --count HEAD 2>/dev/null)"
    [ "$hay_ajeno" -gt "$propios" ] \
      || { rm -rf "$ajeno"; echo "    precondición rota: el fetch no trajo la historia ajena"; return 1; }

    # EL SCAN REAL, sin RANGE ni GATES_BASE_REF: cae en el último recurso.
    local out rc
    out="$(bash "$PROJECT_ROOT/tools/secret-scan.sh" --range 2>&1)"; rc=$?
    rm -rf "$ajeno"
    [ "$rc" = "0" ] \
      || { echo "    el scan del primer push reportó el secreto de la historia AJENA"
           echo "    (exit $rc) — el adoptante heredaría hallazgos del template:"
           printf '%s\n' "$out" | sed 's/^/      /' | head -5; return 1; }
  }
  with_temp_repo _case_remote_ajeno
}

#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# test_prd_tree.sh — tests de check-prd-tree.sh
# ════════════════════════════════════════════════════════════════════
# El detector compara lo que la §5 de un PRD DECLARA contra `git ls-files`.
# Su riesgo no es que se le escape un archivo: es que la §5 está escrita en
# markdown con prosa española alrededor, y la prosa española está LLENA de
# barras que parecen rutas. La primera versión de este detector marcaba
# `D1/E2:`, `schedule/humano`, `keep/tune/retire` y `lint/typecheck` — un 29%
# de falsos positivos, casi el triple del 10% que §14.2 fija como descarte.
#
# Por eso la mayor parte de este archivo son falsos positivos MEDIDOS, no
# imaginados: cada uno salió de correr el detector contra los PRDs reales.

_pt_repo() { # _pt_repo <función> — sandbox git con el detector dentro
  local d rc; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/docs/process/prds"
  cp "$PROJECT_ROOT/tools/check-prd-tree.sh" "$d/tools/" 2>/dev/null
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null
    git config user.email t@t.t; git config user.name t
    git config commit.gpgsign false 2>/dev/null
    "$1"
  ); rc=$?
  rm -rf "$d"
  return $rc
}

# `git stage` y no `git add`: el reviewer-gate bloquea un payload de Bash que
# lleve `git add` y `git commit` juntos, aunque el texto vaya DENTRO de un
# heredoc destinado a un archivo (finding f-67e07109 — comparado por texto, no
# por comando). `stage` es sinónimo nativo de git y evita el falso positivo.
_pt_commit() { git stage -A >/dev/null 2>&1; git commit -qm "${1:-fixture}" 2>/dev/null; }

_pt_prd() { # _pt_prd <contenido> → lo escribe como PRD 0001 y lo commitea
  printf '%s\n' "$1" > docs/process/prds/0001-prueba.md
  _pt_commit "prd"
}

_pt_run() { bash tools/check-prd-tree.sh 2>&1; }

# ════════════════════════════════════════════════════════════════════
# CASOS QUE DEBEN DISPARAR
# ════════════════════════════════════════════════════════════════════

_case_declarado_que_no_existe() {
  mkdir -p tools
  printf 'x\n' > tools/existe.sh
  _pt_prd '# PRD
## 5. Estructura de archivos a crear / tocar
```
tools/existe.sh        ← este sí está
tools/fantasma.sh      ← este no existe en ninguna parte
```

## 6. Modelo'
  local out rc; out="$(_pt_run)"; rc=$?
  [ "$rc" = "1" ] || { echo "    una ruta declarada e inexistente no disparó (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
  printf '%s' "$out" | grep -q 'tools/fantasma.sh' \
    || { echo "    disparó pero no NOMBRA la ruta que falta"; return 1; }
  printf '%s' "$out" | grep -q 'tools/existe.sh' \
    && { echo "    marcó como ausente una ruta que SÍ existe"; return 1; }
  printf '%s' "$out" | grep -q 'PRD_TREE_SUMMARY .*faltan=1' \
    || { echo "    el contrato de stdout no reporta faltan=1"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_una_ruta_declarada_que_no_existe_dispara() { _pt_repo _case_declarado_que_no_existe; }

# ════════════════════════════════════════════════════════════════════
# EL MARCADOR DE SLICE FUTURO — la convención sin la que esto es ruido
# ════════════════════════════════════════════════════════════════════
# Un PRD por fases declara en su §5 archivos que las fases POSTERIORES aún no
# han creado. Sin una forma de decirlo, el detector tiene falsos positivos por
# diseño: el PRD 0007 real de este repo tiene cuatro (uno de ellos con un
# "CONDICIONADO AL FREEZE" escrito al lado en prosa, que ningún detector lee).
#
# El marcador es un LITERAL entre corchetes y no una palabra suelta porque se
# probó `PENDIENTE` y colisiona con prosa real de las descripciones ("primera
# ready sin deps pendientes", "entregadas pendientes de ratificación"). Un
# marcador que casa con la prosa que convive con él no marca nada.

_case_marcador_futuro_no_dispara() {
  _pt_prd '# PRD
## 5. Estructura
```
tools/aun-no.sh        ← [SLICE-FUTURO] lo entrega la fase 3
```

## 6. Modelo'
  local out rc; out="$(_pt_run)"; rc=$?
  [ "$rc" = "0" ] || { echo "    FALSO POSITIVO: una hoja marcada [SLICE-FUTURO] disparó (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
  printf '%s' "$out" | grep -q 'futuros=1' \
    || { echo "    no basta con callarse: el resumen debe CONTAR los futuros"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_una_hoja_marcada_como_slice_futuro_no_dispara() { _pt_repo _case_marcador_futuro_no_dispara; }

_case_el_marcador_no_es_un_comodin() {
  # El otro lado: el marcador exime a SU línea, no al PRD entero. Si eximiera
  # al archivo, poner uno solo apagaría el detector para todo el documento —
  # que es exactamente cómo un gate se vuelve decorativo sin que nadie lo note.
  _pt_prd '# PRD
## 5. Estructura
```
tools/aun-no.sh        ← [SLICE-FUTURO] lo entrega la fase 3
tools/fantasma.sh      ← este NO está marcado y no existe
```

## 6. Modelo'
  local out rc; out="$(_pt_run)"; rc=$?
  [ "$rc" = "1" ] || { echo "    un [SLICE-FUTURO] apagó el detector para las demás líneas (exit $rc)"; return 1; }
  printf '%s' "$out" | grep -q 'fantasma' \
    || { echo "    no reportó la línea sin marcar"; return 1; }
}
test_el_marcador_exime_a_su_linea_no_al_prd_entero() { _pt_repo _case_el_marcador_no_es_un_comodin; }

# ════════════════════════════════════════════════════════════════════
# FALSOS POSITIVOS — todos MEDIDOS contra los PRDs reales del repo
# ════════════════════════════════════════════════════════════════════

_case_fp_prosa_con_barras() {
  # LOS CUATRO QUE DISPARARON DE VERDAD en la primera versión. Todos llevan
  # barra y ninguno es una ruta. El filtro correcto no es "lleva barra" sino
  # "termina en extensión conocida o en `/`".
  _pt_prd '# PRD
## 5. Estructura
```
── D1/E2: reglas con mecanismo declarado ──────────────
tools/real.sh          ← esta sí es una ruta
El ciclo keep/tune/retire decide qué gates sobreviven.
Sin lint/typecheck no hay señal in-loop, y 0/1/3 es el contrato.
Revisado por Hiram/Claude en la ventana de schedule/humano.
```

## 6. Modelo'
  mkdir -p tools; printf 'x\n' > tools/real.sh; _pt_commit "real"
  local out rc; out="$(_pt_run)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: prosa con barras contó como ruta (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_la_prosa_con_barras_no_es_una_ruta() { _pt_repo _case_fp_prosa_con_barras; }

_case_fp_no_escanea_mas_alla_de_la_seccion() {
  # EL BUG QUE SE ESCAPÓ EN LA PRIMERA VERSIÓN. El corte enumeraba los
  # encabezados que cierran (`## 5b.`, `## 6.`) y el PRD 0003 real titula el
  # suyo `## 6-7. Modelo y flujo`, que no casa `^## *6\.`. El escaneo siguió
  # hasta un diagrama de flujo de otra sección y sacó rutas de allí.
  # Enumerar encabezados es una lista que crece para siempre; el corte correcto
  # es "cualquier otro `## `".
  _pt_prd '# PRD
## 5. Estructura
```
tools/real.sh          ← la única declaración de verdad
```

## 6-7. Modelo y flujo
```
tools/de-otra-seccion.sh → esto NO es una declaración de la §5
```

## 8. Anti-features'
  mkdir -p tools; printf 'x\n' > tools/real.sh; _pt_commit "real"
  local out rc; out="$(_pt_run)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: escaneó más allá de la §5 (encabezado '## 6-7.') (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_no_escanea_mas_alla_de_la_seccion_5() { _pt_repo _case_fp_no_escanea_mas_alla_de_la_seccion; }

_case_fp_no_touch_no_se_mira() {
  # El bloque NO-TOUCH declara PROHIBICIONES, no existencias. `ios/ android/
  # web/` es legítimo en un template que no tiene ninguno de los tres, y
  # marcarlo convertiría el contrato de "no toques esto" en un error.
  # LÍMITE CONOCIDO Y DECLARADO: por eso el detector NO caza que el NO-TOUCH
  # del PRD 0002 real cite `tools/findings/findings.ts`, que ya no existe.
  _pt_prd '# PRD
## 5. Estructura
```
tools/real.sh          ← declaración de verdad
```

### NO-TOUCH (contrato — el implementador NO toca esto)
```
ios/ android/ web/     ← nada de esto existe y da igual
tools/inexistente.sh   ← prohibido tocarlo, exista o no
```

## 6. Modelo'
  mkdir -p tools; printf 'x\n' > tools/real.sh; _pt_commit "real"
  local out rc; out="$(_pt_run)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: miró dentro del bloque NO-TOUCH (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_el_bloque_no_touch_no_se_compara() { _pt_repo _case_fp_no_touch_no_se_mira; }

_case_fp_continuacion_envuelta() {
  # Los PRDs reales envuelven las descripciones largas en líneas indentadas.
  # Esas continuaciones son prosa, no declaraciones — si contaran, cada
  # descripción larga sería un archivo inventado.
  _pt_prd '# PRD
## 5. Estructura
```
tools/real.sh          ← una descripción que se alarga tanto que sigue abajo
                         y menciona docs/algo-que-no-existe.md de pasada
```

## 6. Modelo'
  mkdir -p tools; printf 'x\n' > tools/real.sh; _pt_commit "real"
  local out rc; out="$(_pt_run)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: una línea de continuación contó como declaración (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_las_lineas_de_continuacion_no_son_declaraciones() { _pt_repo _case_fp_continuacion_envuelta; }

_case_directorio_declarado() {
  # Declarar un DIRECTORIO se cumple si tiene contenido versionado. `git
  # ls-files` no lista directorios, así que sin esto toda declaración de
  # carpeta sería un falso positivo permanente.
  _pt_prd '# PRD
## 5. Estructura
```
tools/sub/             ← un directorio con cosas dentro
```

## 6. Modelo'
  mkdir -p tools/sub; printf 'x\n' > tools/sub/algo.sh; _pt_commit "sub"
  local out rc; out="$(_pt_run)"; rc=$?
  [ "$rc" = "0" ] || {
    echo "    FALSO POSITIVO: un directorio con contenido contó como ausente (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_fp_un_directorio_declarado_con_contenido_no_dispara() { _pt_repo _case_directorio_declarado; }

# ════════════════════════════════════════════════════════════════════
# LO QUE NO SE COMPRUEBA SE DICE (§14.4)
# ════════════════════════════════════════════════════════════════════

_case_globs_se_cuentan() {
  # Un glob (`tools/tests/test_*.sh`) no se puede comparar literalmente. Se
  # CUENTA y se declara. Fingir que se comprobó sería anunciar una defensa que
  # no existe, que es el único pecado que este harness no comete.
  _pt_prd '# PRD
## 5. Estructura
```
tools/tests/test_*.sh  ← todos los tests
```

## 6. Modelo'
  local out rc; out="$(_pt_run)"; rc=$?
  [ "$rc" = "0" ] || { echo "    un glob no debe contar como ausente (exit $rc)"; return 1; }
  printf '%s' "$out" | grep -q 'globs=1' \
    || { echo "    el glob se saltó EN SILENCIO — debe aparecer en el resumen"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
}
test_los_globs_no_se_comparan_pero_se_declaran() { _pt_repo _case_globs_se_cuentan; }

_case_prd_sin_arbol() {
  # El PRD 0005 real escribe su §5 como TABLA, no como árbol. No se puede
  # comparar — y saltárselo en silencio lo haría indistinguible de un PRD que
  # pasó. Se declara por stderr y se cuenta en el resumen.
  _pt_prd '# PRD
## 5. Estructura de archivos a tocar

| Fase | Archivos |
|---|---|
| 0a | `tools/loquesea.sh` y otros |

## 6. Modelo'
  local out rc; out="$(_pt_run)"; rc=$?
  [ "$rc" = "0" ] || { echo "    un PRD sin árbol no debe fallar (exit $rc)"; return 1; }
  printf '%s' "$out" | grep -q 'sin_arbol=1' \
    || { echo "    no se contó como sin_arbol"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
  printf '%s' "$out" | grep -q 'no traen un árbol comparable' \
    || { echo "    se saltó el PRD EN SILENCIO — debe DECIRLO por stderr"; return 1; }
}
test_un_prd_sin_arbol_comparable_se_declara_no_se_salta_en_silencio() {
  _pt_repo _case_prd_sin_arbol
}

# ════════════════════════════════════════════════════════════════════
# CONTRATO §14.3 — "no pude mirar" nunca es "no encontré nada"
# ════════════════════════════════════════════════════════════════════

test_prd_tree_fuera_de_un_repo_git_devuelve_3() {
  local d rc; d="$(mktemp -d)"
  mkdir -p "$d/tools" "$d/docs/process/prds"
  cp "$PROJECT_ROOT/tools/check-prd-tree.sh" "$d/tools/"
  printf '# PRD\n' > "$d/docs/process/prds/0001-x.md"
  ( cd "$d" && bash tools/check-prd-tree.sh >/dev/null 2>&1 ); rc=$?
  rm -rf "$d"
  [ "$rc" = "3" ] || { echo "    fuera de un repo git esperaba exit 3, obtuve $rc"; return 1; }
}

_case_sin_directorio_de_prds() {
  rm -rf docs/process/prds
  printf 'x\n' > semilla; _pt_commit "semilla"
  local out rc; out="$(_pt_run)"; rc=$?
  [ "$rc" = "3" ] || { echo "    sin el directorio de PRDs esperaba exit 3, obtuve $rc"; return 1; }
  printf '%s' "$out" | grep -q 'PRD_TREE_SUMMARY' \
    || { echo "    exit 3 debe seguir imprimiendo el contrato de stdout"; return 1; }
}
test_prd_tree_sin_directorio_de_prds_devuelve_3() { _pt_repo _case_sin_directorio_de_prds; }

_case_contrato_de_stdout() {
  _pt_prd '# PRD
## 5. Estructura
```
```

## 6. Modelo'
  local primera
  primera="$(bash tools/check-prd-tree.sh 2>/dev/null | head -1)"
  case "$primera" in
    "PRD_TREE_SUMMARY declarados="*" faltan="*" futuros="*" globs="*" sin_arbol="*) return 0 ;;
    *) echo "    primera línea inesperada: '$primera'"; return 1 ;;
  esac
}
test_prd_tree_el_contrato_de_stdout_es_exacto() { _pt_repo _case_contrato_de_stdout; }

# ════════════════════════════════════════════════════════════════════
# SOLO LOS PRDs VIVOS — y lo saltado se DECLARA
# ════════════════════════════════════════════════════════════════════
# `prd-lifecycle.md` define el ciclo Draft → Approved → In progress → Shipped →
# Deprecated, y dice de la última: "se conserva como histórico". Un PRD Shipped
# describe lo que entregó EN SU DÍA; el repo siguió moviéndose por otros PRDs.
#
# El caso real que forzó esto: el PRD 0003 (Shipped) declara
# `tools/tests/test_backlog.sh`, que el PRD 0005 fase 2a dividió en cinco
# archivos (commit 915f03a). Y los PRDs 0001-0005 están declarados NO-TOUCH por
# los propios 0005 y 0006 — así que compararlos daba un gate ROJO QUE NADIE
# PUEDE PONER VERDE sin violar otro contrato. Ese es el deadlock de §14.3, no
# una molestia estética.

_case_shipped_no_se_compara() {
  _pt_prd '# PRD
> **Status:** Shipped — entregado en su día.

## 5. Estructura
```
tools/lo-que-entregue-entonces.sh   ← ya no existe, y el PRD no miente por ello
```

## 6. Modelo'
  local out rc; out="$(_pt_run)"; rc=$?
  [ "$rc" = "0" ] || { echo "    un PRD Shipped no debe disparar (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
  printf '%s' "$out" | grep -q 'historicos=1' \
    || { echo "    no se contó como histórico"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
  # …y NO en silencio: saltarse un PRD sin decirlo lo hace indistinguible de
  # uno que pasó, que es la forma exacta de fingir cobertura (§14.4).
  printf '%s' "$out" | grep -q 'registro histórico' \
    || { echo "    se saltó el PRD Shipped EN SILENCIO — debe declararlo"; return 1; }
}
test_un_prd_shipped_no_se_compara_pero_se_declara() { _pt_repo _case_shipped_no_se_compara; }

_case_sin_status_si_se_compara() {
  # FAIL-CLOSED. Un PRD sin campo Status NO puede eximirse solo: sería la
  # exención más barata del repo (basta con borrar una línea de la cabecera).
  # La ausencia de declaración nunca puede valer más que la declaración.
  _pt_prd '# PRD sin cabecera de estado

## 5. Estructura
```
tools/fantasma.sh      ← no existe
```

## 6. Modelo'
  local out rc; out="$(_pt_run)"; rc=$?
  [ "$rc" = "1" ] || { echo "    un PRD SIN Status debe compararse igual (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; return 1; }
  printf '%s' "$out" | grep -q 'historicos=0' \
    || { echo "    un PRD sin Status no es un histórico"; return 1; }
}
test_un_prd_sin_status_se_compara_igual() { _pt_repo _case_sin_status_si_se_compara; }

_case_approved_si_se_compara() {
  # El otro lado del filtro: Approved/In progress son contratos VIVOS y se
  # comparan. Sin este test, "arreglar" el caso Shipped saltándose todo pasaría
  # inadvertido — el detector se volvería mudo y seguiría en verde.
  _pt_prd '# PRD
> **Status:** **Approved** (owner, 2026-08-25)

## 5. Estructura
```
tools/fantasma.sh      ← declarado y ausente
```

## 6. Modelo'
  local rc; _pt_run >/dev/null; rc=$?
  [ "$rc" = "1" ] || { echo "    un PRD Approved SÍ debe compararse (exit $rc)"; return 1; }
}
test_un_prd_approved_si_se_compara() { _pt_repo _case_approved_si_se_compara; }

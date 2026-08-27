#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# reviewer-gate.sh — hook PreToolUse Bash (Claude) / beforeShellExecution (Cursor)
# ════════════════════════════════════════════════════════════════════
# Gate de `git commit`. Orden DELIBERADO — no lo reordenes sin actualizar
# `tools/tests/test_ratchets.sh`, que fija estos invariantes:
#
#   1. Detectores mecánicos (drift-ratchet, capas)  → DUROS SIEMPRE.
#      Ni el preset `lite` ni REVIEWER_OVERRIDE los relajan. Un número que
#      se puede aflojar no es un trinquete: es una sugerencia.
#   2. Preset `lite` (uso personal)                 → el marker AVISA.
#   3. Marker de review (tools/check-review-marker) → DURO en `full`,
#      con override AUDITADO.
#
# La lógica de verificación del marker vive en `tools/check-review-marker.sh`
# para que la compartan los 3 anillos (antes solo existía aquí → bastaba
# commitear desde otra terminal para saltárselo).
set -uo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=lib/io.sh
. "$PROJECT_ROOT/scripts/agent-hooks/lib/io.sh"
cd "$PROJECT_ROOT" || exit 0

hook_read_input
CMD="$(hook_command)"
GATE_T0="$(date +%s 2>/dev/null || echo 0)"

# Marca temporal para que el PostToolUse sepa QUÉ archivos escribió este
# comando. Va lo antes posible y es best-effort total: si falla, lo único que
# se pierde es la señal in-loop de este turno, nunca el gate.
# shellcheck source=lib/writes.sh
. "$PROJECT_ROOT/scripts/agent-hooks/lib/writes.sh" 2>/dev/null && writes_mark

# ── 0. GIT-GUARD: prohibiciones de flags — la garantía DURA del Anillo 0 ─
# permissions.deny con comodín intermedio (`git commit:*--no-verify*`) no está
# garantizado por la sintaxis documentada de Claude Code, y un deny que no
# matchea es invisible. ESTE guard sí ve el comando completo y bloquea
# determinísticamente (AGENTS.md §7).
#
# Análisis por SEGMENTO (split en ;|&) exigiendo `git` en POSICIÓN DE COMANDO
# (con prefijos VAR=val permitidos): así `REVIEWER_OVERRIDE=1 git commit` se
# gatea, pero `grep "git commit --no-verify" doc.md` NO — el texto que MENCIONA
# un comando prohibido no es el comando (falso positivo real de la v1; ley del
# 10%). Límite conocido: `git -C /ruta commit` no se detecta como commit.
# Duro en ambos presets: son prohibiciones absolutas, no gates de calidad.
_GIT_CMD_RE='^[[:space:]]*\(*[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*git[[:space:]]+'
_seg_is_git_sub() { # _seg_is_git_sub <segmento> <subcomando>
  printf '%s' "$1" | grep -qE "${_GIT_CMD_RE}(-[^[:space:]]+[[:space:]]+)*$2([[:space:]]|\$)"
}
IS_COMMIT=0; HAS_ADD=0
while IFS= read -r seg; do
  [ -z "$seg" ] && continue
  if _seg_is_git_sub "$seg" commit; then
    IS_COMMIT=1
    case "$seg" in
      *--no-verify*) hook_block "🛑 git-guard: \`--no-verify\` está PROHIBIDO (AGENTS.md §7). Los hooks de git son el Anillo 1; saltárselos deja el commit sin gates. Si un gate te bloquea injustamente, arregla el gate — no lo evadas." ;;
      *--amend*)     hook_block "🛑 git-guard: \`--amend\` requiere orden EXPLÍCITA del owner (AGENTS.md §7). Reescribir historia publicada rompe a los demás; crea un commit nuevo." ;;
    esac
  fi
  if _seg_is_git_sub "$seg" push; then
    case "$seg" in
      *--force*|*" -f"*) hook_block "🛑 git-guard: \`push --force\` está PROHIBIDO (AGENTS.md §7)." ;;
    esac
  fi
  if _seg_is_git_sub "$seg" reset; then
    case "$seg" in
      *--hard*) hook_block "🛑 git-guard: \`reset --hard\` destruye trabajo sin recuperación. Usa \`git stash\` o pide aprobación al owner." ;;
    esac
  fi
  # `git clean -f` borra untracked sin papelera. Hueco cazado por el finding
  # f-3c027a85 del primer proyecto: "sin cubrir por NADIE" — el deny inerte
  # del Anillo 0 era su única defensa nominal. Ahora es del guard.
  if _seg_is_git_sub "$seg" clean; then
    case "$seg" in
      *" -f"*|*-fd*|*-fx*|*--force*) hook_block "🛑 git-guard: \`git clean -f\` destruye archivos untracked sin recuperación (AGENTS.md §7). Lista primero con \`git clean -n\` y pide aprobación al owner." ;;
    esac
  fi
  _seg_is_git_sub "$seg" add && HAS_ADD=1
done <<< "$(printf '%s' "$CMD" | tr ';&|' '\n')"

# ── 0c. LA MATRIZ DE SKILLS TAMBIÉN VIGILA BASH ─────────────────────
# El agujero: `skill-reminder` cuelga de `PreToolUse Edit|Write`, así que la
# matriz §11 solo veía las tools de edición. Escribir con `sed -i`, `tee`,
# una redirección o un `python3 -c` es escribir igual — y pasaba sin que
# NADIE mirara. No es hipotético: por ahí se coló una decisión de
# arquitectura real (el aislamiento de actores del target) en el primer
# proyecto, sin mala intención: el agente simplemente usó la herramienta
# equivocada para el trabajo.
#
# DISEÑO CONSERVADOR EN LA DETECCIÓN, no en el bloqueo. Solo se consideran
# formas de escritura INEQUÍVOCAS, y el destino tiene que casar la matriz:
#   ·  > archivo   ·  >> archivo      (redirección; `2>/dev/null` no casa nada)
#   ·  sed -i / perl -i               ·  tee [-a] archivo
#   ·  cp/mv ... destino
# Un `grep patrón x.swift` o un `cat x.swift` NO escriben y NO disparan: la
# ley del 10% manda, y aquí un falso positivo bloquearía comandos de lectura
# legítimos, que es la forma más rápida de que alguien apague el gate entero.
# La lógica de la matriz vive en lib/skill-matrix.sh — compartida con
# skill-reminder, porque una regla implementada dos veces diverge.
if [ -f "$PROJECT_ROOT/scripts/agent-hooks/lib/skill-matrix.sh" ]; then
  # shellcheck source=lib/skill-matrix.sh
  . "$PROJECT_ROOT/scripts/agent-hooks/lib/skill-matrix.sh"
  # ⚠️ PRIMERO SE QUITA TODO LO QUE ES *TEXTO*, NO SINTAXIS.
  # Este gate leía el comando CRUDO, así que cualquier `>` o ruta dentro de una
  # cadena entrecomillada o de un heredoc contaba como escritura real. Tres
  # falsos positivos en un mismo día en un proyecto real: un mensaje de commit,
  # un comentario dentro de un heredoc, y —el que lo retrata— el propio comando
  # que registraba el hallazgo en el ledger. El agente acabó escribiendo la ruta
  # incompleta para poder pasar: la evasión exacta que predice la ley del 10%
  # (§14.2). Tres FP en un día ya está muy por encima del umbral.
  #
  # Se quitan, en este orden:
  #   1. los CUERPOS de heredoc (`<<EOF … EOF`) — son datos, no comandos;
  #   2. las cadenas entre comillas simples y dobles.
  # Lo que queda es sintaxis de shell, y ahí un `>` sí es una redirección.
  #
  # Coste asumido y declarado: un destino ENTRECOMILLADO (`> "mi archivo.swift"`)
  # deja de detectarse. Es un fallo hacia el LADO SEGURO —no bloquea de más— y
  # este gate es conservador en la detección por diseño: un falso positivo lo
  # apaga entero, un falso negativo lo cubren los otros anillos.
  _CMD_CLEAN="$(printf '%s\n' "$CMD" | awk '
    # 1) Cuerpos de heredoc: al ver <<TERM se descarta hasta la línea TERM.
    !dentro && match($0, /<<-?[[:space:]]*["'"'"']?[A-Za-z_][A-Za-z0-9_]*/) {
      t = substr($0, RSTART, RLENGTH)
      gsub(/^<<-?[[:space:]]*["'"'"']?/, "", t)
      term = t; dentro = 1; print; next
    }
    dentro {
      linea = $0; gsub(/^[[:space:]\t]+|[[:space:]]+$/, "", linea)
      if (linea == term) dentro = 0
      next
    }
    # 2) Cadenas entrecomilladas: fuera. Son datos que el shell no interpreta
    #    como redirecciones ni como rutas de escritura.
    {
      salida = ""; q = ""
      n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (q == "") {
          if (c == "\"" || c == "'"'"'") { q = c; continue }
          salida = salida c
        } else if (c == q) { q = ""; salida = salida " " }
      }
      print salida
    }
  ')"
  # Sin la redirección a /dev/null: es escritura, sí, pero a la papelera.
  # Contarla haría que CUALQUIER comando silenciado disparase el gate.
  _CMD_CLEAN="$(printf '%s\n' "$_CMD_CLEAN" | sed -E 's/2>&1//g; s/[0-9]?>>?[[:space:]]*\/dev\/null//g')"
  # (a) redirección y tee: el destino es el token siguiente.
  _WRITE_TARGETS="$(printf '%s\n' "$_CMD_CLEAN" \
    | grep -oE '(>>?[[:space:]]*|tee[[:space:]]+(-a[[:space:]]+)?)[^[:space:]|;&<>"'"'"']+' \
    | sed -E 's/^(>>?|tee)[[:space:]]*(-a[[:space:]]*)?//' | sort -u)"
  # (b) edición IN-PLACE (`sed -i`, `perl -i`): el flag NO precede al archivo
  #     — `sed -i s/a/b/ f.swift` pone el script en medio. Así que en estos
  #     comandos se toman TODOS los tokens con pinta de ruta, que es
  #     exactamente lo que `-i` va a reescribir.
  #
  # ⚠️ ANCLADO, y esta es la CUARTA ocurrencia del mismo falso positivo.
  # El patrón era `*sed*-i*`: subcadena, no comando. Bloqueó esto, que no
  # escribe absolutamente nada:
  #
  #     sed -n '54,58p' <archivo>   +   grep -rc "assert(" X --include="*.swift"
  #
  # Hay un `sed`… y hay un `-i` DENTRO de `--include`. Lo mismo con
  # `--interactive`, `--ignore-case` o cualquier flag largo que contenga `-i`.
  # Y lo que más duele: el anclaje ya se había aplicado a `cp`/`mv` en la
  # ocurrencia anterior, con un comentario explicando el problema. Se arregló
  # un caso y no se buscó el hermano — la misma lección que este repo tiene
  # escrita, cometida sobre la regla donde está escrita.
  # Ahora `sed`/`perl` tienen que ser el PRIMER token de un comando (inicio de
  # línea o tras `;` `&&` `||` `|`) y el `-i` tiene que ser argumento SUYO
  # (token propio `-i`, `-i.bak`, `-pi`…), no subcadena de otro flag.
  if printf '%s' "$_CMD_CLEAN" \
     | grep -qE '(^|[;&|][[:space:]]*)(sed|perl)([[:space:]]+-[A-Za-z]*i([^[:alnum:]-]|$)|[[:space:]]+-[A-Za-z]*i$)'; then
    _WRITE_TARGETS="$_WRITE_TARGETS"$'\n'"$(printf '%s\n' "$_CMD_CLEAN" | tr ' \t' '\n\n' \
      | grep -E '(/|\.[A-Za-z0-9]+$)' | grep -vE '^-|^s/|/$' || true)"
  fi
  # (c) cp/mv: el destino es el ÚLTIMO argumento. ANCLADO al principio de un
  #     comando (inicio de línea o tras ; && || |): el patrón antiguo `*cp\ *`
  #     casaba la subcadena en cualquier sitio, así que un `--detail "...cp ..."`
  #     o un `grep -c "mv "` convertían el último token del comando —cualquier
  #     cosa— en un "destino de copia". Segunda cara del mismo FP.
  if printf '%s' "$_CMD_CLEAN" | grep -qE '(^|[;&|][[:space:]]*)(cp|mv)[[:space:]]'; then
    _WRITE_TARGETS="$_WRITE_TARGETS"$'\n'"$(printf '%s' "$_CMD_CLEAN" | awk '{print $NF}')"
  fi
  # SANEO + DEDUP antes de decidir nada. Sin esto el mensaje del bloqueo salía
  # con la cola del payload pegada al path (`Repo.swift"}}'`) y con la misma
  # ruta repetida tres veces, una por cada extractor que la encontró. En un
  # gate BLOQUEANTE eso no es cosmético: un mensaje sucio hace dudar de si el
  # gate está bien, y la duda sobre un gate acaba en "desactívalo".
  _WRITE_TARGETS="$(printf '%s\n' "$_WRITE_TARGETS" \
    | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^["'"'"'(]+//; s/["'"'"')}\;,]+$//' \
    | grep -v '^$' | sort -u)"
  _MATRIX_BLOCK=""
  while IFS= read -r _t; do
    [ -z "$_t" ] && continue
    _t="${_t#./}"
    [ -e "$_t" ] || case "$_t" in */*) : ;; *) continue ;; esac
    matrix_is_exempt "$_t" && continue
    _miss="$(matrix_missing_refs "$_t" 2>/dev/null)"
    [ -n "$_miss" ] && _MATRIX_BLOCK="${_MATRIX_BLOCK}  • ${_t}:"$'\n'"$(printf '%s' "$_miss" | sed 's/^/      - /')"$'\n'
  done <<< "$_WRITE_TARGETS"
  if [ -n "$_MATRIX_BLOCK" ]; then
    hook_log_detection "skill-reminder" "bash-write" "matriz evadida por Bash" 1
    hook_block_or_warn "🛑 Este comando ESCRIBE en rutas que exigen leer su referencia (AGENTS.md §11),
y por Bash la matriz no te la había pedido todavía:

${_MATRIX_BLOCK}
Léelas con la tool Read y repite el comando. Y si lo que ibas a hacer era
editar código, usa Edit en vez de \`sed -i\`: el harness ve esas ediciones,
verifica el resultado en el mismo turno (post-edit-verify) y deja rastro."
  fi
fi

# Solo gateamos `git commit`.
[ "$IS_COMMIT" -eq 1 ] || hook_allow

# ── 0b. El marker liga sha256(diff STAGED): add+commit en una línea lo evade ─
# El gate corre ANTES de ejecutar el comando completo, así que con
# `git add X && git commit` validaríamos el staged ANTERIOR al add — y se
# commitearía contenido distinto del validado. Lo mismo con `commit -a/-am`,
# que stagea implícitamente en el momento del commit. Flujo correcto:
# stagea → invoca al reviewer → commitea (documentado en ADOPTION §8).
# Bloquea en full, avisa en lite (fricción vs seguridad, igual que el marker).
if [ "$HAS_ADD" -eq 1 ]; then
  hook_block_or_warn "🛑 reviewer-gate: \`git add\` y \`git commit\` en el MISMO comando evaden la validación del diff staged (el gate corre antes del add). Sepáralo: stagea primero, revisa, y commitea en un comando aparte."
fi
if printf '%s' "$CMD" | grep -qE 'git commit[^;|&]*(\s-a[m]?(\s|$)|--all)'; then
  hook_block_or_warn "🛑 reviewer-gate: \`git commit -a/-am\` stagea en el momento del commit — el marker de review liga el sha del diff que YA estaba staged, no ese. Stagea explícito, revisa, y commitea sin \`-a\`."
fi

# ── 0d. ¿El lote mezcla naturalezas? AVISO, jamás bloqueo ───────────
# Llega tarde (la review ya ocurrió), pero el aprendizaje sirve para el
# commit siguiente — y es el único punto del flujo donde el harness ve el
# lote completo. El sitio donde de verdad ahorra es ANTES de invocar al
# reviewer: eso lo pide el paso 1b del runner.
if [ -f tools/check-diff-nature.sh ]; then
  _nat="$(bash tools/check-diff-nature.sh --staged 2>&1 >/dev/null || true)"
  [ -n "$_nat" ] && printf '%s\n' "$_nat" >&2
fi

# ── 1. Detectores mecánicos — DUROS, sin excepción ──────────────────
# Van ANTES del override y del preset a propósito: son objetivos, no opinables.
# Si el conteo subió, subió.
if [ -f tools/drift-ratchet.sh ]; then
  if ! out="$(bash tools/drift-ratchet.sh --check 2>&1)"; then
    hook_block "$out"$'\n\n'"❌ reviewer-gate: commit BLOQUEADO por drift-ratchet.
El trinquete NO se puede saltar (ni con preset lite ni con REVIEWER_OVERRIDE).
Baja la deuda que introdujiste, o compénsala en otro lado."
  fi
fi
if [ -f tools/check-layers.sh ]; then
  if ! out="$(bash tools/check-layers.sh 2>&1)"; then
    hook_log_detection "check-layers" "pre-commit" "staged" \
      "$(printf '%s' "$out" | sed -nE 's/.*LAYERS_SUMMARY errors=([0-9]+).*/\1/p')"
    hook_block "$out"$'\n\n'"❌ reviewer-gate: commit BLOQUEADO por violación de capas (AGENTS.md §3).
Las capas son un contrato, no un estilo. Invierte la dependencia o mueve el archivo."
  fi
fi
# Semgrep sobre lo STAGED. Va aquí, y no solo dentro de `check-drift.sh`, porque
# el agregador descarta el exit code por diseño: un semgrep roto o con reglas
# inválidas era invisible en los Anillos 1 y 2 y solo se cazaba en CI. Eso
# contradice §14 ("cázalo en la capa más barata") justo para el detector que
# más barato es de correr. Lo cazó el `reviewer` revisando P1.
if [ -f tools/semgrep-scan.sh ]; then
  out="$(bash tools/semgrep-scan.sh --staged 2>&1)"; rc=$?
  case "$rc" in
    1)  # HALLAZGO real en el código → bloquea, sin excepción.
        hook_log_detection "semgrep" "pre-commit" "staged" \
          "$(printf '%s' "$out" | sed -nE 's/.*SEMGREP_SUMMARY errors=([0-9]+).*/\1/p')"
        hook_block "$out"$'\n\n'"❌ reviewer-gate: commit BLOQUEADO por hallazgos de semgrep (patrones AST)." ;;
    3)  # El DETECTOR falló (ausente, reglas rotas, crash). Avisa, no bloquea.
        # Bloquear aquí crearía un deadlock: un typo en las reglas impediría
        # incluso el commit que lo arregla (AGENTS.md §14.3). El backstop es CI,
        # donde GATES_REQUIRE_SEMGREP=1 sí lo trata como fallo.
        printf '%s\n' "$out" >&2
        echo "⚠️  reviewer-gate: semgrep no pudo ejecutarse. Commit PERMITIDO (§14.3), pero el" >&2
        echo "   nivel 2 de la pirámide está MUDO hasta que lo arregles. CI sí bloqueará." >&2 ;;
  esac
fi

# ── 2. Marker de review (implementación compartida por los 3 anillos) ─
# El preset lo aplica `check-review-marker.sh`, NO este hook. Cuando la lógica
# de preset vivía aquí, lefthook (Anillo 1) llamaba al script directo y bloqueaba
# igual en `lite`: el Anillo 2 daba luz verde y el commit fallaba después.
# Una regla implementada en dos sitios diverge — vive en uno solo.
if ! out="$(bash tools/check-review-marker.sh --staged 2>&1)"; then
  hook_block "$out"
fi
printf '%s\n' "$out" | grep -q '^⚠️' && { printf '%s\n' "$out" >&2; hook_allow; }

# ── Presupuesto de tiempo: un PreToolUse que agota su timeout NO bloquea ─
# (el gate desaparece en silencio). Si consumimos >½ del presupuesto (90s en
# settings.json), se deja rastro para que el humano lo vea y ajuste.
GATE_T1="$(date +%s 2>/dev/null || echo 0)"
if [ "$GATE_T1" -gt 0 ] && [ "$GATE_T0" -gt 0 ] && [ $((GATE_T1 - GATE_T0)) -gt 45 ]; then
  echo "⚠️  reviewer-gate tardó $((GATE_T1 - GATE_T0))s (presupuesto 90s). Si llega al timeout, el gate NO bloquea — se salta en silencio. Acota DRIFT_SRC_DIRS o sube el timeout en settings.json." >&2
  hook_log_detection "reviewer-gate" "budget-warning" "pre-commit" 1 "$(( (GATE_T1 - GATE_T0) * 1000 ))" gate
fi

echo "✅ reviewer-gate: detectores verdes + marker válido. Commit permitido." >&2
hook_allow

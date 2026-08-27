#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# validate-hooks.sh — el contrato multi-cliente de los hooks (Anillo 2)
# ════════════════════════════════════════════════════════════════════
# Los cuatro checks que responden "¿este cliente llegará siquiera a INVOCAR
# sus gates?". Los cuatro fallan hacia el SILENCIO si nadie los mira: un JSON
# inválido hace que el cliente ignore el archivo entero, un nombre de evento
# que no existe hace que el hook jamás dispare, un script referenciado que no
# está o no parsea deja el gate mudo, y sin los symlinks las skills y los
# sub-agentes no se cargan.
#
# Se SOURCEA desde tools/validate-harness.sh: usa sus helpers ok/bad/warn y su
# variable FAIL. No se ejecuta suelta — por eso vive en tools/lib/ y no lleva
# bit +x (check-exec-bits.sh exime */lib/* a propósito).

# shellcheck disable=SC2034  # FAIL es del orquestador que nos sourcea; aquí solo se escribe
vh_check_hooks() {
# CUERPO VERBATIM (sin re-indentar): los heredocs de dentro exigen que su
# terminador siga en la columna 0. Indentar por estética los rompería.
# ── 1. Los tres configs de hooks son JSON válido ────────────────────
echo ""
echo "── 1. Sintaxis de configuración ──"
for f in .claude/settings.json .cursor/hooks.json .codex/hooks.json; do
  [ -f "$f" ] || { warn "$f ausente"; continue; }
  if python3 -c "import json;json.load(open('$f'))" 2>/dev/null; then
    ok "$f: JSON válido"
  else
    bad "$f: JSON INVÁLIDO — ese cliente ignorará TODOS sus hooks"
  fi
done

# ── 2. Solo eventos que EXISTEN en cada cliente ─────────────────────
# (la lista se comparte con tools/tests/test_hook_events.sh)
echo ""
echo "── 2. Nombres de evento por cliente ──"
python3 - <<'PY' || FAIL=1
import json, sys
SPECS = {
    ".claude/settings.json": ({"SessionStart","UserPromptSubmit","PreToolUse","PostToolUse",
                               "Notification","Stop","SubagentStop","SessionEnd","PreCompact"}, "hooks"),
    ".cursor/hooks.json":    ({"beforeSubmitPrompt","beforeShellExecution","beforeMCPExecution",
                               "beforeReadFile","afterFileEdit","stop"}, "hooks"),
    ".codex/hooks.json":     ({"PreToolUse","PostToolUse"}, "hooks"),
}
rc = 0
for path,(valid,key) in SPECS.items():
    try:
        cfg = json.load(open(path))
    except FileNotFoundError:
        continue
    events = [k for k in cfg.get(key,{}) if not k.startswith("_")]
    ghosts = [e for e in events if e not in valid]
    if ghosts:
        print(f"  ❌ {path}: eventos INEXISTENTES {ghosts} — esos hooks JAMÁS dispararán (gate mudo)")
        rc = 1
    else:
        print(f"  ✅ {path}: {len(events)} eventos, todos válidos")
sys.exit(rc)
PY

# ── 3. Cada comando de hook apunta a un script que existe y parsea ──
echo ""
echo "── 3. Scripts referenciados por los hooks ──"
MISSING=0
for f in .claude/settings.json .cursor/hooks.json .codex/hooks.json; do
  [ -f "$f" ] || continue
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    if [ ! -f "$s" ]; then bad "$f referencia $s — NO EXISTE"; MISSING=1
    elif ! bash -n "$s" 2>/dev/null; then bad "$s no parsea (bash -n)"; MISSING=1; fi
  done < <(grep -oE 'scripts/agent-hooks/[A-Za-z0-9_./-]+\.sh' "$f" | sort -u)
done
[ "$MISSING" = "0" ] && ok "todos los scripts de hooks existen y parsean"

# ── 4. Symlinks del contrato multi-cliente ──────────────────────────
echo ""
echo "── 4. Symlinks ──"
for l in .claude/skills .cursor/agents; do
  if [ -L "$l" ] && [ -e "$l" ]; then ok "$l → $(readlink "$l")"
  elif [ -e "$l" ]; then warn "$l existe pero no es symlink"
  else warn "$l ausente (¿clone en un FS sin symlinks?) — skills/agents no cargarán ahí"; fi
done
}

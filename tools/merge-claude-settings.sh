#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# merge-claude-settings.sh — la única parte de `.claude/` que es maquinaria
# ════════════════════════════════════════════════════════════════════
# `SYNC_PATHS` excluye `.claude/`, `.agents/` y `docs/` a propósito: ahí vive
# el contenido del proyecto, y pisarlo en cada upgrade es el daño que hace que
# nadie vuelva a correr el upgrade.
#
# Pero `.claude/settings.json` no es contenido: dentro viven los HOOKS (el
# Anillo 2 entero) y los PERMISOS (el Anillo 0). Eso es harness puro, y al
# quedar fuera del sync se quedaba atrás en silencio. Cazado en vivo: de tres
# arreglos de una tanda, solo uno llegó solo; el `allow` de `findings.sh` hubo
# que traerlo a mano tras comparar contra `template/main` — y solo porque
# alguien se acordó de comparar.
#
# La solución NO puede ser un `checkout` del archivo: se llevaría por delante
# los permisos propios del proyecto. Es un merge de CLAVES, y con una regla
# que hace la operación segura y reversible:
#
#   ▸ SOLO AÑADE. Nunca quita, nunca reordena, nunca reescribe un valor que ya
#     tenga el proyecto. Lo añadido se imprime, línea a línea, para que entre
#     en el diff que el humano revisa antes de commitear.
#
# Consecuencia buscada en `deny`: la lista de prohibiciones solo puede crecer,
# como los trinquetes de §9. Si un proyecto quitó un `deny` a propósito, esto
# se lo devuelve — y lo dice, para que lo vuelva a quitar en el mismo commit
# si de verdad lo quería. Es la dirección correcta para equivocarse.
#
#   bash tools/merge-claude-settings.sh template/main
#
# Contrato de stdout:  SETTINGS_MERGE allow=+N deny=+M ask=+K hooks=+H claves=+J
# Exit: 0 hecho (con o sin cambios) · 1 el JSON local está roto · 3 no pude
#       mirar (falta python3, o el ref no trae el archivo)
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

REF="${1:-}"
FILE=".claude/settings.json"
[ -n "$REF" ] || { echo "uso: bash tools/merge-claude-settings.sh <ref-del-template>" >&2; exit 3; }

if ! command -v python3 >/dev/null 2>&1; then
  {
    echo "⚠️  settings-merge: python3 ausente — NO he podido fundir $FILE."
    echo "   Hazlo a mano:  git diff HEAD $REF -- $FILE"
    echo "   Ahí viven los hooks (Anillo 2) y los permisos (Anillo 0): quedarse"
    echo "   atrás ahí no se nota hasta que un gate no salta."
  } >&2
  echo "SETTINGS_MERGE allow=+0 deny=+0 ask=+0 hooks=+0 claves=+0"
  exit 3
fi

TPL="$(mktemp)"; trap 'rm -f "$TPL"' EXIT
if ! git show "$REF:$FILE" > "$TPL" 2>/dev/null || [ ! -s "$TPL" ]; then
  echo "SETTINGS_MERGE allow=+0 deny=+0 ask=+0 hooks=+0 claves=+0"
  exit 0   # el template no trae settings.json: nada que fundir, no es un fallo
fi

# El proyecto no tiene el archivo: no hay nada que perder, se copia entero.
if [ ! -f "$FILE" ]; then
  mkdir -p "$(dirname "$FILE")"
  cp "$TPL" "$FILE"
  echo "✓ settings-merge: $FILE no existía — traído entero del template."
  echo "SETTINGS_MERGE allow=+0 deny=+0 ask=+0 hooks=+0 claves=+0"
  exit 0
fi

MERGE_TPL="$TPL" MERGE_LOCAL="$FILE" python3 - <<'PY'
import json, os, re, sys

tpl_path, loc_path = os.environ["MERGE_TPL"], os.environ["MERGE_LOCAL"]

def load(p, quien):
    with open(p, encoding="utf-8") as f:
        raw = f.read()
    try:
        return json.loads(raw)
    except json.JSONDecodeError as e:
        # Un JSON local roto NO se "arregla" sobrescribiéndolo: eso borraría
        # permisos que el proyecto puso a mano. Se para y se dice dónde.
        print(f"❌ settings-merge: {quien} no es JSON válido ({e}).", file=sys.stderr)
        print(f"   Arréglalo y vuelve a correr el upgrade. NO lo sobrescribo:", file=sys.stderr)
        print(f"   dentro hay permisos tuyos que no puedo reconstruir.", file=sys.stderr)
        sys.exit(1)

tpl, loc = load(tpl_path, "el settings.json del template"), load(loc_path, os.path.basename(loc_path))
added = {"allow": [], "deny": [], "ask": [], "hooks": [], "claves": []}

# ── permisos: unión, respetando el orden local ──────────────────────
tp, lp = tpl.get("permissions") or {}, loc.setdefault("permissions", {})
for k in ("allow", "deny", "ask"):
    nuevos = [e for e in (tp.get(k) or []) if e not in (lp.get(k) or [])]
    if nuevos:
        lp[k] = list(lp.get(k) or []) + nuevos
        added[k] = nuevos

# ── hooks: unión por (evento, matcher, comando) ─────────────────────
# Un hook se identifica por lo que EJECUTA, no por su posición: así un
# proyecto que añadió sus propios hooks al mismo evento no los pierde, y un
# hook del template que ya existe no se duplica.
#
# ⚠️ LA IDENTIDAD SE CALCULA SOBRE EL COMANDO *NORMALIZADO*, quitándole el
# lanzador. Sin eso, el día que el template envolvió todos los hooks en
# `run-hook.sh` cada proyecto habría acabado con el hook DOS veces —el suyo
# directo y el nuevo envuelto— porque las cadenas difieren aunque el hook sea
# el mismo. Dos ejecuciones por evento: session-start reseteando markers dos
# veces, el gate opinando dos veces. Cambiar de lanzador es UPGRADE de una
# entrada existente, no una entrada nueva, y se reporta como tal.
# Ojo al `bash ` de los dos lados: sin quitarlo, `bash …/run-hook.sh X` y
# `bash X` normalizan a `X` y a `bash X` — distintos, y el hook se duplicaba
# igual. El primer intento de este arreglo falló justo ahí.
_LANZADOR = re.compile(r'^\s*(bash\s+)?(\S*run-hook\.sh\s+)?(bash\s+)?')

def _norm(h):
    h = dict(h)
    c = h.get("command")
    if isinstance(c, str):
        h["command"] = _LANZADOR.sub("", c).strip()
    return json.dumps(h, sort_keys=True)

def cmds(group):
    return tuple(sorted(_norm(h) for h in (group.get("hooks") or [])))

th, lh = tpl.get("hooks") or {}, loc.setdefault("hooks", {})
for evento, grupos in th.items():
    # ⚠️ Bajo `hooks` no todo es una lista de grupos: este mismo repo mete ahí
    # claves `_comment_*` con un STRING de documentación. `enumerate()` sobre un
    # string da caracteres y `g.get("matcher")` revienta con
    # `AttributeError: 'str' object has no attribute 'get'`.
    # Este merge NACIÓ ROTO contra su propio archivo y nunca funcionó: sus seis
    # tests pasaban porque los fixtures eran sintéticos y no reproducían el
    # settings.json real. Lo cazó el adoptante corriéndolo contra el de verdad.
    # SALTAR ≠ BORRAR: los comentarios del proyecto se conservan intactos, y los
    # del template se copian si no están (son doc de maquinaria, y añadir es
    # seguro).
    if not isinstance(grupos, list):
        if evento not in lh:
            lh[evento] = grupos
            added["claves"].append(f"hooks.{evento}")
        continue
    locales = lh.get(evento)
    if not isinstance(locales, list):
        # El proyecto tiene un no-lista donde el template trae grupos: no se
        # pisa nada, se reporta y se sigue. Perder un hook por sobrescribir es
        # peor que no traerlo.
        continue
    locales = lh.setdefault(evento, [])
    indice = {(g.get("matcher"), cmds(g)): i for i, g in enumerate(locales)}
    for g in grupos:
        clave = (g.get("matcher"), cmds(g))
        if clave not in indice:
            locales.append(g)
            indice[clave] = len(locales) - 1
            added["hooks"].append(f'{evento}[{g.get("matcher") or "*"}]')
            continue
        # Mismo hook, ¿mismo lanzador? Si no, gana el del template: el lanzador
        # es maquinaria pura y quedarse con el viejo es quedarse sin el arreglo.
        i = indice[clave]
        if locales[i] != g:
            locales[i] = g
            added["hooks"].append(f'{evento}[{g.get("matcher") or "*"}] (lanzador actualizado)')

# ── claves de primer nivel ausentes ─────────────────────────────────
# Solo las que NO existen. Una clave con valor distinto es una decisión del
# proyecto (su modelo, su statusLine) y no se toca.
for k, v in tpl.items():
    if k not in ("permissions", "hooks") and k not in loc:
        loc[k] = v
        added["claves"].append(k)

if any(added.values()):
    with open(loc_path, "w", encoding="utf-8") as f:
        json.dump(loc, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"✓ settings-merge: {os.path.basename(loc_path)} actualizado (solo se AÑADIÓ):")
    for k in ("hooks", "allow", "deny", "ask", "claves"):
        for e in added[k]:
            print(f"    + {k}: {e}")
    if added["deny"]:
        print("    ⚠️  'deny' solo crece, como los trinquetes (§9). Si quitaste alguno a")
        print("       propósito, vuelve a quitarlo en ESTE commit y deja el motivo escrito.")

print("SETTINGS_MERGE " + " ".join(f"{k}=+{len(v)}" for k, v in
      (("allow", added["allow"]), ("deny", added["deny"]), ("ask", added["ask"]),
       ("hooks", added["hooks"]), ("claves", added["claves"]))))
PY

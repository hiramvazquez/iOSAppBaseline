---
description: Imprime EN PANTALLA el estado real del workflow — fase, gates, niveles mudos de la pirámide y findings abiertos — y termina con lo que falta, ordenado por coste. Solo lectura: no arregla nada, no escribe ningún archivo.
---

# /status — qué está cableado, qué está mudo, y qué toca ahora

No lleva argumentos. **Todo lo que imprimas sale de un comando ejecutado en ESTE turno.**

## Por qué existe

El fallo caro de este harness nunca fue un gate que bloqueara de más: fue un gate que
**jamás disparó**. Un repo arranca con la mitad de los `<!-- FILL -->` sin rellenar, los
agentes eligen la arquitectura que les parece porque nadie declaró ninguna, y **nadie se
entera** — un nivel mudo y uno sano se ven exactamente igual desde fuera (AGENTS.md §14.4).

Ya hay dos cosas cerca, y ninguna sirve para esto:

- `session-start` declara la salud… **una vez**, al arrancar, y se pierde en la primera
  compactación. No se puede volver a pedir sin efectos secundarios.
- `tools/harness-report.sh` lo empaqueta **entero**: 9 secciones, telemetría, colas de logs,
  y guarda un `.md`. Está diseñado para **pegar en otra conversación**, no para leerlo tú.

`/status` es la tercera cosa: **una pantalla, ahora**, para el owner que pregunta "¿por dónde
voy?". Corto, priorizado y **prescriptivo** — termina en qué hacer, no en qué mirar.

## Contrato de evidencia (innegociable)

1. **Cada cifra y cada estado sale de la salida real de un comando de este turno.** Nada de
   memoria, nada del bloque que el hook inyectó al arrancar la sesión (describe el estado de
   *entonces*, y el ledger cambia mientras trabajas), nada "de la última vez".
2. **Si un comando falla o no existe, escribe `?` y di cuál falló.** Un gate que no pudo
   mirar NO es un gate que no encontró nada (§14.3). Inventar el dato es el único error
   irreparable de este comando: `/status` existe precisamente para que nadie confunda
   silencio con verde.
3. **Cero cifras derivables escritas a mano** — la misma disciplina que
   `tools/check-execution-map.sh` impone sobre el mapa. Si el número se puede derivar, se deriva.

## Qué ejecutar (todo solo-lectura, ~10 s en total)

```bash
bash scripts/agent-hooks/session-start.sh --report
bash tools/validate-harness.sh
bash tools/drift-ratchet.sh --check
bash tools/check-layers.sh
bash tools/check-execution-map.sh
bash tools/findings/findings.sh list --status open --json
```

Filtros para no ahogarte en su salida (la salida completa es para `harness-report`, no para ti):

- **Salud + niveles mudos** → del `--report`:
  `sed -n '/── Salud de configuración ──/,/── Guardrails/p' | grep -E '^(•|⚠️|✓)'`
- **Gates estáticos** → de `validate-harness`, solo lo que no está en verde:
  `grep -E '^\s+(❌|⚠️)|^(✅|❌) validate-harness'` — su checklist EN VIVO no va aquí.
- **Drift y capas** → sus líneas de contrato: `drift-ratchet` imprime `errors=N/techo`
  (ya corre `check-drift` por dentro: no lo llames aparte), `check-layers` imprime
  `LAYERS_SUMMARY errors=N`.
- **Mapa** → `EXECUTION_MAP_SUMMARY stale=<0|1>`; y el próximo paso, solo sus titulares:
  `awk '/^## Próximo paso/{f=1;next} /^## /{f=0} f' docs/process/current_execution_map.md | grep -E '^([0-9]+\.|-) ' | head -6`
  (acepta lista numerada Y viñetas: cada repo escribe su mapa a su manera, y un filtro
  atado a una sola convención devuelve **vacío en silencio** en el otro — medido, no supuesto)
- **Findings por severidad** — derivado, nunca contado a ojo:

```bash
bash tools/findings/findings.sh list --status open --json | python3 -c '
import json,sys,collections
d=json.load(sys.stdin)
s=collections.Counter(f["severity"] for f in d)
t=collections.Counter(f["tier"] for f in d)
print("abiertos",len(d),"| high",s["high"],"medium",s["medium"],"low",s["low"],
      "| owner-decision",t["owner-decision"],"auto-fix",t["auto-fix"])
for f in d:
    if f["severity"]=="high": print("HIGH", f["id"], f["title"][:70])
'
```

## Qué NO hacer

- **NUNCA `scripts/agent-hooks/session-start.sh` sin `--report`.** El modo normal BORRA los
  markers de skills leídas y la baseline de drift: observar no puede modificar. Ya pasó una
  vez y dejó el siguiente `Edit` bloqueado a mitad de sesión (`f-session-start-fx`).
- **No llames a `tools/harness-report.sh`.** Escribe un archivo en `.agents/state/report/` y
  es justo el formato que este comando NO quiere.
- **No corras la suite** (`tools/tests/run-tests.sh`, ~4 min) ni `validate-harness --selftest`
  ni `--full`. `/status` informa; no verifica de nuevo lo que ya tiene veredicto barato.
- **No arregles nada, no abras findings, no toques archivos.** Si ves algo que merece
  ledger, dilo en el "qué falta" y deja que el owner lo mande. Este comando es una lente.

## Qué imprimir

Una sola pantalla, este esqueleto, **sin secciones vacías de relleno** (una línea que no
cambia una decisión, se borra):

```
═══ /status — <repo> @ <rama> <sha> · preset <full|lite> ═══

FASE      <titular de la fase actual, 1 línea>        mapa: <fresco|STALE>
ÁRBOL     <N archivos sin commitear | limpio>

GATES     drift <e/techo> · capas <e> · validate-harness <✅|❌ N fallos, N avisos>
          <una línea por cada ❌ y ⚠️ real — su texto, no tu paráfrasis>

MUDOS     <niveles de la pirámide sin cubrir, ordenados 0→9>
          <nivel N: qué queda SIN vigilar por eso, 1 línea>

FINDINGS  <N> abiertos — <h> high · <m> medium · <l> low
          <x> owner-decision (deciden ellos) · <y> auto-fix (los cierras tú)
          high: <id + título, máx 3; si hay más, "… y N más">

PRÓXIMO PASO (docs/process/current_execution_map.md)
  <titular 1, y el 2 si sigue vivo>

QUÉ FALTA — por coste, lo barato primero
  1. [nivel N] <acción concreta> → <comando o archivo exacto>
  2. …
```

Reglas del bloque final, que es la razón de ser del comando:

1. **Ordena por nivel de la pirámide, ascendente** (0 → 9). Cada nivel que un defecto sube
   sin detectarse multiplica ~10× su coste (§14.1): un `verify.conf` sin cablear va SIEMPRE
   antes que afinar el juez de IA, aunque el juez sea más interesante.
2. **Máximo 5 ítems.** Una lista de veinte no la ejecuta nadie, y este comando se juzga por
   lo que el owner hace después de leerlo.
3. **Cada ítem termina en un comando o un archivo**, no en un consejo. "Cablear el nivel 4"
   no es accionable; `tools/mutation-score.sh §FILL` sí.
4. **Si no falta nada, dilo en una línea y para.** Inventar trabajo para llenar la sección
   es exactamente la ceremonia que §14 llama añadir ruido en vez de calidad.

> Un `/status` que dice "todo bien" porque un comando falló en silencio es peor que no
> tenerlo: convierte un gate roto en luz verde permanente. Ante la duda, `?` y el nombre del
> comando que no pudo mirar.

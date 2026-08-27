# Findings Ledger — inventario único de hallazgos

> El eslabón que cierra el loop **detección → seguimiento**. Audits, `reviewer`, `process-judge`,
> `check-drift` y advisors producen hallazgos; sin un lugar único con estado terminal, se evaporan
> en resúmenes. Este ledger los hace **durables, machine-writable y con cierre garantizado**.

## Filosofía

La meta NO es "arreglar todo". Es que **cada hallazgo llegue a un estado terminal y visible** —
arreglado **o** explícitamente aceptado/descartado-con-razón. "Nada se evapora" se logra cerrando
cada item, no fijando todos.

Triage en 3 buckets (`tier`):

| tier | qué es | quién lo acciona |
|---|---|---|
| `auto-fix` | mecánico / seguro | el agente, en convergencia |
| `owner-decision` | producto / seguridad / negocio — necesita juicio humano | **el owner** |
| `accepted` | riesgo aceptado / won't-fix | cerrado con razón |

## Arquitectura

```
tools/findings/
  findings.sh     CLI del ledger (bash+python3) — ÚNICO runtime
  ledger.jsonl    ← FUENTE DE VERDAD (1 hallazgo = 1 línea JSON, formato compacto)
  README.md       este archivo
docs/process/
  findings-ledger.md  ← VISTA HUMANA generada (NO editar a mano)
.agents/state/metrics/
  detections.jsonl    ← EVENTOS v1/v2 de los gates (local, gitignored — telemetría,
                        no findings curados; read-events.py da lectura mixta)
```

> **¿Por qué UN solo CLI?** Existió un `findings.ts` (Deno/Node) "equivalente" — y los dos
> emisores divergieron en el byte-formato del JSON (espaciado), con lo que los contadores de
> los hooks reportaban 0 abiertos en silencio (lección 2026-08-07). Dos runtimes para un
> archivo es una fuente de divergencia sin beneficio: `findings.sh` usa lo que el repo ya
> asume (bash+python3), escribe compacto, y el **invariante clave** queda en un solo sitio:
> `add`/`import` jamás resucitan un estado terminal — cerrar es explícito.

## Uso diario

```bash
bash tools/findings/findings.sh add --title "..." --area "file:line" \
     --severity high|medium|low --tier auto-fix|owner-decision --source reviewer \
     --source-event evt-...
bash tools/findings/findings.sh close f-xxxx --resolution "commit abc123"
bash tools/findings/findings.sh list --status open
bash tools/findings/findings.sh render      # regenera la vista humana
bash tools/metrics/escape-rate.sh           # defectos únicos del ledger (ventana 30d)
bash tools/metrics/gate-value.sh            # actividad/latencia de eventos (ventana 30d)
```

Los gates escriben **eventos** solos (`hook_log_detection`), siempre con `triage:"unknown"`.
Después del triage, `add/import --source-event <event_id>` guarda la relación en
`source_event_ids[]` del finding durable. Puede repetirse el flag para unir varias detecciones;
los IDs se deduplican sin cambiar su orden. El evento local no se reescribe: una detección no
se disfraza retrospectivamente de true-positive (AGENTS.md §10).

Las dos métricas no comparten denominador: `escape-rate` cuenta una vez cada `id` del ledger
dentro de `--days` o `--since/--until`; jamás suma eventos. `gate-value` cuenta eventos únicos,
actividad `n` y cobertura de `duration_ms`. Un evento enlazado está **promovido**; uno sin enlace
sigue **untriaged**, no “false-positive”. Mientras no exista triage negativo durable, el FP rate
se muestra `n/a` — ausencia de promoción no es evidencia de falsedad.

## Invariante clave (auto-flow)

`add`/`import` (detección) **nunca** regresan un hallazgo terminal (`fixed`/`accepted`/`wontfix`)
a abierto; solo refrescan metadatos y fusionan `source_event_ids`. Cambiar estado es
**explícito** (`close`/`accept`/`triage`). Esto evita que la re-detección nocturna infle el
ledger o "des-haga" un fix.

## Comandos

```bash
F="bash tools/findings/findings.sh"
$F add --title "Token en logs" --area "src/auth.ts:42" --severity high \
   --tier owner-decision --source-event evt-...
$F import /tmp/batch.json --source-event evt-...  # aplica el vínculo a cada item del batch
$F list --status open --tier owner-decision [--json]
$F close <id> --resolution "commit abc"     $F accept <id> --reason "..."
$F render                          # regenera la vista md
```

## Convención: cada productor anexa (lo que cierra la fuga)

| Productor | Cómo anexa |
|---|---|
| Sesión manual que cierra un audit | `add` por hallazgo, o `import batch.json` → `render` → commit |
| `process-judge` (nocturno) | emite JSON → `import` → triar → `render` |
| `reviewer` (gate) | findings AMBER/RED que no bloquean → `add --tier ...` |
| `check-drift` | (opcional) cada WARN nueva → `add --source check-drift` |

Tras cualquier `add`/`import`/`close`/`accept`: **siempre** `render` y commitea `ledger.jsonl` +
`findings-ledger.md` juntos.

# backlog/ — historias de usuario como cola de trabajo (PRD 0003)

> Pegas historias en `.md` (formato `_template.md`), algo las toma **una a una**, crea una
> rama por historia desde la base, el harness hace su trabajo, y a ti te llegan **ramas ya
> pasadas por todos los gates** esperando tu review. El merge es SIEMPRE humano.

## El ciclo

```
tú escribes backlog/0007-*.md (status: ready)
        │
run.sh  ├─ next.sh elige la primera ready SIN deps pendientes
        ├─ `git worktree add` crea un directorio AISLADO con story/0007-<slug>
        │    (tu checkout NUNCA cambia de rama; tu árbol sucio no estorba)
        ├─ claude -p trabaja DENTRO del worktree + el contrato del harness
        │    └─ dentro rigen los MISMOS gates: TDD, capas, semgrep,
        │       reviewer con VERDICT real, trinquetes (.agents/state limpio)
        ├─ scope-check compara TODO el cambio con `scope: |` del frontmatter
        │    (rango, índice, modificaciones, untracked, deletes y renames)
        ├─ commits quedan EN LA RAMA (jamás push, jamás merge)
        └─ historia → in-review (worktree se limpia) · blocked (worktree
        │    queda para inspección) · in-review NO se re-trabaja: se espera tu merge
        │
tú revisas la rama → merge a develop → status: done → desbloquea dependientes
```

- **Dependencias**: `depends_on: [0001]` solo se satisface cuando 0001 está `done` **en la
  base** — o sea, después de TU merge. El grafo se ordena solo, sin coordinación extra.
- **Secuencial a propósito** (una historia por invocación): el paralelismo correcto es tener
  varias ramas independientes esperando review, no varios agentes escribiendo a la vez
  (`multi-agent-orchestration.md` §Default).
- **Historia sin criterios de aceptación → `blocked`**, no improvisación (§1.4). Los
  criterios SON el contrato: cada uno se convierte primero en un test que falla.
- **`scope: |` es la única allowlist mecánica.** La sección “Fuera de scope” explica la
  intención a humanos, pero no concede permisos. Un path no permitido deja la historia en
  `in-progress` y bloquea el paso a `in-review`. Solo la propia historia se permite
  automáticamente; tests, implementación y ledger deben enumerarse. Antes del run, historia
  y checker deben estar commiteados: sus blobs se fijan en memoria junto con el OID de la base.

## Cómo lanzarlo

```bash
bash tools/backlog/run.sh                 # una historia, ahora
```

> **Escribir la historia es el 80% del resultado.** En Claude Code, `/historia <tu idea>`
> te entrevista (solo lo que no puede deducir del código), redacta los criterios
> Dado/cuando/entonces verificables y deja el archivo en `backlog/` con `status: ready`
> pasando los mismos guards del runner. Flujo completo del día a día: `docs/PLAYBOOK.md` §2c.

Para el ciclo automático, tres opciones según tu setup:

| Mecanismo | Cómo | Cuándo usarlo |
|---|---|---|
| **cron** clásico | `0 6-20/2 * * 1-5 cd /ruta/repo && bash tools/backlog/run.sh >> .agents/state/backlog.log 2>&1` | servidor/mac siempre encendido |
| **Claude Code scheduled tasks** | en una sesión: *"crea una tarea programada que corra `bash tools/backlog/run.sh` cada 2 horas en días laborables"* | ya vives en Claude Code |
| **bucle supervisado** | `while bash tools/backlog/run.sh; do sleep 60; done` | ráfagas supervisadas (tú delante) |

Config útil: `BACKLOG_MAX_TURNS=40` acota el coste por historia ·
`BACKLOG_CLAUDE_FLAGS="--model sonnet"` para historias mecánicas baratas.

## Qué es esto y qué NO es (honestidad de nivel)

**Sí estamos a este nivel** en lo mecánico: selección, ramas, estados, dependencias, scope y guards
están implementados y testeados (los `test_backlog_*.sh`: selección, criterios, cierre de run, aislamiento y scope). Y la pieza que hace viable lo
no-atendido no es el runner: son los gates de dentro — el run headless hereda `settings.json`
completo (permisos deny, hooks, el reviewer con VERDICT), así que "terminó" significa "pasó
todo", no "el modelo dice que terminó".

**Lo pendiente de validar en vivo** (misma transparencia que `tools/tests/README.md`): un run
headless completo de principio a fin con una historia real — los guards y el selector están
testeados, el interior del run está validado en sesiones interactivas pero no aún vía
`claude -p` desatendido. Primera historia real: lánzala con el bucle supervisado mirando, no con cron a
ciegas. Y arranca con historias PEQUEÑAS (tipo 0001, no tipo 0002) hasta calibrar.

**La calidad de salida es proporcional a la historia.** Criterios de aceptación vagos →
`blocked` o trabajo mediocre; criterios verificables → el agente los convierte en tests y los
gates hacen el resto. Tu palanca es escribir buenas historias, no supervisar el teclado.

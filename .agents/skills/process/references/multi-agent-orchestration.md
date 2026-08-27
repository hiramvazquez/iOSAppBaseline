# Multi-agent orchestration

> Patrón para lanzar sub-agentes. Aplica a Cursor (subagents 2.4+), Claude Code (`.claude/agents`)
> y, en general, cualquier cliente que permita delegar. Codex orquesta distinto pero los principios valen.

## Cuándo usar sub-agentes vs sesión principal

| Tarea | Path |
|---|---|
| 1-3 ediciones quirúrgicas | Sesión principal |
| PRD completo (muchos archivos) | Sub-agente |
| Trabajo paralelo independiente | Varios sub-agentes (scopes disjuntos) |
| Discovery / exploración sin escritura | Agente read-only / explore |
| Auditoría / review | Sub-agente dedicado |
| **Decisiones de producto** | **Siempre sesión principal** — los sub-agentes no conocen intent |

**Regla de oro:** si el trabajo se describe como "haz estos N pasos en estos M archivos", es
candidato a sub-agente. Si requiere "decide qué pedirle al owner", **NO** delegues.

## Estructura de un prompt de sub-agente (6 bloques)

1. **Header cold-start** — repo, branch, política de worktree. El agente arranca sin contexto.
2. **Trabajo en fases ordenadas** — bullets con archivos exactos; marca lo paralelizable.
3. **Hardening — skill reads obligatorios** (los refs que debe leer antes de tocar código).
4. **Reglas duras** — scope exclusivo (qué SÍ / qué NO), sin push, sin `--amend`, errores preexistentes se reportan no se tocan.
5. **Validación obligatoria** — build + tests + check-drift + secret-scan.
6. **Reporte final** — resumen, commits, tests, desviaciones del prompt + justificación.

## Paralelización — disjoint-scope rule

Dos agentes corren en paralelo **solo si sus paths NO se intersectan**. Verifica antes de lanzar.
Riesgos del paralelo: race en el índice de git (mitiga con `git add <path>` explícito, nunca `-A`),
build concurrente que corrompe artefactos, drift de schema/codegen (un solo agente dueño de eso).

## Default: SECUENCIAL con ciclo completo cerrado

> Lección dura: paralelismo agresivo + ciclos incompletos = drift acumulado. Una unidad de trabajo
> a la vez, con su ciclo cerrado (design-review → implementación → reviewer → tests → ship), es más
> lento por unidad pero produce ~cero bugs de coordinación. Usa paralelo solo con scopes 100%
> disjuntos y aprobación explícita del owner.

## Review adversarial con N jueces (diffs de ALTO riesgo)

Un solo reviewer tiene una sola lente, y tiende a encontrar un tipo de problema a la vez.
El dato empírico de este mismo repo: cinco rondas de review de UN reviewer sobre el PRD 0001
produjeron 13 hallazgos reales — y los de cada ronda eran de una categoría que la ronda
anterior no miró. Para cambios donde un fallo es caro (auth, pagos, PHI, los propios gates),
lanza **N jueces con lentes DISTINTAS**, no N copias del mismo:

| Juez | Lente | Prompt-semilla |
|---|---|---|
| 1 | Corrección | "Intenta REFUTAR que esto funciona. ¿Qué input lo rompe?" |
| 2 | Seguridad | "¿Qué puede hacer un adversario con este cambio?" |
| 3 | Reproducibilidad | "Ejecuta las verificaciones. ¿La evidencia sostiene lo afirmado?" |

Reglas del patrón:

1. **Contexto fresco cada uno** — ven el diff, no el razonamiento que lo produjo, ni los
   veredictos de los otros (evita anclaje).
1b. **No acotes una review con una afirmación sobre lo que cambió.** "El delta desde tu ronda
   anterior es solo X" le pide al sub-agente que confíe en un recorte que no puede verificar desde
   contexto cero. Pasó: se pidió una re-review acotada al ledger, el reviewer vio 15 archivos
   staged y se negó — con razón. O le das el objeto completo, o le das el **medio para verificar
   el recorte** (el sha de la revisión anterior, para que compare él). Y cuando un reviewer
   rechaza una premisa que no cuadra con lo que ve, está haciendo su trabajo: es la misma
   propiedad que hace que su GREEN valga algo.
2. **Prompt a REFUTAR, no a validar.** "¿Está bien?" produce confirmación; "rómpelo" produce
   hallazgos.
3. **Cada juez emite el contrato `VERDICT:`** — el hook SubagentStop registra cada veredicto.
4. **Decisión por severidad, no por mayoría simple:** un RED de seguridad no se compensa con
   dos GREEN de corrección. Los gates son independientes, como reviewer vs security-reviewer.
5. **Coste:** ~3× una review normal. Resérvalo para lo que lo justifica; para el diff diario,
   un reviewer + los detectores mecánicos es la relación correcta.

⚠️ El sesgo del juez aplica ×N: un revisor al que pides hallazgos casi siempre reporta alguno.
Instruye a cada juez a reportar SOLO lo que afecta a la corrección o a una regla explícita, y
clasifica sus hallazgos en **bloqueante** vs **registrable** (va al ledger) — el bucle de
review tiene que terminar, y el mecanismo para eso es el ledger, no una ronda más.

## Modelo por tarea (orientativo)

- **Razonamiento alto** (PRD, design-review, refactor cross-cutting, auditoría) → el modelo más capaz.
- **Mecánico siguiendo patrón** (implementación con PRD detallado, tests, tooling) → modelo rápido/barato.
- **Repetitivo** (i18n, formato) → el más barato.

# Feature Workflow — start to ship

> Checklist canónico de idea → producción para features **medianas/grandes**. Para bug fixes
> pequeños, usa el flow corto al final. Universal; los comandos concretos los rellenas por plataforma.

## Fase 1 — Antes del primer commit

| Paso | Acción |
|---|---|
| 1.1 | Decidir si requiere PRD (`prd-lifecycle.md` §criterio) |
| 1.2 | Copiar `docs/process/prds/_template.md` + llenar las secciones |
| 1.3 | **Pausar y revisar con el owner** (problema, objetivo, anti-features, escenarios golden) |
| 1.4 | Si toca un contrato (API/edge/schema) → definir el contrato PRIMERO |
| 1.5 | Si rompe una regla de `AGENTS.md` → ADR ligero en `docs/process/decisions/` |
| 1.6 | **Design-review del CÓMO** (sub-agente `design-reviewer`) ANTES de `Approved`: ¿anti-patrón? ¿multilingüe/context-aware? ¿escala? ¿single source of truth? ¿testeable? ¿reúsa lo que existe? Si hay problema de approach → **arregla el PRD, no el código**. |
| 1.7 | PRD `Approved` → siguiente commit es código |

> **El design-review y el "Approved" del owner son gates DISTINTOS.** Aprobar el Draft no exime
> el design-review (valida la solución con la skill de área cargada). No salteable para cambios de
> arquitectura o de datos sensibles/PHI/pagos.

## Fase 2 — Implementación (TDD: 🔴 red → 🟢 green → ♻️ refactor)

> **Regla dura:** ninguna unidad de lógica/orquestación entra sin un test que haya fallado ANTES
> de la implementación. Playbook + ejemplos iOS en `tdd-workflow.md`.

| Paso | Acción |
|---|---|
| 2.0 | **Handshake pre-código** (sub-agentes): resumen ≤8 puntos + archivos a tocar (= PRD §5) + los que NO va a tocar + OQ bloqueantes. Si algo no cuadra → **para y pregunta**. |
| 2.1 | Antes de tocar un file, lee la skill que aplique (matriz `AGENTS.md` §11) + `tdd-workflow.md` |
| 2.2 | 🔴 **RED** — escribe el test del comportamiento/riesgo actual y míralo FALLAR por la razón correcta |
| 2.3 | 🟢 **GREEN** — implementación MÍNIMA que lo pasa (scope = el test, nada de más) |
| 2.4 | ♻️ **REFACTOR** — limpia en verde + cubre cada rama observable, recuperación y límite aplicable. Respeta capas (`architecture/SKILL.md`) |
| 2.5 | `<!-- FILL: build+test -->` verde + `bash tools/check-drift.sh` sin errores nuevos antes de cada commit |

## Fase 3 — Pre-ship

| Paso | Acción |
|---|---|
| 3.1 | Correr **todos** los escenarios golden del PRD manualmente |
| 3.2 | Verificar authz/roles si aplica |
| 3.3 | Verificar multi-device / multi-idioma si aplica |
| 3.4 | Marcar Definition of Done del PRD |

## Fase 4 — Ship

| Paso | Acción |
|---|---|
| 4.1 | `git push` **solo con aprobación explícita del owner** |
| 4.2 | Update PRD a `Shipped` + tracking de commits |
| 4.3 | Update `docs/process/current_execution_map.md` — **en el mismo commit**. Lo verifica `tools/check-execution-map.sh` (Anillo 3) y `tools/backlog/next.sh` lo avisa al cerrar una historia. Este paso estuvo cinco historias sin ejecutarse cuando era solo prosa. |

## Fase 5 — Post-ship learning

| Paso | Acción |
|---|---|
| 5.1 | Llenar §Gaps del PRD con los aprendizajes reales |
| 5.2 | Registrar en el ledger los gaps significativos (`tools/findings/`) |
| 5.3 | A las 2-4 semanas: revisar success metrics |

## Flow corto (bug fixes / tweaks, 1-3h, no cross-feature)

1. Identifica archivo(s). 2. Lee skill del área + `tdd-workflow.md`. 3. 🔴 test que reproduce el bug (falla) → 🟢 fix → ♻️ refactor. 4. Build+test verde. 5. check-drift ok.
6. `reviewer` → marca. 7. Commit. **Sin PRD, sin overhead.** Si empieza a ramificarse a >2 features, promueve a flow medio.

## Plantilla de commit

```
<tipo>(<área>): <qué hizo en 1 línea>

<por qué — racional breve>
- Closes / part of PRD NNNN
```
Tipos: feat, fix, refactor, docs, chore, sec, test.

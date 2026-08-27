# Sub-agentes — <PROJECT>

> Roles especializados. Cada `.md` define un agente con su prompt, sus tools y su modelo
> recomendado. Claude Code los invoca con la tool `Agent`. Cursor los expone vía el symlink
> `.cursor/agents` → `.claude/agents`, pero **verifica la compatibilidad con tu versión de Cursor**
> (su formato de subagents evoluciona; el frontmatter `name/description/tools/model` puede diferir).
> Codex no tiene sub-agentes nativos: usa estos `.md` como checklists que el agente principal sigue.

## Catálogo

| Agente | Cuándo invocar | Modelo sugerido | Escribe código |
|---|---|---|---|
| `design-reviewer` | PRD mediano/grande, ANTES de implementar (gate de diseño) | alto razonamiento | no |
| `reviewer` | ANTES de cada commit de código de producto | medio | no |
| `security-reviewer` | commits que tocan secretos/datos/authz/deps | medio | no |
| `tester` | cuando falta cobertura de tests | medio/rápido | solo tests |
| `prd-writer` | diseñar una feature mediana/grande como PRD | alto razonamiento | no (escribe el PRD) |
| `process-judge` | al cerrar un PR/sesión, o nocturno | alto razonamiento | no (reporta + ledger) |

## Reglas para TODOS los sub-agentes

1. **Scope exclusivo.** Solo los archivos que el prompt/PRD listan. Fuera de scope → reportar, no tocar (`AGENTS.md` §8).
2. **Errores preexistentes:** se registran en el ledger (`bash tools/findings/findings.sh add`), NUNCA se silencian ni se "arreglan de paso".
3. **Sin `git push`, sin `--amend`, sin `--no-verify`.**
4. **Reporte final estructurado:** qué hizo, commits, tests, desviaciones del prompt + razón.
5. Los agentes de review/judge **NO modifican código** — solo reportan y/o anexan al ledger.

## El contrato VERDICT (review/judge — OBLIGATORIO)

`reviewer`, `security-reviewer`, `design-reviewer` y `process-judge` terminan su mensaje final
con tres líneas, cada una en la suya:

```
VERDICT: GREEN|AMBER|RED
FINDINGS: <n>
SCOPE: <qué se revisó, en una línea>
```

El hook `SubagentStop` (`capture-review-verdict.sh`) las parsea y **el sistema** escribe el
marker correspondiente — el modelo no puede escribirlo, y un review sin contrato bloquea el
cierre del propio sub-agente. Efectos por agente:

| Agente | GREEN/AMBER | RED |
|---|---|---|
| `reviewer` | marker canónico → desbloquea `git commit` | sin marker: el commit sigue bloqueado |
| `security-reviewer` / `design-reviewer` | marker propio (trazabilidad) — **no** desbloquea commits | registrado; el `reviewer` debe verlo |
| `process-judge` | marker propio + **vacía la cola de juicio** (cualquier veredicto) | ídem — juzgar no desbloquea commits |

Al revisar, clasifica cada hallazgo como **bloqueante** (rompe una garantía afirmada) o
**registrable** (mejora real → al ledger): el bucle de review tiene que terminar, y el
mecanismo para eso es el ledger, no una ronda más. Para diffs de alto riesgo existe el patrón
N-jueces: `.agents/skills/process/references/multi-agent-orchestration.md`.

> `model:` en el frontmatter es orientativo: <!-- FILL: ajusta a los modelos que tu org tenga habilitados. -->

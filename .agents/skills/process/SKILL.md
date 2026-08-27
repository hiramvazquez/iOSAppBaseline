---
name: process
description: Usar al empezar una feature, abrir un PRD nuevo, o cuando preguntan "¿cuál es nuestro flujo de trabajo?". Cubre PRD lifecycle, feature workflow start-to-ship, TDD, el bucle de verificación y la orquestación multi-agente. Invocar antes de cualquier feature mediana/grande.
when_to_use: Al arrancar una feature, escribir o mover un PRD de estado, decidir si algo necesita PRD, montar un gate nuevo, o preguntar "¿cómo sé que este código está bien?".
paths:
  - "docs/process/**"
  - "tools/**"
  - "ci/**"
  - "scripts/agent-hooks/**"
---

# Process & Workflow — <PROJECT>

> El **CÓMO TRABAJAMOS**. Esta skill es universal (no depende de la plataforma) y viene
> mayormente rellenada. El producto (WHAT) y la arquitectura (HOW del código) viven en otras skills.

## Qué cargar por contexto

| Necesidad | File |
|---|---|
| "¿Cuándo escribo un PRD? ¿Qué template?" | `references/prd-lifecycle.md` |
| "¿Cuál es el flujo start-to-ship?" | `references/feature-workflow.md` |
| "¿Cómo lanzo sub-agentes? ¿En paralelo?" | `references/multi-agent-orchestration.md` |
| "¿Cómo aplico TDD? ¿Cómo testeo en iOS?" | `references/tdd-workflow.md` |
| "¿Dónde vive cada doc?" | `references/documentation-map.md` |
| "¿Cómo funciona el backlog de historias / trabajo desatendido?" | `../../../backlog/README.md` + `../../../docs/EXAMPLES.md` §4 |

## Las 5 reglas de oro del proceso

1. **TDD por defecto** — ninguna lógica nueva sin un test que falle primero (🔴→🟢→♻️). Ver `references/tdd-workflow.md`.
2. **Feature mediana/grande → PRD obligatorio** antes del primer commit de código.
3. **Cambio de contrato (API/edge/schema) → contrato primero** (schema/interfaz), luego código.
4. **Decisión arquitectónica reusable → ADR ligero** en `docs/process/decisions/`.
5. **Feature shipped → cerrar el loop**: PRD a `Shipped`, Definition of Done marcado, gaps capturados.

## Anti-patrones del proceso

- ❌ Code first, doc later → docs muertos, drift, bugs repetidos.
- ❌ "Es solo un quick fix" para algo cross-feature.
- ❌ "Ya lo discutimos en el chat, no hace falta documentarlo" — el chat se pierde, el doc permanece.
- ❌ Inventar un workflow ad-hoc. Si el de `feature-workflow.md` no encaja, primero actualízalo, después rómpelo.

## Cuándo actualizar esta skill

Cuando agreguen un tipo de artefacto nuevo, cuando un anti-patrón aparezca 3+ veces, o cuando el
workflow cambie. **No agregues items aspiracionales que no estén siguiendo de verdad** — mejor ser
honesto sobre el flujo actual e iterar.

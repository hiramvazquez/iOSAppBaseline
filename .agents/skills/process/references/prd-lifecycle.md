# PRD Lifecycle

> Cuándo escribir un PRD, qué template, cómo retroalimentar el doc a lo largo del ciclo.

## Cuándo escribir PRD

| Tipo de cambio | ¿PRD? |
|---|---|
| Bug fix, tweak (1-3h) | **No** — basta el commit message |
| Feature pequeña (≤1 día, sin cambio de datos) | **Opcional** |
| Feature mediana/grande | **Sí, obligatorio** |
| Producto nuevo / pivot | **Sí, obligatorio** |
| Refactor sin cambio de comportamiento | **No** — ADR ligero si es decisión reusable |
| Hotfix urgente | **Después** — flow corto + PRD retroactivo en 48h |

### Criterio "mediano/grande" (≥2 de)

- Dev estimado > 3 días · toca > 1 módulo · cambia schema/datos · cambia contrato de API ·
  decisión de privacy/security/pricing · decisión arquitectónica reusable.

## Status a lo largo del ciclo

```
Draft → Approved → In progress → Shipped → (Deprecated)
```

1. **Draft** — autor escribiendo. 2. **Approved** — owner revisó + design-review pasó.
3. **In progress** — primer commit hecho. 4. **Shipped** — en producción, Definition of Done en `[x]`.
5. **Deprecated** — descontinuada; se conserva como histórico.

## Secciones críticas del template (no skipear)

- **Contexto + Problema** — sin esto no se justifica construir.
- **Estructura de archivos** + **NO-TOUCH** — paths exactos; el reviewer trata NO-TOUCH como bloqueo.
- **Anti-features** — qué NO entra; bloquea scope creep mejor que cualquier código.
- **Escenarios golden** — si no puedes escribir uno, el feature no está bien definido.
- **Definition of Done** — checklist verificable.
- **Gaps detectados** — el valor diferencial de escribir el PRD.

## Pregunta de seguridad antes de escribir

¿Cuál es el dolor real? ¿Para quién? ¿Qué pasa si NO lo construimos? (Si la respuesta es "nada",
no lo construyas.) ¿Cuál es el costo real, incluyendo mantenimiento?

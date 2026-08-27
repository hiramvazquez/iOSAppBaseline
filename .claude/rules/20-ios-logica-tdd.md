---
paths:
  - "**/*ViewModel*.swift"
  - "**/*Logic*.swift"
  - "**/*UseCase*.swift"
  - "**/Domain/**"
---

# Regla path-scoped: lógica iOS (TDD)

> Se carga al tocar lógica/orquestación/dominio. Espejo de `AGENTS.md` §5 y §11.

Antes de editar: `.agents/skills/architecture/SKILL.md` + `domain/SKILL.md` + `process/references/tdd-workflow.md`.

- **TDD obligatorio:** 🔴 escribe el test y míralo fallar → 🟢 implementación mínima → ♻️ refactor. Cubre cada comportamiento/riesgo y rama observable aplicable.
- **Lógica pura:** sin UI ni navegación; habla con **puertos (protocolos)**, no con SDK/red directo.
- **Determinismo:** inyecta reloj/UUID; nunca `Date()`/`UUID()` dentro de la lógica testeable.
- El **dominio** no importa UI ni infraestructura.

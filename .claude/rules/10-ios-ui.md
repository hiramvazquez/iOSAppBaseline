---
paths:
  - "**/*View*.swift"
  - "**/*Screen*.swift"
---

# Regla path-scoped: UI iOS

> Carga nativa de Claude Code cuando tocas una View/Screen (complementa el hook `skill-reminder`,
> sin el coste de re-lectura forzada). Espejo de la matriz `AGENTS.md` §11.

Antes de editar: ten presente `.agents/skills/architecture/SKILL.md` + `platforms/ios.md`.

- La **View** renderiza estado y emite intención (`vm.send(...)`); **sin** lógica de negocio ni llamadas a datos.
- **Navegación:** las pantallas emiten intención; el `NavigationStack` vive en el Coordinator, no en la View.
- **Design System:** usa tokens; prohibido `Color(hex:)` / `Font.system(size:)` / padding numérico suelto.

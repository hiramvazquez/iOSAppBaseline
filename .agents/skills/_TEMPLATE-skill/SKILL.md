---
name: <kebab-case-nombre>
description: <Una frase clara con los TRIGGERS — "Usar cuando ...". El agente decide cargarla por esta línea, así que sé concreto sobre cuándo aplica y qué cubre.>
---

# <Área> — <PROJECT>

> Copia esta carpeta para crear una skill nueva. Renómbrala (quita el `_TEMPLATE-`), ajusta el
> frontmatter, y borra estas instrucciones.

## Cuándo cargar qué (mapa de la skill)

| Necesidad | File |
|---|---|
| <pregunta típica> | esta skill §<sección> |
| <tema profundo / largo> | `references/<tema>.md` |

> Mantén el SKILL.md **corto** (overview + ruteo). El detalle pesado va en `references/*.md`,
> que el agente carga solo cuando lo necesita (ahorra contexto).

## §<Sección principal>

<!-- FILL: contenido real. Marca tu opinión con `<!-- OPINIÓN: ... -->` y lo inferido con `<!-- TODO: validar -->`. -->

## Reglas duras de esta área

- <!-- FILL: lo no negociable. Idealmente cada regla tiene un detector en check-drift o un check del reviewer. -->

## Mantenimiento

- Si cambias un patrón, **actualiza esta skill en el mismo PR** que el código.
- Si un caso real no está cubierto: NO improvises — pregunta al owner y añádelo aquí.

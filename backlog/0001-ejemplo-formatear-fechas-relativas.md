---
id: 0001
titulo: Mostrar fechas relativas en la lista de notas
status: ejemplo      # ← cámbialo a `ready` en tu proyecto; `ejemplo` = el runner lo ignora
depends_on: []
base: develop
scope: |
  ios/Sources/Domain/RelativeDateFormatter*.swift
  ios/Tests/DomainTests/RelativeDateFormatterTests.swift
  ios/Sources/UI/NotesList/NoteRowView.swift
---

# Mostrar fechas relativas en la lista de notas

## Historia
Como usuario quiero ver "hace 2 h" en vez de "05/08/2026 14:32" en cada nota
para escanear la lista de un vistazo.

## Contexto
La lista muestra `Note.updatedAt` crudo. Ya existe un design token de texto
secundario (`.textSecondary`). No hay ninguna utilidad de fechas en Domain.
Idiomas activos: ES + EN (AGENTS.md §2) — nada de strings hardcoded.

## Criterios de aceptación
1. Dado un `updatedAt` de hace 90 segundos, cuando se renderiza la fila,
   entonces muestra la clave i18n de "hace 1 min" (no texto literal en código).
2. Dado un `updatedAt` de hace 3 días, cuando se renderiza, entonces muestra
   "hace 3 d"; y con más de 7 días, la fecha corta localizada.
3. Dado el locale EN, cuando se renderiza, entonces las cadenas salen del
   catálogo i18n (ningún literal español en la lógica — §3).
4. Dado un `updatedAt` en el futuro (reloj desincronizado), cuando se
   renderiza, entonces muestra "ahora" y NO crashea ni muestra negativos.

## Fuera de scope
- Cambiar el diseño de la fila, tipografías o colores.
- Tocar el modelo `Note` o su persistencia.
- Refrescar la celda en vivo cada minuto (queda para otra historia).

## Notas técnicas
- La lógica va en Domain como tipo puro testeable con reloj INYECTADO
  (nunca `Date()` dentro — ver `tdd-workflow.md` §Determinismo).
- `RelativeDateTimeFormatter` de Foundation es válido como implementación,
  envuelto en nuestro puerto para poder fijar el reloj en tests.

---
id: 0002
titulo: Archivar y desarchivar notas con swipe
status: ejemplo      # ← `ready` en tu proyecto
depends_on: [0001]   # ejemplo de dependencia: no arranca hasta que 0001 esté DONE (mergeada)
base: develop
scope: |
  ios/Sources/Domain/ArchiveNote*.swift
  ios/Sources/Domain/Ports/NoteRepository.swift
  ios/Sources/Data/SupabaseNoteRepository.swift
  ios/Sources/UI/NotesList/**
  ios/Tests/**
---

# Archivar y desarchivar notas con swipe

## Historia
Como usuario quiero archivar una nota con swipe (y recuperarla desde
"Archivadas") para limpiar mi lista sin perder nada.

## Contexto
Historia más grande que la 0001 — toca las TRES capas: puerto nuevo en
Domain, implementación en Data y UI con swipe actions. `NoteRepository` hoy
solo tiene `fetch/save`. La pestaña "Archivadas" ya existe vacía tras el
rediseño. Depende de 0001 solo porque ambas tocan `NoteRowView` y queremos
las ramas sin conflictos (§ paralelización: scopes disjuntos o secuencia).

## Criterios de aceptación
1. Dado una nota activa, cuando hago swipe y toco "Archivar", entonces
   desaparece de la lista principal y aparece en "Archivadas".
2. Dado una nota archivada, cuando la desarchivo, entonces vuelve a la lista
   principal conservando su contenido y su `updatedAt` ORIGINAL (archivar no
   es editar).
3. Dado que el backend falla al archivar, cuando hago swipe, entonces la nota
   NO desaparece de la lista y veo el error mapeado a clave i18n (nunca el
   error crudo de infra — `domain/SKILL.md` §Errores).
4. Dado el arranque de la app, cuando cargo la lista principal, entonces las
   archivadas NO viajan en esa query (filtro en servidor, no en cliente).
5. El fake de `NoteRepository` pasa la MISMA suite de conformidad que el
   adapter real, ampliada con los casos de archivo (`domain/SKILL.md`
   §Suite de conformidad — es regla dura).

## Fuera de scope
- Borrado definitivo, papelera y retención.
- Archivar en lote / seleccionar múltiples.
- Sincronización offline del estado de archivo.

## Notas técnicas
- El puerto crece por CAPABILITY (`ArchiveNoteUseCase`), no engordando el
  repo genérico — ver `domain/SKILL.md` §Puertos.
- Cambio de contrato compartido ⇒ drift policy §9: puerto + fake + adapter +
  su doc, en el MISMO PR.
- La migración de DB (columna `archived_at`) exige leer `security/SKILL.md`
  (RLS de la tabla) — el hook lo forzará al tocar `Data/`.

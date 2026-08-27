---
name: architecture
description: Usar cuando la pregunta toca la arquitectura del código — patrón de pantalla/módulo, navegación, inyección de dependencias, capas, manejo de errores, acceso a datos. Es el HOW del código (no el WHAT del producto).
when_to_use: Al editar cualquier View/Screen/ViewModel/Coordinator, al decidir dónde vive una responsabilidad nueva, al añadir una pantalla o un módulo, o al preguntar "¿esto en qué capa va?".
paths:
  - "**/*View*.swift"
  - "**/*Screen*.swift"
  - "**/*ViewModel*.swift"
  - "**/*Coordinator*.swift"
  - "**/ui/**"
  - "**/UI/**"
  - "**/*.tsx"
  - "**/*Screen*.kt"
---

<!-- `paths:` = activación AUTOMÁTICA por glob, nativa de Claude Code. Es la
     versión declarativa de la matriz de AGENTS.md §11: cuando el agente trabaja
     sobre un archivo que casa, la skill se carga sola, sin coste de re-lectura
     forzada. El hook `skill-reminder` sigue siendo el gate DURO (bloquea si no
     la leíste); esto es el camino feliz que hace que casi nunca se dispare. -->


# Arquitectura — <PROJECT>

> El HOW de tu código. Stack de referencia: **iOS 17+ / Swift 6 / SwiftUI vanilla + MVVM-C**.
> Lo específico de iOS vive en `platforms/ios.md`; lo de otras plataformas en `platforms/{android,web}.md`.
> Ajusta los `<!-- FILL -->` a las rutas/nombres reales de tu repo.

## Qué cargar por tema

| Pregunta | Dónde está |
|---|---|
| "¿Cómo construyo una pantalla/módulo nuevo?" | esta skill §Patrón + `platforms/<plataforma>.md` |
| "¿Qué va en la capa de orquestación vs lógica?" | esta skill §Capas |
| "¿Cómo navego entre pantallas?" | esta skill §Navegación |
| "¿Cómo registro/inyecto una dependencia?" | esta skill §DI |
| "¿Cómo llamo a datos/backend?" | esta skill §Datos |

## §Patrón de pantalla/módulo

Tres archivos por pantalla: **(1) presentación/UI, (2) orquestación de estado, (3) lógica pura
testeable**. La lógica NO vive en la UI ni en el orquestador.

- **iOS (referencia):** `View` (SwiftUI) + `ViewModel` (`@Observable @MainActor`) + `Logic`/`UseCase` (Swift puro).
- Equivalentes: Android `Composable+ViewModel+UseCase` · Web `Component+hook+service`.

| Capa | Qué hace | Qué NO hace |
|---|---|---|
| Presentación | renderiza estado, emite intención | lógica condicional de negocio, llamadas a datos |
| Orquestación | mantiene estado de pantalla, llama UseCases | validación de reglas, acceso directo a repos |
| Lógica pura | la regla de negocio, composición de puertos | tocar UI, conocer navegación |

## §Capas y límites

- App / Feature / Domain / Data / Core. Toda dependencia que cruza capa va por **protocolo** +
  **inyección por constructor**.
- El **dominio** (entidades, puertos, errores) NO importa UI ni infraestructura (ver skill `domain`).

## §Navegación

Coordinator/Router central posee el stack de navegación; las pantallas **emiten intención**, no
construyen rutas ni anidan stacks. Detalle iOS en `platforms/ios.md`.

## §Inyección de dependencias (DI)

Inyección **por constructor** por defecto; el composition root (en `App`) arma el grafo. El service
locator global solo en el composition root, nunca dentro de la lógica de dominio.

## §Acceso a datos

La presentación/orquestación habla con **puertos (protocolos)** del dominio; las implementaciones
concretas (red/DB/Keychain) viven en `Data/` e inyectan por ctor (`async/await`, `Sendable`).
<!-- FILL: cliente HTTP/DB real, dónde viven los repos, caché/refresh. -->

## Fuentes de verdad

- <!-- FILL: rutas reales del composition root, navegación, paquetes/módulos. -->

## Mantenimiento

- Cuando cambies un patrón arquitectónico, **actualiza esta skill en el mismo PR** (nunca solo en el código).
- Marca con `<!-- TODO: validar -->` lo que infieras sin certeza; resuélvelo antes de usarlo en producción.

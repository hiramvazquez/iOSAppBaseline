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

# Arquitectura — iOSAppBaseline

> **Las decisiones de arquitectura de este proyecto están TOMADAS Y COMPILADAS** en los dos
> paquetes propios. No se re-litigan por pantalla: se citan.
>
> - **`AppFoundation`** — `BaseViewModel`, `ScreenContainer`, `Coordinator`/`Router`,
>   `Container`/`@Inject`, estados de pantalla (`ViewPhase`, `AlertState`, `BannerState`).
> - **`CoreNetworking`** — `APIService`, `BaseRequest`, `APIError`/`TransportError`, retry,
>   pinning, y `CoreNetworkingTestSupport` con los mocks.
>
> Lo que los paquetes no cubran se decide **una vez** y se escribe en `docs/process/decisions/`.

## Qué cargar por tema

| Pregunta | Dónde está |
|---|---|
| "¿Cómo construyo una pantalla nueva?" | `platforms/ios.md` §1-§2 |
| "¿Cómo navego entre pantallas?" | `platforms/ios.md` §3 |
| "¿Cómo registro/inyecto una dependencia?" | `platforms/ios.md` §4 |
| "¿Cómo mapeo un error a lo que ve el usuario?" | `platforms/ios.md` §5 |
| "¿Cómo llamo a la API / escribo un repositorio?" | `domain/SKILL.md` §La capa Data |
| "¿Qué va en el dominio y qué en datos?" | `domain/SKILL.md` |
| "¿Cómo escribo el test de esto?" | `process/references/tdd-workflow.md` |
| "¿Qué Swift se usa hoy aquí?" | `platforms/swift-estado-del-arte.md` |

> ⚠️ **Los README de los dos SPM contienen ejemplos que rompen la app.** Están catalogados en
> `platforms/ios.md` §9. Si un README contradice a la skill, **gana la skill**.

## §Patrón de pantalla/módulo

Tres piezas por pantalla: **presentación**, **orquestación**, **lógica pura**. La lógica no
vive en la UI ni en el orquestador.

| Capa | Qué hace | Qué NO hace |
|---|---|---|
| **View** (SwiftUI, dentro de `ScreenContainer`) | renderiza estado, emite intención | lógica de negocio, llamadas a datos, pintar carga/error/vacío a mano |
| **ViewModel** (`BaseViewModel`, `@Observable @MainActor`) | mantiene el estado de pantalla, orquesta puertos | reglas de negocio, acceso directo a red/DB |
| **Logic / UseCase** (Swift puro) | la regla de negocio, composición de puertos | tocar UI, conocer navegación |

*Puro = puro en **dependencias** (sin UI ni infra, determinista), no «libre de actor»: con el
default `MainActor` del target, la lógica es implícitamente `@MainActor` y eso está bien. El
escape para cómputo pesado es puntual (`@concurrent`), **nunca** revertir el default del
target.*

## §Capas y límites

```
App/  →  Features/  →  Domain/  ←  Data/
```

Toda dependencia que cruza capa va por **protocolo** + **inyección por constructor**.

Lo que `tools/layers.conf` **prohíbe mecánicamente** (`check-layers.sh` lo verifica en cada
commit):

- `Domain/` no importa `SwiftUI`/`UIKit`, ni persistencia, **ni `AppFoundation`/`CoreNetworking`**.
  El modelo de negocio no sabe cómo se transporta ni cómo se pinta.
- `Features/` no importa `CoreNetworking`: hablar HTTP es trabajo de `Data/` tras un puerto.

**Corolario que ya costó un refactor:** un error de dominio **no puede llevar un
`TransportError` asociado**, porque eso exigiría `import CoreNetworking` en `Domain/`. La
traducción se hace **valor a valor en `Data/`**.

## §Navegación

`Coordinator` + `Router` de AppFoundation. Las vistas **no navegan**: el ViewModel pide al
router, y depende del **protocolo** `Router` (seis métodos, ningún estado de lectura), no de la
clase. Una capa modal por host — el estado es incapaz de representar dos.

⚠️ El closure de rutas de `CoordinatorView` **se reevalúa en cada navegación**: los ViewModels
se retienen fuera, en una factoría memoizada. Detalle y ejemplo en `platforms/ios.md` §3.

## §Inyección de dependencias

`Container` de AppFoundation, con un `DependencyModule` por feature registrado en el
composition root. **Inyección por constructor por defecto**; `@Inject` solo para dependencias
transversales y **siempre con un `init(container:)`** que permita testear con un contenedor
propio. Los tests registran fakes en **contenedores propios**, nunca mutando el global.

⚠️ `Container.shared` es inmutable en la **referencia**, no en el contenido: `register` y
`reset` son públicos sobre él. El aislamiento entre tests es disciplina, no tipos.

## §Acceso a datos

La presentación y la orquestación hablan con **puertos** del dominio. Las implementaciones
viven en `Data/` y entran por constructor. Todo HTTP pasa por `APIService` de CoreNetworking:
nada de `URLSession` suelto. Detalle en `domain/SKILL.md`.

## Fuentes de verdad

| Qué | Dónde |
|---|---|
| Composition root | `Sources/App/BaselineApp.swift` |
| Rutas y su Coordinator | `Sources/Features/<Feature>/<Feature>Route.swift` + `Sources/App/` |
| Módulos de DI | `Sources/Features/<Feature>/<Feature>Module.swift` |
| Identidad de los ViewModels | `Sources/App/<Feature>/<Feature>ScreenStore.swift` |
| Configuración de red y credencial | `Sources/Data/<Feature>/<Feature>Configuration.swift` |
| Reglas de capa ejecutables | `tools/layers.conf` |
| Paquetes y versión fijada | `project.yml` + `Package.resolved` |

> **El módulo de referencia es `Movies`.** Cuando dudes de un patrón, léelo ahí antes de
> inventarlo — y si lo que encuentras contradice esta skill, es un finding, no un ejemplo.

## Mantenimiento

- Cuando cambies un patrón arquitectónico, **actualiza esta skill en el mismo PR**, nunca solo
  el código.
- Si esta skill no cubre tu caso: **no improvises** — pregunta al owner y actualízala antes de
  seguir (AGENTS.md §0.4).

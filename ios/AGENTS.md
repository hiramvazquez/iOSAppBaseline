# <PROJECT> iOS — overrides de plataforma

> `AGENTS.md` anidado. Se **combina** con el raíz; el más cercano al archivo editado gana.
> Solo lo específico de iOS; lo común queda en el raíz. Lo lee Cursor/Codex nativo; Claude vía la skill `architecture`.

## Stack iOS
- **Swift 6**, **iOS 17+**, **SwiftUI** (vanilla, sin TCA).
- **SwiftPM** para modularizar (features/dominio como packages locales).
- **Swift Testing** (Xcode 16+) para unit tests; XCTest solo legacy/UI.
- <!-- FILL: deployment target exacto, versión de Xcode, scheme(s) reales. -->

## Build & test iOS
- **build:** `xcodebuild -scheme <Scheme> -destination 'platform=iOS Simulator,name=iPhone 16' build`
- **test:**  `xcodebuild test -scheme <Scheme> -destination 'platform=iOS Simulator,name=iPhone 16'`
- **spm:**   `swift test --package-path Packages/<Pkg>`
- <!-- FILL: reemplaza <Scheme>/<Pkg> por los reales. -->

## Arquitectura iOS
- Patrón: **View + @Observable @MainActor ViewModel + Logic/UseCase puro + Coordinator + DI por ctor**.
  Detalle y ejemplos: `.agents/skills/architecture/platforms/ios.md`.
- Límites de tamaño y capas: ver `AGENTS.md` §3-§4 (raíz). TDD: `process/references/tdd-workflow.md`.

## Convenciones iOS específicas
- Adaptación iPhone↔iPad DENTRO del componente reutilizable, no `if idiom == .pad` por pantalla.
- Design System tokeniza color/tipografía/spacing — prohibido `Color(hex:)`/`Font.system(size:)` suelto.
- Concurrencia: `async/await`, tipos `Sendable`; el ViewModel es `@MainActor`.
- <!-- FILL: tu Design System y estructura de módulos reales. -->

## Seguridad iOS
- Secretos/sesión → **Keychain** (nunca UserDefaults). Datos sensibles en disco → `NSFileProtection`.
- Sin claves en el bundle; App Lock biométrico opcional. Ver skill `security`.

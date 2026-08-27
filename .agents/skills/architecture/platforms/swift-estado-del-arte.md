# Swift — estado del arte (documento VIVO)

> **Vigente a: 2026-08.** Baseline estable: **Swift 6.2 / Xcode 26** (con *Approachable
> Concurrency*). Anunciado en WWDC26: Swift 6.3 (llega con Xcode 27, ~sept 2026) — sus
> features van al final, en "No usar aún".
>
> **Por qué existe este doc:** un agente programa "el Swift que memorizó", que suele tener
> 1-2 años. Sin esta referencia escribe completion handlers donde va async/await, GCD donde
> va un actor, y ObservableObject donde va @Observable. Esto es lo que SÍ se usa hoy aquí.

## ⚠️ Reglas de vigencia (para el agente que lee esto)

1. **Si la fecha de arriba tiene más de ~4 meses**, avísale al owner y ofrécete a refrescar
   este doc: busca "What's new in Swift" en swift.org y la doc de Apple, actualiza lo que
   cambió y la fecha, y preséntalo como diff para su aprobación. Este doc se pudre — esa es
   su naturaleza — y el ritual de refresco es parte de mantenerlo.
2. **Ante duda de una API concreta, NO programes de memoria:** si tu cliente tiene búsqueda
   web, verifica contra la doc oficial (swift.org / developer.apple.com) antes de usar un
   patrón que podría estar obsoleto. Un patrón viejo que compila es peor que uno que no.
3. Lo de "No usar aún" (final del doc) requiere decisión explícita del owner.

## Concurrencia — el modelo mental de 2026

**Proyecto nuevo = Approachable Concurrency activada + aislamiento por defecto en MainActor —
y ese default NO se revierte a nivel de target.** Aclaración que ya costó una decisión
equivocada en vivo: "Logic *puro*" en esta arquitectura significa puro en DEPENDENCIAS
(sin imports de UI/infra, determinista, testeable con fakes) — no "libre de actor". Que la
lógica de dominio sea implícitamente `@MainActor` en un app target está BIEN; si una función
concreta necesita paralelismo real, se marca ELLA (`@concurrent`/`nonisolated`) con su
justificación — jamás se cambia el default del target entero, que devuelve al proyecto a la
fricción pre-6.2 y contradice esta skill. Conflicto aparente entre docs internos → Open
Question al owner, no elección unilateral (§1.4).
En Xcode: build settings *Approachable Concurrency* = YES y *Default Actor Isolation* =
MainActor. En SPM (tools 6.2+): los cinco upcoming features (`DisableOutwardActorInference`,
`GlobalActorIsolatedTypesUsability`, `InferIsolatedConformances`, `InferSendableFromCaptures`,
`NonisolatedNonsendingByDefault`) — en proyectos existentes, actívalos de uno en uno.
El mundo empieza single-threaded (MainActor) y la concurrencia se INTRODUCE a propósito,
no se sufre por defecto.

| Quieres | Usa | NO uses |
|---|---|---|
| Trabajo asíncrono | `async/await` | completion handlers nuevos, `DispatchQueue` |
| Estado mutable compartido | `actor` | `NSLock`/`DispatchSemaphore`/`DispatchQueue(label:)` |
| Código de UI / estado de pantalla | `@MainActor` (default en 6.2) | `DispatchQueue.main.async` |
| Cómputo pesado fuera del actor | `@concurrent` en la función | `Task.detached` "porque sí" |
| Varias tareas hijas con resultado | `async let` / `withTaskGroup` | N `Task {}` sueltos |
| Trabajo ligado a una vista | `.task {}` (se cancela solo) | `Task {}` en `onAppear` sin cancelar |
| Esperar/retrasar | `try await Task.sleep(for:)` | `Thread.sleep` |

Reglas que el reviewer te va a exigir:

- **Cancelación es parte del contrato:** toda operación larga comprueba
  `Task.checkCancellation()` / `Task.isCancelled` en sus puntos de progreso. Un `Task`
  guardado en una propiedad se cancela en el ciclo de vida correspondiente (`deinit`, task
  modifier, o cancelación explícita) — un Task retenido y jamás cancelado es una fuga.
- **`nonisolated(nonsending)` es el default 6.2** para funciones async no aisladas: corren
  en el actor del llamador. Si de verdad quieres paralelismo, dilo con `@concurrent` — el
  paralelismo es una decisión, no un accidente.
- **`Sendable` no se silencia:** un warning de Sendable es un data race en potencia. Se
  arregla con aislamiento (actor/@MainActor) o inmutabilidad, no con `@unchecked Sendable`
  (eso requiere justificación escrita en el propio código).
- **Capturas en Tasks:** en structured concurrency (`async let`, grupos, `.task`) NO hace
  falta `[weak self]` reflejo — la tarea muere con su scope. En `Task {}` almacenado en una
  propiedad de una clase, sí piénsalo: ahí es donde se forman los ciclos.

## Lenguaje moderno (lo que se espera ver en el código)

- **Errores tipados** (`throws(MyError)`, Swift 6+) cuando el dominio de error es cerrado —
  casan perfecto con los errores de dominio de `domain/SKILL.md`. `Result` ya casi nunca es
  necesario en API nueva.
- **`@Observable`** (framework Observation) para ViewModels — no `ObservableObject` +
  `@Published` en código nuevo.
- **Swift Testing** (`@Test`, `#expect`, `@Suite`, `.tags`) para tests unitarios nuevos —
  XCTest queda para UI tests y lo legacy. Los ejemplos de `tdd-workflow.md` ya están en
  Swift Testing.
- **`~Copyable`** para recursos con propiedad única (handles, tokens de una sola vez):
  hace el doble-uso imposible por tipo — nivel 0 de la pirámide.
- **`InlineArray` / `Span`** (6.2) solo en hot paths medidos — son herramientas de
  rendimiento, no el default.
- **Force-unwrap `!`, `try!`, `as!`: prohibidos en producción** (los cazan
  `tools/semgrep/rules/swift.yaml` y el linter). La excepción legítima (un invariante que
  el tipo no puede expresar) exige comentario justificando en la misma línea — y plantéate
  primero si un tipo mejor lo haría innecesario.
- **`print()` no es logging:** `Logger` (os.log) con categorías. Nada de datos sensibles
  en el log (AGENTS.md §6).

## Anti-patrones que delatan "Swift de memoria vieja" (repórtalos en review)

`DispatchQueue.main.async` dentro de código ya @MainActor · completion handlers en API
nueva · `ObservableObject` nuevo · `weak self` reflejo en structured concurrency ·
`@unchecked Sendable` sin justificación · semáforos para "esperar" un async ·
`Task.detached` como cajón de sastre · XCTest para unit tests nuevos.

## No usar aún (anunciado WWDC26 — Swift 6.3/6.4, llega con Xcode 27)

`weak let` · `~Sendable` en jerarquías · module selectors (`::`) · `@c` para exponer a C ·
`withTaskCancellationShield` · `Continuation` tipada con detección de doble-resume ·
`Ref<T>`/`MutableRef<T>` · `@specialized`/`@inline(always)` · SDK oficial de Android.
Cuando el proyecto adopte Xcode 27, refresca este doc (ritual de arriba) y muévelos a la
sección estable si aplican.

---
*Fuentes del snapshot: swift.org (Swift 6.2 released), guías de Approachable Concurrency,
resúmenes WWDC26. Verifica contra la doc oficial al refrescar.*

## ⚠️ `switch try await` rompe el parser de semgrep (y con él, el nivel 2 del archivo ENTERO)

Confirmado con fixtures aislados en un proyecto real:

| Código | Errores de parseo | ¿Detecta un `try!` en el mismo archivo? |
|---|---:|---|
| `switch try await load() { … }` | 1 | ❌ **no** |
| `let x = try await load(); switch x { … }` | 0 | ✅ sí |

Es **peor** que el caso de `#Preview`: aquel solo perdía lo que iba detrás de la macro; este
deja **el archivo completo sin escanear**. Y es Swift perfectamente idiomático, así que nadie
sospecharía de él.

**Convención mientras la gramática de semgrep no lo soporte:** liga el resultado a una
variable antes del `switch`.

```swift
// ❌ el archivo entero deja de escanearse en el nivel 2
switch try await repository.fetchMovies() { … }

// ✅ mismo comportamiento, y el archivo sí se escanea
let outcome = try await repository.fetchMovies()
switch outcome { … }
```

No es un capricho de estilo: la alternativa es tener un archivo de producto donde ninguna
regla AST corre y nadie te lo dice. Cuando `semgrep-scan` avise de `PartialParsing`, mira si
hay un `switch try` antes de asumir que es un `#Preview`.

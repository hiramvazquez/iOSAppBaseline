# TDD Workflow — 🔴 red → 🟢 green → ♻️ refactor

> El loop canónico de implementación del proyecto. La **disciplina** es universal; los comandos y
> patrones de abajo son de **iOS** (Swift Testing + XCTest). Otras plataformas: el mismo loop con su runner.

## La regla dura

**Ninguna unidad de lógica o de orquestación entra sin un test que haya FALLADO antes de escribir
la implementación.** Si el test pasa antes de implementar, no prueba lo que crees.

- **Aplica a:** lógica de dominio / casos de uso, ViewModels/orquestadores, mapeos, validaciones,
  parsing, reducers, formateadores.
- **NO obligatorio para:** glue de UI puro sin lógica, spikes desechables (márcalos y bórralos),
  wiring de DI trivial. Si dudas, escribe el test.

## El ciclo

1. 🔴 **RED** — escribe UN test del comportamiento esperado o del riesgo actual. Córrelo y míralo
   **fallar por la razón correcta** (aserción, no un error de compilación/typo).
2. 🟢 **GREEN** — la implementación **mínima** que lo pone verde. Nada fuera del test (scope = el test).
3. ♻️ **REFACTOR** — con el test en verde, limpia (nombres, duplicación, capas) y re-corre.
4. Repite por cada comportamiento observable. Cubre cada rama de error, recuperación, permisos
   o límite que aplique; no inventes ramas para satisfacer una cuota numérica.

> **Bug fix = regresión primero:** 🔴 un test que **reproduce el bug** (falla) → 🟢 fix → ♻️ limpia.
> Ese test es la prueba de que lo arreglaste y de que no vuelve.

## iOS — runner y estructura

- **Framework:** **Swift Testing** (Xcode 16+, `import Testing`, `@Test`, `#expect`, `#require`).
  XCTest sigue válido para casos legacy y UI tests (`import XCTest`, `XCTestCase`).
- **Correr:**
  - `swift test` — paquetes SwiftPM; rápido para lógica pura.
  - `xcodebuild test -scheme <Scheme> -destination 'platform=iOS Simulator,name=iPhone 16'`
  - <!-- FILL: el comando/scheme/destino reales de tu proyecto. -->
- **Dónde viven:** target de tests espejo del de producción (`Sources/Domain` → `Tests/DomainTests`).
- **Naming por comportamiento:** `loadProfile_whenOffline_returnsCachedValue`.

## Patrones iOS clave

- **Fakes por protocolo (puerto), no por clase concreta.** La lógica depende de un protocolo; el
  test inyecta un fake. **Nada de red real** en unit tests.
- **Async:** `@Test func ...() async throws { ... }` + `await`; `#expect(try await sut.x() == y)`.
- **`@MainActor`** en tests de ViewModels que tocan estado de UI.
- **Determinismo:** inyecta reloj/fecha/UUID; nunca `Date()`/`UUID()` directo dentro de la lógica testeable.

## Dobles de test: fake, spy — y cuándo usar cada uno

> La regla que decide: **¿qué es el comportamiento observable de ESTA capa?**
> - **Lógica pura (UseCase/Logic):** el comportamiento es la SALIDA (retorno/estado/error).
>   Doble correcto: **fake** (con su suite de conformidad, `domain/SKILL.md`). Verificar
>   "se llamó a X" aquí acopla el test a la implementación — es el anti-patrón.
> - **Orquestación (ViewModel/Coordinator):** el comportamiento ES la coreografía — qué
>   puertos se invocan, con qué, y **en qué orden** (validar ANTES de autenticar; guardar
>   ANTES de navegar; analytics DESPUÉS del éxito). Doble correcto: **spy** — ahí el orden
>   no es un detalle interno, es el contrato de la capa.

**El patrón spy del proyecto (Swift 6.2, un solo doble que actúa Y registra):**

```swift
// Tests/ProfileTests/LoginDoubles.swift
// Eventos como ENUM tipado (no strings): el compilador vigila el test.
enum LoginEvent: Equatable {
    case validated(email: String)
    case authenticated(email: String)
    case sessionSaved
    case navigatedHome
}

// Fake+Spy: implementa los PUERTOS reales (frontera), se comporta (fake)
// y registra (spy). @MainActor porque el ViewModel vive ahí — sin locks.
@MainActor final class LoginPortsSpy: AuthPort, SessionPort, RouterPort {
    private(set) var events: [LoginEvent] = []
    var authResult: Result<Session, AuthError> = .success(.stub)

    func validate(_ email: String) throws { events.append(.validated(email: email)) }
    func authenticate(_ email: String, _ pass: String) async throws -> Session {
        events.append(.authenticated(email: email))
        return try authResult.get()
    }
    func save(_ s: Session) { events.append(.sessionSaved) }
    func showHome() { events.append(.navigatedHome) }
}

// 🔴 El test de orquestación: el ORDEN es la aserción.
@MainActor @Test func login_success_ejecutaElFlujoEnOrden() async throws {
    let spy = LoginPortsSpy()
    let sut = LoginViewModel(auth: spy, session: spy, router: spy)

    await sut.submit(email: "a@b.c", password: "x")

    #expect(spy.events == [.validated(email: "a@b.c"),
                           .authenticated(email: "a@b.c"),
                           .sessionSaved,
                           .navigatedHome])          // ← orden completo, una aserción
}

@MainActor @Test func login_authFalla_noGuardaNiNavega() async throws {
    let spy = LoginPortsSpy(); spy.authResult = .failure(.invalidCredentials)
    let sut = LoginViewModel(auth: spy, session: spy, router: spy)

    await sut.submit(email: "a@b.c", password: "x")

    #expect(!spy.events.contains(.sessionSaved))     // el efecto NO ocurrió
    #expect(!spy.events.contains(.navigatedHome))
    #expect(sut.state == .error("login.error.invalidCredentials"))
}
```

**Reglas del spy (para que no degenere en el anti-patrón):**

1. **Solo en la frontera (puertos/protocolos)**, jamás espiando métodos internos o privados
   del propio SUT — eso sí acopla al detalle de implementación.
2. **Aserta el orden solo cuando el orden es contrato.** Si da igual que analytics dispare
   antes o después de guardar, no lo fijes: cada aserción de orden innecesaria es un test
   que se rompe en el próximo refactor legítimo (ley del 10% aplicada a tests).
3. **Eventos como enum `Equatable`**, no strings — typo imposible, diff legible al fallar.
4. **El spy que implementa un puerto pasa su suite de conformidad** igual que cualquier
   fake: espiar no exime de comportarse como el contrato promete.
5. La prueba de bolsillo sigue mandando: *si reordeno a propósito las llamadas en el
   ViewModel, ¿el test falla?* Si no, el spy es decorativo — y el mutation score lo dirá.

## Ejemplo (red → green → refactor)

Caso: `GreetingUseCase` saluda según la hora; de noche (≥21h) devuelve un saludo distinto.

```swift
// 🔴 RED — Tests/DomainTests/GreetingUseCaseTests.swift
import Testing
@testable import Domain

@Test func greeting_atNight_saysGoodNight() {
    let sut = GreetingUseCase(clock: FixedClock(hour: 23))   // FixedClock: fake del puerto, vive en el target de tests
    #expect(sut.greeting() == .goodNight)
}
```
```swift
// 🟢 GREEN — Sources/Domain/GreetingUseCase.swift
struct GreetingUseCase {
    let clock: Clock                                  // puerto (protocolo), inyectado por ctor
    func greeting() -> Greeting {
        clock.hour() >= 21 ? .goodNight : .hello
    }
}
```
```swift
// ♻️ REFACTOR — con el test en verde, añade ramas de borde como @Test extra:
//   greeting_atMidnight_saysGoodNight (0h), greeting_atNoon_saysHello (12h).
```

## Aserciones / Design by Contract — el complemento obligatorio del TDD

> Los tests comprueban los casos que **se te ocurrieron**. Las aserciones comprueban
> los que no.

Las reglas *Power of Ten* de NASA/JPL motivan una alta densidad de checks en software crítico,
pero una cuota universal por función produce aserciones decorativas. Aquí el estándar es:
cada precondición/invariante real se expresa, sin efectos secundarios; input recuperable usa
tipos/errores y las aserciones quedan para errores de programación.

**Por qué importa especialmente con agentes:** un agente que escribe aserciones produce
código que **falla ruidosamente en vez de silenciosamente**, y deja una especificación
verificable por máquina para el siguiente agente que toque ese archivo. Es la forma más
barata que existe de convertir intención en algo comprobable.

Las tres formas, de la más fuerte a la más débil — **usa siempre la más fuerte posible**:

```swift
// 1. IMPOSIBLE POR TIPO (lo mejor: no hay nada que verificar en runtime).
struct Percentage {                 // no puede existir un Percentage inválido
    let value: Int
    init?(_ v: Int) { guard (0...100).contains(v) else { return nil }; self.value = v }
}

// 2. PRECONDICIÓN + POSTCONDICIÓN (Design by Contract).
func aplicarDescuento(_ precio: Decimal, _ pct: Percentage) -> Decimal {
    precondition(precio >= 0, "precio negativo: invariante de dominio roto")
    let out = precio * (1 - Decimal(pct.value) / 100)
    assert(out <= precio, "un descuento nunca puede aumentar el precio")
    return out
}

// 3. FALLO CON RECUPERACIÓN EXPLÍCITA (nunca silencioso — AGENTS.md §6).
guard let user = try? repo.fetch(id: id) else {
    logger.error("fetch falló para id (sin loguear el id: es PII)")
    throw ProfileError.notFound          // ← acción explícita, no `return nil`
}
```

❌ **Nunca** una aserción con efectos secundarios (`assert(contador.increment() > 0)`):
en builds de release las aserciones desaparecen y el comportamiento cambia.

## Property-based testing — para invariantes

Cuando lo que quieres fijar es una **propiedad que debe valer siempre**, no tres ejemplos.
El dato empírico: **un test property-based mata ~50× más mutantes que un test unitario
promedio**. Y los agentes son mucho mejores generando propiedades que generando casos de
ejemplo interesantes.

```swift
// En vez de 3 ejemplos de descuento, la propiedad que los cubre todos:
@Test(arguments: (0...100))
func descuento_nuncaAumentaElPrecio(pct: Int) {
    let precio = Decimal(100)
    let out = aplicarDescuento(precio, Percentage(pct)!)
    #expect(out <= precio)              // ← invariante, no ejemplo
    #expect(out >= 0)
}
```

Herramientas por stack: SwiftCheck · Hypothesis (Python) · fast-check (TS) · jqwik (Java) · Kotest.
**Regla:** toda invariante declarada en `domain/SKILL.md` §Invariantes tiene su property test.

## Mutation score — cómo sabemos que los tests COMPRUEBAN algo

La cobertura es un piso, no una meta: un test sin aserciones da 100% de cobertura y 0 de
valor. La métrica real es el **mutation score** — se inyectan fallos en el código y se mide
qué porcentaje matan los tests.

> **Esto es lo que más importa con código escrito por IA.** La función objetivo de un
> agente es "que los tests pasen", y la forma más barata de conseguirlo es escribir tests
> que no comprueban nada. El mutation score es el único gate que distingue un test que
> verifica de uno que solo pasa.

```bash
bash tools/mutation-score.sh --check     # ¿estamos por encima del piso?
bash tools/mutation-score.sh --update    # sube el piso (SOLO sube)
```

**La pregunta de bolsillo** antes de dar un test por bueno:
*si rompo a propósito la lógica que este test dice cubrir, ¿falla?* Si no, es decorativo.

## Anti-patrones

- ❌ Escribir el test **después** de la implementación "para tener cobertura" — no es TDD y suele
  testear la implementación, no el comportamiento.
- ❌ Tests acoplados a detalles internos (privados, orden de llamadas **de la lógica pura**)
  → se rompen al refactorizar. Matiz importante: en la capa de ORQUESTACIÓN el orden de
  llamadas a los puertos sí es contrato — ver §Dobles de test (spy).
- ❌ Mocks que verifican "se llamó a X" **cuando la capa tiene un resultado observable**
  (lógica pura → aserta la salida). El spy es legítimo donde la interacción ES el
  comportamiento (orquestación), no como sustituto de asertar resultados.
- ❌ Lógica en la View/ViewModel que no se puede testear sin levantar UI → muévela a la capa pura.
- ❌ **Tests que pasan con cualquier implementación** (`#expect(resultado != nil)`, `XCTAssertNoThrow`
  como única aserción). Es el modo de fallo nº1 del código escrito por agentes: parece cobertura,
  no lo es. Lo caza el mutation score.
- ❌ **Un fake que no pasa la suite de conformidad del puerto** (`domain/SKILL.md`): tus tests
  verifican una semántica inventada, no la real.

## Qué exige el enforcement (no es solo doc)

| Gate | Qué comprueba |
|---|---|
| `tester` (sub-agente) | Escribe los tests siguiendo este loop |
| `reviewer` | RED si falta un comportamiento/riesgo o rama observable aplicable, **y si los tests pasan con cualquier implementación** |
| `check-drift.sh` | Señala lógica nueva sin archivo de test espejo (señal, no veredicto) |
| `tools/mutation-score.sh` | **El veredicto real**: piso de mutation score con trinquete que solo sube |
| DoD del PRD | "tests (happy + errores) verdes" es checkbox obligatorio de cierre |

El contexto completo de dónde encaja cada uno: `verification-loop.md`.

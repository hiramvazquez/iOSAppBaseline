---
name: domain
description: Referencia de la capa de dominio — entidades, puertos de repositorio, casos de uso, invariantes y errores de dominio. Invocar al escribir lógica de dominio o de datos. El dominio NO depende de UI ni de infraestructura.
when_to_use: Al crear o modificar una entidad, un puerto de repositorio, un caso de uso o un error de dominio. También al escribir un fake de repositorio — debe pasar la MISMA suite de conformidad que el adapter real.
paths:
  - "**/Domain/**"
  - "**/domain/**"
  - "**/Data/**"
  - "**/*UseCase*"
  - "**/*Logic*"
  - "**/*Repository*"
---

# Dominio — <PROJECT>

> Define el contrato puro del negocio. **Regla dura (universal):** el dominio **no importa** UI,
> frameworks de red, ni SDKs de backend. Ejemplos en Swift (iOS de referencia); el principio es
> agnóstico. Rellena los `<!-- FILL -->` con TU negocio. La lógica aquí es TDD-first (`process/references/tdd-workflow.md`).

## Entidades

Value types inmutables donde se pueda; sin lógica pesada ni dependencias de infra; `Sendable`.

```swift
struct Profile: Equatable, Sendable {
    let id: String
    let name: String
    let plan: Plan
}
enum Plan: String, Sendable { case free, pro }
```
<!-- FILL: tus entidades reales y sus invariantes. -->

## Puertos de repositorio (protocolos)

Define el puerto **por capability** ("LoadX", "SaveY"), no un repo gigante. `Sendable` donde aplique.

```swift
protocol LoadProfileUseCase: Sendable {            // puerto = capability, invocable como función
    func callAsFunction() async throws -> Profile
}
protocol ProfileRepository: Sendable {
    func fetch(id: String) async throws -> Profile
}
```
<!-- FILL: los puertos que tu lógica necesita. -->

## Casos de uso / reglas

Componen puertos + validaciones. Swift puro, testeable sin UI ni red (inyecta reloj/UUID, no `Date()`).

```swift
struct LoadProfile: LoadProfileUseCase {
    let repo: ProfileRepository
    let currentUserId: () -> String
    func callAsFunction() async throws -> Profile {
        try await repo.fetch(id: currentUserId())
    }
}
```
<!-- FILL: tus reglas de negocio reusables. -->

## Errores de dominio (tipados)

Errores **tipados**, no strings; nunca propagues el error crudo de infra a la UI. Mapea a `userMessage`.

```swift
enum ProfileError: Error, Equatable {
    case notFound, offline, unknown
    static func from(_ error: Error) -> ProfileError { (error as? ProfileError) ?? .unknown }
    var userMessageKey: String {            // i18n: clave, no texto suelto (ver AGENTS.md §3)
        switch self {
        case .notFound: "profile.error.notFound"
        case .offline:  "profile.error.offline"
        case .unknown:  "profile.error.unknown"
        }
    }
}
```
<!-- FILL: tu tipo de error de dominio y su mapeo a claves de localización (NO texto natural en la lógica). -->

## Invariantes (qué nunca debe pasar)

Un invariante es una afirmación que debe ser cierta **siempre**. Tienen tres formas de
existir, de menos a más fuerte — usa la más fuerte que puedas:

1. **Imposible por tipo** (lo mejor): si el estado inválido no se puede construir, no
   hay nada que verificar. Un `NonEmptyString` vence a cualquier validación.
2. **Aserción en el borde** (Design by Contract): precondición al entrar, postcondición
   al salir. Ver `process/references/tdd-workflow.md` §Aserciones.
3. **Property-based test**: declaras la propiedad y la herramienta busca contraejemplos.

<!-- FILL: invariantes que tests/CI deben proteger. Ej.: "un Profile con plan .pro siempre tiene método de pago". -->

## Mapa de utilidades compartidas (ANTES de escribir un helper, mira aquí)

> **El bug de contexto estrecho:** un sub-agente que solo ve su tarea no sabe que
> `String.isValidEmail` ya existe — así que escribe la suya, y el proyecto acaba con cinco
> validadores de email distintos (caso real). Este mapa es la vacuna: como esta skill es de
> lectura OBLIGATORIA antes de tocar lógica (matriz §11), todo agente entra sabiendo qué
> existe. **Regla dura: antes de crear un helper/extensión, buscas aquí y con Grep en el
> código. Si creas uno nuevo, lo AÑADES a este mapa en el mismo cambio** — un helper que no
> está en el mapa es un duplicado esperando a nacer.

| Utilidad | Dónde vive | Qué hace |
|---|---|---|
| <!-- FILL: ej. `String+Validation` --> | <!-- ej. `Shared/Extensions/String+Validation.swift` --> | <!-- ej. `isValidEmail`, `isBlank` --> |
| <!-- FILL: ej. `DateFormatting` --> | <!-- ej. `Shared/DateFormatting.swift` --> | <!-- ej. formato relativo i18n --> |

<!-- OPINIÓN: mantén el mapa pequeño y de grano grueso (archivos/namespaces, no cada
     función). Si crece a decenas de filas, agrupa por dominio. El reviewer verifica la
     regla (ítem "duplicación" de su checklist); si la duplicación reincide pese al mapa,
     añade un detector mecánico (jscpd o similar) en CI — lección→detector. -->

## Suite de conformidad puerto ↔ fake (regla dura)

> **Todo fake debe pasar exactamente la misma suite de tests que el adapter real.**

Es la técnica más barata del nivel 5 de `verification-loop.md`, y elimina de raíz la
categoría de bug más frustrante del testing con puertos: *los tests pasan con el fake y
explota en producción*, porque el fake se comporta como el agente **creyó** que se
comportaba el real.

Con agentes es especialmente valioso: un modelo que escribe un fake tiende a escribirlo
para que sus tests pasen, no para que replique la semántica real.

**El patrón:** escribes la suite UNA vez contra el protocolo, parametrizada por la
implementación. Luego la corres N veces, una por implementación.

```swift
// Tests/DomainTests/ProfileRepositoryConformance.swift
// UNA suite. Todas las implementaciones del puerto la pasan, o no son ese puerto.
func assertProfileRepositoryConformance(
    _ make: () -> ProfileRepository,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    // Contrato 1: un id inexistente lanza .notFound, NUNCA devuelve vacío ni nil.
    let repo = make()
    await #expect(throws: ProfileError.notFound) { try await repo.fetch(id: "no-existe") }

    // Contrato 2: fetch es idempotente para el mismo id.
    let a = try await repo.fetch(id: "u1")
    let b = try await repo.fetch(id: "u1")
    #expect(a == b)

    // <!-- FILL: un caso por cada garantía que el puerto PROMETE. Si el adapter
    //      real hace algo que el fake no, o es un bug del fake, o el contrato
    //      estaba mal escrito. En ambos casos quieres saberlo aquí. -->
}

@Test func fakeRepository_cumpleElContrato() async throws {
    try await assertProfileRepositoryConformance { FakeProfileRepository(seed: .standard) }
}

@Test(.tags(.integration))          // corre en CI, no en el loop local
func realRepository_cumpleElContrato() async throws {
    try await assertProfileRepositoryConformance { SupabaseProfileRepository(client: .test) }
}
```

**Regla de mantenimiento:** cuando añadas una garantía al puerto, la añades a la suite de
conformidad **en el mismo cambio**. Es la misma disciplina que la drift policy de
`AGENTS.md §9`: el contrato y su verificación viajan juntos.

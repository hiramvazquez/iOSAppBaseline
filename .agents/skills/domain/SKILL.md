---
name: domain
description: Referencia de la capa de dominio y de datos — entidades, puertos de repositorio, casos de uso, invariantes, errores de dominio y los adapters sobre CoreNetworking. El dominio NO depende de UI ni de infraestructura.
when_to_use: Al crear o modificar una entidad, un puerto de repositorio, un caso de uso, un error de dominio o un adapter en Data/. También al escribir un fake de repositorio — debe pasar la MISMA suite de conformidad que el adapter real.
paths:
  - "**/Domain/**"
  - "**/domain/**"
  - "**/Data/**"
  - "**/*UseCase*"
  - "**/*Logic*"
  - "**/*Repository*"
---

# Dominio y Datos — iOSAppBaseline

> **Regla dura:** el dominio **no importa** UI, ni `AppFoundation`, ni `CoreNetworking`.
> Lo prohíbe `tools/layers.conf:41` y lo verifica `check-layers.sh`. `Data/` **sí** importa
> `CoreNetworking` — ahí es donde vive el conocimiento del transporte.
>
> Editar `Sources/Data/**` exige también **`security/SKILL.md`**: es por donde entran las
> credenciales.

## Entidades

Value types inmutables, `Sendable`, sin lógica pesada ni dependencias de infra. No son «lo que
devuelve la API»: son lo que el dominio decidió que le importa.

```swift
public struct Movie: Equatable, Sendable, Identifiable {
    public let id: MovieID
    public let title: String

    /// Ruta relativa tal como la publica el proveedor (`/abc.jpg`). **No es una URL**:
    /// componerla exige base y tamaño, que son detalle de transporte.
    public let posterPath: String?

    /// Opcional porque una película recién estrenada puede no tener votos, y ese `nil`
    /// **es un dato, no un error**.
    public let voteAverage: Double?
}

/// Tipo propio y no un `Int` suelto, para que el compilador impida pasar un id de página
/// donde va un id de película. Hacer el estado inválido imposible por tipo (§14.0).
public struct MovieID: Hashable, Sendable {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
}
```

## Puertos de repositorio

Un puerto **por capability**, no un repositorio gigante. `Sendable`. Con **typed throws**, que
es lo que hace el dominio de error cerrado y verificable:

```swift
public protocol PopularMoviesRepository: Sendable {
    func popularMovies() async throws(MoviesError) -> [Movie]
}
```

## Errores de dominio — tipados, y **SIN `messageKey`**

```swift
public enum MoviesError: Error, Equatable, Sendable, CaseIterable {
    case offline, unauthorized, notFound, rateLimited, server
    case malformedResponse, connectionInterrupted, unknown
}
```

⚠️ **NO añadas `userMessageKey: String` ni `messageKey: String`.** Es la prescripción que este
proyecto **rechazó** tras verificarla (PRD 0001, bloqueante B4), y por una razón mecánica:
`ScreenError` de AppFoundation tiene dos inits de la misma aridad, uno de
`LocalizedStringResource` y uno `@_disfavoredOverload` de `String` que guarda el valor
**verbatim**. Una clave de runtime cae siempre en el segundo, así que la pantalla mostraría
`movies.error.offline` tal cual. Además, las claves construidas en runtime **no las extrae** el
String Catalog.

**En su lugar**, el copy vive en `Features/` como un `switch` exhaustivo con literales
`LocalizedStringResource` (ver `architecture/platforms/ios.md` §5). El dominio no conoce la UI.

`CaseIterable` está a propósito: permite que el test de «dos casos no comparten copy» itere
`allCases` en vez de una lista escrita a mano que envejece en silencio.

## Invariantes

De más fuerte a más débil — **usa siempre la más fuerte posible**:

1. **Imposible por tipo** (lo mejor): si el estado inválido no se puede construir, no hay nada
   que verificar. `MovieID` frente a un `Int` suelto es exactamente esto.
2. **Aserción en el borde** (precondición/postcondición), para errores de programación.
3. **Property-based test**, cuando la regla vale para todos los valores y no para tres ejemplos.

Input recuperable se valida con **tipos y errores explícitos**, nunca con un crash.

## Mapa de utilidades compartidas

> **Antes de crear un helper, busca aquí y con Grep.** Si creas uno nuevo, lo AÑADES aquí en el
> mismo cambio — un helper que no está en el mapa es un duplicado esperando a nacer.

| Utilidad | Dónde vive | Qué hace |
|---|---|---|
| `TMDBConfiguration` | `Data/Movies/TMDBConfiguration.swift` | Construye `NetworkingConfiguration` desde el bundle; falla cerrada sin credencial |
| `TMDBDTOs` | `Data/Movies/TMDBDTOs.swift` | DTOs de transporte + `asMovie` (frontera, NO dominio) |
| *(aún no hay helpers de formato ni de validación — añádelos aquí al crearlos)* | | |

---

# La capa `Data/` — adapters sobre CoreNetworking

## Estructura de un adapter

```swift
import Foundation
import CoreNetworking

struct TMDBPopularMoviesRepository: PopularMoviesRepository {
    private let api: any APIServiceProtocol       // el PROTOCOLO, nunca la clase

    init(api: any APIServiceProtocol) { self.api = api }

    func popularMovies() async throws(MoviesError) -> [Movie] {
        do {
            // ⚠️ El tipo de Response NO se infiere del Request: hay que anotarlo.
            let pagina: PopularMoviesPageDTO = try await api.execute(request: PopularMoviesRequest())
            return pagina.results.map(\.asMovie)
        } catch {
            throw Self.mapear(error)              // typed throws: `error` YA es APIError
        }
    }
}
```

Depender de `APIServiceProtocol` y no de `APIService` no es estilo: la clase es `final`, posee
una `URLSession` real y no es sustituible. El protocolo es lo único mockeable.

⚠️ **`Response` es un genérico libre**, no un `associatedtype` de `BaseRequest`. Nada ata
`PopularMoviesRequest` a `PopularMoviesPageDTO`: si omites la anotación no compila, y si pones
el DTO equivocado **compila y falla en runtime** con `.decodingError`. Un `typealias` por
request lo mitiga.

## El request

Solo `path` y `method` son obligatorios (más `typealias Parameters` cuando no hay body); el
resto tiene default: `headers` = `["Content-Type": "application/json"]`, `parameters` = `nil`,
`queryItems` = `nil`, `timeoutInterval` = 30 s, `allowsNonIdempotentRetry` = `false`.

```swift
/// La credencial **no viaja aquí**: va en `defaultHeaders` como `Authorization: Bearer`.
private struct PopularMoviesRequest: BaseRequest {
    typealias Parameters = EmptyParameters        // obligatorio: no hay body
    var path = "/3/movie/popular"
    var method: HTTPMethod = .GET
    var headers: [String: String] = [:]           // un GET no necesita Content-Type
    var queryItems: [URLQueryItem]?
}
```

⚠️ **Sobrescribir `headers` sustituye, no fusiona**: un POST con `headers: [:]` va sin
`Content-Type`.
⚠️ **No existe `makeEncoder`.** `makeDecoder` sí es configurable, pero los bodies se serializan
con un `JSONEncoder()` desnudo: si tu backend quiere `snake_case` al escribir, van `CodingKeys`
a mano en cada `RequestParameters`.

## Los DTOs, en su propio archivo

```swift
struct MovieDTO: Decodable, Sendable {
    let id: Int
    let title: String
    let posterPath: String?
    let voteAverage: Double?

    /// `CodingKeys` explícitas y no `.convertFromSnakeCase`: la traducción se lee **aquí**,
    /// delante de quien la mantiene, en vez de ocurrir por una estrategia global invisible.
    enum CodingKeys: String, CodingKey {
        case id, title
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
    }

    var asMovie: Movie {
        Movie(id: MovieID(id), title: title, posterPath: posterPath, voteAverage: voteAverage)
    }
}
```

`BaseResponse` es un alias vacío de `Decodable` y **no lo exige ninguna firma** — tus DTOs no
necesitan conformarlo.

## El mapeo de errores

El adapter decide **solo lo que es juicio de su dominio**; el resto lo delega a
`TransportError` de CoreNetworking, que centraliza el mapeo por código HTTP.

```swift
private static func mapear(_ error: APIError) -> MoviesError {
    switch error {                       // SIN `default:`: un caso nuevo del paquete debe
    case .cancelled:                     // romper la compilación, no degradarse en silencio
        // El único discriminador: si NUESTRA Task está cancelada, la pedimos nosotros.
        return Task.isCancelled ? .unknown : .connectionInterrupted
    case .decodingError:
        return .malformedResponse        // un JSON raro NO es «cero resultados»
    case .httpStatus(404, _), .custom(_, 404, _):
        return .notFound                 // qué significa un 404 aquí es decisión del dominio
    case .httpStatus, .custom, .networkError, .certificateValidationFailed,
         .invalidURL, .invalidResponse, .encodingError, .unknown:
        return mapearTransporte(TransportError(from: error))
    }
}
```

`TransportError` **no lleva payloads `String` a propósito**: `APIError.custom` arrastra el
mensaje crudo del servidor y esta conversión lo descarta, quedándose solo con el `statusCode`.
Eso sostiene por construcción la garantía de que ningún error propagado contiene la credencial
ni texto del servidor, y hay un test centinela en el paquete que lo vigila.

⚠️ **Un JSON inesperado es un fallo, no una lista vacía.** Degradarlo a `[]` esconde una
rotura de contrato detrás de una pantalla de «no hay resultados».
⚠️ **Deja pasar `CancellationError` sin traducir.** `performLoad` de AppFoundation solo captura
ese tipo exacto; un adapter que lo convierta en un error propio hará que la pantalla pinte un
error tras una simple navegación.
⚠️ `.certificateValidationFailed` **es inalcanzable por el pipeline real**: un fallo de pinning
llega como `.networkError`. Cubrirlo en el `switch` es defensivo, no un detector de MITM.

## La credencial

```swift
enum TMDBConfiguration {
    private static let placeholder = "pon_aqui_tu_token_de_lectura"

    /// `leer` es inyectable **porque los tests corren sin `Secrets.xcconfig`**: está
    /// gitignorado y en CI no existe.
    static func live(
        leer: (String) -> String? = { Bundle.main.object(forInfoDictionaryKey: $0) as? String }
    ) -> NetworkingConfiguration? {
        guard let host = leer("TMDBHost"), !host.isEmpty,
              let token = leer("TMDBReadAccessToken"),
              !token.isEmpty, token != placeholder,       // falla cerrada ante el placeholder
              let baseURL = URL(string: "https://\(host)")
        else { return nil }                               // sin credencial NO se construye cliente

        return NetworkingConfiguration(
            baseURL: baseURL,
            // ⚠️ En CABECERA, nunca en la query: el interceptor de logs redacta los headers
            // sensibles SIEMPRE, pero loguea la URL entera sin redactar.
            defaultHeaders: ["Authorization": "Bearer \(token)"],
            environment: "production"
        )
    }
}
```

Cuatro decisiones que van juntas: **cabecera y no query** · **devuelve `Optional` en vez de
crashear** (sin credencial no se construye un cliente que solo produciría 401s) · **rechaza el
placeholder explícitamente** (un 401 no dice «no rellenaste el xcconfig») · **la lectura del
bundle es inyectable** (si no, la lógica es intestable justo en CI).

`environment` es **puro metadato**: nada del paquete lo lee. El timeout es **por request**, y
el pinning entra por el init de `APIService`, no por `NetworkingConfiguration`.

---

# Tests

## Suite de conformidad puerto ↔ fake (regla dura)

> **Todo fake pasa exactamente la MISMA suite que el adapter real.**

Elimina de raíz el bug más caro del testing con puertos: los tests pasan con el fake y explota
en producción, porque el fake se comporta como quien lo escribió **creyó** que se comportaba el
real. Con agentes es aún más valioso: un modelo tiende a escribir el fake para que sus tests
pasen, no para que replique la semántica.

Escribes la suite **una vez** contra el protocolo y la corres **N veces**, una por
implementación. **Cuando añadas una garantía al puerto, la añades a la suite en el mismo
cambio.**

Declara explícitamente qué implementaciones están bajo conformidad y cuáles no: los *stubs de
escenario* (uno que siempre lanza, uno que cuenta invocaciones) están exentos porque no
pretenden ser el puerto — pero la exención se **escribe**, no se asume.

## Tests de repositorio: `MockURLProtocol` con `APIService` real

Para probar el repositorio se usa el pipeline entero — es el único modo de verificar que tus
`CodingKeys` y tu mapeo de errores funcionan de verdad.

```swift
private func sut(host: String, respuesta: MockResponse) -> TMDBPopularMoviesRepository {
    let baseURL = URL(string: "https://\(host)")!
    MockURLProtocol.register(MockNetworkExchange(
        url: baseURL.appendingPathComponent("3/movie/popular"),   // URL EXACTA
        response: respuesta
    ))
    return TMDBPopularMoviesRepository(
        api: APIService(
            configuration: NetworkingConfiguration(
                baseURL: baseURL,
                defaultHeaders: ["Authorization": "Bearer token-de-prueba-no-real"],
                protocolClasses: [MockURLProtocol.self]
            ),
            retryPolicy: .noRetry        // ⚠️ sin esto, cada test de error hace 3 requests
        )
    )
}
```

### ⚠️ La trampa del aislamiento — mordió de verdad

El registro de `MockURLProtocol` es **estático y compartido por todo el proceso**, y Swift
Testing **paraleliza las suites**. Tres reglas:

1. **Un host distinto por test** (`tmdb-401.test`, `tmdb-500.test`). El matching es por URL
   exacta, así que dos suites nunca colisionan.
2. **NUNCA llames a `removeAll()`**: borrarías los mocks de las suites vecinas. Ya pasó — dejó
   cinco tests de cancelación en rojo, con un fallo que no tenía nada que ver con lo que se
   probaba.
3. **Filtra `recordedRequests` por host** al contar peticiones: graba también las que no tienen
   mock.

Los mocks son inmutables y reutilizables: acumularlos no molesta.

---

# Trampas de CoreNetworking que muerden desde `Data/`

- **`Retry-After` NO está acotado por `maxDelay`.** Un servidor que responda `Retry-After: 3600`
  hace dormir al cliente una hora; el backoff configurado no interviene. Solo lo corta cancelar
  la `Task`. Si el servidor no es de fiar, `.noRetry` o un `shouldRetry` propio.
- **`DELETE` y `PUT` reintentan por defecto** (son idempotentes por RFC 9110). `POST` y `PATCH`
  no, salvo `allowsNonIdempotentRetry = true` — actívalo solo si el endpoint deduplica
  server-side con clave de idempotencia.
- **`maxAttempts` cuenta requests TOTALES**, no reintentos: `3` son 3 peticiones.
- **`isRetryable` no la llames tú**: cuando el error te llega, el retry ya ocurrió y se agotó.
  Sirve solo para decidir si ofreces botón de reintentar.
- **`upload`/`download` exigen `progress:` explícito** si la variable está tipada como el
  protocolo (los requisitos de protocolo no admiten argumentos por defecto).
- **`EmptyResponse` no sirve para un 204**: `execute` decodifica siempre, y `Data()` vacío lanza
  `.decodingError`. Para respuestas sin cuerpo, `download`.
- **`baseURL` inválida crashea en construcción** (`precondition`), no en el primer request.
- **`validated()` / `isValid` / `requestDescription` son API pública muerta**: `execute` nunca
  los llama. No confíes en que el paquete valide tu `path`.

## ⚠️ Trampa de workflow: editar el SPM no cambia nada

`spm-pro/CoreNetworking` es un **monorepo**; el paquete publicado es un *subtree split* en la
rama `cn-only`, y la app resuelve **por tag** desde GitHub. Editar el paquete en local **no
afecta a la app** hasta que hagas re-split, tag nuevo y re-fijes `Package.resolved`. Sin eso
aparece el clásico «pero si ya lo arreglé».

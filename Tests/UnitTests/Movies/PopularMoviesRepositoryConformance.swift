import Testing
import Foundation
import CoreNetworking
import CoreNetworkingTestSupport
@testable import iOSAppBaseline

/// La suite de conformidad del puerto `PopularMoviesRepository`.
///
/// Se escribe **una vez** contra el protocolo y se corre **N veces**, una por
/// implementación (`domain/SKILL.md` §Suite de conformidad). Es lo que impide
/// la categoría de bug más cara del testing con puertos: los tests pasan con el
/// fake y explota en producción, porque el fake se comporta como quien lo
/// escribió **creyó** que se comportaba el real.
///
/// Lo que verifica hoy: que **toda implementación del puerto devuelve exactamente
/// el mismo `[Movie]`** a partir de la misma fuente. No solo los ids: la entidad
/// entera. Si el adapter mapeara `original_title` en vez de `title`, perdiera
/// `voteAverage`, o convirtiera un `poster_path: null` en `""`, el fake y el real
/// divergirían y **es aquí donde se ve** — que es el único motivo por el que esta
/// suite existe.
///
/// **Qué implementaciones están bajo conformidad, y cuáles no.** En el árbol hay
/// seis tipos que implementan `PopularMoviesRepository`, y meterlos a todos aquí
/// sería un error: no todos pretenden ser el puerto.
///
/// - **Fake de referencia** (uno por puerto, OBLIGADO a pasar esta suite):
///   `FakePopularMoviesRepository`, aquí abajo.
/// - **Adapter real** (obligado): `TMDBPopularMoviesRepository`.
/// - **Stubs de escenario** (exentos): `FakePopularMovies`, `RepoQueFalla`,
///   `FakeRepo`, `RepoConPeliculas`. Están configurados para producir UN
///   resultado concreto —lanzar, devolver vacío, contar invocaciones— para
///   probar OTRA capa. No pretenden ser implementaciones fieles del contrato.
/// - **Null object de composition root** (exento y declarado):
///   `SinCredencialRepository` en `BaselineApp.swift`. Siempre lanza
///   `.unauthorized`, así que por construcción no puede pasar el camino feliz.
///   Es una decisión legítima; lo que no sería legítimo es que existiera sin
///   estar declarada aquí.
///
/// **Regla de mantenimiento:** cuando añadas una garantía al puerto, la añades
/// aquí en el mismo cambio. El contrato y su verificación viajan juntos.

/// El catálogo canónico. Toda implementación bajo conformidad devuelve
/// exactamente esto, para que C3 (orden) sea comprobable sin acoplar la suite a
/// una fuente concreta.
@MainActor enum CatalogoDeConformidad {
    static let esperadas: [Movie] = [
        Movie(id: MovieID(438_631), title: "Dune", posterPath: "/dune.jpg", voteAverage: 8.1),
        Movie(id: MovieID(329_865), title: "Arrival", posterPath: nil, voteAverage: 7.6),
    ]

    /// La misma lista, en la forma real de `/3/movie/popular`, para que el
    /// adapter llegue al mismo resultado por su camino de verdad (HTTP +
    /// decodificación + mapeo) y no por un atajo del test.
    static let json = Data("""
    {
      "page": 1,
      "results": [
        {"id": 438631, "title": "Dune", "poster_path": "/dune.jpg", "vote_average": 8.1},
        {"id": 329865, "title": "Arrival", "poster_path": null, "vote_average": 7.6}
      ],
      "total_pages": 500,
      "total_results": 10000
    }
    """.utf8)
}

/// El fake canónico del puerto. **No** es un stub de escenario: es la
/// implementación de referencia, y por eso pasa esta misma suite.
@MainActor struct FakePopularMoviesRepository: PopularMoviesRepository {
    var resultado: Result<[Movie], MoviesError> = .success(CatalogoDeConformidad.esperadas)

    func popularMovies() async throws(MoviesError) -> [Movie] {
        switch resultado {
        case .success(let peliculas): return peliculas
        case .failure(let error): throw error
        }
    }
}

/// Las garantías del puerto que HOY son verificables. C1 y C5 no lo son, y el
/// cuerpo explica por qué cada una está fuera — un hueco declarado es una
/// decisión; uno silencioso es el fallo de §14.4.
///
/// C7 (toda salida de error es un `MoviesError`) **no aparece aquí a
/// propósito**: `throws(MoviesError)` lo hace imposible por tipo, y escribir un
/// test para algo que el compilador ya impide es una aserción decorativa
/// (AGENTS.md §5 — la forma más fuerte del invariante es la que no necesita
/// verificarse en runtime). Que el adapter mapee CADA error de transporte al
/// caso correcto sí se prueba, en su propia suite.
@MainActor func verificaConformidadDelPuerto(
    _ construir: () -> any PopularMoviesRepository,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let repositorio = construir()

    // C1 NO se asevera aquí, y es una corrección deliberada.
    //
    // La primera versión de esta suite hacía `#expect(!resultado.isEmpty)`, que
    // convierte «devolvió algo» en garantía del puerto. No lo es: una lista
    // vacía es un resultado VÁLIDO (§7 del PRD: «primera carga OK con 0
    // resultados → .empty»). Esa aserción era una propiedad del fixture, y
    // además dejaba fuera de la suite a cualquier implementación legítima que
    // devuelva vacío. Lo que C1 promete de verdad —nunca `nil`— lo garantiza el
    // tipo de retorno `[Movie]`, así que no hay nada que verificar en runtime.
    let resultado = try await repositorio.popularMovies()

    // C2 se RETIRÓ del contrato el 2026-08-28 (decisión del owner, OQ-17,
    // ledger f-f6b72573). Prometía «los ids del resultado son únicos», y eso es
    // incompatible con C3: si la fuente devolviera un id repetido, cumplir C2
    // exigiría deduplicar y deduplicar es reordenar lo que dio la fuente. Las
    // dos no pueden ser ciertas a la vez.
    //
    // La aserción que había aquí pasaba solo porque el fixture trae dos ids
    // distintos — una propiedad del fixture, no del contrato. Es la tercera vez
    // en este archivo que aparece esa patología (C1 y C5 fueron las otras dos),
    // y merece decirse en voz alta: **un test que solo puede pasar porque el
    // dato de prueba se eligió así no está verificando el contrato.**
    //
    // El puerto NO deduplica. La unicidad la impone el acumulador de paginación
    // (T-P-6), que es quien tiene el estado donde un duplicado importa.
    // C3 — el orden es el que dio la fuente. El puerto no reordena.
    //
    // Se compara la ENTIDAD COMPLETA, no solo los ids, y la diferencia no es
    // cosmética: con `map(\.id)` esta suite pasaba aunque el adapter mapeara mal
    // `title`, `posterPath` o `voteAverage`. Es decir, prometía «toda
    // implementación devuelve exactamente esto» y solo comprobaba el orden de
    // los identificadores — la divergencia fake↔real, que es justo lo que esta
    // suite existe para cazar, la habría cazado únicamente la suite propia del
    // adapter, que es de la que el patrón existe para no depender.
    #expect(
        resultado == CatalogoDeConformidad.esperadas,
        "el resultado no coincide con el catálogo canónico (orden, mapeo de campos, o ambos)",
        sourceLocation: sourceLocation
    )

    // C5 tampoco se asevera, y esto es lo que más importa de esta corrección.
    //
    // La primera versión hacía `#expect(segunda == primera)` tras llamar dos
    // veces. Es LITERALMENTE la forma que el design-review del 2026-08-27 había
    // rechazado (bloqueante B2): con la fuente fija por `MockURLProtocol`, esa
    // aserción verifica que el mock devuelve lo mismo dos veces —cosa que el
    // mock hace por construcción—, no que el repositorio carezca de estado.
    // No podía fallar por la razón que decía cubrir, que es la definición de
    // test decorativo (AGENTS.md §5).
    //
    // C5 solo es observable con un puerto que admita más de una operación
    // distinguible: pedir A, pedir B, volver a pedir A y comprobar que B no
    // alteró A. `popularMovies()` no toma parámetros, así que hoy no hay dos
    // operaciones que distinguir y **la garantía no es verificable**. Entra en
    // esta suite cuando exista el primer cliente que pueda romperla — el
    // decorador de caché de §16.2 del PRD.
    //
    // Dejarla fuera y decir por qué es honesto. Dejar la aserción anterior
    // habría sido peor que no tener ninguna: ocupaba el hueco de cobertura de
    // C5 sin cubrirlo, y en verde.
}

@MainActor
@Suite("PopularMoviesRepository — conformidad del puerto")
struct PopularMoviesRepositoryConformanceTests {

    @Test("el fake cumple el contrato del puerto")
    func elFakeCumpleElContrato() async throws {
        try await verificaConformidadDelPuerto {
            FakePopularMoviesRepository()
        }
    }

    /// La misma suite, contra el adapter de verdad. Si el fake y el real
    /// divergen, es aquí donde se ve — que es el único motivo por el que esta
    /// suite existe.
    ///
    /// Host propio y sin `removeAll()`: el registro de `MockURLProtocol` es
    /// estático y compartido, y Swift Testing paraleliza las suites.
    @Test("el adapter real cumple el mismo contrato")
    func elAdapterRealCumpleElContrato() async throws {
        try await verificaConformidadDelPuerto {
            let baseURL = URL(string: "https://tmdb-conformidad.test")!
            MockURLProtocol.register(MockNetworkExchange(
                url: baseURL.appendingPathComponent("3/movie/popular"),
                response: MockResponse(statusCode: 200, data: CatalogoDeConformidad.json)
            ))
            return TMDBPopularMoviesRepository(
                api: APIService(
                    configuration: NetworkingConfiguration(
                        baseURL: baseURL,
                        defaultHeaders: ["Authorization": "Bearer token-de-prueba-no-real"],
                        protocolClasses: [MockURLProtocol.self]
                    ),
                    retryPolicy: .noRetry
                )
            )
        }
    }
}

import Testing
import Foundation
import CoreNetworking
import CoreNetworkingTestSupport
@testable import iOSAppBaseline

/// El adapter real contra TMDB, sin salir a la red.
///
/// `MockURLProtocol` intercepta **todo** (`canInit` devuelve `true` siempre),
/// así que ni un byte llega a internet y la credencial de estos tests es
/// ficticia por construcción.
///
/// ⚠️ Aislamiento: el registro del mock es **estático y compartido**, y Swift
/// Testing paraleliza las suites. Estos tests usan **un host distinto cada uno**
/// y NO llaman a `removeAll()`, que borraría los mocks de las suites vecinas.
/// (Es la trampa documentada en el README de `CoreNetworking`, y mordió de
/// verdad al escribir los tests del decoder.)
@Suite("TMDBPopularMoviesRepository — slice 0")
struct TMDBPopularMoviesRepositoryTests {

    /// Forma real de `/3/movie/popular`, recortada a los campos que el slice 0
    /// consume. Los nombres son los de TMDB (`snake_case`), que es justo lo que
    /// obliga a `CodingKeys` explícitas.
    private static let paginaPopulares = Data("""
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

    private func sut(host: String, respuesta: MockResponse) -> TMDBPopularMoviesRepository {
        let baseURL = URL(string: "https://\(host)")!
        MockURLProtocol.register(MockNetworkExchange(
            url: baseURL.appendingPathComponent("3/movie/popular"),
            response: respuesta
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

    // MARK: - Camino feliz: el mapeo DTO → entidad

    @Test("decodifica la página y mapea a entidades de dominio")
    func decodificaYMapea() async throws {
        let repo = sut(host: "tmdb-feliz.test", respuesta: MockResponse(statusCode: 200, data: Self.paginaPopulares))

        let peliculas = try await repo.popularMovies()

        #expect(peliculas.count == 2)
        #expect(peliculas[0] == Movie(id: MovieID(438_631), title: "Dune",
                                      posterPath: "/dune.jpg", voteAverage: 8.1))
        // `poster_path: null` es un dato válido, no un error: hay películas sin
        // póster y la vista debe poder pintarlas.
        #expect(peliculas[1].posterPath == nil)
        // C3: el orden es el de la fuente, el puerto no reordena.
        #expect(peliculas.map(\.id) == [MovieID(438_631), MovieID(329_865)])
    }

    // MARK: - Errores mapeados

    @Test("401 → .unauthorized, y el mensaje no menciona la credencial")
    func noAutorizado() async {
        let repo = sut(host: "tmdb-401.test", respuesta: MockResponse(statusCode: 401))

        await #expect(throws: MoviesError.unauthorized) {
            try await repo.popularMovies()
        }
    }

    @Test("500 → .server")
    func errorDelServidor() async {
        let repo = sut(host: "tmdb-500.test", respuesta: MockResponse(statusCode: 500))

        await #expect(throws: MoviesError.server) {
            try await repo.popularMovies()
        }
    }

    @Test("429 → .rateLimited")
    func demasiadasPeticiones() async {
        let repo = sut(host: "tmdb-429.test", respuesta: MockResponse(statusCode: 429))

        await #expect(throws: MoviesError.rateLimited) {
            try await repo.popularMovies()
        }
    }

    /// Un JSON que no entendemos es un fallo, **no «cero resultados»**.
    /// Degradarlo a lista vacía escondería una rotura de contrato detrás de una
    /// pantalla de «no hay películas».
    @Test("JSON con forma inesperada → .malformedResponse, NUNCA lista vacía")
    func respuestaMalformada() async {
        let repo = sut(host: "tmdb-malformado.test",
                       respuesta: MockResponse(statusCode: 200, data: Data(#"{"resultados": []}"#.utf8)))

        await #expect(throws: MoviesError.malformedResponse) {
            try await repo.popularMovies()
        }
    }

    /// El par de OQ-14, mitad B: el transporte cancela **sin** que nuestra Task
    /// lo pidiera (sesión invalidada). No es una cancelación propia, así que no
    /// se silencia: se convierte en un error recuperable con reintentar.
    ///
    /// Junto con `cancelacionPropia` de abajo forman un **par**: por separado
    /// ninguno mata los dos mutantes («siempre cancelled» y «nunca cancelled»).
    @Test("URLError.cancelled con la Task VIVA → .connectionInterrupted, no cancelación")
    func cancelacionDeTransporteConLaTaskViva() async {
        let baseURL = URL(string: "https://tmdb-cancel-transporte.test")!
        MockURLProtocol.register(MockNetworkExchange(
            url: baseURL.appendingPathComponent("3/movie/popular"),
            response: MockResponse(statusCode: 200),
            error: URLError(.cancelled)
        ))
        let repo = TMDBPopularMoviesRepository(
            api: APIService(
                configuration: NetworkingConfiguration(baseURL: baseURL,
                                                       protocolClasses: [MockURLProtocol.self]),
                retryPolicy: .noRetry
            )
        )

        await #expect(throws: MoviesError.connectionInterrupted) {
            try await repo.popularMovies()   // esta Task NO está cancelada
        }
    }

    @Test("la Task SÍ cancelada → el error es de cancelación, no .connectionInterrupted")
    func cancelacionPropia() async {
        let baseURL = URL(string: "https://tmdb-cancel-propia.test")!
        MockURLProtocol.register(MockNetworkExchange(
            url: baseURL.appendingPathComponent("3/movie/popular"),
            response: MockResponse(statusCode: 200, data: Self.paginaPopulares),
            latency: .milliseconds(500)
        ))
        let repo = TMDBPopularMoviesRepository(
            api: APIService(
                configuration: NetworkingConfiguration(baseURL: baseURL,
                                                       protocolClasses: [MockURLProtocol.self]),
                retryPolicy: .noRetry
            )
        )

        let tarea = Task { () -> MoviesError? in
            do {
                _ = try await repo.popularMovies()
                return nil
            } catch let error as MoviesError {
                return error
            } catch {
                return nil   // CancellationError: no es un MoviesError, y ese es el punto
            }
        }
        tarea.cancel()
        let error: MoviesError? = await tarea.value

        #expect(error != MoviesError.connectionInterrupted,
                "una cancelación pedida por nosotros no puede presentarse al usuario como fallo de conexión")
    }
}

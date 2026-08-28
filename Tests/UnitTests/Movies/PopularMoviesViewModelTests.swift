import Testing
import Foundation
import AppFoundation
@testable import iOSAppBaseline

/// El ViewModel del listado. Su comportamiento observable es la **fase de
/// pantalla** y las películas que expone, así que eso es lo que se asevera —
/// no «se llamó al repositorio», que sería acoplar el test a la implementación
/// (`tdd-workflow.md` §Dobles de test).
@MainActor
@Suite("PopularMoviesViewModel — slice 0")
struct PopularMoviesViewModelTests {

    /// Fake del puerto. Implementa el contrato real, no una semántica
    /// inventada: devuelve lo que se le configura, o lanza el `MoviesError`
    /// que se le configura. Nada más — el orden de llamadas no es el contrato
    /// de esta capa.
    private struct FakePopularMovies: PopularMoviesRepository {
        var resultado: Result<[Movie], MoviesError>

        func popularMovies() async throws(MoviesError) -> [Movie] {
            switch resultado {
            case .success(let peliculas): return peliculas
            case .failure(let error): throw error
            }
        }
    }

    private static let dune = Movie(id: MovieID(438_631), title: "Dune", voteAverage: 8.1)
    private static let arrival = Movie(id: MovieID(329_865), title: "Arrival", voteAverage: 7.6)

    // MARK: - Camino feliz

    @Test("cargar con películas → fase .content y las películas expuestas, en el orden de la fuente")
    func cargaConPeliculas() async {
        let sut = PopularMoviesViewModel(
            repository: FakePopularMovies(resultado: .success([Self.dune, Self.arrival]))
        )

        await sut.load().value

        #expect(sut.phase == .content)
        #expect(sut.movies == [Self.dune, Self.arrival])
    }

    /// Lista vacía **no** es un error: el proveedor respondió y no había nada.
    /// Confundirlos deja al usuario con una pantalla de error por un caso
    /// normal.
    @Test("cargar sin películas → fase .empty, no .content ni .error")
    func cargaVacia() async {
        let sut = PopularMoviesViewModel(
            repository: FakePopularMovies(resultado: .success([]))
        )

        await sut.load().value

        #expect(sut.phase == .empty)
        #expect(sut.movies.isEmpty)
    }

    // MARK: - Errores

    @Test("error del puerto → fase .error y sin películas a medias")
    func errorDelPuerto() async {
        let sut = PopularMoviesViewModel(
            repository: FakePopularMovies(resultado: .failure(.offline))
        )

        await sut.load().value

        guard case .error = sut.phase else {
            Issue.record("esperaba .error, hay \(sut.phase)")
            return
        }
        #expect(sut.movies.isEmpty)
    }

    /// El caso que motivó OQ-14. Una cancelación de transporte llega con la
    /// Task **viva**, así que `performLoad` no la filtra: si el ViewModel la
    /// dejara pasar como cancelación propia, la pantalla se quedaría en
    /// `.loading` **para siempre** — sin error, sin contenido y sin reintentar.
    /// La aserción es que NO se queda cargando; una aserción negativa sobre
    /// `.error` pasaría igual con la pantalla colgada.
    @Test("conexión interrumpida con la Task viva → NO se queda cargando")
    func conexionInterrumpidaNoDejaLaPantallaColgada() async {
        let sut = PopularMoviesViewModel(
            repository: FakePopularMovies(resultado: .failure(.connectionInterrupted))
        )

        await sut.load().value

        #expect(sut.phase != .loading(.fullScreen))
        #expect(sut.phase != .idle)
    }

    // MARK: - Estado inicial

    @Test("antes de cargar → fase .idle y sin películas")
    func estadoInicial() {
        let sut = PopularMoviesViewModel(
            repository: FakePopularMovies(resultado: .success([Self.dune]))
        )

        #expect(sut.phase == .idle)
        #expect(sut.movies.isEmpty)
    }
}

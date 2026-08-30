import Testing
import Foundation
import AppFoundation
@testable import iOSAppBaseline

/// El ViewModel del listado. Su comportamiento observable es la **fase de
/// pantalla** y las películas que expone, así que eso es lo que se asevera —
/// no «se llamó al repositorio», que sería acoplar el test a la implementación
/// (`tdd-workflow.md` §Dobles de test).
///
/// **Excepción deliberada a esa regla: la idempotencia.** «Cuántas veces se
/// llamó al puerto» sí es el contrato cuando lo que se verifica es que NO se
/// llame de más. Ahí el conteo no es un detalle interno: es el comportamiento.
@MainActor
@Suite("PopularMoviesViewModel — acciones")
struct PopularMoviesViewModelTests {

    /// Fake del puerto. Implementa el contrato real, no una semántica
    /// inventada: devuelve lo que se le configura, o lanza el `MoviesError`
    /// que se le configura.
    ///
    /// Cuenta invocaciones porque hay un caso —y solo uno— en que ese número
    /// es el contrato de esta capa: la carga inicial no debe repetirse.
    @MainActor
    private final class FakePopularMovies: PopularMoviesRepository {
        private(set) var invocaciones = 0
        var resultado: Result<[Movie], MoviesError>

        init(resultado: Result<[Movie], MoviesError>) {
            self.resultado = resultado
        }

        func popularMovies() async throws(MoviesError) -> [Movie] {
            invocaciones += 1
            switch resultado {
            case .success(let peliculas): return peliculas
            case .failure(let error): throw error
            }
        }
    }

    private static let dune = Movie(id: MovieID(438_631), title: "Dune", voteAverage: 8.1)
    private static let arrival = Movie(id: MovieID(329_865), title: "Arrival", voteAverage: 7.6)

    private static func sut(_ resultado: Result<[Movie], MoviesError>)
    -> (PopularMoviesViewModel, FakePopularMovies) {
        let repo = FakePopularMovies(resultado: resultado)
        return (PopularMoviesViewModel(repository: repo), repo)
    }

    // MARK: - Camino feliz

    @Test("alAparecer con películas → fase .content y las películas en el orden de la fuente")
    func cargaConPeliculas() async {
        let (sut, _) = Self.sut(.success([Self.dune, Self.arrival]))

        await sut.send(.alAparecer)

        #expect(sut.phase == .content)
        #expect(sut.movies == [Self.dune, Self.arrival])
    }

    /// Lista vacía **no** es un error: el proveedor respondió y no había nada.
    /// Confundirlos deja al usuario con una pantalla de error por un caso
    /// normal.
    @Test("alAparecer sin películas → fase .empty, no .content ni .error")
    func cargaVacia() async {
        let (sut, _) = Self.sut(.success([]))

        await sut.send(.alAparecer)

        #expect(sut.phase == .empty)
        #expect(sut.movies.isEmpty)
    }

    // MARK: - Idempotencia de la primera carga (f-31902e86)

    /// El bug que motivó este refactor. `PopularMoviesView` monta la carga en
    /// `.task`, y `.task` se re-dispara al re-montarse la vista — al volver del
    /// detalle, por ejemplo. Con `load()` llamando a `performLoad` sin
    /// condición, cada vuelta repintaba `.loading(.fullScreen)` sobre contenido
    /// que ya estaba y emitía otra petición.
    ///
    /// Y el daño no era solo el parpadeo: `popular` de TMDB **se reordena entre
    /// llamadas** (la no-garantía del puerto), así que la lista volvía barajada
    /// y la posición del scroll saltaba. El escenario golden 6 pide justo lo
    /// contrario.
    ///
    /// `MoviesScreenStore` salva la INSTANCIA del ViewModel; no salvaba el
    /// escenario. Esto sí.
    @Test("alAparecer dos veces → una sola petición: la carga inicial no se repite")
    func alAparecerEsIdempotente() async {
        let (sut, repo) = Self.sut(.success([Self.dune]))

        await sut.send(.alAparecer)
        await sut.send(.alAparecer)

        #expect(repo.invocaciones == 1, "la segunda aparición volvió a pedir al puerto")
        #expect(sut.phase == .content)
        #expect(sut.movies == [Self.dune])
    }

    /// La otra mitad del contrato: no basta con no repetir la petición, hay que
    /// no destruir lo que ya se mostraba. Un guard mal puesto podría dejar el
    /// conteo en 1 y aun así vaciar `movies` o volver a `.loading`.
    @Test("alAparecer sobre contenido ya cargado → ni repinta carga ni pierde las películas")
    func alAparecerNoDestruyeElContenido() async {
        let (sut, _) = Self.sut(.success([Self.dune, Self.arrival]))
        await sut.send(.alAparecer)

        await sut.send(.alAparecer)

        #expect(sut.phase == .content, "volvió a una fase que no es contenido")
        #expect(sut.movies == [Self.dune, Self.arrival], "perdió o reordenó las películas")
    }

    /// La rama de **recuperación** que el primer guard rompió (5ª review del
    /// refactor). `DefaultEmptyView` de AppFoundation **no ofrece reintentar** —
    /// a diferencia de `DefaultErrorView`, que sí trae el `retry` que
    /// `performLoad` asigna—, así que si `.alAparecer` tampoco recarga desde
    /// `.empty`, el usuario queda atrapado en «no hay películas» para siempre.
    ///
    /// Antes del refactor, un remontaje sí recuperaba (no había guard). El
    /// primer guard lo impedía: era una regresión de recuperabilidad
    /// introducida por el propio arreglo de idempotencia.
    @Test("alAparecer sobre .empty → vuelve a pedir: el usuario no queda atrapado")
    func alAparecerRecuperaDeVacio() async {
        let (sut, repo) = Self.sut(.success([]))
        await sut.send(.alAparecer)
        #expect(sut.phase == .empty)
        repo.resultado = .success([Self.dune])

        await sut.send(.alAparecer)

        #expect(repo.invocaciones == 2, "quedó atrapado en .empty sin forma de recargar")
        #expect(sut.phase == .content)
        #expect(sut.movies == [Self.dune])
    }

    // MARK: - Reintentar

    /// `reintentar` es una recarga explícita, así que **sí** vuelve a pedir.
    ///
    /// Ojo con la justificación fácil, que es falsa y estuvo escrita aquí: el
    /// botón de la pantalla de error **no** pasa por este caso — usa el `retry`
    /// de `ScreenError`, que `performLoad` asigna por su cuenta en el `catch`.
    /// `.reintentar` no tiene todavía call site en `Sources/`.
    ///
    /// La razón real de que sea un caso aparte del enum es que su contrato es
    /// el **opuesto** al de `alAparecer`: con un único `load()` esa distinción
    /// no era expresable, y por eso el bug de idempotencia pudo existir.
    @Test("reintentar tras un error → vuelve a pedir al puerto")
    func reintentarRecarga() async {
        let (sut, repo) = Self.sut(.failure(.offline))
        await sut.send(.alAparecer)
        repo.resultado = .success([Self.dune])

        await sut.send(.reintentar)

        #expect(repo.invocaciones == 2)
        #expect(sut.phase == .content)
        #expect(sut.movies == [Self.dune])
    }

    // MARK: - Errores

    @Test("error del puerto → fase .error y sin películas a medias")
    func errorDelPuerto() async {
        let (sut, _) = Self.sut(.failure(.offline))

        await sut.send(.alAparecer)

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
        let (sut, _) = Self.sut(.failure(.connectionInterrupted))

        await sut.send(.alAparecer)

        #expect(sut.phase != .loading(.fullScreen))
        #expect(sut.phase != .idle)
    }

    // MARK: - Estado inicial

    @Test("antes de cualquier acción → fase .idle, sin películas y sin tocar el puerto")
    func estadoInicial() {
        let (sut, repo) = Self.sut(.success([Self.dune]))

        #expect(sut.phase == .idle)
        #expect(sut.movies.isEmpty)
        #expect(repo.invocaciones == 0)
    }
}

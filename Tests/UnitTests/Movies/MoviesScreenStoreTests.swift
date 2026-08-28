import Testing
import Foundation
@testable import iOSAppBaseline

/// La identidad del ViewModel a través de la navegación (Trampa C / OQ-13).
///
/// Este es el test que **no se podía escribir** con `@State`: la identidad de
/// `@State` solo existe cuando SwiftUI instala la vista, y aquí no hay UI
/// tests. Con la factoría memoizada es un test corriente — y puede fallar,
/// que era el requisito que las dos versiones anteriores no cumplían.
@MainActor
@Suite("MoviesScreenStore — identidad a través de la navegación")
struct MoviesScreenStoreTests {

    private struct FakeRepo: PopularMoviesRepository {
        func popularMovies() async throws(MoviesError) -> [Movie] { [] }
    }

    @Test("dos invocaciones devuelven la MISMA instancia")
    func memoiza() {
        var construcciones = 0
        let store = MoviesScreenStore {
            construcciones += 1
            return PopularMoviesViewModel(repository: FakeRepo())
        }

        let primera = store.popular()
        let segunda = store.popular()

        #expect(primera === segunda,
                "cada push/pop reevalúa el closure de rutas: si aquí nace un ViewModel nuevo, el listado se vacía al volver del detalle")
        #expect(construcciones == 1, "la factoría solo debe construir una vez")
    }

    /// El efecto que de verdad le importa al usuario: lo cargado sobrevive.
    @Test("el contenido cargado sigue ahí en la segunda invocación")
    func conservaElContenido() async {
        let dune = Movie(id: MovieID(438_631), title: "Dune")
        let store = MoviesScreenStore {
            PopularMoviesViewModel(repository: RepoConPeliculas(peliculas: [dune]))
        }

        let vm = store.popular()
        await vm.handle(.alAparecer)
        #expect(vm.movies == [dune])

        // Simula la vuelta del detalle: el closure de rutas se reevalúa.
        let despuesDeNavegar = store.popular()

        #expect(despuesDeNavegar.movies == [dune],
                "volver atrás no puede vaciar el listado (escenario golden 6)")
    }

    private struct RepoConPeliculas: PopularMoviesRepository {
        let peliculas: [Movie]
        func popularMovies() async throws(MoviesError) -> [Movie] { peliculas }
    }
}

import Testing
import Foundation
import AppFoundation
@testable import iOSAppBaseline

/// G4 del PRD 0002: **el closure de rutas usa el store, no construye el
/// ViewModel inline**. Es el punto exacto donde la Trampa C reaparecería —
/// `CoordinatorView` reevalúa el closure en cada push/pop, y un ViewModel
/// nacido ahí dentro vuelve vacío al volver del detalle.
///
/// La aserción es sobre el CONTADOR de la factoría, no sobre la vista
/// (verificable sin UI tests, la misma razón por la que existe el store):
///   · si el builder construyera el VM inline, la factoría quedaría en 0;
///   · si usara el store pero la memoización se rompiera, subiría a N.
/// El `== 1` exacto mata los dos mutantes.
///
/// **Residuo declarado** (PRD §7): esto prueba el builder, no que
/// `AppCoordinatorView` le PASE el builder a `CoordinatorView`. Esa conexión
/// es una sola línea sin cuerpo, y su verificación de extremo a extremo llega
/// con el slice de detalle (cuando exista un push/pop real).
@MainActor
@Suite("MoviesRouteBuilder — G4: el closure de rutas usa el store")
struct MoviesRouteBuilderTests {

    @Test("N invocaciones para la misma ruta → UNA construcción: el builder pasa por el store")
    func elBuilderUsaElStoreMemoizado() {
        var construcciones = 0
        let store = MoviesScreenStore {
            construcciones += 1
            return PopularMoviesViewModel(repository: RepoVacio())
        }

        // Simula lo que CoordinatorView hace de verdad: reevaluar el closure
        // de rutas en cada navegación.
        _ = MoviesRouteBuilder.view(for: .listado, store: store)
        _ = MoviesRouteBuilder.view(for: .listado, store: store)
        _ = MoviesRouteBuilder.view(for: .listado, store: store)

        #expect(construcciones == 1,
                "cada reevaluación del closure debe REUSAR el ViewModel del store; \(construcciones) construcciones delatan la Trampa C")
    }

    /// Stub de escenario (exento de la suite de conformidad, como los demás):
    /// solo existe para que la factoría tenga algo que construir.
    private struct RepoVacio: PopularMoviesRepository {
        func popularMovies() async throws(MoviesError) -> [Movie] { [] }
    }
}

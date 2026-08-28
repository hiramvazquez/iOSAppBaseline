import Foundation

/// Dueño de los ViewModels del módulo de películas.
///
/// Existe por la **Trampa C** del PRD: `CoordinatorView` reevalúa el closure de
/// rutas en cada cambio del path, así que un ViewModel construido dentro de ese
/// closure se recrearía vacío en cada `push`/`pop` — el listado aparecería en
/// blanco al volver del detalle, sin error y sin carga.
///
/// **Por qué una factoría memoizada y no un `@State` en una vista-pantalla**
/// (OQ-13): `@State` solo tiene identidad cuando SwiftUI *instala* la vista, y
/// este proyecto no tiene UI tests que puedan instalarla. Un test unitario no
/// podría distinguir la implementación correcta de la rota. Con la factoría, el
/// test es corriente: dos invocaciones devuelven la misma instancia.
///
/// Vive en `App/` y no en `Features/` a propósito: es composition root, y el
/// composition root no es presentación.
@MainActor
final class MoviesScreenStore {
    private let makePopular: @MainActor () -> PopularMoviesViewModel
    private var popularVM: PopularMoviesViewModel?

    init(makePopular: @escaping @MainActor () -> PopularMoviesViewModel) {
        self.makePopular = makePopular
    }

    /// El ViewModel del listado. **Siempre la misma instancia**: es lo que hace
    /// que el contenido sobreviva a la navegación.
    func popular() -> PopularMoviesViewModel {
        if let popularVM { return popularVM }
        let nuevo = makePopular()
        popularVM = nuevo
        return nuevo
    }
}

import SwiftUI
import AppFoundation

/// La costura entre el `CoordinatorView` y las pantallas del módulo — **la
/// única forma de construir el closure de rutas** (PRD 0002 §7).
///
/// Existe por verificabilidad, no por gusto: el closure de rutas de
/// `CoordinatorView` se reevalúa en cada push/pop, y un ViewModel construido
/// inline ahí dentro se recrearía vacío (la Trampa C). Con el builder
/// extraído, G4 es un test corriente —invocarlo N veces y contar
/// construcciones en la factoría del store— y el residuo no verificado se
/// reduce a «¿`AppCoordinatorView` llama al builder?», una línea sin cuerpo.
///
/// El builder SOLO ENSAMBLA: pide instancias al store (memoizadas — misma
/// instancia siempre) y las envuelve en su vista. Nunca construye tipos
/// referencia.
@MainActor
enum MoviesRouteBuilder {
    @ViewBuilder
    static func view(for route: MoviesRoute, store: MoviesScreenStore) -> some View {
        switch route {
        case .listado:
            PopularMoviesView(viewModel: store.popular())
        }
    }
}

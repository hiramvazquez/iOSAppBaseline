import SwiftUI
import AppFoundation

/// Monta el `Coordinator<MoviesRoute>` sobre el `CoordinatorView` de
/// AppFoundation (PRD 0002, fase 2). Desde aquí, la navegación es del
/// coordinator: las vistas emiten intención y nadie vuelve a construir un
/// `NavigationStack` a mano.
///
/// El closure de rutas es **una sola línea sin cuerpo, a propósito**: delega
/// TODO en `MoviesRouteBuilder`, que es la costura que G4 verifica. Escribir
/// aquí un `switch` con vistas inline reintroduciría la Trampa C fuera del
/// alcance de cualquier test — es exactamente lo que este archivo existe para
/// impedir.
struct AppCoordinatorView: View {
    let coordinator: Coordinator<MoviesRoute>
    let store: MoviesScreenStore

    var body: some View {
        CoordinatorView(coordinator: coordinator) { MoviesRouteBuilder.view(for: $0, store: store) }
    }
}

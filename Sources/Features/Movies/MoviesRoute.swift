import Foundation

/// Las rutas del módulo de películas (PRD 0002, fase 2).
///
/// `Hashable` es el ÚNICO requisito que `Coordinator<Route>` impone. Vive en
/// `Features/` —es vocabulario de presentación, no de dominio— y no importa
/// nada de AppFoundation: el enum es solo datos; quien lo entiende es el
/// `Coordinator` del composition root.
///
/// Hoy una sola ruta. El caso `detalle(id:)` llega con su slice — añadirlo
/// aquí sin pantalla detrás sería un case sin destino, la misma ceremonia que
/// el PRD rechazó para el `Router` en el ViewModel.
enum MoviesRoute: Hashable {
    /// El listado de populares — la raíz del módulo.
    case listado
}

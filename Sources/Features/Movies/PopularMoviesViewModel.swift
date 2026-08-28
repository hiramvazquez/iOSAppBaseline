import Foundation
import AppFoundation

/// Orquesta la carga del listado de películas populares.
///
/// Hereda de `BaseViewModel`, que aporta la fase de pantalla (`idle`,
/// `loading`, `content`, `empty`, `error`) y `performLoad`, que además cancela
/// la carga anterior al empezar una nueva.
///
/// No conoce HTTP: depende del **puerto** `PopularMoviesRepository`. Esa es la
/// razón de que `layers.conf` prohíba a `*/Features/*` importar `CoreNetworking` — y
/// aquí no hace falta.
@MainActor
@Observable
final class PopularMoviesViewModel: BaseViewModel {
    private let repository: any PopularMoviesRepository

    /// Lo que la vista pinta. Se rellena solo cuando la carga tuvo éxito: un
    /// fallo no deja películas a medias en pantalla.
    private(set) var movies: [Movie] = []

    init(repository: any PopularMoviesRepository) {
        self.repository = repository
        super.init()
    }

    /// Lo que la pantalla puede pedir.
    ///
    /// Es un enum y no dos métodos sueltos porque las dos intenciones tienen
    /// **contratos opuestos sobre la repetición**: aparecer no debe recargar,
    /// reintentar debe hacerlo siempre. Con un único `load()` esa distinción no
    /// se podía expresar, y por eso no existía.
    enum Action: Equatable {
        /// La vista se montó. **Idempotente**: la primera carga ocurre una vez.
        case alAparecer
        /// Recarga explícita pedida por el usuario. **Siempre** vuelve a pedir.
        ///
        /// Hoy **no tiene call site en `Sources/`**, y conviene decirlo en vez
        /// de insinuar una cobertura que no existe: el botón de la pantalla de
        /// error usa el `retry` de `ScreenError`, que asigna `performLoad`. Este
        /// caso es el punto de entrada para una recarga explícita con UI propia
        /// —pull-to-refresh, un botón de la barra— y existe porque su contrato
        /// es el **opuesto** al de `alAparecer`: con un único `load()` esa
        /// distinción no era expresable, que es exactamente por lo que el bug de
        /// idempotencia pudo existir.
        case reintentar
    }

    /// El punto de entrada de la pantalla para **iniciar** trabajo.
    ///
    /// Matiz honesto: no es el único camino hacia una recarga. `ScreenError`
    /// lleva un `retry` que `BaseViewModel.performLoad` asigna por su cuenta en
    /// el `catch`, así que el botón de la pantalla de error recarga por esa vía
    /// —de AppFoundation— y no por `.reintentar`. Lo que sí garantiza este tipo
    /// es que **nadie puede saltarse el guard de idempotencia**: `load()` es
    /// `private`.
    func handle(_ action: Action) async {
        switch action {
        case .alAparecer:
            // La idempotencia de la primera carga (ledger `f-31902e86`).
            //
            // `.task` se re-dispara cada vez que la vista se re-monta —al volver
            // del detalle, por ejemplo—, y `performLoad` no distingue esa
            // segunda llamada de la primera: repintaba `.loading(.fullScreen)`
            // sobre contenido ya cargado y emitía otra petición. Como `popular`
            // de TMDB se reordena entre llamadas (la no-garantía del puerto), la
            // lista volvía barajada y el scroll saltaba.
            //
            // El guard mira la FASE y no un booleano `yaCargue` a propósito: la
            // fase ES el estado de esta pantalla, y un flag paralelo sería una
            // segunda fuente de verdad que se puede desincronizar de ella.
            //
            // `.empty` recarga, y no es un descuido. `DefaultEmptyView` de
            // AppFoundation **no ofrece reintentar** —a diferencia de
            // `DefaultErrorView`, que sí trae el `retry` que `performLoad`
            // asigna—, así que un guard que solo dejara pasar `.idle` dejaría al
            // usuario atrapado en «no hay películas» sin ninguna salida. Antes
            // del refactor un remontaje sí recuperaba: proteger la idempotencia
            // sin esto habría sido cambiar un bug por otro.
            switch phase {
            case .idle, .empty: await load().value
            case .loading, .content, .error: return
            }

        case .reintentar:
            await load().value
        }
    }

    /// Carga la primera página.
    ///
    /// `successTransition: .preserveCurrentPhase` porque la fase de éxito **la
    /// decide este método**, no `performLoad`: una respuesta vacía es `.empty`,
    /// no `.content`. Con la transición por defecto, una lista vacía habría
    /// pintado la pantalla de contenido sin nada dentro.
    @discardableResult
    private func load() -> Task<Void, Never> {
        performLoad(successTransition: .preserveCurrentPhase) { [weak self] in
            guard let self else { return }
            let peliculas = try await self.repository.popularMovies()
            self.movies = peliculas
            peliculas.isEmpty ? self.setEmpty() : self.setContent()
        }
    }
}

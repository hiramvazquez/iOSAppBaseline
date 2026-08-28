import SwiftUI
import CoreNetworking

@main
struct BaselineApp: App {
    /// Composition root: aquí, y solo aquí, se conocen las implementaciones
    /// concretas. Todo lo de abajo habla de puertos.
    @State private var store = MoviesScreenStore {
        PopularMoviesViewModel(repository: BaselineApp.repositorio())
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                PopularMoviesView(viewModel: store.popular())
            }
        }
    }

    /// El repositorio real, o uno que falla en claro si falta la credencial.
    ///
    /// No se cae ni se queda en blanco: sin `Config/Secrets.xcconfig` la app
    /// **compila y arranca**, y muestra el error de credencial en su sitio —
    /// la pantalla de error del listado. Un clon recién hecho nunca se rompe
    /// por un archivo que no está.
    private static func repositorio() -> any PopularMoviesRepository {
        guard let configuracion = TMDBConfiguration.live() else {
            return SinCredencialRepository()
        }
        return TMDBPopularMoviesRepository(api: APIService(configuration: configuracion))
    }
}

/// Lo que se usa cuando no hay credencial: lanza el error que corresponde en
/// vez de fingir que no hay películas.
private struct SinCredencialRepository: PopularMoviesRepository {
    func popularMovies() async throws(MoviesError) -> [Movie] {
        throw .unauthorized
    }
}

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

    /// Carga la primera página.
    ///
    /// `successTransition: .preserveCurrentPhase` porque la fase de éxito **la
    /// decide este método**, no `performLoad`: una respuesta vacía es `.empty`,
    /// no `.content`. Con la transición por defecto, una lista vacía habría
    /// pintado la pantalla de contenido sin nada dentro.
    @discardableResult
    func load() -> Task<Void, Never> {
        performLoad(successTransition: .preserveCurrentPhase) { [weak self] in
            guard let self else { return }
            let peliculas = try await self.repository.popularMovies()
            self.movies = peliculas
            peliculas.isEmpty ? self.setEmpty() : self.setContent()
        }
    }
}

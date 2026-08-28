import SwiftUI
import AppFoundation

/// El listado de películas populares.
///
/// Renderiza estado y emite intención; no decide nada. Las fases de pantalla
/// —cargando, vacío, error, contenido— las pinta `ScreenContainer`, así que
/// aquí no hay ni un `if phase == …` (prohibido por `architecture/SKILL.md`).
struct PopularMoviesView: View {
    @State private var viewModel: PopularMoviesViewModel

    init(viewModel: PopularMoviesViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        ScreenContainer(viewModel: viewModel, title: "Películas populares") {
            List(viewModel.movies) { pelicula in
                MovieRow(movie: pelicula)
            }
            .listStyle(.plain)
        }
        .task {
            // ⚠️ ESTO NO ES IDEMPOTENTE, y decir lo contrario era el problema.
            //
            // `load()` llama a `performLoad` **incondicionalmente**: cancela la
            // carga anterior, sí, pero cada re-disparo de `.task` vuelve a poner
            // `.loading(.fullScreen)` sobre contenido ya cargado y emite otra
            // petición. Y como `popular` de TMDB se reordena entre llamadas (la
            // no-garantía del puerto), la lista vuelve barajada y la posición
            // salta — que es justo lo que el escenario golden 6 pide conservar
            // al volver del detalle.
            //
            // `MoviesScreenStore` salva la INSTANCIA del ViewModel, no el
            // escenario. Falta el guard de «ya cargué», y su sitio es el
            // ViewModel: entra con el refactor a `enum Action` + `handle(_:)`.
            // Ledger `f-31902e86` (abierto, high).
            await viewModel.load().value
        }
    }
}

/// Una fila del listado.
///
/// Sin números sueltos de espaciado ni fuentes por tamaño: los estilos
/// semánticos de SwiftUI (`.headline`, `.subheadline`) respetan Dynamic Type
/// solos, que es justo lo que el slice de cierre tendrá que verificar.
private struct MovieRow: View {
    let movie: Movie

    var body: some View {
        VStack(alignment: .leading) {
            Text(movie.title)
                .font(.headline)

            if let nota = movie.voteAverage {
                // `formatted` respeta la configuración regional: en español
                // escribe «7,6», no «7.6». Un `String(format:)` no lo haría.
                Text(nota.formatted(.number.precision(.fractionLength(1))))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

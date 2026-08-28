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
            // La vista emite INTENCIÓN, no órdenes: no sabe si esto carga o no.
            // Esa decisión es del ViewModel, y `.alAparecer` es idempotente —
            // `.task` se re-dispara al re-montarse la vista (al volver del
            // detalle, por ejemplo) y la carga inicial ocurre una sola vez.
            //
            // Antes aquí se llamaba a `load()`, que entraba a `performLoad` sin
            // condición: cada vuelta repintaba `.loading(.fullScreen)` sobre
            // contenido ya cargado y emitía otra petición. Como `popular` de
            // TMDB se reordena entre llamadas (la no-garantía del puerto), la
            // lista volvía barajada y la posición saltaba — justo lo contrario
            // de lo que el escenario golden 6 pide conservar.
            //
            // `MoviesScreenStore` salva la INSTANCIA del ViewModel; el guard de
            // `handle(.alAparecer)` salva el escenario. Hacían falta los dos.
            await viewModel.handle(.alAparecer)
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

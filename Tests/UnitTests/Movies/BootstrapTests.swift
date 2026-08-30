import Testing
import Foundation
import AppFoundation
@testable import iOSAppBaseline

/// El criterio PRIMARIO de §3 del PRD 0002: el cableado REAL de la app, en
/// las dos direcciones. Un test que solo construyera tipos sueltos pasaría
/// con `BaselineApp` montando cualquier otra cosa; este invoca la misma
/// costura que la app usa en su arranque.
///
/// ⚠️ La dirección (a) asevera «NO es el fallback» y no «es
/// `TMDBPopularMoviesRepository`», **a propósito**: en CI no existe
/// `Config/Secrets.xcconfig`, así que el módulo registra
/// `SinCredencialRepository` — endurecer la aserción al tipo real rompería CI
/// siempre. No lo «arregles». (PRD 0002 §3.)
///
/// La invocación de `Coordinator<MoviesRoute>` + `MoviesRouteBuilder` que la
/// fila primaria también exige llega con la **fase 2**, que es la que crea
/// esos tipos. Este archivo se amplía entonces.
@MainActor
@Suite("BaselineApp.bootstrap — el grafo real")
struct BootstrapTests {

    @Test("con los módulos registrados, lo resuelto NO es el fallback de cableado roto")
    func conModulosNoCaeAlFallback() {
        let container = Container()
        var señales: [String] = []

        let repo = BaselineApp.bootstrap(container: container) { señales.append($0) }

        #expect(!(repo is CableadoRotoRepository),
                "el grafo real de la app cayó al fallback: el cableado está roto")
        #expect(señales.isEmpty,
                "el bootstrap emitió señal de mala configuración en el camino sano")
    }

    /// El RECÍPROCO que fija el arreglo de OQ-4 (6ª pasada del design-review):
    /// sin él, la mutación `?? SinCredencialRepository()` —el fail-silent que
    /// la 4ª pasada bloqueó— pasa todos los gates, porque «no es el fallback»
    /// se cumple más fácil con el tipo equivocado.
    ///
    /// Pasa un ESPÍA como `onMisconfiguration`: el default de producción hace
    /// `assertionFailure` y atraparía el runner (los tests corren en Debug).
    /// Y asevera TAMBIÉN que la señal se emitió: borrar el log o el assert del
    /// default no puede quedar gratis — este test muere si la señal desaparece
    /// del camino roto.
    @Test("con el grafo VACÍO, devuelve el fallback Y emite la señal — no falla en silencio")
    func sinGrafoCaeAlFallbackYLoSeñala() {
        let vacio = Container()
        var señales: [String] = []

        let repo = BaselineApp.bootstrap(
            container: vacio,
            modules: [],                      // el grafo NO se arma: cableado roto simulado
            onMisconfiguration: { señales.append($0) }
        )

        #expect(repo is CableadoRotoRepository,
                "un grafo vacío tiene que caer al fallback de cableado roto, no a otro tipo")
        #expect(!señales.isEmpty,
                "el camino roto tiene que EMITIR la señal: fail-silent nunca (AGENTS.md §6)")
    }

    /// El fallback lanza el mismo error vago que el caso sin credencial: al
    /// usuario no se le cuenta la causa (§6); la distinción es para el
    /// operador, vía la señal.
    @Test("el fallback lanza .unauthorized, como el caso sin credencial")
    func elFallbackLanzaElMismoError() async {
        let repo = CableadoRotoRepository()

        await #expect(throws: MoviesError.unauthorized) {
            try await repo.popularMovies()
        }
    }
}

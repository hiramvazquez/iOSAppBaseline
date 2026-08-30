import SwiftUI
import AppFoundation
import CoreNetworking
import os

@main
struct BaselineApp: App {
    /// Composition root: aquí, y solo aquí, se conocen las implementaciones
    /// concretas — vía los `DependencyModule` que el bootstrap registra. Todo
    /// lo de abajo habla de puertos.
    @State private var store: MoviesScreenStore

    init() {
        // La costura del arranque (PRD 0002 §7): la app pasa `.shared`; los
        // tests le pasan un contenedor propio y prueban EL MISMO grafo.
        let repositorio = BaselineApp.bootstrap(container: .shared)

        #if DEBUG
        // Aviso ADICIONAL, no la protección: corre DESPUÉS del bootstrap, así
        // que el fallback ya habría ocurrido — quien impide que un cableado
        // roto llegue a release es `BootstrapTests`, y quien lo señala en el
        // momento es el `onMisconfiguration` del propio bootstrap.
        Container.shared.validateRegistrations([(any PopularMoviesRepository).self])
        #endif

        _store = State(initialValue: MoviesScreenStore {
            PopularMoviesViewModel(repository: repositorio)
        })
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                PopularMoviesView(viewModel: store.popular())
            }
        }
    }

    /// Arma el grafo de la feature y resuelve su puerto — **la costura que un
    /// test puede invocar** con un contenedor propio (PRD 0002, criterio
    /// primario de §3).
    ///
    /// Registra EN EL CONTENEDOR RECIBIDO: sin eso, el test primario mutaría
    /// el global (prohibido) o probaría un grafo distinto del de la app.
    ///
    /// `onMisconfiguration` es la señal de **cableado roto** — un módulo no
    /// registrado, o registrado bajo el tipo estático equivocado. Se INYECTA
    /// (6ª pasada del design-review) porque el default de producción hace
    /// `assertionFailure`, que atraparía el runner de tests en Debug: el test
    /// recíproco pasa un espía y asevera que la señal se emitió. En release el
    /// assert desaparece, queda el log, y la app degrada al fallback en vez de
    /// crashear — la decisión de OQ-4, con la mitad visible que §6 exige.
    static func bootstrap(
        container: Container,
        modules: [any DependencyModule] = [MoviesModule()],
        onMisconfiguration: (String) -> Void = { mensaje in
            // La señal nombra la operación, nunca datos (security/SKILL.md):
            // aquí no viaja ninguna credencial, solo el nombre de un puerto.
            Logger(subsystem: "com.hiram.iOSAppBaseline", category: "Bootstrap")
                .error("\(mensaje, privacy: .public)")
            assertionFailure(mensaje)
        }
    ) -> any PopularMoviesRepository {
        container.register(modules: modules)

        guard let repositorio = container.tryResolve((any PopularMoviesRepository).self) else {
            onMisconfiguration("""
            Cableado roto: ningún módulo registró `any PopularMoviesRepository`. \
            NO es el caso «falta la credencial» — ese lo cubre MoviesModule \
            registrando SinCredencialRepository. Esto es un bug del grafo de DI.
            """)
            return CableadoRotoRepository()
        }
        return repositorio
    }
}

/// Lo que se usa cuando no hay credencial: lanza el error que corresponde en
/// vez de fingir que no hay películas. Lo registra `MoviesModule` cuando
/// `TMDBConfiguration.live()` devuelve `nil` — estado **esperado**, no bug.
struct SinCredencialRepository: PopularMoviesRepository {
    func popularMovies() async throws(MoviesError) -> [Movie] {
        throw .unauthorized
    }
}

/// El fallback del bootstrap cuando el grafo de DI está **roto** — jamás en
/// operación normal (con o sin credencial, `MoviesModule` siempre registra).
///
/// Es un tipo PROPIO y no `SinCredencialRepository` a propósito (PRD 0002,
/// 4ª pasada): reutilizarlo daría al mismo tipo dos causas indistinguibles
/// —estado esperado y bug— y dejaría G2 pasando con el cableado roto. El
/// usuario ve el mismo copy vago (§6: no se le cuenta la causa); el operador
/// distingue por la señal que `bootstrap` emite al caer aquí.
struct CableadoRotoRepository: PopularMoviesRepository {
    func popularMovies() async throws(MoviesError) -> [Movie] {
        throw .unauthorized
    }
}

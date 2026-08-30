import Foundation
import AppFoundation
import CoreNetworking

/// El módulo de DI de la feature de películas (PRD 0002, fase 1).
///
/// Vive en `App/` y no en `Features/` a propósito: registra implementaciones
/// concretas —construye el `APIService`, que es `CoreNetworking`— y
/// `layers.conf` prohíbe ese import a `*/Features/*`. Un `DependencyModule`
/// es, por definición, la lista de implementaciones concretas: composition
/// root, no presentación.
///
/// **El guard de la credencial vive AQUÍ** (PRD 0002 §7): sin
/// `Config/Secrets.xcconfig` el módulo registra `SinCredencialRepository`, así
/// que el contenedor SIEMPRE resuelve el puerto en operación normal — con
/// credencial o sin ella—. Con eso, el fallback del bootstrap
/// (`CableadoRotoRepository`) es alcanzable **únicamente por bug de cableado**,
/// que es exactamente lo que su señal debe reportar.
struct MoviesModule: DependencyModule {
    func register(in container: Container) {
        // El registro es bajo el TIPO DEL PUERTO, no el concreto: la clave de
        // `Container` es el tipo estático (`ios.md` §4 — registrar el concreto
        // y resolver el protocolo NO resuelve, y explota en runtime).
        //
        // `register` toma un autoclosure: la expresión se evalúa perezosamente
        // en la PRIMERA resolución, no aquí — el `APIService` no se construye
        // hasta que alguien pide el puerto, igual que hacía `repositorio()`.
        container.register(
            Self.hacerRepositorio() as any PopularMoviesRepository,
            lifecycle: .singleton
        )
    }

    /// El repositorio real, o el que falla en claro si falta la credencial.
    ///
    /// (Movido desde `BaselineApp.repositorio()` sin cambio de comportamiento:
    /// un clon recién hecho sigue compilando y arrancando sin `Secrets.xcconfig`,
    /// y muestra el error de credencial en la pantalla del listado.)
    private static func hacerRepositorio() -> any PopularMoviesRepository {
        guard let configuracion = TMDBConfiguration.live() else {
            return SinCredencialRepository()
        }
        return TMDBPopularMoviesRepository(api: APIService(configuration: configuracion))
    }
}

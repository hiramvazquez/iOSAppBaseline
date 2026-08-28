import Foundation
import AppFoundation

/// La traducción de un error de dominio al copy que ve el usuario.
///
/// Vive en `Features/` y no en `Domain/` a propósito: `ScreenError` es un tipo
/// de presentación, y el dominio no depende de la UI (AGENTS.md §3). Por eso
/// `MoviesError` no lleva `messageKey` — un `String` con una clave dentro
/// acabaría impreso verbatim en pantalla por el init `@_disfavoredOverload` de
/// `ScreenError`.
///
/// El `switch` es **exhaustivo y sin `default`** a propósito: al añadir un caso
/// nuevo a `MoviesError`, el compilador obliga a escribirle copy aquí. Es el
/// nivel 0 del bucle de verificación —hacerlo imposible por tipo— en vez de
/// confiar en que alguien se acuerde.
///
/// El `retry` no se decide aquí: `BaseViewModel` lo inyecta al mapear
/// (`retry ?? base.retry`), porque quién puede reintentar y cómo es cosa de la
/// pantalla, no del error.
extension MoviesError: AppErrorConvertible {
    public var screenError: ScreenError {
        switch self {
        case .offline:
            ScreenError(
                title: "Sin conexión",
                message: "Comprueba tu conexión a internet y vuelve a intentarlo."
            )

        // Deliberadamente vago sobre la CAUSA: al usuario no le sirve saber que
        // es un problema de credencial, y a un atacante sí (AGENTS.md §6).
        case .unauthorized:
            ScreenError(
                title: "No se pudo cargar",
                message: "Ahora mismo no podemos mostrar las películas. Inténtalo más tarde."
            )

        case .notFound:
            ScreenError(
                title: "No encontrado",
                message: "El contenido que buscas ya no está disponible."
            )

        case .rateLimited:
            ScreenError(
                title: "Demasiadas peticiones",
                message: "Estás yendo muy rápido. Espera un momento y vuelve a intentarlo."
            )

        case .server:
            ScreenError(
                title: "El servicio no responde",
                message: "El proveedor de películas está teniendo problemas. Inténtalo más tarde."
            )

        case .malformedResponse:
            ScreenError(
                title: "Respuesta inesperada",
                message: "Hemos recibido datos que no sabemos interpretar. Vuelve a intentarlo."
            )

        case .connectionInterrupted:
            ScreenError(
                title: "Conexión interrumpida",
                message: "La conexión se cortó a mitad de la carga. Vuelve a intentarlo."
            )

        case .unknown:
            ScreenError(
                title: "Algo ha ido mal",
                message: "No hemos podido cargar las películas. Vuelve a intentarlo."
            )
        }
    }
}

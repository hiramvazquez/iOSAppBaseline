import Foundation
import CoreNetworking

/// Adapter del puerto `PopularMoviesRepository` contra la API de TMDB.
///
/// Es el único sitio del proyecto que sabe que existe TMDB. El dominio habla de
/// películas; esta clase traduce entre eso y `/3/movie/popular`.
struct TMDBPopularMoviesRepository: PopularMoviesRepository {
    private let api: APIServiceProtocol

    init(api: APIServiceProtocol) {
        self.api = api
    }

    func popularMovies() async throws(MoviesError) -> [Movie] {
        do {
            let pagina: PopularMoviesPageDTO = try await api.execute(request: PopularMoviesRequest())
            return pagina.results.map(\.asMovie)
        } catch {
            throw Self.mapear(error)
        }
    }

    /// Traduce el error de transporte al vocabulario del dominio.
    ///
    /// **Sin `default:` a propósito**: si `CoreNetworking` añade un caso en una
    /// versión futura, esto deja de compilar en vez de convertirlo en
    /// `.unknown` en silencio. El compilador es el primer reviewer (§14.0).
    ///
    /// Los tres casos con juicio propio de este dominio (cancelación,
    /// decodificación, 404) se resuelven aquí; el resto se delega a
    /// `TransportError` de `CoreNetworking` (OQ-18) — el mapeo por código
    /// HTTP/red que antes vivía suelto en este archivo, ahora centralizado y
    /// reusable por cualquier repositorio futuro de la app. `MoviesError`
    /// sigue sin importar `CoreNetworking`: `layers.conf` se lo prohíbe a
    /// `Domain/` a propósito (el modelo de negocio no sabe cómo se
    /// transporta), así que `mapearTransporte` traduce valor a valor en vez
    /// de que el dominio adopte el tipo.
    private static func mapear(_ error: APIError) -> MoviesError {
        switch error {
        case .cancelled:
            // La distinción que decide OQ-14. `URLError.cancelled` llega igual
            // la pidiéramos nosotros o no: el ÚNICO discriminador disponible es
            // si nuestra propia Task está cancelada.
            //
            // - Task cancelada → la pedimos nosotros. Se mapea a `.unknown`, y
            //   quien evita que llegue al usuario es el `guard !Task.isCancelled`
            //   de `performLoad`, en AppFoundation.
            // - Task viva → la cortó el transporte (sesión invalidada, red
            //   caída a mitad). Es un fallo real y recuperable, y presentarlo
            //   como «cancelado» dejaría la pantalla cargando para siempre.
            //
            // ⚠️ ESTO NO ES LO QUE EL PRD PRESCRIBE. §6.5-Trampa A y OQ-14 piden
            // relanzar `CancellationError()` desde aquí, para que la protección
            // viva en una capa que los tests de este módulo alcanzan (bloqueante
            // B1). Con el `.unknown` actual, un consumidor fuera de
            // `performLoad` —el decorador de caché de §16.2— mostraría «Algo ha
            // ido mal» por una navegación del propio usuario. Decisión pendiente
            // del owner: ver el recuadro de §6.4 del PRD 0001. Este comentario
            // dice lo que el código HACE, no lo que debería hacer.
            return Task.isCancelled ? .unknown : .connectionInterrupted

        case .decodingError:
            return .malformedResponse

        case .httpStatus(404, _), .custom(_, 404, _):
            return .notFound

        case .httpStatus, .custom, .networkError, .certificateValidationFailed,
             .invalidURL, .invalidResponse, .encodingError, .unknown:
            return mapearTransporte(TransportError(from: error))
        }
    }

    /// Traduce el vocabulario transversal de `CoreNetworking` al de este
    /// dominio. Sin `default:` por el mismo motivo que `mapear`: un caso
    /// nuevo en `TransportError` fuerza una decisión aquí, no se hereda en
    /// silencio.
    private static func mapearTransporte(_ error: TransportError) -> MoviesError {
        switch error {
        case .offline: .offline
        case .unauthorized: .unauthorized
        case .rateLimited: .rateLimited
        case .server: .server
        case .connectionInterrupted: .connectionInterrupted
        case .unknown: .unknown
        }
    }
}

// MARK: - Transporte

/// `GET /3/movie/popular`.
///
/// La credencial **no viaja aquí**: va en `defaultHeaders` de la configuración,
/// como `Authorization: Bearer`. En la query acabaría en los logs — el
/// interceptor redacta headers siempre, pero loguea la URL entera. (OQ-1.)
private struct PopularMoviesRequest: BaseRequest {
    typealias Parameters = EmptyParameters
    var path = "/3/movie/popular"
    var method: HTTPMethod = .GET
    var headers: [String: String] = [:]
    var queryItems: [URLQueryItem]?
}

import Foundation
import CoreNetworking

/// La configuración de red contra TMDB, armada desde el bundle.
///
/// **Falla cerrada**: sin credencial no construye un cliente que haría
/// peticiones destinadas a fallar con 401 — devuelve `nil` y quien lo pide
/// decide qué mostrar. Un fallo visible y temprano vale más que uno tardío
/// disfrazado de error de red.
enum TMDBConfiguration {

    /// Placeholder del `.xcconfig` de ejemplo. Si llega esto, el desarrollador
    /// copió el archivo y no lo rellenó — y es mejor decírselo que dejar que lo
    /// descubra por un 401 en runtime.
    private static let placeholder = "pon_aqui_tu_token_de_lectura"

    /// Construye la configuración leyendo del bundle.
    ///
    /// El `leer` es inyectable **porque los tests tienen que poder correr sin
    /// `Secrets.xcconfig`**: ese archivo está gitignorado y en CI no existe, así
    /// que una lectura directa del bundle habría hecho intestable esta lógica
    /// justo en el entorno que más importa.
    static func live(
        leer: (String) -> String? = { Bundle.main.object(forInfoDictionaryKey: $0) as? String }
    ) -> NetworkingConfiguration? {
        guard let host = leer("TMDBHost"), !host.isEmpty,
              let token = leer("TMDBReadAccessToken"),
              !token.isEmpty, token != placeholder,
              let baseURL = URL(string: "https://\(host)")
        else { return nil }

        return NetworkingConfiguration(
            baseURL: baseURL,
            // En cabecera, nunca en la query: el interceptor de logs redacta
            // los headers siempre, pero loguea la URL entera. (OQ-1.)
            defaultHeaders: ["Authorization": "Bearer \(token)"],
            environment: "production"
        )
    }
}

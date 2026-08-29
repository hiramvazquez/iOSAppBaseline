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
        // `TMDBHost` es SOLO el host: el esquema lo impone el código y no se
        // puede configurar. No es rigidez, es la regla 5 de `security/SKILL.md`
        // ("TLS para todo") hecha imposible de romper: el token viaja en
        // `Authorization: Bearer`, así que un `http://` en un `.xcconfig` lo
        // pondría en claro en la red. Un valor con esquema falla CERRADA en vez
        // de degradarse en silencio — §14.0 prefiere el estado inválido
        // imposible por construcción antes que verificado en runtime.
        //
        // Tampoco lleva prefijo de versión: `APIService` compone
        // `baseURL.appendingPathComponent(request.path)` y los requests ya
        // declaran `/3/...`. Un host con `/3` produce `…/3/3/movie/popular` y
        // un 404 en CADA petición, que ningún test de repositorio ve porque
        // esos construyen su propia baseURL.
        // LA condición, y una sola a propósito: **lo configurado tiene que SER
        // el host**, verbatim. Todo lo que el parser reinterprete deja de
        // coincidir y no se construye cliente.
        //
        // Empezó siendo `!host.contains("://")` y el `security-reviewer` la
        // tumbó: `api.themoviedb.org@attacker.com` no lleva `://`, y el `@`
        // degrada lo de su izquierda a userinfo — el host REAL pasaba a ser
        // `attacker.com` y el `Authorization: Bearer` viajaba hasta allí.
        // Enumerar lo prohibido siempre deja algo fuera.
        //
        // La segunda versión añadía además una allow-list de caracteres, y
        // sobraba: la mutación lo demostró —quitar cualquiera de las dos dejaba
        // los tests en verde, o sea que ninguna era individualmente
        // verificable—. Esta comparación sola cubre `@`, `://`, `//evil.com`
        // (que colaba un `host == nil` y hacía saltar el `precondition` de
        // NetworkingConfiguration: un crash, lo contrario de fallar cerrada),
        // rutas, query, espacios y homógrafos unicode.
        //
        // Efecto lateral aceptado: prohíbe puerto explícito. Si algún día hace
        // falta apuntar a `host:puerto`, se cambia AQUÍ y con su test.
        guard let host = leer("TMDBHost"), !host.isEmpty,
              let token = leer("TMDBReadAccessToken"),
              !token.isEmpty, token != placeholder,
              let baseURL = URL(string: "https://\(host)"),
              baseURL.host?.lowercased() == host.lowercased(),
              baseURL.user == nil, baseURL.password == nil
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

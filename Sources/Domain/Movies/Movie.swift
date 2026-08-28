import Foundation

/// Una película, tal como la necesita esta app.
///
/// No es «lo que devuelve TMDB»: es lo que el dominio decidió que le importa. El
/// DTO de transporte vive en `Data/` y se mapea aquí; si mañana cambiamos de
/// proveedor, este tipo no se entera.
public struct Movie: Equatable, Sendable, Identifiable {
    public let id: MovieID
    public let title: String

    /// Ruta relativa del póster tal como la publica el proveedor (p. ej.
    /// `/abc123.jpg`). **No es una URL**: componerla exige la base y el tamaño,
    /// que son detalle de transporte. El dominio no habla de URLs.
    public let posterPath: String?

    /// Nota media. Opcional porque una película recién estrenada puede no tener
    /// votos, y ese `nil` es un dato, no un error.
    public let voteAverage: Double?

    public init(id: MovieID, title: String, posterPath: String? = nil, voteAverage: Double? = nil) {
        self.id = id
        self.title = title
        self.posterPath = posterPath
        self.voteAverage = voteAverage
    }
}

/// Identificador de película.
///
/// Es un tipo propio y no un `Int` suelto para que el compilador impida pasar
/// un id de página donde va un id de película — la regla de §14.0: hacer el
/// estado inválido imposible por tipo antes que verificarlo en runtime.
public struct MovieID: Hashable, Sendable {
    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }
}

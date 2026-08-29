import Foundation
import CoreNetworking

/// La página tal como la publica TMDB.
///
/// `CodingKeys` explícitas y no `.convertFromSnakeCase`: la traducción se lee
/// **aquí**, delante de quien mantiene el mapeo, en vez de ocurrir por una
/// estrategia global invisible. (OQ-2: el decoder es configurable desde
/// `CoreNetworking` 0.1.2; usar el de por defecto es una elección, no una
/// restricción.)
struct PopularMoviesPageDTO: BaseResponse {
    let results: [MovieDTO]
}

struct MovieDTO: Decodable, Sendable {
    let id: Int
    let title: String
    let posterPath: String?
    let voteAverage: Double?

    enum CodingKeys: String, CodingKey {
        case id, title
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
    }

    var asMovie: Movie {
        Movie(id: MovieID(id), title: title, posterPath: posterPath, voteAverage: voteAverage)
    }
}

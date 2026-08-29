import Testing
import Foundation
@testable import iOSAppBaseline

/// Decodificación y mapeo de `MovieDTO`, aisladas del transporte.
///
/// Decodifica JSON directamente contra el DTO — sin `APIService` ni red
/// simulada — porque esta lógica no depende de HTTP y no debería necesitar su
/// plumbing para probarse. `TMDBPopularMoviesRepositoryTests` cubre el camino
/// completo; aquí se cubre lo que ninguna fixture de ese archivo ejercita:
/// `vote_average` nunca falta en ellas.
@Suite("MovieDTO — decodificación y mapeo a dominio")
struct TMDBDTOsTests {

    @Test("decodifica snake_case y mapea cada campo a Movie")
    func decodificaYMapea() throws {
        let dto = try JSONDecoder().decode(MovieDTO.self, from: Data("""
        {"id": 438631, "title": "Dune", "poster_path": "/dune.jpg", "vote_average": 8.1}
        """.utf8))

        let movie = dto.asMovie

        #expect(movie.id == MovieID(438_631))
        #expect(movie.title == "Dune")
        #expect(movie.posterPath == "/dune.jpg")
        #expect(movie.voteAverage == 8.1)
    }

    /// Una película recién estrenada no tiene votos todavía, y eso es un dato
    /// (`nil`), no un cero.
    @Test("vote_average nulo → voteAverage nil, no cero")
    func voteAverageNuloEsNilNoCero() throws {
        let dto = try JSONDecoder().decode(MovieDTO.self, from: Data("""
        {"id": 1, "title": "Recién estrenada", "poster_path": null, "vote_average": null}
        """.utf8))

        #expect(dto.asMovie.voteAverage == nil)
    }
}

import Testing
import Foundation
import AppFoundation
@testable import iOSAppBaseline

/// El copy de error es lo único que el usuario llega a ver de un fallo, y hasta
/// ahora no lo verificaba nada.
///
/// Sin conformidad con `AppErrorConvertible`, la función de mapeo de
/// AppFoundation (`BaseViewModel.screenError(from:fallbackTitle:retry:)`) cae a
/// su última rama —`ScreenError(title: fallbackTitle, message:
/// error.localizedDescription, …)`—, y para un enum de Swift sin
/// `LocalizedError` eso renderiza «The operation couldn't be completed.
/// (iOSAppBaseline.MoviesError error 1.)»: ni localizado, ni el copy por caso
/// que `MoviesError` promete en su documentación.
@Suite("MoviesError → ScreenError")
struct MoviesErrorScreenErrorTests {

    /// El test que la doc de `MoviesError` pide explícitamente: itera
    /// `allCases` en vez de una lista escrita a mano, que envejecería en
    /// silencio al añadir un caso nuevo.
    @Test("cada caso tiene copy propio, y ningún par lo comparte")
    func cadaCasoTieneCopyPropio() {
        let errores = MoviesError.allCases
        #expect(!errores.isEmpty)

        for error in errores {
            let copy = error.screenError
            #expect(!copy.title.isEmpty, "\(error) no tiene título")
            #expect(!copy.message.isEmpty, "\(error) no tiene mensaje")
        }

        let mensajes = Set(errores.map { $0.screenError.message })
        #expect(
            mensajes.count == errores.count,
            "hay casos que comparten mensaje: \(errores.count) casos, \(mensajes.count) mensajes distintos"
        )
    }

    /// AGENTS.md §6: el copy no menciona la credencial. Al usuario no le sirve
    /// saberlo y a un atacante sí.
    ///
    /// La lista es de términos exactos y no de fragmentos sueltos a propósito:
    /// un detector con falsos positivos se acaba desactivando entero (§14.2).
    @Test("ningún copy filtra la credencial")
    func ningunCopyFiltraLaCredencial() {
        let prohibidos = [
            "api key", "apikey", "api_key", "token", "bearer",
            "credencial", "credential", "authorization", "unauthorized",
        ]

        for error in MoviesError.allCases {
            let texto = "\(error.screenError.title) \(error.screenError.message)".lowercased()
            for termino in prohibidos {
                #expect(!texto.contains(termino), "«\(termino)» aparece en el copy de \(error)")
            }
        }
    }

    /// El que ata el mapeo al comportamiento observable. Los dos de arriba
    /// verifican la tabla de copy; este verifica que la tabla llega de verdad a
    /// la pantalla — que es lo que se rompió al no existir la conformidad.
    @MainActor
    @Test("el ViewModel muestra el copy de dominio, no el fallback de Swift")
    func elViewModelMuestraElCopyDeDominio() async {
        let sut = PopularMoviesViewModel(repository: RepoQueFalla(error: .unauthorized))

        await sut.load().value

        guard case .error(let mostrado) = sut.phase else {
            Issue.record("esperaba .error, hay \(sut.phase)")
            return
        }
        #expect(mostrado.message == MoviesError.unauthorized.screenError.message)
        #expect(
            !mostrado.message.contains("couldn't be completed"),
            "el usuario está viendo el localizedDescription de Swift: \(mostrado.message)"
        )
    }

    private struct RepoQueFalla: PopularMoviesRepository {
        let error: MoviesError

        func popularMovies() async throws(MoviesError) -> [Movie] {
            throw error
        }
    }
}

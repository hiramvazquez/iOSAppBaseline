import Testing
import Foundation
import AppFoundation
@testable import iOSAppBaseline

/// G3 del PRD 0002: el módulo registra lo que promete, **en un contenedor
/// propio** — `Container.shared` no se toca jamás desde un test (la garantía
/// de aislamiento del global es disciplina, no tipos, y esta suite es parte
/// de esa disciplina).
@MainActor
@Suite("MoviesModule — registro de la feature")
struct MoviesModuleTests {

    @Test("registra el puerto de populares en el contenedor recibido")
    func registraElPuerto() {
        let container = Container()

        container.register(modules: [MoviesModule()])

        // La CLAVE de registro es el tipo estático del puerto — la trampa
        // documentada en `ios.md` §4: registrar el concreto y resolver el
        // protocolo NO resuelve. Este test fija que el módulo registra bajo
        // el protocolo, que es lo único que los consumidores piden.
        #expect(container.canResolve((any PopularMoviesRepository).self))
        #expect(container.tryResolve((any PopularMoviesRepository).self) != nil)
    }

    @Test("un contenedor sin el módulo NO resuelve el puerto — el registro no es global")
    func sinModuloNoResuelve() {
        let container = Container()

        #expect(!container.canResolve((any PopularMoviesRepository).self))
        #expect(container.tryResolve((any PopularMoviesRepository).self) == nil)
    }
}

import Foundation
import Testing
import AppFoundation
import CoreNetworking
import CoreNetworkingTestSupport

/// Smoke del cableado: si los tres módulos no estuvieran enlazados de verdad,
/// esto no compilaría. Un test que solo dijera `#expect(true)` habría pasado
/// igual con el proyecto mal configurado — y eso es un test decorativo.
@Suite("Cableado del proyecto base")
struct WiringSmokeTests {
    @Test("Los dos paquetes propios están enlazados y son usables")
    func packagesAreLinked() {
        let container = Container.shared
        #expect(container.tryResolve(String.self) == nil)

        let configuration = NetworkingConfiguration(
            baseURL: URL(string: "https://unit.test")!,
            protocolClasses: [MockURLProtocol.self]
        )
        #expect(configuration.baseURL.host() == "unit.test")
    }
}

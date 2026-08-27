// El fixture que de verdad importa: formas SEGURAS que se parecen a las
// prohibidas. Ninguna regla puede tocar nada de aquí. Cada bloque nació de un
// falso positivo real o de uno que estuvo a punto de serlo.
import Foundation

actor Ejemplo {
    // `as?` es la alternativa que el propio mensaje de swift-force-cast
    // recomienda. El parser de Swift lo normaliza al mismo nodo que `as!`, así
    // que sin `pattern-regex` la regla castigaba justo lo que aconseja — y
    // dejaba imposible escribir un adapter de URLSession correcto.
    func estado(de respuesta: URLResponse) -> Int? {
        guard let http = respuesta as? HTTPURLResponse else { return nil }
        return http.statusCode
    }

    // `try` y `try await` legítimos: el mismo defecto del parser con `try!`.
    func cargar(_ url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(Data.self, from: data)
    }

    // `try?` es manejo explícito del error, no una bomba.
    func opcional(_ url: URL) async -> Data? {
        try? await URLSession.shared.data(from: url).0
    }

    // Concurrencia moderna: nada de GCD ni de locks manuales.
    func trabajo() async {
        await withTaskGroup(of: Void.self) { grupo in
            grupo.addTask { }
        }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }

    // Logging estructurado, no `print`.
    func registra(_ mensaje: String) {
        let log = Logger(subsystem: "app", category: "ejemplo")
        log.debug("\(mensaje, privacy: .public)")
    }
}

import OSLog

import Foundation

/// Los errores que el dominio de películas admite. Tipados, no strings.
///
/// **Sin `messageKey`**, a propósito y contra lo que prescribe hoy
/// `domain/SKILL.md`: una clave de texto en `String` acabaría impresa en
/// pantalla, porque `ScreenError` tiene un init `@_disfavoredOverload` que
/// guarda los `String` **verbatim**. La traducción a copy vive en `Features/`, en un
/// `switch` exhaustivo con literales `LocalizedStringResource` — así el
/// compilador obliga a cubrir cada caso nuevo y el String Catalog los extrae
/// solo. (PRD 0001, bloqueante B4.)
///
/// `CaseIterable` para que el test de «dos casos no comparten copy» itere
/// `allCases` en vez de una lista escrita a mano que envejece.
public enum MoviesError: Error, Equatable, Sendable, CaseIterable {
    /// Sin conexión. El usuario puede reintentar y tiene sentido hacerlo.
    case offline

    /// Credencial ausente o inválida. El copy **no menciona la credencial**
    /// (AGENTS.md §6): al usuario no le sirve y a un atacante sí.
    case unauthorized

    /// El recurso no existe. Nunca se degrada a una lista vacía.
    case notFound

    /// El proveedor pide bajar el ritmo.
    case rateLimited

    /// Fallo del lado del proveedor.
    case server

    /// La respuesta llegó, pero no tiene la forma acordada. **No se degrada a
    /// lista vacía**: un JSON que no entendemos es un fallo, no «cero
    /// resultados» — confundirlos esconde una rotura de contrato.
    case malformedResponse

    /// La conexión se cortó sin que nadie de nuestro lado lo pidiera (sesión
    /// invalidada, transporte caído). Es **recuperable**: se ofrece reintentar.
    ///
    /// Existe separada de `offline` porque no es lo mismo «no hay red» que «la
    /// petición se cortó a mitad», y el copy honesto difiere.
    ///
    /// ⚠️ Y existe separada de una cancelación propia, pero **hoy el mecanismo
    /// no es el que el PRD prescribe**: el adapter mapea la cancelación propia a
    /// `.unknown` (`Task.isCancelled ? .unknown : .connectionInterrupted`), y
    /// quien impide que llegue a la pantalla es el `guard !Task.isCancelled` de
    /// `performLoad`, en AppFoundation — no este enum. §6.5-Trampa A y OQ-14
    /// piden que el adapter relance `CancellationError()`; está sin implementar
    /// y es decisión pendiente del owner (§6.4 del PRD 0001).
    case connectionInterrupted

    /// Lo que no encaja en ningún caso anterior.
    case unknown
}

import Foundation

/// El puerto que el dominio necesita para conocer las películas populares.
///
/// Es una **capability**, no un repositorio gigante: pide exactamente una cosa.
/// Quien lo implemente —el adapter de TMDB hoy, un decorador con caché mañana—
/// tiene que cumplir las garantías de abajo, y las cumple o no es este puerto.
///
/// `throws(MoviesError)` (typed throws) para que el compilador impida que un
/// `APIError` o un `DecodingError` escapen a las capas de arriba: la garantía
/// C7 del PRD deja de depender de que alguien se acuerde.
public protocol PopularMoviesRepository: Sendable {
    /// Devuelve la primera página de películas populares.
    ///
    /// **Este doc-comment ES el contrato publicado** (§6.3 del PRD 0001 lo cita
    /// así), de modo que cada garantía dice también **quién la verifica**. Una
    /// lista de promesas sin esa columna es una defensa anunciada: la versión
    /// anterior afirmaba que «las verifica la suite de conformidad, que pasan
    /// por igual el fake y el adapter real» y la suite solo verifica C3.
    ///
    /// **Garantías vigentes:**
    ///
    /// - **C1** — nunca devuelve `nil`: o hay películas, o hay lista vacía, o
    ///   lanza. *Verificada **por el tipo** (`[Movie]`), sin test: no hay nada
    ///   que comprobar en runtime. Una lista vacía es un resultado válido.*
    /// - **C3** — el orden es el que dio la fuente. El puerto no reordena.
    ///   *Verificada por la **suite de conformidad**, contra el fake y contra el
    ///   adapter real, comparando la entidad completa.*
    /// - **C7** — toda salida de error es un `MoviesError`; jamás escapa un
    ///   `APIError`, un `URLError` ni un `DecodingError`. *Verificada **por el
    ///   tipo** (`throws(MoviesError)`). Que cada error de transporte se mapee
    ///   al caso correcto lo prueba la suite del adapter.*
    ///
    /// **C2 — RETIRADA** el 2026-08-28 (OQ-17). Prometía ids únicos, y eso es
    /// incompatible con C3: si la fuente devolviera un id repetido, cumplir C2
    /// exigiría deduplicar, y deduplicar es reordenar lo que dio la fuente.
    /// **No-garantía explícita: este puerto NO deduplica.** La unicidad la
    /// impone el acumulador de paginación, que es quien tiene el estado donde un
    /// duplicado importa.
    ///
    /// **C5 — fuera de la suite**, no retirada: «sin efectos secundarios
    /// observables» solo es observable con un puerto que admita más de una
    /// operación distinguible. `popularMovies()` no toma parámetros, así que hoy
    /// no hay forma de comprobarla sin verificar el mock en vez del contrato.
    /// Entra cuando exista el decorador de caché.
    ///
    /// **NO garantiza** que dos llamadas devuelvan lo mismo: `popular` se
    /// reordena en la fuente según cambian los votos. Prometer estabilidad
    /// sería prometer algo que la implementación real no cumple.
    func popularMovies() async throws(MoviesError) -> [Movie]
}

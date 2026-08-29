import Foundation
import Testing
import CoreNetworking

@testable import iOSAppBaseline

/// `TMDBConfiguration` no tenía **ningún** test, y es la pieza por donde entra
/// la credencial. Su `leer` es inyectable justo para esto: la lógica se puede
/// probar sin `Secrets.xcconfig`, que está gitignorado y en CI no existe.
///
/// Lo que fijan estos tests es lo que la skill de seguridad declara y hasta
/// ahora nadie verificaba: **falla cerrada**, y el esquema es `https` por
/// construcción, no por confiar en lo que traiga la configuración.
@Suite("TMDBConfiguration: falla cerrada y fuerza TLS")
struct TMDBConfigurationTests {

    private static let tokenValido = "eyJ-token-de-prueba-no-real"

    /// Bundle falso: devuelve lo que se le diga para cada clave.
    private func leer(host: String?, token: String?) -> (String) -> String? {
        { clave in
            switch clave {
            case "TMDBHost": return host
            case "TMDBReadAccessToken": return token
            default: return nil
            }
        }
    }

    // ── Falla cerrada ────────────────────────────────────────────────

    @Test("Sin host no se construye cliente")
    func sinHostEsNil() {
        #expect(TMDBConfiguration.live(leer: leer(host: nil, token: Self.tokenValido)) == nil)
        #expect(TMDBConfiguration.live(leer: leer(host: "", token: Self.tokenValido)) == nil)
    }

    @Test("Sin token no se construye cliente")
    func sinTokenEsNil() {
        #expect(TMDBConfiguration.live(leer: leer(host: "api.themoviedb.org", token: nil)) == nil)
        #expect(TMDBConfiguration.live(leer: leer(host: "api.themoviedb.org", token: "")) == nil)
    }

    /// El placeholder del `.xcconfig` de ejemplo se rechaza explícitamente: un
    /// 401 en runtime no le dice a nadie «no rellenaste el xcconfig».
    @Test("El placeholder del ejemplo se rechaza como si no hubiera token")
    func placeholderEsNil() {
        let placeholder = "pon_aqui_tu_token_de_lectura"
        #expect(TMDBConfiguration.live(leer: leer(host: "api.themoviedb.org", token: placeholder)) == nil)
    }

    // ── El esquema es https POR CONSTRUCCIÓN ──────────────────────────

    /// LA GARANTÍA QUE ESTE ARCHIVO EXISTE PARA FIJAR. El token viaja en
    /// `Authorization: Bearer`, así que un esquema `http` lo pondría en claro
    /// en la red. La skill de seguridad lo dice en su regla 5 ("TLS para
    /// todo"), y hasta ahora era prosa: nada lo verificaba.
    ///
    /// Se comprueba sobre el valor CONSTRUIDO, no sobre la entrada: da igual
    /// cómo se implemente mientras el resultado no pueda ser texto plano.
    @Test("La baseURL siempre sale con esquema https")
    func laBaseURLEsSiempreHTTPS() {
        let config = TMDBConfiguration.live(
            leer: leer(host: "api.themoviedb.org", token: Self.tokenValido)
        )
        #expect(config?.baseURL.scheme == "https")
    }

    /// Un host que traiga esquema falla CERRADA.
    ///
    /// La primera versión de este test afirmaba `baseURL.scheme != "http"` y era
    /// **vacua**: lo cazó el `security-reviewer` borrando el guard entero y
    /// viéndola pasar igual, porque `URL(string: "https://http://…")` da
    /// `scheme == "https"` de todos modos — el primer `https://` ya ocupó el
    /// papel de esquema. Afirmar `nil` sí distingue las dos implementaciones.
    @Test("Un host con esquema no construye cliente, en vez de reinterpretarlo")
    func hostConEsquemaEsNil() {
        #expect(TMDBConfiguration.live(leer: leer(host: "http://api.themoviedb.org", token: Self.tokenValido)) == nil)
        #expect(TMDBConfiguration.live(leer: leer(host: "https://api.themoviedb.org", token: Self.tokenValido)) == nil)
    }

    /// EL BYPASS QUE ENCONTRÓ EL `security-reviewer`, y la razón de que el guard
    /// sea allow-list y no lista negra. `api.themoviedb.org@attacker.com` no
    /// contiene `://`, así que esquivaba el guard anterior — y el `@` degrada
    /// todo lo de su izquierda a userinfo, de modo que el host REAL pasa a ser
    /// `attacker.com`. El `Authorization: Bearer` habría viajado hasta allí.
    @Test("Un host con userinfo no redirige la credencial a otro servidor")
    func userinfoNoSecuestraElHost() {
        for hostile in ["api.themoviedb.org@attacker.com",
                        "user:pass@attacker.com",
                        "api.themoviedb.org:443@attacker.com"] {
            let config = TMDBConfiguration.live(leer: leer(host: hostile, token: Self.tokenValido))
            #expect(config == nil, "‘\(hostile)’ construyó cliente: la credencial iría a otro host")
        }
    }

    /// El otro bypass del mismo hallazgo. `//evil.com` tampoco lleva `://`, y
    /// producía un `baseURL` con `host == nil` que hacía saltar el
    /// `precondition` de `NetworkingConfiguration` — un CRASH, que es lo
    /// contrario de la promesa de "falla cerrada" del propio archivo.
    @Test("Un host protocol-relative falla cerrada en vez de crashear")
    func protocolRelativeEsNil() {
        #expect(TMDBConfiguration.live(leer: leer(host: "//evil.com", token: Self.tokenValido)) == nil)
    }

    /// La allow-list rechaza lo que no es un hostname, sin enumerar lo malo.
    @Test("Solo pasan hostnames: nada de rutas, query, espacios ni unicode")
    func soloHostnames() {
        for hostile in ["api.themoviedb.org/3", "api.themoviedb.org?x=1", "api.themoviedb.org#f",
                        "api.themoviedb.org ", "аpi.themoviedb.org", "api.themoviedb.org%2Fx"] {
            #expect(TMDBConfiguration.live(leer: leer(host: hostile, token: Self.tokenValido)) == nil,
                    "‘\(hostile)’ no es un hostname y construyó cliente igualmente")
        }
    }

    // ── La URL compuesta, que es donde muerde de verdad ───────────────

    /// EL BUG QUE ESTE TEST HABRÍA CAZADO. `APIService` compone
    /// `baseURL.appendingPathComponent(request.path)` y el request ya declara
    /// `/3/movie/popular`. Si la baseURL trae además el `/3`, la URL real sale
    /// `…/3/3/movie/popular` y CADA petición da 404 — sin que ningún test lo
    /// note, porque los tests de repositorio construyen su propia baseURL.
    ///
    /// Se fija aquí y no allí a propósito: el defecto no está en el
    /// repositorio, está en el acuerdo entre la configuración y el path.
    @Test("La baseURL no duplica el prefijo de versión del path")
    func laURLCompuestaNoDuplicaLaVersion() throws {
        let config = try #require(
            TMDBConfiguration.live(leer: leer(host: "api.themoviedb.org", token: Self.tokenValido))
        )
        let compuesta = config.baseURL.appendingPathComponent("/3/movie/popular")
        #expect(compuesta.absoluteString == "https://api.themoviedb.org/3/movie/popular")
    }

    // ── La credencial, donde toca ─────────────────────────────────────

    /// En CABECERA y no en la query: el `LoggingInterceptor` redacta los
    /// headers sensibles siempre, pero loguea la URL entera sin redactar.
    @Test("El token va en la cabecera Authorization, nunca en la URL")
    func elTokenVaEnCabecera() throws {
        let config = try #require(
            TMDBConfiguration.live(leer: leer(host: "api.themoviedb.org", token: Self.tokenValido))
        )
        #expect(config.defaultHeaders["Authorization"] == "Bearer \(Self.tokenValido)")
        #expect(!config.baseURL.absoluteString.contains(Self.tokenValido))
    }
}

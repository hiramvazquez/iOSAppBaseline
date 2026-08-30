# Arquitectura — iOS (SwiftUI + AppFoundation + CoreNetworking)

> **Esta skill describe los paquetes REALES de este proyecto, no SwiftUI genérico.**
> Stack: iOS 17+, Swift 6 (language mode 6), SwiftUI, Swift Testing.
> Patrón: **View + ViewModel(`BaseViewModel`) + Logic puro**, navegación por `Coordinator`,
> DI por `Container`, red por `APIService`.
>
> **Lee también `swift-estado-del-arte.md`** (misma carpeta): el estado vivo del lenguaje.
>
> ⚠️ **Los README de los dos SPM contienen ejemplos que rompen la app.** Están señalados uno
> a uno en §9. Si un ejemplo del README contradice a esta skill, **gana esta skill** — cada
> afirmación de aquí se verificó leyendo el código fuente del paquete el 2026-08-29.

## Estructura de carpetas

```
Sources/
  Domain/<Feature>/     entidades, puertos (protocolos), errores de dominio
  Data/<Feature>/       adapters de los puertos (red/DB), DTOs, configuración
  Features/<Feature>/   View, ViewModel, mapeo error→copy, rutas
  App/                  composition root: Coordinator, módulos de DI, store de pantallas
```

El **dominio no importa** `AppFoundation` ni `CoreNetworking` — lo prohíbe `tools/layers.conf`
y lo verifica `check-layers.sh`. `Features/` tampoco importa `CoreNetworking`: hablar HTTP es
trabajo de `Data/` a través de un puerto.

---

## 1. El ViewModel — `BaseViewModel`

```swift
@MainActor @Observable
open class BaseViewModel          // AppFoundation
```

No es genérica, no tiene `associatedtype`. Expone **cuatro** propiedades `public var` que
`ScreenContainer` bindea automáticamente:

| Propiedad | Tipo | Inicial |
|---|---|---|
| `phase` | `ViewPhase` | `.idle` |
| `activity` | `ActivityState` | `.none` |
| `alert` | `AlertState?` | `nil` |
| `banner` | `BannerState?` | `nil` |

```swift
@MainActor @Observable                      // ⚠️ SÍ, también en la subclase — ver §9-C1
final class PopularMoviesViewModel: BaseViewModel {
    private let repository: any PopularMoviesRepository
    private let router: any Router<MoviesRoute>

    private(set) var movies: [Movie] = []

    init(repository: any PopularMoviesRepository, router: any Router<MoviesRoute>) {
        self.repository = repository
        self.router = router
        super.init()                        // SIEMPRE al final
    }
}
```

### `performLoad` vs `performActivity` — la distinción que más se equivoca

```swift
@discardableResult
open func performLoad(
    style: ActivityStyle = .fullScreen,
    errorTitle: LocalizedStringResource? = nil,
    successTransition: LoadSuccessTransition = .setContent,
    _ work: @escaping () async throws -> Void
) -> Task<Void, Never>

@discardableResult
open func performActivity(
    style: ActivityStyle = .overlay,
    errorHandling: ActivityErrorHandling = .banner,   // .banner | .alert | .silent
    _ work: @escaping () async throws -> Void
) -> Task<Void, Never>
```

| | `performLoad` | `performActivity` |
|---|---|---|
| Escribe | `phase` | `activity` (**nunca** `phase`) |
| Tapa el contenido | sí, con `.fullScreen` | no |
| Error | `phase = .error(...)` con botón de reintentar | banner (por defecto) |
| Para qué | **la carga inicial** de la pantalla | refresh, paginación, submit, borrado |

**Un refresh con `performLoad` repinta la pantalla en blanco.** Si ya hay contenido, es
`performActivity`.

### Lo que `BaseViewModel` YA hace — no lo reimplementes

- Cancela la carga anterior al empezar otra (un solo slot — ver §9-T22).
- Cancela sus tareas en `deinit`.
- `catch is CancellationError` → no pinta error (cancelar no es fallar).
- Inyecta el `retry` del `ScreenError`, que `DefaultErrorView` pinta como botón.
- Auto-descarta los banners con su duración, cancelando el anterior por `id`.
- Mapea tu error de dominio a copy vía `AppErrorConvertible`.

Nada de `isLoading: Bool` propio, ni `Task.sleep` para banners, ni `if phase == .loading` en
la View.

### Quién es dueño de `ViewPhase`

```swift
public enum ViewPhase: Equatable, Sendable {
    case idle
    case loading(ActivityStyle)     // .fullScreen | .inline | .overlay
    case content
    case empty
    case error(ScreenError)
}
```

Con el `successTransition` por defecto (`.setContent`), **`performLoad` es dueño de
`.loading` y `.content`**; tú nunca los escribes. `.empty` **nunca** lo produce `performLoad`:
en cuanto lo necesites, pasas a `.preserveCurrentPhase` y te haces dueño de la fase de éxito
entera.

```swift
// La lista puede venir vacía → tú decides la fase de éxito
private func load() -> Task<Void, Never> {
    performLoad(successTransition: .preserveCurrentPhase) { [weak self] in
        guard let self else { return }
        let movies = try await self.repository.popularMovies()
        self.movies = movies
        movies.isEmpty ? self.setEmpty() : self.setContent()   // TODOS los caminos
    }
}
```

⚠️ Con `.preserveCurrentPhase`, un camino de éxito que no fije fase deja la pantalla
**colgada en `.loading` para siempre**. Está fijado por un test del paquete.

### La intención: `enum Intent` + `send(_:)`

La View **no llama a `load()`**: emite intención. Distintas intenciones tienen contratos
opuestos sobre la repetición, y un único `load()` no puede expresarlo.

```swift
enum Intent: Equatable {      // ⚠️ `Intent`, NO `Action`: `Action` es un typealias
    case alAparecer           //    de AppFoundation y un enum anidado lo sombrea (§9-T15)
    case reintentar
}

func send(_ intent: Intent) async {
    switch intent {
    case .alAparecer:
        switch phase {                              // la FASE es el estado, no un flag propio
        case .idle, .empty: await load().value      // `.empty` incluido: DefaultEmptyView
        case .loading, .content, .error: return     // no ofrece reintentar (§9-T4)
        }
    case .reintentar:
        await load().value
    }
}
```

`.task { await vm.send(.alAparecer) }` en la View. Es `async` para que los tests sean
deterministas (awaitan la `Task` que devuelve `performLoad`).

> **`send` no es la única entrada a una recarga.** El botón de la pantalla de error usa el
> `retry` que inyecta `performLoad`, y se salta tu enum. El enum garantiza que nadie evite
> tu guard **desde la View**, no que nada más pueda recargar.

---

## 2. La View — `ScreenContainer`

La View **no reimplementa carga/vacío/error/contenido**. Los pinta `ScreenContainer`.

```swift
struct PopularMoviesView: View {
    /// `let`, NO `@State` (f-54d7ee41, corregido en el PRD 0002): el dueño de la
    /// identidad del ViewModel es el ScreenStore del composition root, y un
    /// `@State` aquí duplicaría esa propiedad — dos dueños que pueden divergir.
    /// Con `@Observable`, un `let` re-renderiza igual: el tracking es por acceso
    /// a propiedad, no por el wrapper que sostiene la referencia.
    let viewModel: PopularMoviesViewModel

    var body: some View {
        ScreenContainer(viewModel: viewModel, title: "peliculas.titulo", style: .solid) {
            List(viewModel.movies) { MovieRow(movie: $0) }
                .listStyle(.plain)
        }
        .task { await viewModel.send(.alAparecer) }
    }
}
```

*(La versión anterior de este ejemplo enseñaba `@State private var viewModel` + init con
`State(wrappedValue:)` — el patrón exacto que `f-54d7ee41` pagó por quitar. Lo cazó el revisor
E2E: el refactor corrigió el código y nadie propagó a la skill.)*

Ni un `if phase == …`. Ese es el punto.

**Init canónico** (hay 5; éste es el que se usa):

```swift
init(viewModel: BaseViewModel,
     navigation: NavigationBarConfiguration = .hidden,     // ⚠️ .hidden por defecto
     navigationPlacement: NavigationPlacement = .stack,
     backgroundColor: Color = .platformBackground,
     @ViewBuilder content: @escaping () -> Content)
```

Con `viewModel:`, los cuatro overlays (`phase`, `activity`, `alert`, `banner`) se cablean
**solos**. Con el init de `phase:` (para previews) los otros tres tienen default
`.constant(...)` y **nunca se muestran** si no los pasas.

| `phase` | Tapa el contenido | Vista por defecto |
|---|---|---|
| `.loading(.fullScreen)` | sí | `DefaultLoadingView` |
| `.loading(.inline)` / `.loading(.overlay)` | no | píldora / velo + spinner |
| `.empty` | sí | `DefaultEmptyView` — **sin botón de reintentar** |
| `.error(_)` | sí | `DefaultErrorView` — con botón si hay `retry` |

Personalización: `.loadingView { }`, `.errorView { error in }`, `.emptyView { }`,
`.alertView { }`, `.bannerView { }`. Devuelven `Self`, así que van **antes** de cualquier
modificador de SwiftUI (`.frame`, `.padding`).

---

## 3. Navegación — `Coordinator` + `Router`

```swift
@MainActor @Observable
public final class Coordinator<Route: Hashable>: Router     // AppFoundation
```

Las vistas **no navegan**: el ViewModel pide al router.

```swift
enum MoviesRoute: Hashable {            // Hashable es el ÚNICO requisito
    case listado
    case detalle(id: MovieID)
    case ajustes
}
```

El ViewModel depende del **protocolo** `Router`, no de la clase:

```swift
private let router: any Router<MoviesRoute>

func abrirDetalle(_ id: MovieID) { router.push(.detalle(id: id)) }
func abrirAjustes()              { router.present(.ajustes, as: .sheet) }
```

`Router` expone exactamente seis métodos —`push`, `pop`, `popToRoot`, `popTo`, `present`,
`dismiss`— y **ningún estado de lectura**. Un ViewModel no puede saber dónde está ni resetear
el root: solo emitir intención. Esa línea la impone el tipo, no la disciplina.

### ⚠️ La trampa más cara del paquete, y el README la enseña

`CoordinatorView.body` lee `coordinator.mainStack.path`; como `Coordinator` es `@Observable`,
**cada `push`/`pop` reevalúa el closure de rutas**. Un ViewModel construido ahí dentro se
recrea vacío en cada navegación, y como la identidad SwiftUI de la vista no cambia,
`onAppear` **no vuelve a dispararse**: la pantalla aparece en blanco al volver del detalle,
sin carga y sin error. Compila y pasa cualquier test de estado.

**El paquete no lo resuelve** (verificado: cero memoización en `Navigation/`). El consumidor
retiene los ViewModels fuera del closure, en una **factoría memoizada**:

```swift
// Sources/App/<Feature>/<Feature>ScreenStore.swift — es composition root, no presentación
@MainActor
final class MoviesScreenStore {
    private let makePopular: @MainActor () -> PopularMoviesViewModel
    private var popularVM: PopularMoviesViewModel?

    init(makePopular: @escaping @MainActor () -> PopularMoviesViewModel) {
        self.makePopular = makePopular
    }

    func popular() -> PopularMoviesViewModel {        // memoizada: MISMA instancia siempre
        if let popularVM { return popularVM }
        let nuevo = makePopular()
        popularVM = nuevo
        return nuevo
    }
}
```

Y el closure **solo ensambla**, nunca construye tipos referencia:

```swift
CoordinatorView(coordinator: coordinator) { route in
    switch route {
    case .listado:          PopularMoviesView(viewModel: store.popular())   // ✅ memoizada
    case .detalle(let id):  MovieDetailView(id: id)                         // ✅ value type
    case .ajustes:          SettingsView(router: coordinator)
    }
}
```

> Se eligió factoría memoizada y no `@State` en una vista envolvente por **verificabilidad**:
> `@State` solo tiene identidad cuando SwiftUI instala la vista, y sin UI tests un test
> unitario no distinguiría la implementación correcta de la rota. Con la factoría,
> `primera === segunda` es un test corriente que puede fallar.

### Modales: una capa por host

`modal` es un `Optional` único — el estado es *incapaz* de representar dos modales.
`present` sobre un modal existente **lo reemplaza en silencio**, con su path. Para
modal-sobre-modal, la ruta presentada necesita su propio `Coordinator` + `CoordinatorView`.

`push`/`pop`/`popToRoot`/`popTo` actúan sobre la **capa activa** (el modal si lo hay).
`popToRoot()` dentro de un sheet **no cierra el sheet**; en la raíz de un modal, `pop()` es
un no-op silencioso — el botón «atrás» de una raíz modal llama `dismiss()`, no `pop()`.

⚠️ **`setStack` NO es layer-aware**: escribe siempre en `mainStack`, aunque haya un modal
abierto. Con un sheet delante, muta el stack de detrás y no se ve nada.

**La barra de navegación del sistema está oculta en todas las rutas**
(`.toolbar(.hidden, for: .navigationBar)`). El back y el título los dibujas con
`ScreenContainer` + `NavigationBarConfiguration`; `.navigationTitle(...)` no hace nada.

---

## 4. Inyección de dependencias — `Container`

```swift
public func register<T>(_ factory: @autoclosure @escaping () -> T,
                        lifecycle: Lifecycle,          // ⚠️ OBLIGATORIO, sin default
                        as type: T.Type = T.self)
public func resolve<T>(_ type: T.Type = T.self) -> T   // ⚠️ fatalError si no está registrado
public func tryResolve<T>(_ type: T.Type = T.self) -> T?
```

`Lifecycle`: `.singleton` (una por container, creada perezosamente) · `.transient` (una por
resolución) · `.scoped(key:)` (compartida dentro de un scope con nombre; el scope debe existir
antes o es `preconditionFailure`).

⚠️ **La clave es el tipo ESTÁTICO.** Registrar la implementación y resolver el protocolo
**no funciona**:

```swift
container.register(TMDBPopularMoviesRepository(api: api), lifecycle: .singleton)
let r: any PopularMoviesRepository = container.resolve()      // 💥 fatalError

// ✅ cualquiera de las dos:
container.register(TMDBPopularMoviesRepository(api: api) as any PopularMoviesRepository,
                   lifecycle: .singleton)
container.register(TMDBPopularMoviesRepository(api: api), lifecycle: .singleton,
                   as: (any PopularMoviesRepository).self)
```

### El módulo de la feature

```swift
struct MoviesModule: DependencyModule {          // @MainActor func register(in:)
    func register(in container: Container) {
        container.register(
            TMDBPopularMoviesRepository(api: container.resolve()) as any PopularMoviesRepository,
            lifecycle: .singleton
        )
    }
}

// Composition root:
Container.shared.register(modules: [NetworkModule(), MoviesModule()])

#if DEBUG
Container.shared.validateRegistrations([(any PopularMoviesRepository).self])
#endif
```

`validateRegistrations` (solo DEBUG) convierte un crash tardío en producción en un fallo
temprano al arrancar. Úsalo al cerrar el bootstrap.

### Inyección por constructor primero, `@Inject` con escape hatch

**`Container.shared` es inmutable en la REFERENCIA, no en el contenido**: `register`, `reset`
y `resetOnly` son públicos sobre el global. No hay `seal()`. La garantía de aislamiento entre
tests es disciplina, no tipos: **los tests usan contenedores propios y jamás tocan el global.**

Por eso el default es **inyección por constructor**. `@Inject` resuelve de `Container.shared`
y cachea para siempre; un tipo con `@Inject` y sin escape hatch **no se puede testear con un
container propio**, que es justo lo que AGENTS.md §3 exige:

```swift
final class ProfileViewModel: BaseViewModel {
    @Inject private var analytics: any AnalyticsService

    init(container: Container = .shared) {          // ← el escape hatch, obligatorio
        _analytics = Inject(container: container)
        super.init()
    }
}
```

Usa `@Inject` solo para dependencias transversales (analítica, logger). Todo lo demás, por
constructor.

**Tests:**

```swift
let container = Container()                 // propio, SIN parent: nada del global se filtra
container.register(FakeRepo() as any PopularMoviesRepository, lifecycle: .singleton)
let sut = PopularMoviesViewModel(repository: container.resolve(), router: FakeRouter())
```

---

## 5. Errores → copy de usuario

El error de dominio vive en `Domain/`; **el copy vive en `Features/`**, porque `ScreenError`
es un tipo de presentación.

```swift
// Sources/Features/Movies/MoviesError+ScreenError.swift
extension MoviesError: AppErrorConvertible {
    public var screenError: ScreenError {
        switch self {                       // exhaustivo y SIN `default`: un caso nuevo
        case .offline:                      // rompe la compilación hasta que le des copy
            ScreenError(title: "Sin conexión",
                        message: "Comprueba tu conexión y vuelve a intentarlo.")
        case .unauthorized:                 // vago sobre la CAUSA a propósito (§6 de AGENTS.md)
            ScreenError(title: "No se pudo cargar",
                        message: "Ahora mismo no podemos mostrar las películas.")
        }
    }
}
```

⚠️ **NO pongas `messageKey: String` en el error de dominio.** `ScreenError` tiene dos inits
con la misma aridad: uno de `LocalizedStringResource` y uno `@_disfavoredOverload` de `String`
que guarda **verbatim**. Un literal localiza; una `String` de runtime (una clave calculada, el
mensaje del servidor) cae en el segundo y se imprime tal cual — la pantalla mostraría
`movies.error.offline`. Por eso el copy es un `switch` con literales.

⚠️ **NO pongas `retry:` en tu `screenError`**: `performLoad` hace `retry ?? base.retry` y el
suyo nunca es `nil`, así que el tuyo es código muerto.

Si el error **no** conforma a `AppErrorConvertible`, la pantalla muestra
`error.localizedDescription` — para un enum de Swift sin `LocalizedError` eso es
«The operation couldn't be completed. (App.MiError error 1.)». Conformar no es opcional.

---

## 6. Acceso a datos

Todo HTTP pasa por `APIService` de CoreNetworking, en `Data/`, detrás de un puerto del
dominio. La View y el ViewModel hablan con el **puerto**, nunca con `APIService`.

```swift
struct TMDBPopularMoviesRepository: PopularMoviesRepository {
    private let api: any APIServiceProtocol          // el protocolo, no la clase

    func popularMovies() async throws(MoviesError) -> [Movie] {
        do {
            let pagina: PopularMoviesPageDTO = try await api.execute(request: PopularMoviesRequest())
            return pagina.results.map(\.asMovie)
        } catch {
            throw Self.mapear(error)                  // APIError → MoviesError
        }
    }
}
```

- **DTOs en su propio archivo** (`TMDBDTOs.swift`), con `CodingKeys` explícitas: la traducción
  se lee delante de quien la mantiene, no por una estrategia global invisible.
- El mapeo de errores de transporte genéricos (401/429/5xx/offline) lo hace
  `TransportError(from:)` de CoreNetworking; el adapter solo decide lo que es **juicio de su
  dominio** (qué significa un 404 aquí, qué hacer con una cancelación).
- **La credencial va en `defaultHeaders`**, nunca en la query: el interceptor de logs redacta
  headers pero loguea la URL entera.
- Los `switch` sobre `APIError` van **sin `default:`**, para que un caso nuevo del paquete
  rompa la compilación en vez de degradarse a `.unknown` en silencio.

---

## 7. Design System

**AppFoundation no trae un design system.** Solo tres colores de fondo multiplataforma:
`Color.platformBackground`, `.platformSecondaryBackground`, `.platformFill`. No hay tokens de
tipografía ni de espaciado.

La alternativa a `Font.system(size:)` son los **estilos semánticos** (`.headline`,
`.subheadline`, `.caption`), que respetan Dynamic Type solos. Color de marca: Asset Catalog +
`.accentColor`. Prohibidos `Color(hex:)`, `Font.system(size:)` y padding numérico suelto.

> El propio paquete viola esa regla internamente (`Font.system(size:)` y colores literales en
> `CustomNavigationBar`, `DefaultBannerView` y `BadgeView`) y **no son configurables**. Si tu
> marca lo exige, sustituye con `.bannerView { }` y evita `BadgeView`.

## 8. i18n

`Localizable.xcstrings` en la app, idioma fuente **`es`**, con EN. Ningún texto visible se
escribe suelto en el código, y **jamás se ramifica lógica sobre texto natural**.

Los ~8 textos por defecto del paquete («Reintentar», «Actualizando…») salen de su propio
bundle y ya vienen traducidos: no intentes traducirlos desde tu catálogo. Para cambiarlos, la
única vía es `.emptyView { }` / `.errorView { }` / `.loadingView { }`.

`L10n` de AppFoundation es **internal**: no es API para consumidores.

---

## 9. Trampas verificadas (2026-08-29)

Cada una se comprobó leyendo el código del paquete. Las marcadas ⛔ son **errores en la
documentación oficial de los SPM**: no "arregles" esta skill para que coincida con ellos.

- **⛔ C1 — `@Observable` en la subclase.** El README de AppFoundation dice que las stored
  properties de las subclases se rastrean solas y su ejemplo omite `@Observable`. La macro
  instrumenta solo la declaración a la que está adjunta. El consumidor real **sí** anota la
  subclase y compila. **Anótala.** El paquete no tiene ningún test que lo decida.
- **⛔ T1 — el ejemplo de la doc de `ViewPhase` está mal.** Muestra `setEmpty()` dentro de un
  `performLoad` con transición por defecto; `setContent()` lo pisa después. Hace falta
  `.preserveCurrentPhase`.
- **⛔ T9 — los ejemplos del README capturan `self` fuerte** en `performLoad`. Eso cierra el
  ciclo `self → phase → retry → work → self`. Usa `[weak self] in guard let self else { return }`.
- **⛔ El README enseña construir el ViewModel dentro del closure de rutas** (la trampa de §3).
- **T4 — `DefaultEmptyView` no tiene botón de reintentar.** Un guard que solo deje pasar
  `.idle` deja al usuario atrapado en «no hay nada». Incluye `.empty`.
- **T15 — `enum Action` anidado sombrea el `typealias Action` de AppFoundation** dentro de esa
  clase. Usa `Intent`.
- **T22 — un solo slot de carga**: dos `performLoad` concurrentes en la misma pantalla se
  matan entre sí. Para cargas paralelas, un `performLoad` con `async let`.
- **T24 — `catch is CancellationError` solo atrapa ese tipo exacto.** Un adapter que traduzca
  la cancelación a un error propio pintará pantalla de error tras un `.task` cancelado.
- **T6 — `ScreenError` compara solo `title` y `message`**, ignorando `retry`. Un test que
  afirme «ahora hay retry» comparando `ScreenError`s pasa siempre: asevera
  `currentError?.retry != nil`.
- **`AlertState` y `BannerState` son `Equatable` solo por `id` (UUID).** Dos alertas de igual
  texto son distintas: en tests asevera `alert?.title`, no el valor entero.
- **`Container`: registrar `.transient` sobre un `.singleton` ya materializado se ignora en
  silencio** (ledger). Usa `resetOnly([T.self])` antes de re-registrar con otro lifecycle.
- **`@Inject` cachea aunque el tipo sea `.transient`** — es un singleton de facto.
- **`WrappedError` destruye el copy de tu error de dominio** (no consulta
  `AppErrorConvertible`). Es para diagnóstico, no para el camino de presentación.

## ⚠️ Nada de `.gitkeep` en proyectos Xcode 16+

Con `PBXFileSystemSynchronizedRootGroup` (default desde Xcode 16), **todo archivo bajo la
carpeta del target entra al target automáticamente**. Cuatro `.gitkeep` en cuatro subcarpetas
producen cuatro recursos que quieren copiarse al mismo destino, `App.app/.gitkeep`, y el build
falla con un error de duplicados que no menciona `.gitkeep` por ningún lado.

Pasó en el primer proyecto real: **rompió el build con los nueve niveles del harness en
verde**. Y no hacen falta: git no trackea directorios vacíos, así que la carpeta aparecerá
sola con su primer archivo real.

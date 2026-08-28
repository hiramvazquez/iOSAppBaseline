# PRD 0001 — Vertical de referencia: películas (listado + detalle, TMDB)

> **Tipo:** Forward · **Status:** Draft — **los 4 bloqueantes del design-review, cerrados**
>
> El gate del CÓMO (§12) dio 🔴 RED el 2026-08-27 con 4 bloqueantes y 29 hallazgos, todos
> verificados contra el código real de los paquetes. Dictamen completo:
> [`docs/process/reviews/2026-08-27-design-review-prd-0001.md`](../reviews/2026-08-27-design-review-prd-0001.md).
>
> **Los cuatro están cerrados (2026-08-28), editando este documento y sin escribir Swift:**
> - **B1** — la «Trampa A» describía un escenario que `performLoad` ya cubre (hace
>   `guard !Task.isCancelled` antes de `setError`), y su test habría pasado con y sin la
>   mitigación. §6.5 reescrita con el caso real —cancelación de transporte con la Task viva— y
>   T-VM-4 con ella.
> - **B2** — la garantía C5 («dos llamadas devuelven lo mismo») es falsa contra TMDB, que reordena
>   `popular`. Sustituida por «sin efectos secundarios observables», más una **no-garantía**
>   explícita de que el contenido de una página no es estable.
> - **B3** — añadida la **Trampa C**: `CoordinatorView` reevalúa el closure de rutas, así que un
>   ViewModel construido ahí se recrea vacío en cada navegación y rompe el golden 6. El PRD decide
>   dónde vive la identidad (factoría memoizada, OQ-13) en vez de delegarlo.
> - **B4** — fuera `messageKey: String`: caería en el init verbatim de `ScreenError` y pintaría la
>   clave cruda. Sustituido por un `switch` exhaustivo con literales `LocalizedStringResource`.
>
> **Resueltas también** OQ-1 (Bearer, con la doc de TMDB), OQ-2 (decoder), OQ-3(b), OQ-10 y OQ-11.
> **Sigue en `Draft`**: quedan Open Questions de owner (OQ-4 a OQ-9, OQ-12) y el `Approved` es
> suyo, no del design-review.
> **Autor:** prd-writer (sub-agente) · **Fecha:** 2026-08-27 · **Tracking:** —
> **Design-review:** pendiente
>
> **Lecturas obligatorias antes de implementar** (matriz `AGENTS.md` §11 / `tools/skill-matrix.conf`,
> el hook `skill-reminder` BLOQUEA sin ellas): `.agents/skills/domain/SKILL.md`,
> `.agents/skills/architecture/SKILL.md`, `.agents/skills/architecture/platforms/ios.md`,
> `.agents/skills/architecture/platforms/swift-estado-del-arte.md`,
> `.agents/skills/process/references/tdd-workflow.md`, `.agents/skills/security/SKILL.md`.
> Cada fase de §5b declara cuáles aplican.

---

## 1. Contexto

`iOSAppBaseline` es el proyecto base del que salen los proyectos iOS nuevos. Hoy tiene tres cosas
en verde y una vacía:

- **Esqueleto y harness listos.** `project.yml` (xcodegen), nivel 0 en ambos targets (Swift 6,
  `SWIFT_STRICT_CONCURRENCY=complete`, `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`,
  warnings como errores), preset `full`, Anillo 3 cableado (`.github/workflows/gates.yml`),
  `verify.conf` atado a `xcodegen generate && xcodebuild test`.
- **Los dos paquetes propios entran por URL con versión fijada** — `AppFoundation` 0.1.1
  (arquitectura, navegación, DI, estados de pantalla) y `CoreNetworking` 0.1.3 (lo que fija `Package.resolved`) (red, pinning,
  reintentos, errores tipados). Hay un smoke test que los importa y los **usa**.
- **La clave de TMDB ya tiene su tubería**: `Config/Secrets.xcconfig` (gitignored, copiado de
  `Secrets.example.xcconfig`) → build settings `TMDB_READ_ACCESS_TOKEN` / `TMDB_HOST` →
  `Config/Info.plist` como `TMDBReadAccessToken` / `TMDBHost`. El `#include?` es opcional: un clon recién hecho compila igual.
- **La app está vacía.** `Sources/App/BaselineApp.swift` pinta `Text("iOSAppBaseline")` y nada más.

Es decir: hay una arquitectura decidida y compilada, un harness que la vigila, y **cero código de
producto que la ejerza**. Ninguna de las reglas propias de `tools/layers.conf` (el dominio no
importa `CoreNetworking`/`AppFoundation`; la UI no habla HTTP) tiene hoy un solo archivo sobre el
que dispararse, y el nivel 4 de la pirámide (`tools/mutation-ratchet.json`) dice literalmente
`"measured": false` — nunca se ha medido, porque no hay nada que medir.

## 2. Problema

**Las skills describen la arquitectura en prosa y con `<!-- FILL -->`, y la prosa se interpreta.**
`architecture/platforms/ios.md` dice "tres archivos por pantalla" y pone un ejemplo de un
`ProfileViewModel` que no existe; `domain/SKILL.md` explica la suite de conformidad puerto↔fake con
un `SupabaseProfileRepository` inventado. Un agente que entra en frío no tiene ni un solo archivo
real que copiar: tiene que *deducir* cómo se combinan `BaseViewModel`, `ScreenContainer`,
`Coordinator`, `Container` y `APIService`, y cada agente lo deducirá distinto. Ya pasó una vez en
este stack: leyendo "Logic puro" un agente revirtió el default de concurrencia del target entero
(`lessons_learned.md`, 2026-08-08).

Además, los dos paquetes siguen en `0.x` **a propósito**: no se congela un `1.0.0` de una API que
nadie ha consumido de verdad. Sin una vertical que la cruce entera, ese `1.0.0` no puede llegar.

Si no lo construimos: los proyectos nuevos arrancan de un esqueleto que no demuestra nada, las
skills siguen citando ejemplos inventados, tres reglas de `layers.conf` siguen mudas, el nivel 4
sigue sin estrenarse y la API de los paquetes se congela a ciegas o no se congela nunca.

## 3. Objetivo

Una vertical **completa y delgada** —listado de películas populares de TMDB con paginación por
scroll, y pantalla de detalle— que cruce todas las capas del stack correctamente y quede como
**el módulo de referencia que las skills citan en vez de describir**.

Medible cuando esté hecho:

| Señal | Antes | Después |
|---|---|---|
| Archivos evaluados por las reglas propias de `layers.conf` (`*/Domain/*`, `*/UI/*`) | 0 | > 0, y `check-layers.sh` en verde |
| `tools/mutation-ratchet.json` | `measured: false` | piso real medido (sujeto a **OQ-9**) |
| Bloques `<!-- FILL -->` en las 3 skills de arquitectura/dominio sustituidos por una cita a un archivo real | 0 | ≥ 1 por skill |
| Pantallas de la app con datos reales | 0 | 2 |

**Su valor está en cruzar las capas correctamente, no en las features.** Cualquier disyuntiva
entre "más funcionalidad" y "capa mejor demostrada" se resuelve a favor de la segunda.

## 4. Filosofía / principios

1. **El contrato primero, y el contrato es el puerto.** La persistencia es *ninguna* hoy, pero el
   puerto se define de forma que añadir caché mañana sea **un adapter más** (un decorador que
   envuelve al de red) sin tocar una línea de ViewModel. Concretamente: el puerto habla de
   `MoviePage` y `PageNumber`, jamás de `URL`, `HTTPURLResponse`, `ETag` ni `staleness`.
2. **Lo que el compilador puede impedir no se valida en runtime (nivel 0).** El caso de manual de
   esta feature es la paginación: `PageNumber` es un tipo con rango cerrado, y `MoviePage` expone
   `nextPage: PageNumber?` en vez de `totalPages: Int`. Con eso, "pedir la página 0", "pedir la
   501" y "calcular mal si hay más páginas" dejan de ser bugs posibles y pasan a ser código que
   no compila. **Regla de dónde parar de envolver:** se envuelve en un tipo aquello sobre lo que
   el código *ramifica* (ids, páginas); no se envuelve lo que solo se pinta (título, sinopsis).
3. **El fake y el adapter real pasan LA MISMA suite.** No dos suites parecidas: una función de
   conformidad parametrizada por la implementación (`domain/SKILL.md` §Suite de conformidad). Es
   la vacuna contra "pasa con el fake y explota en producción", que es el modo de fallo típico de
   un fake escrito por un agente para que sus propios tests pasen.

---

## 5. Estructura de archivos a crear / tocar

```
Sources/
  Domain/Movies/
    Movie.swift                        ← entidad + MovieID (value types puros, Sendable)
    MovieDetail.swift                  ← entidad del detalle (fase 7)
    PageNumber.swift                   ← tipo-valor con rango cerrado 1...500 (invariante por tipo)
    MoviePage.swift                    ← página de resultados + nextPage: PageNumber?
    MoviesError.swift                  ← error de dominio tipado, CaseIterable. SIN messageKey (§6.4)
    PopularMoviesRepository.swift      ← PUERTO (capability: cargar una página de populares)
    MovieDetailRepository.swift        ← PUERTO (capability: cargar el detalle de una película)
    MoviesPaginationLogic.swift        ← lógica pura de acumulación/paginación (fase 2)

  Data/TMDB/
    TMDBConfiguration.swift            ← lee TMDBReadAccessToken/TMDBHost; falla CERRADA
    TMDBRequests.swift                 ← BaseRequest para /3/movie/popular y /3/movie/{id}
    TMDBDTOs.swift                     ← DTOs Decodable (frontera de transporte, NO dominio)
    TMDBMovieMapper.swift              ← DTO → dominio (única traducción, sin lógica de negocio)
    TMDBErrorMapper.swift              ← APIError → MoviesError
    TMDBPopularMoviesRepository.swift  ← ADAPTER del puerto sobre APIServiceProtocol
    TMDBMovieDetailRepository.swift    ← ADAPTER del puerto de detalle (fase 7)

  UI/Movies/                           ← ⚠️ carpeta sujeta a OQ-4 (UI/ vs Features/)
    MoviesRoute.swift                  ← enum de rutas (Hashable)
    MoviesModule.swift                 ← DependencyModule: registra los adapters reales
    MoviesError+ScreenError.swift      ← mapeo error de dominio → ScreenError (AppErrorConvertible)
    PopularMoviesViewModel.swift       ← orquestación sobre BaseViewModel
    PopularMoviesView.swift            ← SwiftUI dentro de ScreenContainer
    MovieRowView.swift                 ← fila del listado
    MovieDetailViewModel.swift         ← orquestación del detalle (fase 8)
    MovieDetailView.swift              ← detalle dentro de ScreenContainer (fase 8)

  App/
    BaselineApp.swift                  ← TOCAR: composition root real (hoy pinta un Text)
    AppCoordinatorView.swift           ← monta Coordinator<MoviesRoute> + CoordinatorView

  Resources/
    Localizable.xcstrings              ← String Catalog ES+EN (sujeto a OQ-3 si hay que declararlo)

Tests/UnitTests/
  Domain/
    PageNumberTests.swift              ← property-based (rango cerrado)
    MoviePageTests.swift               ← invariantes de nextPage
    MoviesErrorTests.swift             ← copy distinto por caso + traducción real en es (T-D-4/5)
    MoviesPaginationLogicTests.swift   ← el grueso del TDD puro
  Support/
    MoviesRepositoryConformance.swift  ← LA suite de conformidad (una, parametrizada)
    FakePopularMoviesRepository.swift  ← fake del puerto; pasa la MISMA suite
    FakeMovieDetailRepository.swift
    MoviesPortsSpy.swift               ← fake+spy con eventos enum (orquestación)
    TMDBFixtures.swift                 ← carga de los .json capturados
  Fixtures/
    popular_page1.json                 ← capturas REALES de la API (evidencia, no invención)
    popular_last_page.json
    popular_beyond_last_page.json
    movie_detail.json
    movie_detail_404.json
    malformed_page.json
  Data/
    TMDBPopularMoviesRepositoryTests.swift   ← incluye la suite de conformidad contra el adapter
    TMDBMovieDetailRepositoryTests.swift
    TMDBErrorMapperTests.swift
    TMDBSecretLeakTests.swift          ← la clave (sentinela) no aparece en NINGÚN mensaje
  UI/
    PopularMoviesViewModelTests.swift
    MovieDetailViewModelTests.swift
    MoviesErrorPresentationTests.swift
```

### NO-TOUCH (contrato — el implementador NO toca esto)

```
tools/**                          ← tooling compartido: exige aprobación explícita del owner (§8)
ci/**  ·  .github/**  ·  lefthook.yml  ·  scripts/agent-hooks/**
tools/drift-ratchet.json          ← trinquete: SOLO lo mueve su script, y solo baja (§9)
tools/mutation-ratchet.json       ← trinquete: SOLO lo mueve su script, y solo sube (§9)
tools/layers.conf · tools/skill-matrix.conf · tools/verify.conf
AGENTS.md · CLAUDE.md · docs/process/prds/_template.md
.agents/skills/**                 ← meta-doc (§8). La fase 9 PROPONE un diff; no lo mergea sin OK
project.yml                       ← build settings = decisión de owner (lección 2026-08-08). Ver OQ-3
Config/Info.plist                 ← la tubería del secreto ya está cableada; cambiarla es del owner
Config/Secrets.xcconfig           ← gitignored. NUNCA se lee, se escribe ni se imprime su contenido
Config/Debug.xcconfig · Config/Release.xcconfig
/Users/hiram/Desktop/PROYECTOS/spm-pro/**   ← AppFoundation y CoreNetworking son OTROS repos.
                                              Esta vertical los CONSUME. Si falta algo en su API:
                                              Open Question + finding, jamás un parche local.
Tests/UnitTests/SmokeTests.swift  ← el smoke del cableado se queda como está
```

> **Errores preexistentes** (los haya donde los haya): se **registran en el ledger**
> (`bash tools/findings/findings.sh add ...`), no se silencian ni se arreglan de paso (§8, §10).

## 5b. Fases entregables

> Cada fase es **mergeable por sí sola**, deja la base verde, y cabe en una sesión de agente que
> arranca con **contexto 0**: su memoria son este PRD, las skills y lo ya mergeado. Ninguna fase
> necesita "recordar" la sesión de otra. Orden canónico: contrato → lógica → orquestación/UI →
> pulido. Ninguna fase toca red + dominio + UI a la vez.

| Fase | Entrega (mergeable) | Depende de | Skills obligatorias (§11) |
|---|---|---|---|
| **1** | **Contrato del dominio**: `Movie`, `MovieID`, `PageNumber`, `MoviePage`, `MoviesError`, puerto `PopularMoviesRepository`, `FakePopularMoviesRepository` y **la suite de conformidad** parametrizada. Sin red, sin UI. | — | `domain/SKILL.md` + `tdd-workflow.md` |
| **2** | **Lógica pura de paginación** (`MoviesPaginationLogic`): acumular páginas, orden, unicidad de ids, "¿hay más?", guardas de re-entrada y de página fuera de orden. TDD puro contra el fake. | 1 | `architecture/SKILL.md` + `domain/SKILL.md` + `tdd-workflow.md` + `swift-estado-del-arte.md` |
| **3** | **Adapter TMDB del listado** sobre `APIServiceProtocol`: `TMDBConfiguration` (fail-closed), requests, DTOs, mappers, mapeo de errores, fixtures capturados de la API real, y **la MISMA suite de conformidad de la fase 1 corriendo contra el adapter** vía `MockURLProtocol`. Sin UI. | 1 | `domain/SKILL.md` + `security/SKILL.md` |
| **4** | **ViewModel del listado, primera carga** (sin paginación): `PopularMoviesViewModel` sobre `BaseViewModel` + `MoviesError+ScreenError` + las claves i18n de esos errores. Tests de orquestación con spy. Sin View. | 2, 3 | `architecture/SKILL.md` + `domain/SKILL.md` + `tdd-workflow.md` + `swift-estado-del-arte.md` |
| **5** | **La app muestra películas de verdad**: `PopularMoviesView` dentro de `ScreenContainer`, `MovieRowView`, `MoviesRoute`, `MoviesModule` (DI), `AppCoordinatorView` y `BaselineApp` como composition root. Goldens 1, 2, 8. | 4 | `architecture/SKILL.md` + `architecture/platforms/ios.md` |
| **6** | **Paginación por scroll**: `loadNextPageIfNeeded` en el ViewModel usando la lógica de la fase 2, `performActivity(style: .inline)`, rama de fallo de página N. Goldens 3, 4, 5. | 5 | `architecture/SKILL.md` + `domain/SKILL.md` + `tdd-workflow.md` + `swift-estado-del-arte.md` |
| **7** | **Contrato + adapter del detalle**: `MovieDetail`, puerto `MovieDetailRepository`, fake, su suite de conformidad, adapter TMDB y fixtures (incluido el 404). Sin UI. | 3 | `domain/SKILL.md` + `security/SKILL.md` + `tdd-workflow.md` |
| **8** | **Pantalla de detalle + navegación**: `MovieDetailViewModel`, `MovieDetailView` en `ScreenContainer`, ruta y `push` desde el listado. Golden 6. | 6, 7 | `architecture/SKILL.md` + `architecture/platforms/ios.md` + `domain/SKILL.md` + `tdd-workflow.md` + `swift-estado-del-arte.md` |
| **9** | **Cierre del módulo de referencia**: i18n ES+EN completa con test de claves, accesibilidad mínima (Dynamic Type + labels de VoiceOver), primera medición del mutation score (sujeta a **OQ-9**), diff propuesto de las skills para que CITEN este módulo, y `current_execution_map.md` actualizado. Golden 7. | 8 | `architecture/SKILL.md` + `architecture/platforms/ios.md` |

**Gate común a TODAS las fases (ninguna se da por cerrada sin esto):**

```bash
bash tools/verify-run.sh          # build + suite, y FIRMA la evidencia contra el diff staged
bash tools/check-drift.sh         # 0 errores nuevos (el ratchet está en errors:0 warns:0)
bash tools/check-layers.sh        # dirección de imports
bash tools/semgrep-scan.sh        # 0 hallazgos ERROR y 0 archivos con PartialParsing en Sources/
```
y después: stagea → invoca al sub-agente `reviewer` → commitea en un comando aparte (§13).

## 6. Modelo de datos

> No hay schema propio ni persistencia. El "modelo de datos" son **tres contratos**: la entidad de
> dominio, el puerto, y el DTO de transporte — y la frontera entre ellos.

### 6.1 Quién depende de quién (la única figura que importa)

```
        UI/Movies                     ← SwiftUI + AppFoundation. NO importa CoreNetworking.
   PopularMoviesView ──▶ PopularMoviesViewModel ──┐
   MovieDetailView   ──▶ MovieDetailViewModel   ──┤ (por protocolo, inyectado por ctor)
                                                  │
        Domain/Movies  ◀──────────────────────────┘  ← Foundation y NADA MÁS.
   Movie · MovieID · PageNumber · MoviePage · MoviesError
   PopularMoviesRepository (puerto) · MovieDetailRepository (puerto)
   MoviesPaginationLogic (lógica pura)
                    ▲
                    │ implementa
        Data/TMDB   │                              ← CoreNetworking. NO importa SwiftUI.
   TMDBPopularMoviesRepository ──▶ APIServiceProtocol ──▶ (red real o MockURLProtocol)
```

Reglas mecánicas que lo fijan (ya vivas en `tools/layers.conf`, no hay que escribirlas):

- `*/Domain/*` no puede importar `SwiftUI|UIKit|AppKit|WatchKit`, ni
  `CoreNetworking|CoreNetworkingTestSupport|AppFoundation`.
- `*/UI/*` no puede importar `CoreNetworking|CoreNetworkingTestSupport`.

> **Consecuencia directa y no negociable:** `MoviesError` **NO puede** conformar
> `AppErrorConvertible` dentro de `Domain/` — ese protocolo vive en `AppFoundation`. La conformidad
> va en `Sources/UI/Movies/MoviesError+ScreenError.swift`, que es donde el error de negocio se
> convierte en copy de pantalla. Esto no es un rodeo: es exactamente la separación que la regla
> existe para forzar. El dominio publica **casos de error tipados** (no claves de texto: ver §6.4,
> una clave `String` acabaría impresa en pantalla), la presentación publica
> **texto localizado**.

### 6.2 Entidades y tipos-valor (Domain — puro)

| Tipo | Forma | Por qué así |
|---|---|---|
| `MovieID` | envoltorio sobre el id de TMDB, `Hashable`, `Sendable` | pasar una página donde va un id deja de compilar |
| `PageNumber` | init **falible** con rango cerrado `1...500`; `static let first` | página 0 y página 501 dejan de ser representables (**OQ-8** fija el 500) |
| `Movie` | `id: MovieID`, `title`, `overview`, `posterPath: String?`, `releaseDate`, `voteAverage`; `Equatable, Sendable` | value type inmutable; sin lógica ni dependencias |
| `MoviePage` | `movies: [Movie]`, `page: PageNumber`, `nextPage: PageNumber?` | **`nextPage` en vez de `totalPages`**: el cálculo de "¿hay más?" ocurre UNA vez, en el adapter, y el ViewModel no puede equivocarse |
| `MovieDetail` | superset de `Movie` con los campos del endpoint de detalle | fase 7 |

`releaseDate` llega como `String` (OQ-2 resuelta: decoder por defecto, sin
`dateDecodingStrategy`). Junto con `voteAverage` se modela opcional —**OQ-7** (idioma) sigue
abierta— y **nunca** se ramifica sobre su texto.

### 6.3 Puertos

```
protocol PopularMoviesRepository: Sendable      // capability, no repo gigante (domain/SKILL.md)
    popularMovies(page: PageNumber) async throws(MoviesError) -> MoviePage

protocol MovieDetailRepository: Sendable
    movieDetail(id: MovieID) async throws(MoviesError) -> MovieDetail
```

**Garantías que el puerto PROMETE** (y que por tanto la suite de conformidad verifica en TODAS sus
implementaciones):

| # | Garantía |
|---|---|
| C1 | `popularMovies(page: p)` devuelve una `MoviePage` cuyo `page == p`. Nunca otra. |
| C2 | `nextPage` es `p + 1` mientras haya más páginas, y `nil` en la última. Nunca salta. |
| C3 | El orden de `movies` es el que dio la fuente. El puerto no reordena. |
| C4 | Pedir una página válida **más allá** de la última devuelve `MoviePage` vacía con `nextPage == nil`. **No lanza.** (Sujeto a **OQ-8**.) |
| C5 | `popularMovies(page:)` **no tiene efectos secundarios observables**: llamarlo N veces no altera el estado del repositorio ni el resultado de pedir otra página. |
| C6 | Un `MovieID` inexistente en `movieDetail` lanza `MoviesError.notFound`. Nunca devuelve un `MovieDetail` vacío ni `nil`. |
| C7 | Toda salida de error es un `MoviesError`; jamás escapa un `APIError`, un `URLError` ni un `DecodingError`. |
| C8 | Ningún valor lanzado ni devuelto contiene la clave de API. |

> ⚠️ **No-garantía explícita:** el contenido de una página **no es estable entre llamadas**.
> `popular` de TMDB se reordena según cambian los votos, así que pedir la página 1 dos veces puede
> devolver películas distintas. La versión anterior de C5 prometía justo lo contrario
> («dos llamadas seguidas devuelven lo mismo»), y su test habría pasado **solo porque
> `MockURLProtocol` reproduce la respuesta registrada**: habría verificado el mock, no el contrato.
> Un puerto de referencia que promete algo que su única implementación real no cumple es el peor
> artefacto que puede copiar un adoptante. Por esta inestabilidad existe el invariante de unicidad
> de la fase 2 (T-P-6): las páginas se deduplican por `MovieID` al acumularlas.

> **Cómo se añade caché mañana sin tocar ViewModels** (el diseño hay que dejarlo *posible*, no
> construirlo — ver §8): un `CachedPopularMoviesRepository` que envuelve a otro
> `PopularMoviesRepository`, se registra en `MoviesModule` en lugar del de red, y **pasa la misma
> suite de conformidad**. Cero cambios en `Domain/`, cero en `UI/`.

### 6.4 Errores de dominio

```
enum MoviesError: Error, Equatable, Sendable, CaseIterable   // CaseIterable: T-D-4 itera allCases
                                                             // en vez de una lista escrita a mano
    offline · unauthorized · notFound · rateLimited · server · malformedResponse · cancelled · unknown
    // SIN `messageKey`. Ver la nota de abajo: una clave de runtime acaba impresa en pantalla.
```

> ⚠️ **Por qué NO hay `messageKey: String`.** `ScreenError` tiene dos inits: uno con
> `LocalizedStringResource`, que localiza, y un `@_disfavoredOverload init(title: String, …)` que
> **guarda el valor verbatim** (`ViewPhase.swift:83-108`). Un `messageKey` es un `String` de
> runtime, así que caería **siempre** en el segundo: la pantalla mostraría `movies.error.offline`
> tal cual — que es exactamente el síntoma que el golden 7 dice cazar. Y hay un segundo problema:
> las claves construidas en runtime **no las extrae** el String Catalog, así que el test de
> «toda clave existe en ES y EN» habría verificado un catálogo que nadie llenó automáticamente.
>
> **En su lugar:** `Sources/UI/Movies/MoviesError+ScreenError.swift` es un `switch` **exhaustivo
> sin `default:`** que devuelve `ScreenError(title:message:)` con literales
> `LocalizedStringResource`. Se gana todo a la vez: el compilador (nivel 0) obliga a cubrir cada
> caso nuevo del enum, los literales los extrae el catálogo solos, y se usa el init que sí
> localiza. T-D-4/T-D-5 se convierten en «el switch es exhaustivo» (lo fija el compilador, no un
> test) más un test de que dos casos no comparten copy.
>
> Esto **contradice `domain/SKILL.md` §Errores**, que prescribe `userMessageKey`. Es un
> `<!-- FILL -->` heredado del template que este módulo debe corregir en vez de propagar: la
> corrección de la skill va en la fase 9, con su propio diff.

- `unauthorized` existe separado a propósito: es el síntoma de una clave ausente o inválida, y su
  copy **no menciona la clave** (§6 de AGENTS.md).
- `malformedResponse` cubre decoding y forma inesperada. **No se degrada a lista vacía**: un JSON
  roto es un error, no un resultado vacío (fail-silent nunca).
- `cancelled` tiene una regla propia, abajo.

### 6.5 Las trampas del contrato (leerlas antes de escribir el ViewModel)

**Trampa A — una cancelación con la Task VIVA sí pinta pantalla de error.**
`BaseViewModel.performLoad` no solo captura `CancellationError`: su rama genérica hace
`guard !Task.isCancelled, let self else { return }` **antes** de `setError`
(`BaseViewModel.swift:203`). Eso significa que el escenario obvio —dos `onAppear` seguidos, el
primero superseded— **ya está cubierto por el paquete**: esa tarea está cancelada, así que aunque
escape un `MoviesError.cancelled` no se pinta nada.

La trampa real es la otra mitad: un `MoviesError.cancelled` que llega con la Task **viva**. Ocurre
cuando la cancelación no la originó la Task sino el transporte — una `URLSession` invalidada, o un
`URLError.cancelled` que `APIService` mapea a `APIError.cancelled`. Ahí `Task.isCancelled` es
`false`, el guard no protege, y el usuario ve una pantalla de error por algo que no provocó.

**Regla del módulo (OQ-14):** el **adapter** decide. Si `Task.isCancelled` es `false`, la
cancelación es de transporte y se mapea a un error recuperable con retry; `MoviesError.cancelled`
queda solo para la cancelación propia, y esa sí la convierte en `throw CancellationError()` el
cierre de `performLoad` —**solo el de `performLoad`**: en `performActivity` dejaría el indicador
encendido para siempre—.

> **Por qué `MoviesError` tiene un caso `.cancelled` para empezar** —que es la decisión de diseño
> de verdad y faltaba escrita—: el puerto usa `throws(MoviesError)`. Con typed throws el adapter
> **no puede** relanzar un `CancellationError`, porque no es un `MoviesError`; está obligado a
> modelarla dentro del error de dominio. La conversión de vuelta en el ViewModel es el precio de
> esa decisión, no un capricho.

> ⚠️ **La versión anterior de esta trampa describía el escenario cubierto**, y su test (T-VM-4)
> habría pasado con y sin la mitigación — el anti-patrón nº1 de `tdd-workflow.md`, en el módulo
> que existe para enseñar a testear. Lo cazó el design-review. T-VM-4 está reescrito abajo para
> que muera si se quita la conversión.

**Trampa B — `performActivity` cancela la actividad en vuelo.**
Un scroll rápido puede disparar dos veces la carga de la página siguiente; la segunda cancela la
primera y el listado se queda sin crecer y **sin error visible**. **Regla del módulo:** el guard de
re-entrada vive en la **lógica pura** (fase 2), no en el ViewModel: si ya hay una página en vuelo,
la petición se ignora — no se lanza una segunda. Tiene test propio (T-VM-6).

**Trampa C — el ViewModel se recrea vacío en cada navegación si nace dentro del closure de rutas.**
`CoordinatorView.body` lee `Bindable(coordinator).mainStack.path` y `coordinator.modal`, y llama
`content(route)` **en cada evaluación** (`CoordinatorView.swift:55-87`). El ejemplo del README de
`AppFoundation` —el que un agente copiará— construye el ViewModel dentro de ese closure. Resultado:
cada `push`/`pop` fabrica un `PopularMoviesViewModel` nuevo, con `phase == .idle` y `movies == []`,
y `onAppear` **no vuelve a dispararse** porque la vista ya apareció. El listado queda en blanco al
volver del detalle, sin error y sin carga: rompe de frente el escenario **golden 6** («al volver
atrás el listado conserva su contenido y su posición»).

**Regla del módulo (OQ-13):** la identidad vive en un `MoviesScreenStore` que retiene el
composition root, y el closure pide la instancia:

```swift
@MainActor final class MoviesScreenStore {          // lo retiene el composition root
    private var popularVM: PopularMoviesViewModel?
    func popular() -> PopularMoviesViewModel {      // memoizada: misma instancia siempre
        if let popularVM { return popularVM }
        let vm = PopularMoviesViewModel(...)
        popularVM = vm
        return vm
    }
}
// en el closure de rutas:  PopularMoviesView(viewModel: store.popular())
```

Se eligió esto y no un `@State` en una vista-pantalla envolvente por una razón de verificación, no
de estilo: `@State` solo tiene identidad cuando SwiftUI **instala** la vista, y §8 prohíbe UI
tests — así que un test unitario no podría distinguir la implementación correcta de la rota. Con la
factoría, **T-VM-11** es un test corriente: dos invocaciones devuelven la misma instancia (`===`) y
conservan las películas. Entra en la **fase 5** junto al closure, no en la 8: una fase que entrega
el closure sin el store mergea con el bug dentro.

### 6.6 Contrato de transporte (Data)

- Endpoints: `GET /3/movie/popular?page=<n>` y `GET /3/movie/{id}`. Host desde `TMDBHost`
  (`Info.plist`), esquema añadido en código (el xcconfig no puede llevar `//`).
- Autenticación: **OQ-1**.
- DTOs `Decodable` separados de las entidades, con **`CodingKeys` explícitas** (OQ-2 resuelta
  leyendo `APIService.swift:225`: `JSONDecoder()` sin configurar, sin conversión de snake_case).
  Lo confirma igualmente el primer test de la fase 3 —decodificar un fixture real a través de
  `APIService` + `MockURLProtocol`—: si el paquete cambiara de decoder en una versión futura, ese
  test se pone rojo. **La lectura del código decide hoy; el test lo mantiene cierto mañana.**
- `TMDBConfiguration` **falla cerrada**: sin `TMDBReadAccessToken` o con el placeholder
  `pon_aqui_tu_token_de_lectura`, construir el repositorio lanza/devuelve `MoviesError.unauthorized` con copy
  localizado ("falta configurar la clave"), sin imprimir jamás el valor leído.

## 7. Flujo de la solución

### User stories

- Como usuario quiero ver las películas populares nada más abrir la app para decidir qué ver.
- Como usuario quiero que el listado siga creciendo al llegar al final, sin pulsar nada.
- Como usuario quiero tocar una película y ver su ficha, y volver al listado donde estaba.
- Como usuario quiero entender qué pasó cuando falla (sin red, servidor caído) y poder reintentar.
- Como **agente que arranca un proyecto nuevo** quiero un módulo real que copiar en vez de un
  ejemplo inventado en una skill.

### Estados de pantalla (quién los pinta)

`ScreenContainer` pinta carga / error / vacío / contenido a partir del `phase` del ViewModel.
**La vista no reimplementa ninguno de los cuatro.** Reparto:

| Situación | `phase` | `activity` | Quién decide |
|---|---|---|---|
| Primera carga | `.loading(.fullScreen)` | `.none` | `performLoad` |
| Primera carga OK con resultados | `.content` | `.none` | el ViewModel (`successTransition: .preserveCurrentPhase`) |
| Primera carga OK con 0 resultados | `.empty` | `.none` | el ViewModel |
| Primera carga falla | `.error(ScreenError con retry)` | `.none` | `performLoad` + `MoviesError+ScreenError` |
| Cargando página N>1 | `.content` (**no cambia**) | `.loading(.inline)` | `performActivity(style: .inline)` |
| Página N>1 falla | `.content` (**no cambia**) | `.none` + banner | `performActivity(errorHandling: .banner)` — ver **OQ-12** |
| Sin más páginas | `.content` | `.none` | `MoviesPaginationLogic` (no se llama al puerto) |

### Edge cases

- **Última página** → `nextPage == nil` → el scroll al final no dispara nada. Cero peticiones.
- **Página vacía dentro del rango** → C4: página vacía con `nextPage == nil`; si es la primera,
  `.empty`; si es una posterior, **no se pierden** los elementos ya cargados y la fase sigue
  `.content`.
- **Ids duplicados entre páginas.** `popular` de TMDB se reordena entre peticiones, así que una
  película puede volver a aparecer en la página siguiente. Invariante del módulo: **los ids del
  listado acumulado son únicos y conservan el orden de primera aparición.** Property-based.
- **Página fuera de orden** (llega la 3 cuando se esperaba la 2, por un retry raro): se descarta.
- **JSON malformado / campos ausentes** → `.malformedResponse`, nunca lista vacía silenciosa.
- **401 por clave ausente o inválida** → `.unauthorized`, y la clave no aparece en el mensaje.
- **429** → `.rateLimited`. `CoreNetworking` ya reintenta con `Retry-After`; si aun así falla, el
  error llega mapeado.
- **Sin red** → `.offline` con botón de reintentar que vuelve a llamar al puerto.
- **Doble `onAppear`** (vuelta desde el detalle, re-montaje de la vista) → no dispara una segunda
  carga completa ni pierde el contenido. Ojo: la razón de que el contenido sobreviva es la
  **Trampa C** (el ViewModel lo memoiza `MoviesScreenStore`, OQ-13), no la Trampa A —
  `performLoad` ya protege el caso superseded por su cuenta.
- **Rotación / Dynamic Type XXL** → el listado no rompe (fase 9).

## 8. Anti-features (qué NO entra)

- ❌ **Persistencia de cualquier tipo**: sin Core Data, sin SwiftData, sin caché en disco, sin
  `URLCache` configurado a mano. El puerto queda **preparado** para un decorador de caché; el
  decorador **no se escribe** en este PRD.
- ❌ Búsqueda, filtros, ordenación, favoritos, listas del usuario, valoraciones, login, trailers,
  reparto, películas similares, recomendaciones.
- ❌ Pull-to-refresh (`performActivity` lo soportaría; no está pedido).
- ❌ Otros endpoints de TMDB (`now_playing`, `top_rated`, `upcoming`, `search`).
- ❌ SSL pinning de TMDB. `CoreNetworking` lo soporta; fijar los SPKI de un tercero es una decisión
  de operación con coste de rotación, y no está pedida.
- ❌ Snapshot tests / UI tests. Los tests de esta vertical son unitarios (Swift Testing) sobre
  dominio, lógica, adapters y ViewModels. Ver §16.
- ❌ Design system, tokens, tema propio, animaciones. La UI usa componentes SwiftUI estándar.
- ❌ Analytics, crash reporting, feature flags.
- ❌ Publicar `1.0.0` de los paquetes. Es la consecuencia de esta vertical, no parte de ella (§16).
- ❌ Tocar cualquier cosa del §NO-TOUCH "porque ya que estamos" (§8 de AGENTS.md).

## 9. Escenarios golden (deben pasar al terminar)

1. **Listado.** Dado `Config/Secrets.xcconfig` con una clave válida, cuando arranco la app,
   entonces veo el listado de populares de la página 1 y `phase == .content`.
2. **Sin red.** Dado el simulador en modo avión, cuando arranco, entonces `ScreenContainer` muestra
   la pantalla de error con el copy localizado de "sin conexión" y un botón de reintentar; al
   restaurar la red y pulsarlo, el listado carga.
3. **Paginación.** Dado el listado cargado, cuando hago scroll hasta el final, entonces se añade la
   página 2 **debajo**, sin duplicar filas, sin que salte la posición, con indicador `.inline` y
   con el contenido visible todo el tiempo.
4. **Última página.** Dado que el fake/fixture está en la última página, cuando sigo haciendo
   scroll, entonces **no se emite ninguna petición más** (`MockURLProtocol.recordedRequests` no
   crece).
5. **Fallo de página N.** Dado el listado con 2 páginas y la 3ª devolviendo 500, cuando llego al
   final, entonces las películas ya cargadas siguen visibles, `phase` sigue `.content` y aparece un
   banner de error.
6. **Detalle.** Dado el listado, cuando toco la tercera película, entonces navego al detalle de
   **esa** película (id correcto) y al volver atrás el listado conserva su contenido y su posición.
7. **i18n.** Dado el simulador en español y luego en inglés, cuando recorro las dos pantallas y
   fuerzo un error, entonces ningún texto visible es una clave sin traducir ni está en el idioma
   equivocado.
8. **La clave no se filtra.** Dada una clave inválida, cuando arranco, entonces veo el error de
   autenticación **y la clave no aparece** en la UI, ni en los logs de la app, ni en el mensaje del
   error, ni en la salida de los tests.

> ### ⚠️ La pregunta que hay que hacerle a cada fila de esta tabla
>
> Tres rondas de design-review encontraron **el mismo defecto tres veces**, y siempre disfrazado
> de otra cosa: *el test se coloca en una capa donde el mecanismo que dice proteger no existe.*
>
> - **B1** puso el test en el ViewModel cuando la protección vivía en `BaseViewModel` (el paquete).
> - **OQ-13** lo puso en un `@State` cuando el proyecto no tiene UI tests que puedan instalarlo.
> - **OQ-14** lo puso en el ViewModel con un **fake del puerto**, cuando la regla vive en el
>   **adapter** — y un fake no contiene la lógica del adapter, así que el test decidía él mismo
>   qué lanzar.
>
> Los tres pasaban en verde con la implementación correcta **y con la rota**. Antes de dar por
> buena una fila, una sola pregunta:
>
> **¿Qué línea concreta borro para que este test se ponga rojo — y está esa línea en la misma capa
> que el doble que estoy usando?**
>
> Si la respuesta es «ninguna» o «está en otra capa», la fila no vale todavía.

## 9b. Matriz de tests (derivada del contrato y del riesgo, no de una cuota)

> 🔴 **rojo primero, siempre.** Cada fila entra como test que falla por la razón correcta antes de
> existir su implementación (§5 de AGENTS.md).

**Dominio — invariantes por tipo (fase 1). PBT = property-based.**

| id | Qué fija | Tipo |
|---|---|---|
| T-D-1 | `PageNumber(n)` existe ⟺ `n ∈ 1...500`; `rawValue == n` | PBT |
| T-D-2 | `PageNumber(n) == nil` para `n ≤ 0` y `n > 500` | PBT |
| T-D-3 | `MoviePage.nextPage` es `page+1` o `nil` — nunca otro valor | PBT |
| T-D-4 | Dos casos distintos de `MoviesError` no comparten copy | exhaustivo |
| T-D-5 | Por cada caso, su `ScreenError` renderizado en `Locale(identifier: "es")` **difiere del literal fuente** | exhaustivo (fase 9). No basta con que el `switch` sea exhaustivo —eso solo garantiza que hay literal, no que esté traducido—: sin este test, una cadena sin traducir cae al inglés y solo lo caza el golden 7 a ojo. **Muere si falta la traducción.** Depende de `SWIFT_EMIT_LOC_STRINGS` (OQ-3) |

**Conformidad puerto ↔ implementaciones (fases 1, 3, 7). UNA suite, dos ejecuciones.**

| id | Contrato | Fake | Adapter |
|---|---|:--:|:--:|
| T-C-1 | C1 — la página devuelta es la pedida | ✓ | ✓ |
| T-C-2 | C2 — `nextPage` = `p+1` o `nil` en la última | ✓ | ✓ |
| T-C-3 | C3 — el orden de la fuente se conserva | ✓ | ✓ |
| T-C-4 | C4 — página válida más allá de la última: vacía, `nextPage nil`, no lanza | ✓ | ✓ |
| T-C-5 | C5 — sin efectos secundarios observables: pedir la página 1 dos veces no altera lo que devuelve la página 2 | ✓ | ✓ |

> Nota honesta sobre T-C-5: hoy **no puede fallar** en ninguna de las dos implementaciones (ni el
> fake ni un adapter HTTP sin estado tienen estado que corromper), y el nivel 4 lo delatará como
> test que no mata mutantes. Se mantiene porque su valor real llega con el **decorador de caché**
> (§16.2), que sí tiene estado: es la garantía que ese decorador tendrá que seguir cumpliendo.
> Se declara aquí para que nadie lo cuente como cobertura de hoy.
| T-C-6 | C6 — id inexistente ⇒ `.notFound` | ✓ | ✓ |
| T-C-7 | C7 — nunca escapa un `APIError`/`URLError`/`DecodingError` | ✓ | ✓ |
| T-C-8 | C8 — ninguna salida contiene la clave sentinela | ✓ | ✓ |

**Lógica de paginación (fase 2) — el núcleo del TDD.**

| id | Caso | Tipo |
|---|---|---|
| T-P-1 | happy: estado vacío + página 1 ⇒ N elementos, `canLoadMore == true` | ejemplo |
| T-P-2 | append de la página 2 ⇒ 2N elementos **en orden**, `canLoadMore` según `nextPage` | ejemplo |
| T-P-3 | última página (`nextPage == nil`) ⇒ `canLoadMore == false` | ejemplo |
| T-P-4 | primera página vacía ⇒ estado "vacío" y `canLoadMore == false` | ejemplo |
| T-P-5 | página posterior vacía ⇒ **no se pierden** los elementos ya cargados; sigue "contenido" | ejemplo |
| T-P-6 | ids duplicados entre páginas ⇒ **unicidad + orden de primera aparición** | **PBT** |
| T-P-7 | página fuera de orden (≠ la esperada) ⇒ se descarta, el estado no cambia | ejemplo |
| T-P-8 | petición mientras hay una página en vuelo ⇒ se ignora (guard de re-entrada) | ejemplo |
| T-P-9 | fallo de página ⇒ el estado conserva lo cargado y **conserva la página a reintentar** | ejemplo |

**Adapter / mapeo de errores (fases 3 y 7), con `MockURLProtocol` y fixtures reales.**

| id | Entrada | Salida esperada |
|---|---|---|
| T-A-1 | `popular_page1.json`, 200 | `MoviePage` con los datos del fixture (fija de paso el decoder — **OQ-2**) |
| T-A-2 | `URLError(.notConnectedToInternet)` | `.offline` |
| T-A-3 | HTTP 401 | `.unauthorized` |
| T-A-4 | HTTP 404 (detalle) | `.notFound` |
| T-A-5 | HTTP 429 con `Retry-After` | `.rateLimited` |
| T-A-6 | HTTP 500 | `.server` |
| T-A-7 | `malformed_page.json` (falta `results`) | `.malformedResponse` |
| T-A-8 | `results` con tipos equivocados | `.malformedResponse` |
| T-A-9 | `MockNetworkExchange(latency:)` + `Task` cancelado a media petición | `.cancelled` |
| T-A-9b | `MockURLProtocol` devuelve `URLError(.cancelled)` **sin** cancelar la Task | el repositorio lanza el caso **recuperable**, NO `.cancelled` (OQ-14). **T-A-9 y T-A-9b son un par**: por separado ninguno mata los dos mutantes («siempre `.cancelled`» y «nunca `.cancelled`»); juntos, sí. Aquí vive la regla —en el adapter—, así que aquí va su test |
| T-A-10 | la query/headers enviados incluyen `page=<n>` (assert sobre `recordedRequests`) | request correcta |
| T-A-11 | config sin clave o con el placeholder | `.unauthorized`, sin imprimir el valor |
| T-A-12 | **sentinela**: para CADA caso de error, ni `description`, ni `ScreenError.title/message`, ni la traza contienen la clave | 0 apariciones |

**Orquestación — ViewModel (fases 4, 6, 8). Doble = fake+spy con eventos `enum`; el ORDEN es contrato.**

| id | Caso | Aserción |
|---|---|---|
| T-VM-1 | `onAppear` OK con resultados | eventos `[.loadedPage(1)]`; `phase: .idle → .loading(.fullScreen) → .content`; películas publicadas |
| T-VM-2 | `onAppear` OK con 0 resultados | `phase == .empty` (**no** `.content` con lista vacía) |
| T-VM-3 | `onAppear` con error | `phase == .error(...)`; el `retry` del `ScreenError` vuelve a llamar al puerto (2ª entrada en el spy) |
| T-VM-4 | el fake lanza `MoviesError.cancelled` con la Task **viva** | `phase` **NO es `.loading`** (ni se queda colgada ni pinta error espurio). Aserción sobre el estado que de verdad puede romperse: la anterior (`== .error` con retry) es cierta para *cualquier* error que escape, con o sin la regla de OQ-14, porque `performLoad` siempre pasa un `retry` no-nil (`BaseViewModel.swift:204-213`) |
| T-VM-11 | reevaluar el closure de rutas del `Coordinator` (simulando un `push`+`pop`) | el ViewModel **no** se reemplaza y las películas acumuladas siguen ahí (Trampa C). Muere si la factoría construye una instancia nueva en vez de devolver la memoizada |
| T-VM-5 | scroll al final con `nextPage != nil` | el puerto se llama **exactamente una vez** con `nextPage` |
| T-VM-6 | scroll al final llamado 5 veces seguidas | el puerto se llama **una** vez (Trampa B) |
| T-VM-7 | scroll al final en la última página | el puerto **no se llama** |
| T-VM-8 | fallo de la página N>1 | `phase` sigue `.content`, las películas siguen, `banner != nil` |
| T-VM-9 | seleccionar una película | `router.push(.detail(id:))` con el id correcto **y nada más** en el spy |
| T-VM-10 | detalle OK / `.notFound` / `.offline` | fases y copys correspondientes |

**Lo que NO se testea, dicho a propósito:** los `body` de SwiftUI (glue sin lógica), el
`DependencyModule` (wiring trivial) y los `#Preview`. Ver `tdd-workflow.md` §"NO obligatorio para".

## 10. Métricas de éxito

A las 2-4 semanas:

1. **El siguiente proyecto nuevo se arranca copiando este módulo** y llega a su primera pantalla
   con datos reales sin abrir un solo archivo de `AppFoundation`/`CoreNetworking`.
2. **Las skills citan archivos, no ejemplos inventados**: ≥1 `<!-- FILL -->` sustituido por una
   referencia real en cada una de `architecture/SKILL.md`, `architecture/platforms/ios.md` y
   `domain/SKILL.md`.
3. **El nivel 4 deja de estar mudo**: `tools/mutation-ratchet.json` con `measured: true` y un piso
   real (sujeto a **OQ-9**).
4. **Las reglas propias de `layers.conf` dejan de ser prosa**: `check-layers.sh` evalúa archivos
   reales en `Domain/` y `UI/` y pasa.
5. **Cero findings de tier alto abiertos** contra el módulo en el ledger al cerrar la fase 9.

## 11. Rollout

- **Sin feature flag.** La app no está publicada; no hay usuarios que proteger ni tráfico que
  dividir. Un flag aquí sería ceremonia.
- **Sin migración de datos** (no hay datos).
- **El rollout ES el troceo de §5b**: cada fase se mergea sola y deja `main` verde. Las fases 1-4 y
  7 no cambian nada visible; la 5 enciende la primera pantalla; la 6 la paginación; la 8 el
  detalle.
- **Rollback** = revertir el commit de la fase. Como ninguna fase depende de estado externo ni deja
  migraciones, revertir es suficiente y no hay que deshacer nada más.
- **Push solo con aprobación explícita del owner** (§7).

## 12. Riesgos

| # | Riesgo | Mitigación |
|---|---|---|
| R1 | **La API que asume este PRD la leí de los clones locales de `spm-pro`, no de los tags publicados** (AppFoundation 0.1.1 / CoreNetworking 0.1.3). Pueden divergir. | **OQ-10**. La fase 3 es la primera que compila contra los paquetes de verdad; si diverge, Open Question + finding, **jamás un parche local** (§NO-TOUCH). |
| R2 | La clave de TMDB acaba en una URL logueada. `LoggingInterceptor` redacta **headers** sensibles; una query `?api_key=` viaja en la URL completa. | **OQ-1** + T-A-12 (sentinela) como test permanente en toda fase que toque `Data/`. |
| R3 | `switch try await` deja el archivo **entero** sin escanear en el nivel 2, y nadie avisa. | Convención del proyecto (ligar el resultado a una variable antes del `switch`) + criterio de aceptación "0 `PartialParsing` en `Sources/`". |
| R4 | Fallo silencioso de paginación: `performActivity` cancela la actividad en vuelo y el listado deja de crecer sin error. | Trampa B: guard de re-entrada en la lógica **pura** + T-P-8 y T-VM-6. |
| R5 | Flash de pantalla de error por una cancelación de transporte (sesión invalidada), con la Task viva. | Trampa A + T-VM-4. El caso superseded lo cubre ya `performLoad`. |
| R6 | `popular` de TMDB se reordena entre peticiones ⇒ filas duplicadas. | T-P-6 (property-based de unicidad y orden). |
| R7 | El drift-ratchet está en `errors: 0, warns: 0` y `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`: **un solo warning nuevo bloquea**. | No es un riesgo a mitigar, es la condición de trabajo. Se declara aquí para que nadie lo descubra a mitad de fase. |
| R8 | Contexto agotado a mitad de capa (el modo de fallo del PRD-monolito). | §5b: 9 fases, ninguna cruza red+dominio+UI. |

## 13. Open Questions

> **Bloqueantes** para `Approved` o para la fase indicada. Ninguna tiene un default inventado (§1.4).

- [x] **OQ-1 — RESUELTA (2026-08-28). `Authorization: Bearer <read access token>`.**
      Decidido con la documentación de TMDB delante, no por preferencia:
      - **Es lo que TMDB recomienda.** Su guía de autenticación llama al token de lectura *"the
        default method to authenticate"*, y señala que sirve **para v3 y v4 a la vez**: una sola
        credencial en vez de dos. Ambos métodos dan el mismo nivel de acceso, así que no se
        renuncia a nada.
      - **Y es lo que nuestro propio código exige.** `LoggingInterceptor` redacta los headers
        siempre (`HeaderRedactor.redact`, `RequestInterceptor.swift:102`) pero loguea la URL
        entera —`NetLog.network.debug("→ \(method) \(url, privacy: .private)")`, línea 99—. Con
        `?api_key=` la clave real aparece en la consola de Xcode de cualquiera que depure el
        proyecto; en un header no aparece nunca. Chocaba de frente con AGENTS.md §6.
      - `api_key` en query **no está deprecado** y seguiría funcionando; se descarta por lo de
        arriba, no porque vaya a dejar de servir.

      **Consecuencia para el diseño:** la credencial entra por `defaultHeaders` de
      `NetworkingConfiguration`, no por `queryItems` del request. El xcconfig pasa a llamarse
      `TMDB_READ_ACCESS_TOKEN` (el nombre `TMDB_API_KEY` describía la otra opción y habría
      quedado mintiendo). Y **desaparece un problema de tests que este PRD daba por inevitable**:
      `MockURLProtocol` casa por método + URL exacta, así que con la credencial en la query cada
      registro de mock habría tenido que incluirla en la URL; en un header, las URLs de los mocks
      quedan limpias. Ojo: eso era incomodidad, no un riesgo de secretos — en tests la credencial
      siempre habría sido ficticia, porque `MockURLProtocol.canInit` devuelve `true` siempre y
      **ninguna petición sale a la red**.
- [x] **OQ-2 — RESUELTA (2026-08-28, corregida). El decoder lo elige el consumidor; aquí se elige
      el de por defecto.** La primera versión de esta resolución citaba
      `APIService.swift:225` (`JSONDecoder()` recién instanciado) y abría un finding contra
      `CoreNetworking` por no ser configurable. **Ese finding ya está cerrado**: el paquete lo
      resolvió en `0.1.2` — `NetworkingConfiguration.makeDecoder` es una fábrica
      `@Sendable () -> JSONDecoder` con default `{ JSONDecoder() }`, y `APIService` la usa
      (`:76`, `:94`). El PRD se había quedado atrás de su propio arreglo; lo cazó el design-review.
      **Lo que esto cambia:** usar el decoder por defecto deja de ser una restricción del paquete y
      pasa a ser una **elección de este módulo**, y como tal se declara: DTOs con `CodingKeys`
      explícitas (`case posterPath = "poster_path"`) **porque preferimos que la traducción
      snake_case→camelCase se lea en el DTO**, delante de quien mantiene el mapeo, en vez de
      ocurrir por una estrategia global invisible. `release_date` llega como `String`; convertirlo
      —si hace falta— es trabajo del mapeo a la entidad, no del decoder.
      T-A-1 fija la elección contra un fixture real: si alguien pone `.convertFromSnakeCase` en la
      configuración, ese test se pone rojo.
- [ ] **OQ-3 — 🔴 BLOQUEANTE fase 5. ¿Se autoriza tocar `project.yml`?** Queda **solo la parte
      (a)**: declarar `Sources/Resources/Localizable.xcstrings` para que el String Catalog entre al
      bundle. Son build settings ⇒ decisión de owner (lección [2026-08-08]).
      **Y dos cosas más en el mismo viaje**, que sin ellas el mecanismo de B4 no funciona:
      `knownRegions`/`CFBundleLocalizations` con `es` (sin eso el golden 7 falla aunque el
      `.xcstrings` esté perfecto) y `SWIFT_EMIT_LOC_STRINGS: YES` (sin eso el catálogo no extrae
      nada, en silencio — ver OQ-15).
      *(La parte (b) —`package: AppFoundation` en el target de tests— **está resuelta**:
      `Tests/UnitTests/SmokeTests.swift:3` ya hace `import AppFoundation` y compila.)*
- [ ] **OQ-4 — 🟠 BLOQUEANTE fase 4/5. ¿`Sources/UI/Movies/` o `Sources/Features/Movies/`?** Dos
      docs internos se contradicen: `architecture/platforms/ios.md` prescribe `Features/<Nombre>/`,
      y `tools/layers.conf` solo aplica la regla "la UI no habla HTTP" al glob `*/UI/*`. Con
      `Features/`, **esa regla queda muda para todo el módulo de referencia** — justo el módulo que
      existe para demostrar que las capas se respetan. Este PRD asume `UI/` provisionalmente; es
      decisión del owner (y arrastra o bien renombrar aquí, o bien tocar `layers.conf`, que es
      NO-TOUCH).
- [ ] **OQ-5 — 🟠 ¿Se muestran pósters, y cómo?** Tres tensiones a la vez: (a) AGENTS.md §3 dice
      "todo acceso HTTP pasa por `APIService` … nada de `URLSession` suelto", y `AsyncImage` **es**
      `URLSession` por dentro; (b) `layers.conf` prohíbe `import CoreNetworking` en `*/UI/*`, así
      que la vista no puede descargar por su cuenta ni con el paquete; (c) TMDB devuelve
      `poster_path` relativo — la URL completa necesita la base de imágenes y un tamaño, que
      oficialmente salen del endpoint `/3/configuration`. Opciones: `AsyncImage` con excepción
      declarada en `docs/process/decisions/`; un puerto `MoviePosterLoading` con adapter sobre
      `APIService.download`; o listado sin imagen. Y si hay imagen: ¿base y tamaño fijos o desde
      `/configuration`? *(Si la respuesta es "puerto propio", esto es **una fase más**, no un
      añadido a la 5.)*
- [ ] **OQ-6 — 🟠 BLOQUEANTE fase 7. ¿El detalle re-consulta `/3/movie/{id}` o reutiliza la entidad
      del listado?** Reutilizar ahorra un puerto, un adapter y dos fases; consultar ejercita una
      segunda ruta completa (request, decoding, 404, error en contexto de detalle), que es
      exactamente lo que un módulo de referencia debe demostrar. Este PRD asume **re-consultar**
      (fases 7-8) porque el owner declaró que el valor está en cruzar capas; confírmalo o córtalo.
- [ ] **OQ-7 — 🟡 ¿Qué `language` se envía a TMDB, y qué hacemos con los campos vacíos?** La app es
      ES+EN. ¿Derivamos `language` del locale del dispositivo (`es-ES`/`en-US`)? TMDB devuelve con
      frecuencia `overview` **vacío** en español: ¿fallback a inglés (segunda petición), placeholder
      localizado, u ocultar el campo? Nota: derivar de un identificador de locale es legítimo;
      ramificar sobre el texto devuelto **no lo es** (§3).
- [ ] **OQ-8 — 🟡 BLOQUEANTE fase 1 (fija un tipo). Confirmar contra la API real dos cosas:**
      (a) que `page > 500` es un error del servidor —lo que justifica que `PageNumber` cierre el
      rango en 500—, y (b) que una página válida **más allá** de `total_pages` devuelve 200 con
      `results: []` en vez de un error. La garantía C4 del puerto depende de (b). *Resolución:
      un `curl` manual del owner cuya respuesta se congela como `popular_beyond_last_page.json`
      — la evidencia es el fixture, no una afirmación.*
- [ ] **OQ-9 — 🟠 El nivel 4 está MUDO y esta es la ocasión de estrenarlo.**
      `tools/mutation-ratchet.json` dice `"measured": false` y **no existe `muter.conf.yml`** en la
      raíz, así que `mutation-score.sh` no tiene runner. ¿Se autoriza crear esa config en la fase 9
      para fijar el primer piso con este módulo? Si la respuesta es no, el §15 **no puede** incluir
      el gate de mutación y hay que decirlo en vez de fingirlo.
- [x] **OQ-10 — RESUELTA (2026-08-28). El clon local y lo publicado son idénticos.** Se clonaron
      ambos repos publicados en un temporal y se comparó `Sources/` contra el árbol local:
      `diff -rq` sin diferencias en los dos paquetes. Así que la API que este PRD asume, leída del
      clon, **es** la que resuelve `Package.resolved` (AppFoundation 0.1.1, CoreNetworking 0.1.3).
      *Nota de método, por si alguien repite la comprobación:* no sirve `git merge-base
      --is-ancestor` contra el clon, porque las revisiones publicadas salieron de un
      `git subtree split` y son commits distintos con el mismo contenido. Se compara **contenido**,
      no ancestría. Y `DeepLinkAction` sale de la lista: es de otro scope.
- [x] **OQ-11 — RESUELTA (2026-08-28). Las tres cosas existen.** No era una pregunta para el
      owner: era una lectura que faltó. El archivo está en
      `Sources/AppFoundation/UI/Containers/ScreenContainer.swift`:
      (a) **sí** — `navigation:` es `.hidden` por defecto y hay init de conveniencia
      `ScreenContainer(viewModel:title:style:navigationPlacement:content:)` sin botón atrás
      (`:457-471`); (b) **sí** — `.emptyView { }` acepta vista y copy propios (`:437-441`);
      (c) **sí** — el título es `LocalizedStringResource`. Ninguna petición a `AppFoundation`.
      Corregido de paso: la firma real es `.withBack(title:style:backAction:)`, no
      `.withBack(title:)`.
- [x] **OQ-13 — RESUELTA por el owner (2026-08-28). Factoría memoizada.** La identidad del
      ViewModel **no** se confía a `@State`: vive en un `MoviesScreenStore` retenido por el
      composition root, y el closure de rutas hace `PopularMoviesView(viewModel: store.popular())`.
      La vista-pantalla con `@State` sigue siendo válida encima, pero deja de ser lo único que
      sostiene el golden 6.
      **Por qué esta y no `@State` a secas:** `@State` solo tiene identidad cuando SwiftUI
      *instala* la vista, y §8 prohíbe UI tests — así que la versión anterior de T-VM-11 **no podía
      fallar**, la misma patología que motivó B1. Con la factoría, T-VM-11 es un test unitario
      corriente: dos invocaciones de `store.popular()` devuelven la **misma instancia** (`===`) y
      conservan las películas acumuladas. Muere si la factoría construye una nueva.
      **Entregable:** `MoviesScreenStore.swift` entra en §5 y en la **fase 5** (no en la 8): si la
      fase 5 entrega el closure sin él, mergea con el bug de identidad dentro, y cada fase tiene
      que ser mergeable con la base verde.
- [x] **OQ-14 — RESUELTA por el owner (2026-08-28). El adapter distingue quién canceló.**
      Si `Task.isCancelled` es `false`, la cancelación **no la pidió nadie de nuestro lado** (sesión
      invalidada, `URLError.cancelled` de transporte): el adapter la mapea a un error **recuperable
      con retry**, no a `MoviesError.cancelled`. Ese caso queda reservado a la cancelación propia,
      la que sí debe convertirse en `CancellationError`.
      **Qué resuelve, en orden de importancia:**
      1. Desaparece el spinner permanente. `performLoad` captura `CancellationError` sin tocar
         `phase` (`BaseViewModel.swift:200-201`), así que convertir *toda* cancelación habría
         dejado la pantalla cargando para siempre — cambiar un fallo visible por uno silencioso es
         peor que el original.
      2. **T-VM-4 pasa a aserción positiva**: `phase == .error` con retry disponible, en vez de
         «NO queda en `.error`». Una aserción negativa pasaba igual con la pantalla colgada.
      3. La conversión a `CancellationError` queda **acotada a los cierres de `performLoad`**. Sin
         acotarla, aplicada a la paginación, `performActivity` la captura sin llamar a
         `stopActivity()` (`:240-241`): indicador encendido para siempre y paginación muerta — que
         es el riesgo R4 entrando por la puerta que abre la Trampa A.
      **Fila nueva en la matriz:** *página N cancelada con la Task viva ⇒ `activity == .none`, el
      guard de re-entrada liberado, y un scroll posterior vuelve a pedir esa página* (T-P-11).
- [ ] **OQ-15 — 🟠 ¿Entra `SWIFT_EMIT_LOC_STRINGS: YES` en el mismo permiso de `project.yml` que
      OQ-3(a)?** Sin él, el String Catalog **no extrae nada** y todo el mecanismo de B4 produce un
      catálogo vacío en silencio. Va junto a `knownRegions`/`CFBundleLocalizations` con `es`.
- [ ] **OQ-12 — 🟡 ¿Cómo se presenta el fallo de una página N>1?** El default de `performActivity`
      es un **banner**; la alternativa es una fila de "reintentar" al final del listado (más
      descubrible, más código). Y en cualquier caso: al fallar, ¿se conserva la página pendiente
      para reintentar la MISMA (asumido en T-P-9) o se reintenta desde `nextPage` del último éxito?

## 14. Mockups / referencias

```
┌─ Populares ──────────────┐        ┌─ ‹ Volver ───────────────┐
│ ▢ Título de la película  │        │  ▢▢▢▢  Título            │
│   2026 · ★ 7.8           │        │        2026 · ★ 7.8      │
│ ─────────────────────────│  tap   │                          │
│ ▢ Otra película          │ ─────▶ │  Sinopsis…               │
│   2025 · ★ 6.4           │        │                          │
│ ─────────────────────────│        │                          │
│ ▢ …                      │        │                          │
│      ⟳  (inline)         │◀─ carga la página siguiente       │
└──────────────────────────┘        └──────────────────────────┘
   phase .content                       phase .content
   activity .loading(.inline)
```

- API de TMDB: `https://developer.themoviedb.org/reference/movie-popular-list`
- `AppFoundation` README §"Primary phase vs secondary activity" y §"Errors: `AppErrorConvertible`".
- `CoreNetworking` README §"Testing" (`MockURLProtocol`, `MockAPIService`, `recordedRequests`).
- Layout y pósters dependen de **OQ-5**; el ASCII no prejuzga la respuesta.

## 15. Definition of Done

**Verificable por comando (no por opinión):**

- [ ] `bash tools/verify-run.sh` → **exit 0** (build + suite completa, evidencia firmada contra el
      diff staged)
- [ ] `bash tools/check-drift.sh` → **0 errores y 0 warnings nuevos** (el ratchet está en 0/0)
- [ ] `bash tools/check-layers.sh` → **exit 0**, y evalúa archivos reales en `Domain/` y `UI/` — **no en `Data/`**: `layers.conf` no tiene ninguna regla `*/Data/*`, así que esa carpeta no la mira nadie (pedirla es NO-TOUCH: OQ nueva si se quiere)
- [ ] `bash tools/semgrep-scan.sh` → **exit 0** y **0 archivos con `PartialParsing` bajo `Sources/`**
- [ ] `bash tools/lesson-detector-link.sh` → exit 0
- [ ] `bash tools/check-execution-map.sh` → exit 0 (mapa actualizado en el **mismo** commit)
- [ ] `bash tools/findings/findings.sh render` → sin findings de tier alto abiertos contra el módulo
- [ ] Anillo 1 en verde: `gitleaks` sin leaks sobre el staged
- [ ] Anillo 3 en verde en el push (`.github/workflows/gates.yml`, ambos jobs)
- [ ] `bash tools/mutation-score.sh --check` → exit 0; y `--update` deja `measured: true` con piso
      real **— condicionado a OQ-9. Si el owner no autoriza `muter.conf.yml`, esta casilla se
      TACHA con la razón, no se marca.**

**De contenido:**

- [ ] Los 8 escenarios golden de §9 pasan (los 3-6 con fixtures deterministas; 1, 2, 7 y 8 a mano
      en el simulador, dejando constancia en el PR)
- [ ] **TDD**: cada fila de §9b existe, se escribió **antes** de su implementación y cubre las ramas
      de error, recuperación y límite; los tests de conformidad corren **contra el fake y contra el
      adapter**
- [ ] Ningún archivo supera el hard limit de §4 (400 líneas / 60 por función / 250 el ViewModel)
- [ ] `reviewer` GREEN o AMBER atendido en cada fase · `security-reviewer` en las fases 3, 5 y 7
      (tocan la clave)
- [ ] `design-reviewer` pasado sobre este PRD **antes** del primer commit de código (§12 — gate
      distinto del `Approved` del owner)
- [ ] Ninguna ruta del §NO-TOUCH aparece en el diff de ninguna fase
- [ ] Sin secretos en código, logs ni mensajes de error; T-A-12 (sentinela) en verde
- [ ] Docs actualizados en el mismo PR: `current_execution_map.md` y el **diff propuesto** de las
      skills (que el owner aprueba aparte)

## 16. Próximos pasos

1. **Publicar `1.0.0` de `AppFoundation` y `CoreNetworking`.** Era el plan declarado en
   `current_execution_map.md` §2: se congela cuando la vertical haya ejercitado la API entera. Esta
   vertical es esa vertical — y las OQ-10 y OQ-11 son justo la lista de lo que hay que confirmar
   antes de congelar.
2. **El decorador de caché.** El puerto queda preparado (§6.3); escribirlo será un PRD corto:
   un `CachedPopularMoviesRepository`, su registro en `MoviesModule` y la misma suite de
   conformidad. Cero cambios en `Domain/` y `UI/` — y si hicieran falta, el diseño de este PRD
   estaba mal.
3. **Snapshot tests** de las dos pantallas (fuera de scope aquí, §8): decisión de herramienta +
   coste de mantenimiento.
4. ~~Cerrar los findings de R9 y R10~~ — **ya cerrados** durante la preparación de este PRD. Lo
   que el documento pedía registrar ya estaba arreglado: ordenar findings falsos rompe §10 justo
   en el módulo que existe para enseñar §10.
5. **Pull-to-refresh** y el resto de endpoints, si alguna vez hacen falta como demostración.

## 17. Change log

| Fecha | Cambio | Quién |
|---|---|---|
| 2026-08-27 | Draft inicial: contratos por capa, matriz de tests, 9 fases, 12 Open Questions | prd-writer |
| 2026-08-28 | Cierre de los 4 bloqueantes del design-review + OQ-1/2/3(b)/10/11/13/14 resueltas; T-VM-4 recolocado al adapter (T-A-9b) y regla de capa añadida a §9b | owner + reviewer |

## 18. Gaps detectados (llenar post-ship)

*(Se rellena al cerrar la fase 9. Alimenta `docs/process/lessons_learned.md` —toda entrada exige
`Detector:`— y `tools/findings/`.)*

Semillas ya identificadas al escribir el PRD, para no perderlas:

- ~~R9~~ **CERRADO (2026-08-28)**: `skill-matrix.conf:42` ya tiene `*/UI/*` junto a `*/ui/*`,
  con el comentario que explica por qué hacen falta las dos grafías. No queda gap.
- ~~R10~~ **CERRADO (2026-08-28)**: `verify.conf:46` ya lleva `-test-timeouts-enabled YES`. Lo que
  queda —que el umbral no esté fijado, sino en el default de Xcode— vive como finding
  `f-5529624d` en el ledger, con su redacción exacta.
- El README de `CoreNetworking` documenta el pipeline pero **no** la configuración del `JSONDecoder`
  (OQ-2), que es lo primero que necesita quien escribe un DTO.

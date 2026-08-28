# PRD 0001 — Vertical de referencia: películas (listado + detalle, TMDB)

> **Tipo:** Forward · **Status:** ✅ **Approved** (owner, 2026-08-28) — los 4 bloqueantes del
> design-review cerrados y verificados en el archivo a lo largo de seis pasadas del gate
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
> **`Approved` el 2026-08-28.** Siguen abiertas —y NO bloquean el slice 0, que es lo que este
> `Approved` habilita— las Open Questions OQ-3, OQ-5 a OQ-9, OQ-12, OQ-15, OQ-21 y OQ-22
> (índice completo en §13). Cada una bloquea el slice donde toca, no este. **OQ-4 resuelta el 2026-08-28** (`Features/`, con `layers.conf`
> actualizado para que la regla de capa no quedara muda — ver la OQ).
> **Autor:** prd-writer (sub-agente) · **Fecha:** 2026-08-27 · **Tracking:** —
> **Design-review:** **seis** pasadas, todas 🔴 RED. 2026-08-27 (4 bloqueantes) · 2026-08-28 ×5
> (26, 13, 12, 13 y 14 hallazgos). Los 4 bloqueantes originales —N1 troceo, N2 contrato
> republicado, N3 forma de C5, N4 idioma fuente— **están cerrados y verificados en el archivo**.
> Cada pasada posterior encontró la misma clase de defecto en una variante nueva: un arreglo
> escrito donde se descubrió el problema y no propagado a las secciones que se marcan o se
> ejecutan — primero otras secciones del PRD, luego el registro de las propias revisiones, luego
> el contrato publicado en código. Historial y hallazgos:
> [`reviews/2026-08-28-design-review-prd-0001.md`](../reviews/2026-08-28-design-review-prd-0001.md).
>
> El `Approved` del owner se dio **sobre un gate que nunca llegó a GREEN**, y eso es legítimo
> por §12: el design-review y el `Approved` son gates distintos. Lo que el owner aprobó es que
> los cuatro bloqueantes de diseño están cerrados y que el resto son desalineamientos de
> documento, ninguno de los cuales bloquea el slice 0.
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
| Archivos evaluados por las reglas propias de `layers.conf` (`*/Domain/*`, `*/Features/*`) | 0 | > 0, y `check-layers.sh` en verde |
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
    MovieDetail.swift                  ← entidad del detalle (slice de detalle)
    PageNumber.swift                   ← tipo-valor con rango cerrado 1...500 (invariante por tipo)
    MoviePage.swift                    ← página de resultados + nextPage: PageNumber?
    MoviesError.swift                  ← error de dominio tipado, CaseIterable. SIN messageKey (§6.4)
    PopularMoviesRepository.swift      ← PUERTO (capability: cargar una página de populares)
    MovieDetailRepository.swift        ← PUERTO (capability: cargar el detalle de una película)
    MoviesPaginationLogic.swift        ← lógica pura de acumulación/paginación (slice de paginación)

  Data/Movies/
    TMDBConfiguration.swift            ← lee TMDBReadAccessToken/TMDBHost; falla CERRADA
    TMDBRequests.swift                 ← BaseRequest para /3/movie/popular y /3/movie/{id}
    TMDBDTOs.swift                     ← DTOs Decodable (frontera de transporte, NO dominio)
    TMDBMovieMapper.swift              ← DTO → dominio (única traducción, sin lógica de negocio)
    TMDBErrorMapper.swift              ← APIError → MoviesError
    TMDBPopularMoviesRepository.swift  ← ADAPTER del puerto sobre APIServiceProtocol
    TMDBMovieDetailRepository.swift    ← ADAPTER del puerto de detalle (slice de detalle)

  Features/Movies/                     ← OQ-4 RESUELTA (2026-08-28): Features/, no UI/
    MoviesRoute.swift                  ← enum de rutas (Hashable)
    MoviesModule.swift                 ← DependencyModule: registra los adapters reales
    MoviesError+ScreenError.swift      ← mapeo error de dominio → ScreenError (AppErrorConvertible)
    PopularMoviesViewModel.swift       ← orquestación sobre BaseViewModel
    PopularMoviesView.swift            ← SwiftUI dentro de ScreenContainer
    MovieRowView.swift                 ← fila del listado
    MovieDetailViewModel.swift         ← orquestación del detalle (slice de detalle)
    MovieDetailView.swift              ← detalle dentro de ScreenContainer (slice de detalle)

  App/
    BaselineApp.swift                  ← TOCAR: composition root real (hoy pinta un Text)
    AppCoordinatorView.swift           ← monta Coordinator<MoviesRoute> + CoordinatorView

  Resources/
    Localizable.xcstrings              ← String Catalog ES+EN (sujeto a OQ-3 si hay que declararlo)

> ⚠️ **Este árbol es el PLAN, y el slice 0 entregó otra cosa** (5ª pasada, H-9). Lo entregado:
> `Tests/UnitTests/Movies/` —una carpeta por módulo, no por capa— con el fake canónico y el
> catálogo **dentro** de `PopularMoviesRepositoryConformance.swift` y los JSON inline en vez de
> en `Fixtures/`. Y en `Sources/`, `App/Movies/MoviesScreenStore.swift` **no aparece en este
> árbol** pese a que OQ-13 dice que entra.
>
> No es cosmético: un agente que entre en frío al slice 1 leerá este árbol, creará
> `Tests/UnitTests/Support/FakePopularMoviesRepository.swift` y **duplicará el fake canónico** —
> justo el escenario que la suite de conformidad existe para evitar. **Decidir en el slice 1**:
> o el árbol se actualiza a `Movies/`, o los archivos se mueven al plan. Hoy manda el árbol real.

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
.agents/skills/**                 ← meta-doc (§8). El slice de cierre PROPONE un diff; no lo mergea sin OK
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
> pulido.

> 🔴 **La regla «ninguna fase toca red + dominio + UI a la vez» se ABANDONA para el slice 0, a
> propósito y por decisión del owner (2026-08-28).**
>
> El slice 0 es un **walking skeleton**: cruza Domain + Data + Features + App de una vez, con
> `Movie`, el puerto, el adapter TMDB, el ViewModel, la vista y el composition root. Rompe la
> regla deliberadamente, porque **el cableado tiene que existir antes que la funcionalidad**: una
> fase 1 que entregara solo el contrato del dominio no habría demostrado que los dos paquetes,
> el composition root, la fase de pantalla y los gates encajan — y ese encaje es justo lo que
> este módulo existe para demostrar.
>
> **A partir del slice 1 la regla vuelve a regir.** El troceo restante es por capacidad
> observable, no por capa.
>
> Esto se declara aquí porque durante un tiempo el PRD dijo una cosa y la ejecución hizo otra: el
> criterio de troceo es la decisión más *load-bearing* del documento, y un agente entrando en frío
> a «la fase 2» habría buscado una fase 1 con `PageNumber` que nunca existió.

**Troceo vigente:**

| Slice | Entrega | Revisores obligatorios | Skills obligatorias (§11) | Estado |
|---|---|---|---|---|
| **0** | Vertical mínima end-to-end: listado de populares (primera página), sin paginación ni detalle ni pósters. Cruza todas las capas. | `design-reviewer` · `reviewer` · **`security-reviewer`** (toca la credencial) | `domain/SKILL.md` · `architecture/SKILL.md` · `architecture/platforms/ios.md` · `platforms/swift-estado-del-arte.md` · `process/references/tdd-workflow.md` · `security/SKILL.md` | escrito, pendiente de commit |
| **1+** | Por capacidad observable (paginación, detalle, pósters, i18n), cada una respetando de nuevo el orden contrato → lógica → UI. | `reviewer` siempre; `security-reviewer` en todo slice que toque credencial, almacenamiento o authz | las que exija `tools/skill-matrix.conf` para los paths que toque — **el conf es la fuente, esta columna la vista** | por trocear |

> ⚠️ **La columna de revisores existe por un fallo de esta misma reescritura.** El DoD anclaba
> el `security-reviewer` a «las fases 3, 5 y 7», y al declarar no vigente la tabla de 9 fases esa
> obligación se quedó sin ancla: el slice 0 **sí** toca la credencial y se iba a commitear sin
> ese gate. Anclar una defensa a una numeración que puede cambiar es cómo una defensa
> desaparece sin que nadie la retire (§14.4). Ahora va anclada al slice y a lo que el slice
> toca. Ledger: `f-3236fb0`.

> 🗑️ **La tabla de 9 fases se BORRÓ el 2026-08-28** (4ª pasada del design-review, B-1).
>
> No se conserva «como histórico», y esa es la decisión: mientras existía, seguía siendo la
> **fuente** de una veintena de citas «fase N» repartidas por §5, §6, §9b, §12 y §13 — y cada
> pasada del gate encontraba referencias nuevas apuntándola. Una de ellas se llevó por delante
> un gate de seguridad real: el DoD ancló el `security-reviewer` a «las fases 3, 5 y 7» y, al
> declarar la tabla no vigente, esa obligación se quedó sin ancla mientras el slice 0 —que sí
> toca la credencial— iba camino de commitearse sin ella.
>
> Es el nivel 0 aplicado a un documento: en vez de detectar las citas inválidas una a una,
> hacer que no puedan escribirse. El plan de 9 fases queda pegado entero en
> el **Anexo** del dictamen `docs/process/reviews/2026-08-28-design-review-prd-0001.md`, donde
> está pegada entera. *(La versión anterior de esta frase decía que quedaba «en el change log §17
> y en el dictamen» y no estaba en ninguno de los dos: se borró afirmando que se preservaba, que
> es §14.4 aplicado a un archivo. La 5ª pasada lo cazó y el anexo lo arregla.)* **El troceo
> vigente es el de la tabla de slices de arriba**, y es el único al que se debe citar.

**Gate común a TODAS las fases (ninguna se da por cerrada sin esto):**

```bash
bash tools/verify-run.sh          # build + suite, y FIRMA la evidencia contra el diff staged
bash tools/check-drift.sh         # 0 errores nuevos (el ratchet está en errors:0 warns:0)
bash tools/check-layers.sh        # dirección de imports
bash tools/semgrep-scan.sh        # 0 hallazgos ERROR y 0 archivos con PartialParsing en Sources/
```
y después: stagea → invoca al sub-agente `reviewer` → commitea en un comando aparte (§13).

> ✅ **Autorizaciones del owner sobre rutas NO-TOUCH (registradas, §8 / H-7).** El DoD exige que
> ninguna ruta NO-TOUCH aparezca en el diff sin permiso; estas lo tienen:
>
> | Ruta | Autorizado para | Cuándo |
> |---|---|---|
> | `tools/layers.conf` | añadir las reglas `*/Features/*` y borrar la `*/UI/*` huérfana | OQ-4, 2026-08-28 |
> | `tools/check-layers-coverage.sh` (nuevo) | crear el detector de la lección del glob mudo | 2026-08-28 — §10 obliga a que toda lección tenga detector, así que el permiso es consecuencia de la regla, no una excepción a ella |
> | `ci/run-gates.sh` | cablear ese detector como paso 4a | 2026-08-28 — un detector que no corre en ningún gate no es un detector |
> | `tools/skill-matrix.conf` | añadir `*/Features/*` y `*/App/*` | **OQ-C, 2026-08-28** — sin ellos `Sources/App/**` se editaba sin ninguna lectura obligatoria, incluido el archivo que compone el header `Authorization` |
> | `AGENTS.md` §11 (tabla) | las dos filas correspondientes | **OQ-C, 2026-08-28** — el conf y la tabla deben coincidir; lo verifica `check-skill-matrix-doc.sh` |
> | `tools/tests/test_layers_coverage.sh` (nuevo) | crear los tests de FALSO POSITIVO del detector | **2026-08-28** — el `MANIFEST` de `test_meta_fp.sh` exige que todo detector tenga tests de FP; sin ellos no sabríamos si supera el ~10% que lo condenaría (§14.2) |
> | `tools/tests/test_meta_fp.sh` | registrar el detector en el `MANIFEST` | **2026-08-28** — su propio comentario lo pide «en el MISMO cambio» |
> | `tools/tests/test_e2e_gates_anillo3.sh` | añadir el detector a `_G9_INVENTARIO` | **2026-08-28** — sin ello el golden 9 corría el detector real contra un repo fake y tumbaba el escenario «todo en verde» |
>
> *(Esta tabla decía «lo que **no** está autorizado y por eso no se hizo: `skill-matrix.conf` y
> `AGENTS.md`» **después** de que el owner autorizara ambos y de que el cambio estuviera hecho.
> Corregido en la 6ª pasada, B-3: una tabla de autorizaciones que niega un permiso concedido
> vuelve imposible de marcar la casilla del DoD que ella misma hace marcable.)*

## 6. Modelo de datos

> No hay schema propio ni persistencia. El "modelo de datos" son **tres contratos**: la entidad de
> dominio, el puerto, y el DTO de transporte — y la frontera entre ellos.

### 6.1 Quién depende de quién (la única figura que importa)

```
        Features/Movies                     ← SwiftUI + AppFoundation. NO importa CoreNetworking.
   PopularMoviesView ──▶ PopularMoviesViewModel ──┐
   MovieDetailView   ──▶ MovieDetailViewModel   ──┤ (por protocolo, inyectado por ctor)
                                                  │
        Domain/Movies  ◀──────────────────────────┘  ← Foundation y NADA MÁS.
   Movie · MovieID · PageNumber · MoviePage · MoviesError
   PopularMoviesRepository (puerto) · MovieDetailRepository (puerto)
   MoviesPaginationLogic (lógica pura)
                    ▲
                    │ implementa
        Data/Movies │                              ← CoreNetworking. NO importa SwiftUI.
   TMDBPopularMoviesRepository ──▶ APIServiceProtocol ──▶ (red real o MockURLProtocol)
```

Reglas mecánicas que lo fijan (ya vivas en `tools/layers.conf`, no hay que escribirlas):

- `*/Domain/*` no puede importar `SwiftUI|UIKit|AppKit|WatchKit`, ni
  `CoreNetworking|CoreNetworkingTestSupport|AppFoundation`.
- `*/Features/*` no puede importar `CoreNetworking|CoreNetworkingTestSupport` (la UI no habla
  HTTP), ni `Supabase|Firebase|CoreData|…` (no accede a datos directamente). Son las dos reglas
  vivas en `tools/layers.conf`. La versión `*/UI/*` de la primera **se borró** el 2026-08-28:
  tras el movimiento a `Features/` no casaba con ningún archivo, y conservarla «como red para
  código heredado» era una racionalización — una regla que no mira nada no es una red.

> **Consecuencia directa y no negociable:** `MoviesError` **NO puede** conformar
> `AppErrorConvertible` dentro de `Domain/` — ese protocolo vive en `AppFoundation`. La conformidad
> va en `Sources/Features/Movies/MoviesError+ScreenError.swift`, que es donde el error de negocio se
> convierte en copy de pantalla. Esto no es un rodeo: es exactamente la separación que la regla
> existe para forzar. El dominio publica **casos de error tipados** (no claves de texto: ver §6.4,
> una clave `String` acabaría impresa en pantalla), la presentación publica
> **texto localizado**.

### 6.2 Entidades y tipos-valor (Domain — puro)

| Tipo | Forma | Por qué así |
|---|---|---|
| `MovieID` | envoltorio sobre el id de TMDB, `Hashable`, `Sendable` | pasar una página donde va un id deja de compilar |
| `PageNumber` | init **falible** con rango cerrado `1...500`; `static let first` | página 0 y página 501 dejan de ser representables (**OQ-8** fija el 500) |
| `Movie` | **HOY**: `id: MovieID`, `title`, `posterPath: String?`, `voteAverage: Double?`; `Equatable, Sendable, Identifiable`. **PENDIENTE**: `overview` y `releaseDate`, que entran con el slice de detalle | value type inmutable; sin lógica ni dependencias. *(Esta fila publicaba `overview` y `releaseDate` como si existieran: §6.3 recibió el corte vigente/pendiente tras N2 y §6.2 no. 6ª pasada, H-9.)* |
| `MoviePage` | `movies: [Movie]`, `page: PageNumber`, `nextPage: PageNumber?` | **`nextPage` en vez de `totalPages`**: el cálculo de "¿hay más?" ocurre UNA vez, en el adapter, y el ViewModel no puede equivocarse |
| `MovieDetail` | superset de `Movie` con los campos del endpoint de detalle | slice de detalle |

`releaseDate` llega como `String` (OQ-2 resuelta: decoder por defecto, sin
`dateDecodingStrategy`). Junto con `voteAverage` se modela opcional —**OQ-7** (idioma) sigue
abierta— y **nunca** se ramifica sobre su texto.

### 6.3 Puertos

> 🔴 **Regla dura, nacida de un fallo real (2026-08-28).** Un identificador de garantía
> (`C-n`) es **inmutable**. Cuando una garantía cambia de significado, se **retira** y se
> numera una nueva; **no se recicla la etiqueta**. Esta sección tuvo durante un tiempo un `C1`
> («la página devuelta es la pedida») en el PRD y otro `C1` distinto («nunca devuelve `nil`»)
> en el código publicado, con el mismo nombre y contenidos incompatibles. El identificador es
> lo único estable de un contrato: si miente, todo lo que lo cita miente con él.

#### Contrato VIGENTE — el publicado en `Sources/Domain/Movies/PopularMoviesRepository.swift`

```
protocol PopularMoviesRepository: Sendable      // capability, no repo gigante (domain/SKILL.md)
    popularMovies() async throws(MoviesError) -> [Movie]
```

Sin paginación: el slice 0 entrega la primera página y nada más. Estas son las garantías que
el puerto promete **hoy**, y las únicas que la suite de conformidad puede citar:

| # | Garantía | Cómo se verifica |
|---|---|---|
| C1 | Nunca devuelve `nil`: o hay películas, o hay lista vacía, o lanza. | **Por tipo** (`[Movie]`). Sin test: no hay nada que verificar en runtime. |
| ~~C2~~ | **RETIRADA el 2026-08-28** (OQ-17, ledger `f-f6b72573`). Prometía ids únicos, incompatible con C3: deduplicar es reordenar. **No-garantía explícita: el puerto NO deduplica.** La unicidad la impone el acumulador de paginación (T-P-6), que es quien tiene el estado donde un duplicado importa. | — |
| C3 | El orden es el que dio la fuente. El puerto no reordena. | Suite de conformidad, fake + adapter real. |
| C5 | No tiene efectos secundarios observables: llamarlo N veces no altera el estado del repositorio. | **Hoy no verificable — ver el recuadro de abajo.** |
| C7 | Toda salida de error es un `MoviesError`; jamás escapa un `APIError`, un `URLError` ni un `DecodingError`. | **Por tipo** (`throws(MoviesError)`). El mapeo caso a caso sí se prueba, en la suite del adapter. |

> ⚠️ **C5: la forma de la aserción, no solo su enunciado.** Se prohíbe expresamente
> verificar C5 como *«llamar dos veces y comprobar que devuelve lo mismo»*. Con la fuente fija
> por `MockURLProtocol`, esa aserción comprueba que el mock reproduce su respuesta registrada
> —cosa que hace por construcción—, no que el repositorio carezca de estado. Es la forma que
> el design-review ya rechazó en su bloqueante B2, y **se volvió a escribir igual** el
> 2026-08-28 porque el PRD había renombrado la garantía sin prohibir la forma.
>
> **Forma admisible:** mutar el repositorio entre llamadas — pedir A, pedir B, volver a pedir
> A y comprobar que B no alteró A. `popularMovies()` no toma parámetros, así que **hoy no hay
> dos operaciones que distinguir y C5 no es observable**. Entra en la suite cuando exista el
> primer cliente capaz de romperla: el decorador de caché de §16.2.

#### Contrato PENDIENTE — el slice de paginación (aún no escrito)

Numeración **propia** (`PG-n`), precisamente para no reciclar las etiquetas de arriba. Nada de
esto existe todavía en el código: ni `PageNumber`, ni `MoviePage`, ni la firma con `page:`.

```
popularMovies(page: PageNumber) async throws(MoviesError) -> MoviePage    // PENDIENTE
```

| # | Garantía (pendiente) |
|---|---|
| PG1 | `popularMovies(page: p)` devuelve una `MoviePage` cuyo `page == p`. Nunca otra. |
| PG2 | `nextPage` es `p + 1` mientras haya más páginas, y `nil` en la última. Nunca salta. |
| PG3 | Pedir una página válida **más allá** de la última devuelve `MoviePage` vacía con `nextPage == nil`. **No lanza.** (Sujeto a **OQ-8**.) |

#### Contrato PENDIENTE — el slice de detalle (aún no escrito)

```
protocol MovieDetailRepository: Sendable                                   // PENDIENTE
    movieDetail(id: MovieID) async throws(MoviesError) -> MovieDetail
```

| # | Garantía (pendiente) |
|---|---|
| DT1 | Un `MovieID` inexistente lanza `MoviesError.notFound`. Nunca devuelve un `MovieDetail` vacío ni `nil`. |

#### Garantía transversal

| # | Garantía | Cómo se verifica |
|---|---|---|
| S1 | Ningún valor lanzado ni devuelto contiene la credencial de API. | Por construcción: ningún caso de `MoviesError` tiene valores asociados de tipo `String`. Más el test de copy (`MoviesErrorScreenErrorTests`) y T-A-12 (sentinela, pendiente). |

> ⚠️ **No-garantía explícita:** el contenido de una página **no es estable entre llamadas**.
> `popular` de TMDB se reordena según cambian los votos, así que pedir la página 1 dos veces puede
> devolver películas distintas. La versión anterior de C5 prometía justo lo contrario
> («dos llamadas seguidas devuelven lo mismo»), y su test habría pasado **solo porque
> `MockURLProtocol` reproduce la respuesta registrada**: habría verificado el mock, no el contrato.
> Un puerto de referencia que promete algo que su única implementación real no cumple es el peor
> artefacto que puede copiar un adoptante. Por esta inestabilidad existe el invariante de unicidad
> del slice de paginación (T-P-6): las páginas se deduplican por `MovieID` al acumularlas.

> **Cómo se añade caché mañana sin tocar ViewModels** (el diseño hay que dejarlo *posible*, no
> construirlo — ver §8): un `CachedPopularMoviesRepository` que envuelve a otro
> `PopularMoviesRepository`, se registra en `MoviesModule` en lugar del de red, y **pasa la misma
> suite de conformidad**. Cero cambios en `Domain/`, cero en `Features/`.

> 🔴 **OQ-18 RESUELTA (2026-08-28, owner): `TransportError` va al SPM, partido en dos.**
>
> - **`TransportError` (enum) + `init(from: APIError)` → `CoreNetworking`**, junto a `APIError`.
>   Es transporte puro (401/429/500/offline): ni dominio ni app.
> - **`extension TransportError: AppErrorConvertible` (el copy) → se queda en la app**, en
>   `Sources/Features/Movies/`.
>
> **Por qué partido y no entero en el paquete.** Los dos SPM son hoy **independientes**
> (verificado en sus `Package.swift`: ninguno depende del otro). Conformar `AppErrorConvertible`
> dentro de `CoreNetworking` obligaría a que el paquete de red dependiera de `AppFoundation`, y
> se perdería poder usar el cliente HTTP sin arrastrar la arquitectura de UI. Y el copy es
> **producto y está en español** (decisión de §6.4): un paquete compartido no puede llevar
> «Sin conexión» dentro.
>
> **Por qué al SPM y no local a la app — el argumento decisivo.** La app es un **módulo único**:
> con `TransportError` en `Sources/App/` o `Sources/Core/`, un tipo referenciado desde
> `Sources/Domain/` **compila sin que ningún gate lo vea** (`check-layers.sh` trabaja sobre
> imports, y dentro de un módulo no hay imports que mirar). Habría habido que declarar la
> frontera como no vigilada. En el paquete llega por `import CoreNetworking`, y la regla
> `*/Domain/* :: ^(CoreNetworking|…)$` que ya existe **lo cubre automáticamente**. Mover al SPM
> convierte una frontera no verificable en verificable: sube del nivel «disciplina humana» al
> nivel 6.
>
> **Restricción dura heredada del design-review (T-S-1):** `TransportError` **sin payloads
> `String`**. Hoy S1 se sostiene *por construcción* —ningún caso de error lleva `String`
> asociado— y un mensaje libre mataría ese argumento. Atención especial a
> `APIError.custom(APIMessageError, …)`, que arrastra el mensaje del servidor: **no entra**.
>
> **Orden:** el slice 0 se commitea **primero**. No puede quedar bloqueado esperando a un
> paquete publicado; publicar `CoreNetworking 0.1.4` y re-fijar `Package.resolved` es el paso
> siguiente, ya con un punto de retorno en `main`.

> 🔴 **OQ-20 RESUELTA (2026-08-28, owner): `TMDBConfiguration.swift` vive en `Data/Movies/`.**
>
> **El fallo:** tras mover a `Features/` (OQ-4) se actualizó `tools/layers.conf` y **no**
> `tools/skill-matrix.conf`. Verificado con el matcher real del hook: el archivo que lee
> `TMDBReadAccessToken` y compone `Authorization: Bearer` **no casaba con ningún glob de la
> matriz**, así que podía editarse sin haber leído `security/SKILL.md`. Es la lección del glob
> mudo cobrándose una segunda víctima el mismo día en que se escribió, en otro conf.
>
> **El arreglo:** `git mv Sources/App/Movies/TMDBConfiguration.swift Sources/Data/Movies/`.
> Ahora casa `*/Data/*` → exige `domain/SKILL.md` + `security/SKILL.md`. Y es donde §5 de este
> PRD ya decía que vivía: componer la configuración HTTP a partir del bundle es infraestructura,
> no composition root. No hubo que tocar meta-doc ni el conf.
>
> **Lo que NO cierra esto.** Mover un archivo arregló *ese* archivo; la clase entera seguía sin
> barrer. Pasados **los diez del slice 0** por el matcher real del hook (5ª pasada, H-6):
>
> | Archivo | Lecturas que exige la matriz |
> |---|---|
> | `App/BaselineApp.swift` | ⚠️ **NINGUNA** — y construye el `APIService` con el header `Authorization` y define `SinCredencialRepository` |
> | `App/Movies/MoviesScreenStore.swift` | solo `*Screen*.swift` — **accidente léxico** («ScreenStore»); no exige `tdd-workflow.md` pese a ser el dueño de una identidad que un test verifica |
> | `Features/Movies/MoviesError+ScreenError.swift` | solo `*Screen*.swift` — **accidente léxico** («ScreenError») |
> | `Features/Movies/PopularMoviesView.swift` | `*View*.swift` ✅ |
> | `Features/Movies/PopularMoviesViewModel.swift` | `*View*.swift` + `*ViewModel*.swift` ✅ |
> | `Domain/Movies/*` (3) | `*/Domain/*` ✅ |
> | `Data/Movies/*` (2) | `*/Data/*` ✅ |
>
> O sea: **`Sources/App/**` entero se edita sin ninguna lectura obligatoria**, y dos archivos
> están cubiertos por una coincidencia de letras, no por una regla. Una cobertura accidental no
> es cobertura: el día que alguien renombre `MoviesScreenStore` a `MoviesStore`, desaparece sin
> que nadie lo note — que es la misma clase de fallo que la lección del glob mudo.
>
> ✅ **CERRADO el 2026-08-28 (OQ-C, autorizado por el owner).** `tools/skill-matrix.conf` gana
> `*/Features/*` → `architecture` + `platforms/ios`, y `*/App/*` → `architecture` + **`security`**
> (es composition root: arma el grafo y es por donde entran las credenciales al proceso). La
> tabla §11 de `AGENTS.md` recibe las dos filas correspondientes.
>
> **La evidencia es la pasada con el matcher real del hook:** los **diez** archivos del slice 0
> casan ahora con una regla, no con un accidente léxico. `BaselineApp.swift` pasa de cero
> lecturas a exigir `security/SKILL.md`, que es lo que debía exigir desde el principio.
>
> *(Y NO vale citar aquí `check-skill-matrix-doc.sh` en `0/0`, como decía la primera versión de
> este recuadro: ese script compara solo el **conjunto de referencias**, nunca los globs, y esas
> tres skills ya estaban citadas antes de OQ-C. Habría dado `0/0` igual si me hubiera olvidado de
> las filas de `AGENTS.md`. Una evidencia que no depende del cambio no es evidencia de ese
> cambio. 6ª pasada, H-12.)*

### 6.4 Errores de dominio

```
enum MoviesError: Error, Equatable, Sendable, CaseIterable   // CaseIterable: T-D-4 itera allCases
                                                             // en vez de una lista escrita a mano
    offline · unauthorized · notFound · rateLimited · server · malformedResponse
    · connectionInterrupted · unknown
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
> **En su lugar:** `Sources/Features/Movies/MoviesError+ScreenError.swift` es un `switch` **exhaustivo
> sin `default:`** que devuelve `ScreenError(title:message:)` con literales
> `LocalizedStringResource`. Se gana todo a la vez: el compilador (nivel 0) obliga a cubrir cada
> caso nuevo del enum, los literales los extrae el catálogo solos, y se usa el init que sí
> localiza. T-D-4/T-D-5 se convierten en «el switch es exhaustivo» (lo fija el compilador, no un
> test) más un test de que dos casos no comparten copy.
>
> Esto **contradice `domain/SKILL.md` §Errores**, que prescribe `userMessageKey`. Es un
> `<!-- FILL -->` heredado del template que este módulo debe corregir en vez de propagar: la
> corrección de la skill va en el slice de cierre, con su propio diff. **También contradice
> `architecture/platforms/ios.md:84-85`** («error de dominio tipado con `userMessageKey` que la
> View localiza»), que es **lectura obligatoria para editar cualquier `*View*.swift`** — o sea,
> hoy un agente que toque una View lee la prescripción rechazada. Esa skill entra en el mismo
> diff de corrección.

> 🔴 **DECISIÓN (2026-08-28, owner): el idioma fuente de los literales es `es`.**
>
> No es una OQ más: es consecuencia obligada de B4, igual que `layers.conf` lo fue de OQ-4.
> `ScreenError.init` hace `String(localized: title)` (`ViewPhase.swift:83-91`), así que **el
> literal fuente ES la clave del String Catalog**. Los literales escritos son castellanos
> (`"Sin conexión"`, `"Películas populares"`), y por tanto las claves del catálogo lo serán.
>
> **Consecuencias que hay que ejecutar, no solo anotar:**
>
> 1. **`developmentRegion: es` en `project.yml`** — se añade a la lista de **OQ-3** junto a
>    `knownRegions`/`CFBundleLocalizations` y `SWIFT_EMIT_LOC_STRINGS`. Sin él, las otras tres no
>    bastan: el `.xcstrings` registraría «Sin conexión» como cadena *inglesa*, porque el default
>    de Xcode es `en`.
> 2. **T-D-5 está mal escrito y hay que reformularlo.** Hoy pide que el render en `Locale("es")`
>    *difiera* del literal fuente — imposible, si la fuente ya es `es`. Debe rendir en **`en`** y
>    exigir que difiera. Y hace falta un segundo test de **cobertura de claves** (toda clave
>    existe en ambos idiomas), no solo de diferencia.
> 3. **Deuda declarada con fecha:** hasta que OQ-3 se autorice y el catálogo exista, hay copy de
>    producto castellano en `Sources/` **sin ninguna tubería de i18n cableada**, y la app se
>    renderiza en español en todos los locales, inglés incluido. Esto no es «pendiente de la fase
>    9»: es un estado conocido del producto. Si se descubre a ojo en el simulador durante el
>    golden 7, se habrá cazado en el nivel más caro (§14.1) algo que ya estaba escrito aquí.

- `unauthorized` existe separado a propósito: es el síntoma de una clave ausente o inválida, y su
  copy **no menciona la clave** (§6 de AGENTS.md).
- `malformedResponse` cubre decoding y forma inesperada. **No se degrada a lista vacía**: un JSON
  roto es un error, no un resultado vacío (fail-silent nunca).
- `connectionInterrupted` —**no `cancelled`**— es el caso publicado, y la diferencia importa:
  nombra la conexión cortada *por el transporte*, con la `Task` viva. Una cancelación **propia**
  no llega hasta aquí.

> ⚠️ **Lo que el adapter hace HOY ante una `Task` cancelada, que no es lo que este PRD
> prescribía.** §6.5-Trampa A y OQ-14 decían que la cancelación propia se convierte en
> `throw CancellationError()`. No se implementó así:
> `TMDBPopularMoviesRepository.mapear` hace `Task.isCancelled ? .unknown : .connectionInterrupted`,
> y quien protege la pantalla vuelve a ser el `guard !Task.isCancelled` **de `performLoad`**, en
> el paquete — la misma capa donde el bloqueante B1 dijo que los tests del módulo no llegan.
>
> Las dos versiones no pueden convivir. **Decisión pendiente del owner:** o se implementa el
> `CancellationError` que el PRD prescribe, o se acepta el `.unknown` actual y se reescriben
> §6.5-A, OQ-14, T-VM-4 y T-A-9/9b en consecuencia. Con `.unknown`, un consumidor fuera de
> `performLoad` —el decorador de caché de §16.2— mostraría «Algo ha ido mal» por una navegación
> del propio usuario.

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
re-entrada vive en la **lógica pura** (slice de paginación), no en el ViewModel: si ya hay una página en vuelo,
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
conservan las películas. Entra en el **slice 0** junto al closure, no en el de detalle: un slice que entrega
el closure sin el store mergea con el bug dentro.

### 6.6 Contrato de transporte (Data)

- Endpoints: `GET /3/movie/popular?page=<n>` y `GET /3/movie/{id}`. Host desde `TMDBHost`
  (`Info.plist`), esquema añadido en código (el xcconfig no puede llevar `//`).
- Autenticación: **OQ-1**.
- DTOs `Decodable` separados de las entidades, con **`CodingKeys` explícitas** (OQ-2 resuelta
  leyendo `APIService.swift:225`: `JSONDecoder()` sin configurar, sin conversión de snake_case).
  Lo confirma igualmente el primer test del adapter —decodificar un fixture real a través de
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
- **Página vacía dentro del rango** → **PG3** (etiqueta antes «C4», retirada en la renumeración de §6.3; pendiente, es del slice de paginación): página vacía con `nextPage == nil`; si es la primera,
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
  carga completa ni pierde el contenido. La **Trampa C** (el ViewModel memoizado en
  `MoviesScreenStore`, OQ-13) es **necesaria pero NO suficiente**, y decir que basta era el error:

  > ✅ **CUBIERTO desde el 2026-08-28** (refactor (b); ledger `f-31902e86` cerrado).
  >
  > Hicieron falta **las dos mitades**, y durante un tiempo el PRD dio por suficiente solo la
  > primera: `MoviesScreenStore` salva la *instancia* del ViewModel (Trampa C), pero no el
  > *escenario*. `PopularMoviesView` hacía `.task { await viewModel.load().value }` y `load()`
  > entraba a `performLoad` **sin condición**, así que cada re-montaje repintaba
  > `.loading(.fullScreen)` sobre contenido ya cargado y emitía otra petición — y como
  > `popular` se reordena entre llamadas (no-garantía de §6.3), la lista volvía barajada y la
  > posición saltaba.
  >
  > La segunda mitad es `PopularMoviesViewModel.handle(.alAparecer)`, con
  > un `switch` exhaustivo sobre la fase: **`.idle` y `.empty` recargan**; `.loading`,
  > `.content` y `.error` no. Mira la **fase** y no un booleano `yaCargue` a propósito —la fase
  > es el estado de esta pantalla, y un flag paralelo sería una segunda fuente de verdad que se
  > puede desincronizar de ella—, y `.empty` está dentro porque `DefaultEmptyView` **no ofrece
  > reintentar**: un guard que solo dejara pasar `.idle` dejaría al usuario atrapado en «no hay
  > películas» sin salida. La primera versión del refactor cometió justo ese error y lo cazó la
  > review: proteger la idempotencia sin esa rama habría sido cambiar un bug por otro
  > (fila T-VM-14). `.reintentar` es un caso distinto del
  > enum porque su contrato es el opuesto —siempre recarga—, y con un solo `load()` esa
  > distinción no era expresable: por eso el bug existía.
- **Rotación / Dynamic Type XXL** → el listado no rompe (slice de cierre).

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

**Dominio — slice 0 (lo que existe hoy).**

| id | Qué fija | Tipo |
|---|---|---|
| T-D-4 | Dos casos distintos de `MoviesError` no comparten copy | exhaustivo |

> ⚠️ **T-D-1, T-D-2 y T-D-3 se movieron al slice de paginación el 2026-08-28** (5ª pasada, B-3).
> Estaban etiquetados «slice 0» y fijan `PageNumber` y `MoviePage` — **tipos que §6.3 declara
> inexistentes** y que el árbol confirma que no existen. Como el DoD exige «cada fila de §9b
> existe», el slice 0 no habría podido cerrar su propio DoD: pedía tests de tipos que aún no se
> han escrito.
>
> Es la cita «fase N» reencarnada en «slice N»: al renombrar el troceo, el sweep siguió la
> palabra y no comprobó si el contenido de la fila seguía siendo cierto. Renombrar no es
> propagar.

**Dominio — slice de paginación (PENDIENTE, los tipos aún no existen). PBT = property-based.**

| id | Qué fija | Tipo |
|---|---|---|
| T-D-1 | `PageNumber(n)` existe ⟺ `n ∈ 1...500`; `rawValue == n` | PBT |
| T-D-2 | `PageNumber(n) == nil` para `n ≤ 0` y `n > 500` | PBT |
| T-D-3 | `MoviePage.nextPage` es `page+1` o `nil` — nunca otro valor | PBT |
| T-D-6 | **Cobertura de claves**: toda clave que el String Catalog extrae existe en `es` **y** en `en` | exhaustivo — anunciado por §6.4 y sin fila hasta la 6ª pasada (H-5). Slice de i18n |
| T-D-5 | Por cada caso, su `ScreenError` renderizado en `Locale(identifier: "en")` **difiere del literal fuente** (que es castellano desde que §6.4 fijó el idioma fuente en `es`; pedir que difiera en `es` era imposible). **Slice de i18n, no de paginación** — estaba en la tabla equivocada tras la partición de B-3 | | exhaustivo (slice de cierre). No basta con que el `switch` sea exhaustivo —eso solo garantiza que hay literal, no que esté traducido—: sin este test, una cadena sin traducir cae al inglés y solo lo caza el golden 7 a ojo. **Muere si falta la traducción.** Depende de `SWIFT_EMIT_LOC_STRINGS` (OQ-3) |

**Conformidad puerto ↔ implementaciones (slice 0 y slice de detalle). UNA suite, dos ejecuciones.**

> ⚠️ **Los ids de esta tabla siguen la regla dura de §6.3: un identificador no se recicla.**
> Renumerada el 2026-08-28 porque publicaba `C1`, `C2`, `C4`, `C6` y `C8` con los significados
> que §6.3 había retirado — la regla de inmutabilidad violada **dentro del mismo documento**, y
> justo en la sección que el implementador copia. La regla aplica a **toda cita del PRD**, no
> solo a §6.3.

**Contrato VIGENTE — lo que la suite de conformidad verifica hoy** (`PopularMoviesRepositoryConformance.swift`):

| id | Contrato | Fake | Adapter |
|---|---|:--:|:--:|
| T-C-3 | C3 — el orden de la fuente se conserva | ✓ | ✓ |

> **C1 y C7 no tienen fila, y es correcto:** los garantiza el tipo (`[Movie]` y
> `throws(MoviesError)`). Un test para lo que el compilador impide es una aserción decorativa.
>
> **C5 tampoco tiene fila.** La versión anterior de esta tabla la daba por cubierta (`✓ | ✓`)
> con la forma *«pedir la página 1 dos veces»* — que §6.3 ahora **prohíbe expresamente**, porque
> con la fuente fija por `MockURLProtocol` verifica el mock y no el contrato. C5 no es observable
> con un puerto sin parámetros; entra cuando exista el decorador de caché de §16.2.
>
> **T-C-2 se retiró** con C2 (OQ-17). Queda una sola fila, y eso es correcto: es la única
> garantía de este puerto que hoy puede fallar. Tres de las cinco garantías originales resultaron
> ser o bien imposibles por tipo (C1, C7), o bien no observables con el contrato actual (C5), o
> bien incompatibles con otra (C2). Una suite con una aserción que muere ante un mutante vale más
> que cinco que pasan siempre.

**Contrato PENDIENTE — paginación** (numeración propia, nada de esto existe todavía):

| id | Contrato | Fake | Adapter |
|---|---|:--:|:--:|
| T-PG-1 | PG1 — la página devuelta es la pedida | pendiente | pendiente |
| T-PG-2 | PG2 — `nextPage` = `p+1` o `nil` en la última | pendiente | pendiente |
| T-PG-3 | PG3 — página válida más allá de la última: vacía, `nextPage nil`, no lanza | pendiente | pendiente |

**Contrato PENDIENTE — detalle y transversal:**

| id | Contrato | Fake | Adapter |
|---|---|:--:|:--:|
| T-DT-1 | DT1 — id inexistente ⇒ `.notFound` | pendiente | pendiente |
| T-S-1 | S1 — ninguna salida contiene la credencial (sentinela) | pendiente | pendiente |

**Lógica de paginación (slice de paginación) — el núcleo del TDD.**

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
| T-P-11 | El caso de cancelación propia **no deja fase de error**: con la `Task` cancelada, la pantalla no pinta error ni se queda cargando | fila que OQ-14 daba por escrita y **no existía** hasta la 6ª pasada (H-6). Es la defensa que OQ-22 difiere: entra con el refactor (b) |
| T-P-9 | fallo de página ⇒ el estado conserva lo cargado y **conserva la página a reintentar** | ejemplo |

**Adapter / mapeo de errores — slice 0 (existe hoy), con `MockURLProtocol`.**

> ⚠️ **Partida el 2026-08-28** (6ª pasada, H-4). Era una sola tabla sin etiqueta de slice que
> mezclaba lo escrito con lo pendiente: fijaba `MoviePage` y `page=<n>` (paginación, que no
> existe), el 404 del detalle (que no existe), fixtures `popular_page1.json`… en archivos
> separados (el JSON va **inline**, ver el recuadro de §5) y `.cancelled` — **un caso que
> `MoviesError` no tiene**: el publicado es `connectionInterrupted` (§6.4).
>
> Es el mismo defecto que B-3 de la 5ª pasada, en la tabla de al lado y más larga: al renombrar
> el troceo se etiquetaron las filas de dominio y nadie miró esta. Con el DoD pidiendo «cada fila
> de §9b existe», el slice 0 volvía a no poder cerrar su propio DoD.

| id | Entrada | Salida esperada |
|---|---|---|
| T-A-2 | `URLError(.notConnectedToInternet)` | `.offline` |
| T-A-3 | HTTP 401 | `.unauthorized` |
| T-A-5 | HTTP 429 con `Retry-After` | `.rateLimited` |
| T-A-6 | HTTP 500 | `.server` |
| T-A-7 | JSON sin `results` | `.malformedResponse` |
| T-A-8 | `results` con tipos equivocados | `.malformedResponse` |
| T-A-9b | `URLError(.cancelled)` **sin** cancelar la Task | `.connectionInterrupted` — es un fallo de transporte, no una cancelación nuestra |
| T-A-9 | `Task` cancelada a media petición | el caso de cancelación propia. **Nombre pendiente de OQ-22**: hoy el adapter devuelve `.unknown` y quien protege la pantalla es el `guard` de `performLoad`; §6.5-A prescribe relanzar `CancellationError()` |
| T-A-11 | config sin clave o con el placeholder | `.unauthorized`, sin imprimir el valor |

**Adapter — PENDIENTE (paginación y detalle; los tipos y endpoints aún no existen).**

| id | Entrada | Salida esperada |
|---|---|---|
| T-A-1 | `popular_page1.json`, 200 | `MoviePage` con los datos del fixture |
| T-A-4 | HTTP 404 (detalle) | `.notFound` |
| T-A-10 | la query/headers enviados incluyen `page=<n>` | request correcta |
| T-A-12 | **sentinela** (T-S-1): para CADA caso de error, ni `description`, ni `ScreenError.title/message` contienen la credencial | **no escrito todavía** — es el gate que `f-3236fb0` exige y la razón de que el `security-reviewer` sea obligatorio en el slice 0 |


**Orquestación — ViewModel (ViewModels del listado, paginación y detalle). Doble = fake+spy con eventos `enum`; el ORDEN es contrato.**

| id | Caso | Aserción |
|---|---|---|
| T-VM-1 | `onAppear` OK con resultados | eventos `[.loadedPage(1)]`; `phase: .idle → .loading(.fullScreen) → .content`; películas publicadas |
| T-VM-2 | `onAppear` OK con 0 resultados | `phase == .empty` (**no** `.content` con lista vacía) |
| T-VM-3 | `onAppear` con error | `phase == .error(...)`; el `retry` del `ScreenError` vuelve a llamar al puerto (2ª entrada en el spy) |
| T-VM-4 | el fake lanza `MoviesError.cancelled` con la Task **viva** | `phase` **NO es `.loading`** (ni se queda colgada ni pinta error espurio). Aserción sobre el estado que de verdad puede romperse: la anterior (`== .error` con retry) es cierta para *cualquier* error que escape, con o sin la regla de OQ-14, porque `performLoad` siempre pasa un `retry` no-nil (`BaseViewModel.swift:204-213`) |
| T-VM-12 | `alAparecer` dos veces ⇒ **una sola** invocación al puerto, y ni la fase ni las películas cambian | el conteo de invocaciones SÍ es el contrato aquí: lo que se verifica es que NO se llame de más |
| T-VM-14 | `alAparecer` sobre `.empty` ⇒ **sí** vuelve a pedir | rama de recuperación: `DefaultEmptyView` no ofrece reintentar, así que un guard que solo dejara pasar `.idle` dejaría al usuario atrapado. La primera versión del refactor introdujo justo esa regresión |
| T-VM-13 | `reintentar` tras un error ⇒ vuelve a pedir | contrato **opuesto** al de `alAparecer`. *(La primera versión de esta fila decía «sin él, el botón de la pantalla de error no haría nada» — falso, y contradecía a T-VM-3: ese botón usa el `retry` de `ScreenError`, que asigna `performLoad`. `.reintentar` no tiene call site en `Sources/` todavía; es el punto de entrada para una recarga con UI propia.)* |
| T-VM-11 | dos invocaciones de `store.popular()` devuelven la MISMA instancia. **No dice «simulando push+pop»**: el slice 0 no tiene `Coordinator`, ni `CoordinatorView`, ni `MoviesRoute`, ni `DependencyModule` — `BaselineApp` monta un `NavigationStack` pelado. **Riesgo residual declarado:** cuando llegue el Coordinator, construir el ViewModel dentro del closure de rutas deja todos los tests en verde y reintroduce el bug de identidad; ese cableado no lo cubre nada todavía | el ViewModel **no** se reemplaza y las películas acumuladas siguen ahí (Trampa C). Muere si la factoría construye una instancia nueva en vez de devolver la memoizada |
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
   reales en `Domain/` y `Features/` y pasa.
5. **Cero findings de tier alto abiertos** contra el módulo en el ledger al cerrar el slice de cierre.

## 11. Rollout

- **Sin feature flag.** La app no está publicada; no hay usuarios que proteger ni tráfico que
  dividir. Un flag aquí sería ceremonia.
- **Sin migración de datos** (no hay datos).
- **El rollout ES el troceo de §5b**: cada slice se mergea solo y deja `main` verde. El **slice 0**
  enciende ya la primera pantalla (listado de populares) porque es un walking skeleton: el
  cableado end-to-end antes que la funcionalidad. Los slices siguientes añaden capacidad
  observable —paginación, detalle, pósters, i18n— cada uno respetando el orden contrato → lógica
  → UI.
- **Rollback** = revertir el commit de la fase. Como ninguna fase depende de estado externo ni deja
  migraciones, revertir es suficiente y no hay que deshacer nada más.
- **Push solo con aprobación explícita del owner** (§7).

## 12. Riesgos

| # | Riesgo | Mitigación |
|---|---|---|
| R1 | **La API que asume este PRD la leí de los clones locales de `spm-pro`, no de los tags publicados** (AppFoundation 0.1.1 / CoreNetworking 0.1.3). Pueden divergir. | **OQ-10**. El slice 0 es el primero que compila contra los paquetes de verdad; si diverge, Open Question + finding, **jamás un parche local** (§NO-TOUCH). |
| R2 | La clave de TMDB acaba en una URL logueada. `LoggingInterceptor` redacta **headers** sensibles; una query `?api_key=` viaja en la URL completa. | **OQ-1** + T-A-12 (sentinela) como test permanente en toda fase que toque `Data/`. |
| R3 | `switch try await` deja el archivo **entero** sin escanear en el nivel 2, y nadie avisa. | Convención del proyecto (ligar el resultado a una variable antes del `switch`) + criterio de aceptación "0 `PartialParsing` en `Sources/`". |
| R4 | Fallo silencioso de paginación: `performActivity` cancela la actividad en vuelo y el listado deja de crecer sin error. | Trampa B: guard de re-entrada en la lógica **pura** + T-P-8 y T-VM-6. |
| R5 | Flash de pantalla de error por una cancelación de transporte (sesión invalidada), con la Task viva. | Trampa A + T-VM-4. El caso superseded lo cubre ya `performLoad`. |
| R6 | `popular` de TMDB se reordena entre peticiones ⇒ filas duplicadas. | T-P-6 (property-based de unicidad y orden). |
| R7 | El drift-ratchet está en `errors: 0, warns: 0` y `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`: **un solo warning nuevo bloquea**. | No es un riesgo a mitigar, es la condición de trabajo. Se declara aquí para que nadie lo descubra a mitad de fase. |
| R8 | Contexto agotado a mitad de capa (el modo de fallo del PRD-monolito). | §5b: troceo por **slices** mergeables, cada uno con contrato y verificación propios. El slice 0 (walking skeleton) cruza todas las capas **a propósito y por una vez**; del 1 en adelante rige el orden contrato → lógica → UI. *(Esta mitigación decía «9 fases, ninguna cruza red+dominio+UI» — la regla que §5b abandonó. Corregida el 2026-08-28: una mitigación apoyada en una regla retirada es un riesgo sin mitigar que parece mitigado.)* |

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
- [ ] **OQ-3 — 🔴 BLOQUEANTE del slice de i18n. ¿Se autoriza tocar `project.yml`?** Queda **solo la parte
      (a)**: declarar `Sources/Resources/Localizable.xcstrings` para que el String Catalog entre al
      bundle. Son build settings ⇒ decisión de owner (lección [2026-08-08]).
      **Y dos cosas más en el mismo viaje**, que sin ellas el mecanismo de B4 no funciona:
      `knownRegions`/`CFBundleLocalizations` con `es` (sin eso el golden 7 falla aunque el
      `.xcstrings` esté perfecto) y `SWIFT_EMIT_LOC_STRINGS: YES` (sin eso el catálogo no extrae
      nada, en silencio — ver OQ-15). **Y una cuarta, añadida el 2026-08-28: `developmentRegion:
      es`** — consecuencia de la decisión de idioma fuente en §6.4. Sin ella el default de Xcode
      es `en` y el catálogo registraría los literales castellanos como cadenas inglesas, así que
      las otras tres no bastan.
      *(La parte (b) —`package: AppFoundation` en el target de tests— **está resuelta**:
      `Tests/UnitTests/SmokeTests.swift:3` ya hace `import AppFoundation` y compila.)*
- [x] **OQ-4 — RESUELTA por el owner (2026-08-28): `Sources/Features/Movies/`.** Dos docs internos
      se contradecían: `architecture/platforms/ios.md` prescribe `Features/<Nombre>/`, y
      `tools/layers.conf` solo aplicaba la regla "la UI no habla HTTP" al glob `*/UI/*`. Con
      `Features/`, **esa regla quedaba muda para todo el módulo de referencia** — justo el módulo
      que existe para demostrar que las capas se respetan.

      **El riesgo era real y se verificó antes de mover**, no después: un `import CoreNetworking`
      colocado bajo `Sources/Features/` daba `LAYERS_SUMMARY errors=0`. La regla no habría fallado
      — habría dejado de existir, en silencio y con el gate en verde, que es el único pecado que
      este harness no comete (§14.4).

      **Cómo se cerró:** `Sources/UI/Movies/` → `Sources/Features/Movies/`, y `tools/layers.conf`
      gana dos reglas `*/Features/*` (HTTP y persistencia) que replican las de `*/UI/*`. Se
      confirmó con prueba de fuego que vuelven a cazar (`errors=1` con el probe, `errors=0` sin
      él). Tocar `layers.conf` es NO-TOUCH y quedó **autorizado explícitamente por el owner** al
      tomar esta decisión, porque era su consecuencia obligada: la regla viaja con la estructura,
      o la estructura se lleva el gate por delante. `project.yml` **no** se tocó — declara
      `- path: Sources`, así que OQ-3 no bloqueaba este movimiento.
- [ ] **OQ-5 — 🟠 ¿Se muestran pósters, y cómo?** Tres tensiones a la vez: (a) AGENTS.md §3 dice
      "todo acceso HTTP pasa por `APIService` … nada de `URLSession` suelto", y `AsyncImage` **es**
      `URLSession` por dentro; (b) **`layers.conf` NO puede arbitrar esto** — corregido el
      2026-08-28: `check-layers.sh` trabaja sobre el grafo de **imports**, y `AsyncImage` solo
      necesita `SwiftUI` (que una View importa obligatoriamente) mientras `URLSession` solo
      necesita `Foundation`. El regex prohibido es `^(CoreNetworking|CoreNetworkingTestSupport)$`
      y no puede ampliarse a `Foundation` sin romper el dominio entero. O sea: la regla de capa
      impide que la vista use **nuestro** cliente HTTP, y nada más. *(La versión anterior de esta
      OQ afirmaba que «la vista no puede descargar por su cuenta ni con el paquete»; la primera
      mitad era falsa.)* **Pregunta añadida:** si el owner elige `AsyncImage`, ¿se autoriza una
      regla Semgrep (nivel 2) en `tools/semgrep/rules/swift.yaml` que acote `URLSession(` y
      `AsyncImage` bajo `Sources/Features/` a la excepción declarada? Sin ella, «la UI no habla
      HTTP» queda como una regla que solo cubre el caso que nadie iba a cometer. Ese fichero es
      NO-TOUCH: es permiso de owner, exactamente como lo fue `layers.conf` en OQ-4; (c) TMDB devuelve
      `poster_path` relativo — la URL completa necesita la base de imágenes y un tamaño, que
      oficialmente salen del endpoint `/3/configuration`. Opciones: `AsyncImage` con excepción
      declarada en `docs/process/decisions/`; un puerto `MoviePosterLoading` con adapter sobre
      `APIService.download`; o listado sin imagen. Y si hay imagen: ¿base y tamaño fijos o desde
      `/configuration`? *(Si la respuesta es "puerto propio", esto es **una fase más**, no un
      añadido a la 5.)*
- [ ] **OQ-6 — 🟠 BLOQUEANTE del slice de detalle. ¿El detalle re-consulta `/3/movie/{id}` o reutiliza la entidad
      del listado?** Reutilizar ahorra un puerto, un adapter y dos fases; consultar ejercita una
      segunda ruta completa (request, decoding, 404, error en contexto de detalle), que es
      exactamente lo que un módulo de referencia debe demostrar. Este PRD asume **re-consultar**
      (el slice de detalle) porque el owner declaró que el valor está en cruzar capas; confírmalo o córtalo.
- [ ] **OQ-7 — 🟡 ¿Qué `language` se envía a TMDB, y qué hacemos con los campos vacíos?** La app es
      ES+EN. ¿Derivamos `language` del locale del dispositivo (`es-ES`/`en-US`)? TMDB devuelve con
      frecuencia `overview` **vacío** en español: ¿fallback a inglés (segunda petición), placeholder
      localizado, u ocultar el campo? Nota: derivar de un identificador de locale es legítimo;
      ramificar sobre el texto devuelto **no lo es** (§3).
- [ ] **OQ-8 — 🟡 BLOQUEANTE del slice de paginación (fija un tipo). Confirmar contra la API real dos cosas:**
      (a) que `page > 500` es un error del servidor —lo que justifica que `PageNumber` cierre el
      rango en 500—, y (b) que una página válida **más allá** de `total_pages` devuelve 200 con
      `results: []` en vez de un error. La garantía **PG3** (antes «C4», retirada esa etiqueta con la renumeración de §6.3) depende de (b). *Resolución:
      un `curl` manual del owner cuya respuesta se congela como `popular_beyond_last_page.json`
      — la evidencia es el fixture, no una afirmación.*
- [ ] **OQ-9 — 🟠 El nivel 4 está MUDO y esta es la ocasión de estrenarlo.**
      `tools/mutation-ratchet.json` dice `"measured": false` y **no existe `muter.conf.yml`** en la
      raíz, así que `mutation-score.sh` no tiene runner. ¿Se autoriza crear esa config en el slice de cierre
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
      **Entregable:** `MoviesScreenStore.swift` entra en §5 y en el **slice 0** (no en el de
      detalle): si el slice 0 entrega el closure sin él, mergea con el bug de identidad dentro, y cada slice tiene
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

### OQ-16 a OQ-21 — resueltas o abiertas fuera de esta lista (índice, 5ª pasada B-4)

> Estas Open Questions se plantearon y algunas se resolvieron **en recuadros dentro de §5b, §6.3
> y §6.4**, y se citan desde `current_execution_map.md` y desde el ledger. Ninguna tenía entrada
> aquí, así que un lector de §13 —que es el índice de lo que bloquea el `Approved`— **no podía
> encontrarlas**. Es la regla de identificadores inmutables de §6.3 aplicada a las OQ: un id
> citado desde otro documento tiene que resolver contra este índice.

| # | Qué preguntaba | Estado | Dónde vive la respuesta |
|---|---|---|---|
| **OQ-16** | ¿El slice 0 pasa por `security-reviewer` antes del commit? Toca la credencial y T-S-1 no existe. | ✅ **decidida: SÍ, obligatorio** · 🟠 **pendiente de EJECUTAR** — el gate no ha corrido y `f-3236fb0` sigue abierto/high | columna «revisores» de §5b · DoD §15 · ledger `f-3236fb0` |
| **OQ-17** | ¿C2 (ids únicos) es garantía del puerto, si contradice a C3? | ✅ **RETIRADA** del contrato: el puerto no deduplica | §6.3 · ledger `f-f6b72573` (cerrado) |
| **OQ-18** | ¿Dónde vive `TransportError`, sabiendo que la app es un módulo único y ningún gate vigilaría la frontera? | ✅ **`CoreNetworking`**, con el copy en la app | recuadro antes de §6.4 |
| **OQ-19** | ¿La suite de conformidad se refuerza o se declara andamiaje? | ✅ **Reforzada** a igualdad completa de `[Movie]` | `PopularMoviesRepositoryConformance.swift` |
| **OQ-20** | `TMDBConfiguration.swift` no exigía `security/SKILL.md`. ¿Mover o ampliar el conf? | ✅ **Movido** a `Data/Movies/` | recuadro antes de §6.4 · ledger |
| **OQ-21** | ¿Chequeo inverso de cobertura (carpeta → regla) y exención por línea en `check-layers-coverage.sh`? | 🟠 **ABIERTA** — no bloquea el slice 0 | ledger |

**Y una que estaba invisible por no tener número** — la única decisión bloqueante que un lector
de §13 no podía encontrar:

- [ ] **OQ-22 — 🟠 ¿El adapter relanza `CancellationError()` o se acepta el `.unknown` actual?**
      §6.5-Trampa A y OQ-14 prescriben lo primero, para que la protección viva en una capa que
      los tests del módulo alcanzan (bloqueante B1 del design-review original).
      `TMDBPopularMoviesRepository.mapear` hace `Task.isCancelled ? .unknown : .connectionInterrupted`,
      y quien protege la pantalla es el `guard` de `performLoad`, en AppFoundation. El código y
      sus comentarios ya son honestos sobre esto, así que **no bloquea el slice 0**; sí bloquea
      el slice de paginación y el decorador de caché de §16.2, donde un consumidor fuera de
      `performLoad` mostraría «Algo ha ido mal» por una navegación del propio usuario.
      Ledger `f-52ef5f6d`.

      > ⏭️ **DIFERIDA por el owner (2026-08-28) al refactor (b)** —`enum Action` + `handle(_:)`—,
      > donde se decide junto con la idempotencia de la primera carga, que vive en la misma
      > capa. **No bloquea el `Approved` ni el commit del slice 0**, por la razón de arriba: el
      > código y sus comentarios ya dicen lo que hacen, así que lo que queda es una decisión de
      > diseño pendiente y declarada, no una divergencia oculta.


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
- [ ] `bash tools/check-layers.sh` → **exit 0**, y evalúa archivos reales en `Domain/` y `Features/` — **no en `Data/`**: `layers.conf` no tiene ninguna regla `*/Data/*`, así que esa carpeta no la mira nadie (pedirla es NO-TOUCH: OQ nueva si se quiere)
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
- [ ] `reviewer` GREEN o AMBER atendido en cada slice · `security-reviewer` en **todo slice que toque credencial, almacenamiento o authz** (criterio, no número de fase: las fases 3/5/7 a las que esto se ancló antes dejaron de existir con el troceo de §5b, y el slice 0 **sí** toca la credencial). Ver la columna «revisores obligatorios» de §5b
      (tocan la clave)
- [ ] `design-reviewer` pasado sobre este PRD **antes** del primer commit de código (§12 — gate
      distinto del `Approved` del owner)
- [ ] Ninguna ruta del §NO-TOUCH aparece en el diff **sin autorización registrada**. **No la marques contra una lista escrita a mano — esa cifra ya se quedó obsoleta dos veces en este mismo PRD.** Sácala del diff:

  ```bash
  git diff --cached --name-only \
    | grep -E '^(tools/|ci/|AGENTS\.md|lefthook\.yml|\.agents/skills/)' \
    | grep -v '^tools/findings/ledger\.jsonl$'
  ```

  (`tools/findings/ledger.jsonl` se excluye porque escribir ahí es el mecanismo sancionado de §10, no una excepción NO-TOUCH.) Toda ruta que salga debe tener fila en la tabla de autorizaciones de §5b. Al cerrar el slice 0 salían **ocho**, y las ocho constan. Sin esa tabla esta casilla sería imposible de marcar en verdad
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
   conformidad. Cero cambios en `Domain/` y `Features/` — y si hicieran falta, el diseño de este PRD
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
| 2026-08-28 | **OQ-4 resuelta**: `Sources/UI/Movies/` → `Sources/Features/Movies/`. Arrastró añadir las reglas `*/Features/*` a `tools/layers.conf` — sin ellas la regla «la UI no habla HTTP» quedaba muda para todo el módulo | owner |
| 2026-08-28 | **Slice 0 escrito** (Domain → Data → Features → App + tests). `MoviesError: AppErrorConvertible` y la suite de conformidad del puerto, que faltaban | reviewer |
| 2026-08-28 | Pasadas 2-5 del design-review (RED ×4). §5b reescrita por slices y **tabla de 9 fases borrada** (su copia vive en el Anexo del dictamen); §6.3 republicada con ids inmutables y bloques vigente/pendiente; §9b renumerada (`T-PG-*`, `T-DT-*`, `T-S-1`) | design-reviewer |
| 2026-08-28 | **OQ-17**: C2 retirada del contrato (el puerto no deduplica). **OQ-18**: `TransportError` va a `CoreNetworking`, el copy se queda en la app. **OQ-19**: suite reforzada a igualdad completa de `[Movie]`. **OQ-20**: `TMDBConfiguration.swift` → `Data/Movies/`, para que exija `security/SKILL.md` | owner |
| 2026-08-28 | Idioma fuente de los literales: **`es`**, con `developmentRegion` añadido a OQ-3 | owner |
| 2026-08-28 | Detector nuevo `tools/check-layers-coverage.sh` (control negativo de `layers.conf`) + paso 4a de `ci/run-gates.sh`, y dos lecciones con `Detector:` en `lessons_learned.md` | owner (NO-TOUCH autorizado, §5b) |
| 2026-08-28 | **OQ-C**: `*/Features/*` y `*/App/*` añadidos a `tools/skill-matrix.conf` y a la tabla §11 de `AGENTS.md`. `BaselineApp.swift` pasa de cero lecturas obligatorias a exigir `security/SKILL.md`. **OQ-22** (cancelación) diferida al refactor (b) | owner |
| 2026-08-28 | Pasada 6: el puerto **seguía publicando C2** en su doc-comment y afirmaba que la suite verifica cinco garantías cuando verifica una. Corregido en `PopularMoviesRepository.swift`, que ahora declara **quién verifica cada garantía** | design-reviewer |
| 2026-08-28 | `security-reviewer` 🟡 **AMBER** sobre la cadena completa de la credencial: sin secretos en el diff, token en header y no en query, fail-closed confirmado, sin interceptors cableados. `f-3236fb0` cerrado | security-reviewer |
| **2026-08-28** | **`Status: Draft → Approved`** | **owner** |

## 18. Gaps detectados (llenar post-ship)

*(Se rellena al cerrar el slice de cierre. Alimenta `docs/process/lessons_learned.md` —toda entrada exige
`Detector:`— y `tools/findings/`.)*

Semillas ya identificadas al escribir el PRD, para no perderlas:

- ~~R9~~ **CERRADO (2026-08-28)**: `skill-matrix.conf:42` ya tiene `*/UI/*` junto a `*/ui/*`,
  con el comentario que explica por qué hacen falta las dos grafías. No queda gap.
- ~~R10~~ **CERRADO (2026-08-28)**: `verify.conf:46` ya lleva `-test-timeouts-enabled YES`. Lo que
  queda —que el umbral no esté fijado, sino en el default de Xcode— vive como finding
  `f-5529624d` en el ledger, con su redacción exacta.
- El README de `CoreNetworking` documenta el pipeline pero **no** la configuración del `JSONDecoder`
  (OQ-2), que es lo primero que necesita quien escribe un DTO.

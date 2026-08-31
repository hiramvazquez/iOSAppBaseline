# PRD — Slice de detalle de película

> **Tipo:** Forward · **Status:** 📝 Draft — **OQ-1 resuelta** (owner, 2026-08-31). Pendientes OQ-2/3/4 y el `design-reviewer`
> **Autor:** sesión de agente (Claude) · **Fecha:** 2026-08-31
> **Tracking:** `f-f88eb0fd` · `f-a452b1de` · `f-5856bd41` · `f-996710c3` (los cuatro con condición de cierre atada a este slice) · el residuo del Router declarado en la resolución de `f-f2a4ca6e` · `f-3d60d1f6` y `f-8ab6c2ad`, que este slice **ejercita pero no cierra**
> **Design-review:** pendiente
> **Origen:** PRD 0001 §5b lo dejó como «slice 1+, por capacidad observable», con su contrato ya escrito en §6.3 (`MovieDetailRepository`, garantía DT1) y su escenario golden 6 redactado

> **Por qué es un PRD y no un flow corto.** Cumple tres del criterio de `prd-lifecycle.md`, no
> dos: toca **cuatro módulos** (Domain, Data, Features, App), **cambia un contrato** (puerto
> nuevo) y fija una **decisión arquitectónica reusable** — *cómo navega un ViewModel* es el
> patrón que copiará todo proyecto que salga de esta baseline.

---

## 1. Contexto

El PRD 0002 dejó el módulo de referencia usando lo que `AGENTS.md` §3 prescribe: `Container` con
`MoviesModule`, `Coordinator<MoviesRoute>` registrado como `any Router<MoviesRoute>`, y
`CoordinatorView` montado vía `MoviesRouteBuilder`. Pero lo dejó **a medio ejercitar**, y lo
declaró en vez de disimularlo:

| Pieza | Estado hoy | Verificado con |
|---|---|---|
| `MoviesRoute` | **una sola ruta**, `.listado` | su propio doc-comment: «el caso `detalle(id:)` llega con su slice» |
| El `Router` | se **registra**, no se **consume** | `grep -rn "Router" Sources/` → solo `BaselineApp.swift` |
| `CoordinatorView` | montado, pero **sin un push/pop real** que lo atraviese | `MoviesRoute` tiene un solo caso |
| `MoviesScreenStore` | memoiza `popular()` | `MoviesScreenStoreTests` |

O sea: **toda la maquinaria de navegación existe y nada la ha recorrido todavía**. Este slice es
el primero que la recorre de verdad, y por eso cuatro findings tienen su condición de cierre
atada a él — no «algún día», sino a este evento concreto (§1.1).

## 2. Problema

**Para el usuario:** toca una película y no pasa nada. La app enseña un listado y termina ahí.

**Para el proyecto, que es lo que más pesa aquí:** una capa de navegación que nunca ha navegado
es una capa **no verificada**. La Trampa C —`CoordinatorView` reevalúa el closure de rutas en
cada cambio del path, y un ViewModel construido ahí dentro se recrea vacío— está mitigada por
diseño y **demostrada solo en un test unitario del builder**. Nadie ha hecho un `push` y un `pop`
de verdad contra este grafo.

**Si no lo construimos:** los cuatro findings se quedan abiertos sin fecha, el `Router` sigue
siendo una pieza registrada que nadie resuelve —código muerto con apariencia de arquitectura— y
el módulo de referencia sigue enseñando media navegación.

## 3. Objetivo

Tocar una película abre su detalle, y al volver el listado sigue como estaba.

Medible, y cada fila con quién la verifica:

| # | Condición | Verificada por |
|---|---|---|
| O1 | Tocar la fila N navega al detalle **de esa** película | test del ViewModel: `send(.seleccionar(id))` empuja `.detalle(id:)` en un `Router` espía |
| O2 | Al volver, el listado **conserva su contenido** | test: misma instancia de ViewModel desde el store, `movies` intacto, `phase == .content` |
| O3 | Al volver, **no se emite una segunda petición** | el guard de idempotencia de `.alAparecer`, ya existente, ahora ejercitado por un remontaje real |
| O4 | Un `MovieID` inexistente da `.notFound` | garantía **DT1** del PRD 0001, en la suite de conformidad |

> **O2 dice «contenido», no «contenido y posición», y la diferencia no es un descuido.** El
> golden 6 del PRD 0001 pide las dos cosas. La **posición de scroll no es verificable en este
> proyecto**: exige UI tests que instalen la vista, y OQ-13 ya decidió que no los hay — es la
> misma razón por la que `MoviesScreenStore` es una factoría memoizada y no un `@State`. Se
> declara como cobertura ausente y se comprueba a mano en el checklist de §15, en vez de
> escribir un DoD que no se puede falsar.

## 4. Filosofía / principios

**4.1 — El contrato primero, y ya está escrito.** El puerto `MovieDetailRepository` y su garantía
DT1 los publicó el PRD 0001 §6.3 antes de que existiera este documento. Este PRD **los implementa,
no los redefine**. Si algo hay que cambiar, se cambia allí y se cita aquí — no se publica una
segunda versión del contrato en otro sitio, que es cómo un id de garantía acaba significando dos
cosas (lección del 2026-08-28).

**4.2 — La vista emite intención; quien navega es el ViewModel pidiéndoselo al `Router`.**
`AGENTS.md` §3 es literal: «las vistas NO navegan: piden al router». La fila del listado no
conoce `MoviesRoute`: manda `.seleccionar(id)` y se acabó. Esto es lo que convierte la navegación
en **testeable sin instalar una vista**, que es la única forma de testearla en este proyecto.

**4.3 — La Trampa C aplica al detalle igual que al listado, y con más filo.** El closure de rutas
se reevalúa en cada cambio del path. Mientras el detalle está en pantalla, cualquier cambio lo
reconstruiría vacío — el usuario vería su detalle recargarse solo. La memoización del store deja
de ser una precaución del listado y pasa a ser **el mecanismo**, ahora con clave (§7, OQ-3).

## 5. Estructura de archivos a crear / tocar

```
Sources/Domain/Movies/MovieDetail.swift              ← [SLICE-FUTURO] fase 1: entidad del detalle
Sources/Domain/Movies/MovieDetailRepository.swift    ← [SLICE-FUTURO] fase 1: el puerto (contrato del PRD 0001 §6.3)
Sources/Data/Movies/TMDBErrorMapper.swift            ← [SLICE-FUTURO] fase 1: EXTRAER el mapeo hoy privado en el adapter de populares
Sources/Data/Movies/TMDBMovieDetailRepository.swift  ← [SLICE-FUTURO] fase 1: adapter de /3/movie/{id}
Sources/Data/Movies/TMDBDTOs.swift                   ← [SLICE-FUTURO] fase 1: TOCAR — DTO del detalle
Sources/Data/Movies/TMDBPopularMoviesRepository.swift ← [SLICE-FUTURO] fase 1: TOCAR — pasa a usar el mapper extraído
Sources/Features/Movies/MovieDetailViewModel.swift   ← [SLICE-FUTURO] fase 2: orquestación del detalle
Sources/Features/Movies/MovieDetailView.swift        ← [SLICE-FUTURO] fase 2: detalle dentro de ScreenContainer
Sources/Features/Movies/MoviesRoute.swift            ← [SLICE-FUTURO] fase 2: TOCAR — case detalle(id:)
Sources/App/Movies/MoviesScreenStore.swift           ← [SLICE-FUTURO] fase 2: TOCAR — detalle(id:) memoizado
Sources/App/Movies/MoviesRouteBuilder.swift          ← [SLICE-FUTURO] fase 2: TOCAR — la rama .detalle
Sources/App/Movies/MoviesModule.swift                ← [SLICE-FUTURO] fase 1: TOCAR — registra el puerto nuevo
Sources/Features/Movies/PopularMoviesViewModel.swift ← [SLICE-FUTURO] fase 3: TOCAR — Intent.seleccionar + el Router
Sources/Features/Movies/PopularMoviesView.swift      ← [SLICE-FUTURO] fase 3: TOCAR — la fila emite intención
Sources/App/BaselineApp.swift                        ← [SLICE-FUTURO] fase 3: TOCAR — coordinator a @State (f-5856bd41)
Tests/UnitTests/Movies/MovieDetailRepositoryConformance.swift ← [SLICE-FUTURO] fase 1: la suite, fake y adapter
Tests/UnitTests/Movies/TMDBMovieDetailRepositoryTests.swift   ← [SLICE-FUTURO] fase 1: el 404 → DT1
Tests/UnitTests/Movies/MovieDetailViewModelTests.swift        ← [SLICE-FUTURO] fase 2
Tests/UnitTests/Movies/MoviesRouteBuilderTests.swift          ← [SLICE-FUTURO] fase 2: TOCAR — y aquí muere RepoVacio (f-996710c3)
Tests/UnitTests/Movies/MoviesScreenStoreTests.swift           ← [SLICE-FUTURO] fase 2: TOCAR — memoización por id
Tests/UnitTests/Movies/PopularMoviesViewModelTests.swift      ← [SLICE-FUTURO] fase 3: TOCAR — O1, O2, O3
docs/process/prds/0001-vertical-de-referencia-peliculas.md    ← fase 1: TOCAR — §6.2 (ver §6.3 de aquí) y el tree de §5
```

### NO-TOUCH (contrato — el implementador NO toca esto)

```
tools/** · ci/** · .github/** · lefthook.yml · scripts/agent-hooks/**
    ← tooling compartido: aprobación explícita del owner (§8). Este slice NO la tiene
tools/drift-ratchet.json · tools/mutation-ratchet.json
    ← trinquetes: solo su script, una dirección (§9)
AGENTS.md · CLAUDE.md · .agents/skills/**
    ← meta-doc (§8). OJO: OQ-1 de este PRD roza AGENTS.md §3, y por eso la decide el owner
      en `f-da257e0c`, no el implementador aquí
/Users/hiram/Desktop/PROYECTOS/spm-pro/**
    ← los SPM son otro repo. Si el slice necesita un cambio en AppFoundation o
      CoreNetworking, eso es un HALLAZGO y una publicación aparte, nunca una edición local
Sources/Domain/Movies/MoviesError.swift
    ← el enum NO cambia de forma. `.notFound` ya existe y es lo que DT1 necesita. Añadir un
      caso obligaría a re-verificar el test de copy y la garantía S1 sin ninguna necesidad
```

## 5b. Fases entregables

| Fase | Entrega (mergeable, base verde) | Depende de | Cierra |
|---|---|---|---|
| **1 — contrato** | `MovieDetail` + puerto + DT1 · adapter TMDB + DTO · **`TMDBErrorMapper` extraído** · suite de conformidad (fake ≡ real) · registro en `MoviesModule`. **Sin UI, sin ruta** | OQ-2 | — |
| **2 — la pantalla y su ruta** | `MovieDetailViewModel` + `MovieDetailView` · `MoviesRoute.detalle(id:)` · `store.detalle(id:)` memoizado · rama del builder. **Alcanzable empujando la ruta desde un test**, todavía no desde el listado | 1, OQ-3 | `f-996710c3` · `f-a452b1de` (parcial) |
| **3 — la navegación real** | `Intent.seleccionar(MovieID)` + el `Router` en el ViewModel · la fila emite intención · `coordinator` a `@State` · O1, O2, O3 | 2, **OQ-1** | `f-f88eb0fd` · `f-a452b1de` · `f-5856bd41` · el residuo del Router de `f-f2a4ca6e` |

> **Por qué la fase 2 entrega una pantalla que el usuario todavía no puede alcanzar.** Es la regla
> «contrato → lógica → UI» aplicada con honestidad: la alternativa era una fase que añade la ruta
> **y** la navegación **y** la pantalla de golpe, que es justo el slice que el PRD 0001 rompió a
> propósito una vez y prometió no volver a romper. Una pantalla alcanzable desde un test es una
> pantalla verificada; el `case` sin destino que `MoviesRoute` rechaza en su doc-comment es otra
> cosa — un caso **sin pantalla**, y en la fase 2 la pantalla existe.

## 6. Modelo de datos

### 6.1 El contrato, que ya estaba publicado

```swift
// PRD 0001 §6.3 — «Contrato PENDIENTE — el slice de detalle». Se implementa tal cual.
protocol MovieDetailRepository: Sendable {
    func movieDetail(id: MovieID) async throws(MoviesError) -> MovieDetail
}
```

| # | Garantía | Quién la verifica |
|---|---|---|
| **DT1** | Un `MovieID` inexistente lanza `MoviesError.notFound`. Nunca un `MovieDetail` vacío ni `nil` | suite de conformidad, contra el fake **y** contra el adapter real |
| **DT2** *(nueva, propuesta)* | Toda salida de error es un `MoviesError` | **por el tipo** (`throws(MoviesError)`), sin test — igual que C7 |

> DT2 se numera nueva en vez de reusar C7: **un id de garantía es inmutable** y C7 es del puerto
> de populares. Reciclarlo entre puertos es cómo una cita deja de saber a qué se refiere (lección
> del 2026-08-28).

### 6.2 `MovieDetail`

Superset de `Movie` con lo que el endpoint de detalle añade: `overview: String?`,
`releaseDate: Date?`, `runtime: Int?`. Value type, `Sendable`, sin lógica. Los campos son
opcionales porque **TMDB los devuelve vacíos o ausentes en películas sin estrenar**, y ese `nil`
es un dato, no un error — la misma decisión que ya se tomó con `voteAverage`.

### 6.3 Drift que este PRD debe corregir en su fase 1

**`Movie` NO cambia.** El PRD 0001 §6.2 dice que `overview` y `releaseDate` «entran con el slice
de detalle» *en `Movie`*, y eso hay que corregirlo allí: el endpoint del listado no los devuelve,
así que ponerlos en `Movie` obligaría a que fueran opcionales-siempre-nil en todo el listado —una
entidad que miente sobre lo que sabe—. Van en `MovieDetail`, que es lo que §6.3 del mismo
documento ya dice. **Es una contradicción interna del PRD 0001**, y §9 (drift policy) obliga a
arreglarla en el mismo PR que la toca.

Segunda corrección al mismo tree: PRD 0001 §5 coloca `MoviesModule.swift` en `Features/Movies/`,
y el código lo tiene en `App/Movies/` **porque `layers.conf` prohíbe a `*/Features/*` importar
`CoreNetworking`**. Es exactamente la clase de `f-2db8ecf0` («nada contrasta un diseño prescrito
en docs contra `layers.conf`»), ya registrada; aquí solo se corrige la instancia.

## 7. Flujo de la solución

### User story

Como espectador quiero tocar una película del listado para ver su sinopsis, su fecha y su
duración, y volver al listado donde lo dejé.

### El camino, pieza a pieza

1. `PopularMoviesView` → la fila manda `viewModel.send(.seleccionar(pelicula.id))`. **La vista no
   conoce `MoviesRoute`.**
2. `PopularMoviesViewModel.send(.seleccionar(id))` → `router.push(.detalle(id: id))`.
3. `Coordinator<MoviesRoute>` cambia el path → `CoordinatorView` reevalúa el closure.
4. `MoviesRouteBuilder.view(for: .detalle(id:), store:)` → `MovieDetailView(viewModel: store.detalle(id: id))`.
5. El store devuelve **la misma instancia para el mismo id** (§4.3).
6. Al volver: el path se acorta, el closure se reevalúa, `store.popular()` devuelve la instancia
   de siempre con su `movies` intacto, y `.task` dispara `.alAparecer`, que **no recarga** porque
   `phase == .content`.

### Edge cases

- **Detalle de un id inexistente** → DT1: `.notFound` → `ScreenError` con el copy que ya existe.
  No hace falta caso nuevo en `MoviesError`.
- **Sin credencial** → el detalle falla igual que el listado: `MoviesModule` registra un
  `SinCredencialRepository` también para este puerto. Sin esto, el listado fallaría en claro y el
  detalle **crashearía por puerto no registrado**, que es peor.
- **Pulsar dos veces rápido la misma fila** → el `Coordinator` recibe dos `push` iguales. Hay que
  decidir y **testear** si apila dos detalles o uno. Propuesta: no se filtra en el ViewModel; si
  el `Coordinator` del paquete no deduplica, se declara y se acepta (es el comportamiento nativo
  de un `NavigationStack`).
- **Cancelación al salir del detalle mientras carga** → `performLoad` ya la cubre. **`f-52ef5f6d`
  NO bloquea este slice**: su propio detalle dice que bloquea paginación y el decorador de caché,
  y este slice no es ninguno de los dos.

## 7b. El borrado del registro del `Router` (OQ-1, rama a)

Inventario **verificado con `grep -rn "Router" Sources/ Tests/`**, no de memoria. Son tres sitios,
todos en `Sources/App/BaselineApp.swift`, y **ningún test referencia el `Router`** — que es
precisamente lo que `f-f88eb0fd` denunciaba:

| Línea | Qué es | Acción |
|---|---|---|
| 21-24 | el comentario que **promete** que «cuando un ViewModel necesite navegar … lo resuelve del contenedor» | **reescribir**: pasa a decir que el `Router` se inyecta por constructor desde el composition root, y por qué |
| 26-30 | `Container.shared.register(coordinator as any Router<MoviesRoute>, …)` | **borrar** |
| 39 | `(any Router<MoviesRoute>).self` dentro de `validateRegistrations([…])` | **borrar esa entrada**; la lista queda con los dos puertos de repositorio |

> El comentario de 21-24 se **reescribe y no se borra sin más**: es la promesa que hizo que este
> registro pareciera arquitectura durante dos PRD, y un archivo que enseña un patrón debe decir
> **cuál** sigue y por qué, no quedarse mudo. Esta es la misma clase de barrido que ya falló una
> vez en esta sesión —corregir donde te señalan y no donde la afirmación también vive—, así que
> el DoD lo exige con un `grep` de cierre.

`MoviesRoute.swift`:12 menciona «el `Router` en el ViewModel» al explicar por qué el PRD 0002 NO
lo metió entonces. Es una referencia histórica correcta, pero **queda desactualizada en cuanto el
Router entra de verdad**: revisarla en la fase 3.

## 8. Anti-features (qué NO entra)

1. **Pósters ni imágenes.** `posterPath` sigue sin usarse. Es su propio slice.
2. **Paginación.** Sigue fuera, y `f-52ef5f6d` sigue siendo su bloqueante, no el nuestro.
3. **String Catalog.** La pantalla de detalle añade literales visibles nuevos. **No se localiza
   aquí** (OQ-4): crear el catálogo y decidir la convención de claves es un cambio con entidad
   propia, exactamente el razonamiento con el que el owner lo sacó del PRD 0002 (OQ-6). Lo que sí
   es obligatorio: **actualizar `f-3d60d1f6`** con los literales nuevos, para que la deuda crezca
   *en el ledger* y no en silencio.
4. **Tests de `CoordinatorView`** (`f-8ab6c2ad`). Vive en el SPM, es otro repo (§5 NO-TOUCH).
   Este slice lo **ejercita** de extremo a extremo, que es evidencia nueva sobre ese finding, pero
   no lo cierra.
5. **Deep links.** El `Coordinator` los soporta; nadie los ha pedido.
6. **Caché del detalle.** El diseño queda *posible* (un decorador que pasa la misma suite de
   conformidad), no construido.

## 9. Escenarios golden (deben pasar al terminar)

1. **Navego al detalle correcto.** Dado el listado con 3 películas, cuando mando
   `.seleccionar(id de la tercera)`, entonces el `Router` espía recibe `.detalle(id:)` con **ese**
   id y ningún otro push.
2. **Al volver, el listado conserva su contenido.** Dado un detalle abierto, cuando el path vuelve
   a `.listado`, entonces `store.popular()` devuelve la **misma instancia**, `movies` es idéntico
   y `phase` sigue `.content`.
3. **Al volver no se recarga.** Mismo escenario: el repositorio espía **no** recibe una segunda
   llamada a `popularMovies()`.
4. **La Trampa C, sobre el detalle.** Dado un detalle abierto, cuando el closure de rutas se
   reevalúa N veces, entonces `store.detalle(id:)` construye **una sola** instancia. *Verificado
   con mutación: un builder que construya el ViewModel inline mata este test.*
5. **DT1.** Dado un id inexistente, cuando pido el detalle, entonces `.notFound` — contra el fake
   **y** contra el adapter real con un 404 de `MockURLProtocol`.
6. **Sin credencial, el detalle falla en claro.** Dado un arranque sin `Secrets.xcconfig`, cuando
   abro el detalle, entonces veo el error de credencial y **no** un crash por puerto no registrado.
7. **El Router está donde se dice que está.** Dado el grafo que arma `bootstrap`, cuando se
   resuelve `any Router<MoviesRoute>` en un contenedor propio, entonces resuelve — el test que
   `f-f88eb0fd` pide y que hoy no existe. *(Su forma exacta depende de OQ-1.)*

## 10. Métricas de éxito

- Los cuatro findings atados al slice, **cerrados con evidencia** (test o commit), no con prosa.
- El mutation score de los tests nuevos... **no se puede medir: el nivel 4 sigue mudo** en este
  repo (sin runner de mutación cableado). Sustituto declarado, no equivalente: cada golden se
  verifica con **una mutación manual** que debe matarlo, hecha en `git worktree` aparte y
  restaurada por checksum.
- A 2-4 semanas: ningún finding nuevo de la clase «la navegación no estaba verificada».

## 11. Rollout

Tres fases, cada una con su commit y su `reviewer`. Sin flags: es una pantalla nueva detrás de un
push. Rollback = revertir la fase. No hay migración de datos ni cambio de credencial, así que
**`security-reviewer` no es obligatorio** por la regla del PRD 0001 §5b (se pide si aparece algo
que toque credencial, almacenamiento o authz).

## 12. Riesgos

| Riesgo | Mitigación |
|---|---|
| **La memoización por id crece sin límite** (una instancia por película visitada) | OQ-3. Propuesta: diccionario por `MovieID`, con el crecimiento **declarado y acotado** (un ViewModel pequeño por película abierta en la sesión). La evicción va a §16, no aquí |
| **Borrar el registro del `Router` deja una punta sin quitar** — el comentario que lo promete, o la entrada de `validateRegistrations` | Ya no es riesgo abierto: §7b inventaria los **tres** sitios exactos, verificados con `grep`, y ningún test lo referencia |
| Golden 2 pasa y la posición de scroll igualmente salta | Declarado en §3: **no es verificable aquí**. Checklist manual en §15 |
| La Trampa C reaparece por la puerta del detalle | Golden 4, con mutación obligatoria |
| El slice crece hacia pósters o i18n | §8, anti-features 1 y 3 |

## 13. Open Questions

- [x] **OQ-1 — RESUELTA por el owner (2026-08-31), literal: «constructor, y borra el registro
      del Router».** Rama **(a)**: `PopularMoviesViewModel(repository:router:)`, con la factoría
      del store cerrando sobre el coordinator, y el registro del contenedor **eliminado por no
      tener consumidor**. Queda alineado con `architecture/SKILL.md`:88-93 —lectura obligatoria
      de este repo, que ya decía «inyección por constructor por defecto»— y con `Inject.swift`
      del paquete. `AGENTS.md` §3, que hasta ese día prescribía `@Inject` en los
      consumidores, se corrigió al mismo idioma por decisión del owner el 2026-08-31
      (`f-da257e0c`, cerrado): ya no hay ninguna fuente del proyecto que contradiga esta rama.
- [ ] **OQ-2 (bloquea la fase 1) — ¿un puerto nuevo o un método más en el existente?**
      Propuesta: **puerto nuevo**. `PopularMoviesRepository` es una *capability* declarada
      («pide exactamente una cosa») y añadirle `movieDetail` rompería esa declaración y obligaría
      a que el fake del listado supiera de detalles. Lo confirmo aquí porque el PRD 0001 ya lo
      publicó así y quiero que quede como decisión, no como inercia.
- [ ] **OQ-3 (bloquea la fase 2) — ¿cómo memoiza el store el detalle?**
      **(a)** Diccionario por `MovieID` *(recomendada)*: correcta siempre, crece con las películas
      visitadas. **(b)** Ranura única por id: no crece, pero se rompe el día que se navegue de
      detalle a detalle. **(c)** Con evicción al volver a la raíz: correcta y sin crecer, pero
      acopla el store al path del coordinator. Recomiendo **(a)** con el límite declarado, y **(c)**
      en §16 si algún día molesta.
- [ ] **OQ-4 — ¿confirmas que el String Catalog sigue fuera?** La pantalla de detalle añade
      literales visibles nuevos. Propuesta: **fuera** (mismo criterio que tu OQ-6), y
      `f-3d60d1f6` se actualiza con lo que este slice añade. Si prefieres que entre, es otro PRD:
      no cabe aquí sin romper §8.

## 15. Definition of Done

- [ ] Los siete escenarios golden pasan
- [ ] **TDD**: cada golden escrito y visto fallar **antes** de su implementación. Cada uno verificado con **mutación manual real** en `git worktree` aparte, restaurando por checksum (sustituto declarado del nivel 4, que está mudo)
- [ ] `bash tools/verify-run.sh` verde ligado al diff staged · `check-drift` sin errores nuevos · `check-layers` 0
- [ ] `reviewer` GREEN/AMBER atendido en **cada** fase
- [ ] **Revisor E2E al cierre del PRD**, con contexto de toda la cadena (encargo → PRD → skills → código → tests → ledger), y con honestidad simétrica: que declare qué de lo suyo ya lo habían cazado los gates baratos
- [ ] **Checklist manual en simulador con datos reales**, porque hay dos cosas que ningún test de este repo alcanza: (1) la **posición de scroll** al volver del detalle (§3), y (2) que el detalle no **parpadee** al cerrarse (`f-8ab6c2ad`, punto 4)
- [ ] **El borrado del `Router` no dejó puntas**: `grep -rn "Router" Sources/ Tests/` devuelve solo
      los usos nuevos (el parámetro del constructor y el tipo en el ViewModel), y **ninguna** mención
      a `Container`, `register` o `validateRegistrations` junto al `Router` (§7b)
- [ ] Los cuatro findings cerrados **con la evidencia dentro de la resolución**, no con «hecho»
- [ ] `f-3d60d1f6` actualizado con los literales nuevos · `f-8ab6c2ad` actualizado con lo que este slice ejercitó
- [ ] Las dos correcciones de §6.3 aplicadas al PRD 0001 en la fase 1
- [ ] Cada fase quitó su `[SLICE-FUTURO]` en su commit; al cierre `check-prd-tree` da `faltan=0 futuros=0`
- [ ] Sin secretos (gitleaks limpio)

## 16. Próximos pasos

- Evicción de la memoización del store (OQ-3, opción c) si el crecimiento llega a molestar.
- Pósters: `posterPath` lleva desde el slice 0 sin consumidor.
- String Catalog (`f-3d60d1f6`), que a partir de aquí tiene dos pantallas de deuda.
- Paginación, cuando `f-52ef5f6d` se decida.

## 17. Change log

| Fecha | Cambio | Quién |
|---|---|---|
| 2026-08-31 | Draft inicial. Contrato y golden 6 tomados del PRD 0001 §6.3/§9 en vez de reinventados. La verificación del código encontró dos cosas que el handoff no decía: el registro del `Router` se queda **sin consumidor** si el ViewModel lo recibe por constructor (OQ-1, ligada a `f-da257e0c`), y el PRD 0001 §6.2 se contradice con su propio §6.3 sobre dónde van `overview`/`releaseDate` (§6.3 de aquí). Corregido también el recuento del handoff: los findings atados son **cuatro** más un residuo declarado, no cinco findings | agente |

## 18. Gaps detectados (llenar post-ship)

_Pendiente._

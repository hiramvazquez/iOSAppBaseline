# PRD — Adopción de los SPM en el módulo de referencia

> **Tipo:** Forward · **Status:** Draft
> **Autor:** sesión de agente (Claude) · **Fecha:** 2026-08-29
> **Tracking:** `f-f2a4ca6e` · `f-a3b6dafc` · `f-e008f6f` · `f-71c669cc` · `f-54d7ee41` · `f-b6f2c1a4`
> **Design-review:** pendiente — **obligatorio antes de `Approved`** (AGENTS.md §12)

> ⚠️ **Por qué esto es un PRD y no un ADR, que no es obvio.** `prd-lifecycle.md` dice
> «Refactor sin cambio de comportamiento → **No** — ADR ligero si es decisión reusable», y este
> refactor congela el comportamiento a propósito (§4.1). Pero el criterio «mediano/grande» de esa
> misma página se cumple por partida doble: **toca más de un módulo** y es una **decisión
> arquitectónica reusable** — este repo es la baseline de la que salen los proyectos nuevos, así
> que lo que se decida aquí se replica en todos. Las dos reglas apuntan a sitios distintos y la
> página no dice cuál gana. Se resuelve como PRD porque **el owner lo pidió explícitamente**, y
> se deja anotado en vez de elegir en silencio: es un hueco real del proceso, no una duda de
> este cambio.

---

## 1. Contexto

El slice 0 entregó la vertical de películas cruzando Domain → Data → Features → App, con todos
los gates en verde. Al revisarlo, el owner detectó que **el módulo de referencia no usa la mitad
de `AppFoundation`**: verificado con `grep` sobre `Sources/`, hay **cero** usos de `Coordinator`,
`Router`, `Container`, `@Inject`, `DependencyModule` y `CoordinatorView`. `BaselineApp.swift`
monta un `NavigationStack` crudo y arma el grafo de dependencias a mano. De los dos paquetes
propios solo se adoptaron `BaseViewModel` y `ScreenContainer`.

**La causa raíz no fue descuido del agente** (`f-a3b6dafc`): `platforms/ios.md` —lectura
OBLIGATORIA por `skill-matrix.conf` para tocar cualquier ViewModel— **no mencionaba ni una vez
los SPM propios**, y lo que sí enseñaba eran las alternativas hechas a mano: un `@Observable`
a pelo en vez de `BaseViewModel`, un `AppCoordinator` propio en vez del `Coordinator` del
paquete, e inyección con `AppEnvironment.live()` en vez de `Container`. El agente **obedeció a
la skill**. Ningún gate lo cazó porque el código sí cumplía la regla que se le dio a leer.

Dato que conviene tener presente al valorar el diseño de abajo: el `design-reviewer` **sí lo
cazó por escrito** (H-7 de su 6ª pasada, dos horas antes del commit). Lo que falló fue el
cierre — ese sub-agente no deja marker, así que seis veredictos RED no impidieron nada
(`f-71c669cc`).

El 2026-08-29 se reescribieron `architecture/SKILL.md`, `platforms/ios.md`, `domain/SKILL.md` y
`security/SKILL.md` contra una auditoría del código fuente de los dos paquetes. **Ese era el
paso previo obligado**, y el mapa de ejecución ya lo decía: un refactor hecho leyendo la skill
vieja se habría desviado igual. Precondición verificable de este PRD:
`grep -rc FILL .agents/skills` — las cuatro skills de producto están a cero.

## 2. Problema

Este repo **no es una app: es la baseline de la que salen los proyectos iOS nuevos**, y su
módulo `Movies` es lo que las skills citan en vez de describir. Un módulo de referencia que no
usa la navegación ni la DI del paquete propio produce tres daños que se componen:

1. **Enseña a no usarlos.** Cada proyecto que salga de aquí copiará el `NavigationStack` crudo.
2. **Paga el coste sin el beneficio.** `MoviesScreenStore` existe *solo* para esquivar la Trampa C
   —que `CoordinatorView` reevalúa el closure de rutas y recrearía el ViewModel vacío— en una app
   que **no usa `CoordinatorView`**. Se pagó la indirección, la OQ-13, una trampa documentada en
   el PRD 0001 y el finding abierto `f-54d7ee41`, sin obtener nada a cambio.
3. **Cada pantalla nueva sube el precio.** Hoy adoptar el `Coordinator` toca ~3 archivos. Con dos
   pantallas es una migración.

Si NO se hace: el segundo slice copia el patrón, la deuda se multiplica por pantalla, y las
skills recién escritas quedan desmentidas por el propio módulo que deben ilustrar.

## 3. Objetivo

Que el módulo `Movies` **use lo que `AGENTS.md` §3 prescribe y las skills ya documentan**, sin
cambiar una sola línea de comportamiento observable para el usuario.

Medible, y verificable por comando:

> ⚠️ **Los criterios se verifican sobre SÍMBOLOS, no sobre texto.** La primera versión de esta
> tabla usaba `grep -rl "CoordinatorView\|any Router<" Sources/`, y el design-review demostró que
> **ya salía verde antes de escribir una línea**: casaba un comentario de `MoviesScreenStore.swift:5`
> que menciona `CoordinatorView` para explicar la Trampa C. Es exactamente lo que `layers.conf:6-9`
> declara que no se hace («trabaja sobre el GRAFO DE IMPORTS, NO sobre el cuerpo del archivo;
> comentarios y strings no cuentan»). Por eso el criterio fuerte es **el compilador**, con el
> patrón que este repo ya usa en `SmokeTests.swift`: un test que USA el tipo no compila si el
> tipo no está enlazado de verdad.

| Condición | Cómo se verifica |
|---|---|
| **PRIMARIO — el cableado REAL de la app** | `BootstrapTests.swift`, DOS direcciones: (a) `bootstrap(container: propio)` con módulos → lo resuelto **no** es `CableadoRotoRepository`; (b) **el recíproco que fija el arreglo de OQ-4**: `bootstrap` sobre un contenedor **vacío** → lo devuelto **sí** es `CableadoRotoRepository` — sin (b), la mutación `?? SinCredencialRepository()` (el fail-silent que la 4ª pasada bloqueó) pasa todos los gates. El recíproco (b) pasa un **espía** como `onMisconfiguration` — el default hace `assertionFailure` y atraparía el runner en Debug — y asevera **también que la señal se emitió**, con lo que borrar el log o el assert mata un test. Además construye `Coordinator<MoviesRoute>` e invoca `MoviesRouteBuilder`. ⚠️ (a) asevera «no es el fallback» y NO «es `TMDBPopularMoviesRepository`», **a propósito**: en CI no hay `Secrets.xcconfig`, el módulo registra `SinCredencialRepository`, y endurecer la aserción al tipo real rompería CI siempre — no lo «arregles» |
| El **módulo** registra lo que promete | G3: test de la fase 1, en contenedor propio |
| El **composition root usa** el módulo | `grep -rnE '^[^/]*register\(modules:' --include="*.swift" Sources/App/` |
| Existe un `DependencyModule` | `grep -rnE '^[^/]*: DependencyModule' --include="*.swift" Sources/App/` |
| La navegación pasa por `CoordinatorView` | `grep -rnE '^[^/]*CoordinatorView[[:space:]]*[({]' --include="*.swift" Sources/` |
| **Ninguna View construye un `NavigationStack`** | `! grep -rnE '^[^/]*NavigationStack[[:space:]]*[({]' --include="*.swift" Sources/` |
| La suite sigue verde y firmada | `bash tools/verify-run.sh` |
| Sin regresión de capas ni drift | `bash tools/check-layers.sh` · `bash tools/check-drift.sh` |

> ⚠️ **Tres pasadas de design-review, tres bugs distintos en esta misma tabla. El problema es el
> mecanismo, no la expresión.** Por orden: (1) el primer grep salía verde casando un **comentario**;
> (2) «endurecerlo» con paréntesis lo volvió a poner verde, ahora porque `NavigationStack {` es
> *trailing closure* y `NavigationStack(` da cero matches — la condición se declaraba cumplida con
> el `NavigationStack` intacto; (3) el escape que la tabla markdown exige para meter una tubería
> en una celda **sobrevive dentro de las comillas**, y en ERE es una tubería **literal**: el patrón
> buscaba la cadena `struct|final class`, que no existe en Swift, así que el criterio era
> **insatisfacible** — imposible de poner verde ni haciendo el trabajo.
>
> Por eso la fila primaria es ahora **el compilador**, que es lo que este repo ya usa en
> `SmokeTests.swift:12-22` («si los tres módulos no estuvieran enlazados de verdad, esto no
> compilaría»). Los greps quedan como comprobación **secundaria**, con la misma técnica en las
> cuatro: `^[^/]*` al principio —que excluye `//` y `///` de verdad, sobre el contenido y no sobre
> la salida de `grep -rn`— y cero tuberías, cero alternancias.
>
> `[[:space:]]` y no la clase corta: en `tools/` hay 55 usos del primero y **cero** de la segunda.
> BSD grep no la define y la degrada a la letra literal, con lo que el patrón deja de casar
> cualquier declaración indentada.

## 4. Filosofía / principios

1. **Comportamiento congelado, con una salvedad declarada.** Es un refactor: el usuario no debe
   notar nada. Todo test que pasaba antes pasa después, **o se explica cuál cambió y por qué** — si
   un test codificaba una decisión y no un hecho, se cambian ambos y se justifica en el propio test.
   **La salvedad, corregida tras la 4ª pasada del design-review:** la fase 1 introduce una clase de
   fallo que hoy no existe. Un registro ausente —o bajo el tipo estático equivocado, la trampa que
   `ios.md` §4 documenta— deja de ser un error de compilación. Y con la resolución de OQ-4 **ni
   siquiera es un `fatalError`: es una degradación**, que es una salvedad distinta y **peor**,
   porque un crash de bootstrap es ruidoso e imposible de ignorar y una degradación no.
   Por eso OQ-4 **no se queda en «no crashear»** — y con la jerarquía honesta: **lo que impide
   que un cableado roto llegue a release es el test primario de §3**, que invoca el bootstrap real
   en `verify-run` de cada fase y en CI. El log y el `assertionFailure` en DEBUG son diagnóstico
   de segunda línea, no la protección: esta app no tiene telemetría (OQ-3), así que un log en el
   dispositivo de un usuario no lo lee nadie — «visible» sin destinatario sería sobrevender.
   AGENTS.md §6 exige que el fallo se haga visible («Fail-silent nunca») y §5 que los errores de
   programación aserten: un grafo mal registrado es error de programación, no input recuperable.
2. **Constructor injection primero; `@Inject` solo con escape hatch.** `@Inject` resuelve de
   `Container.shared` y cachea para siempre, así que un tipo con `@Inject` **sin `init(container:)`
   no se puede testear con un contenedor propio** — justo lo que §3 exige. Ese detalle salió de la
   auditoría del paquete, no de su README, y es la razón de que la regla no sea estilística.
   **Y nunca para dependencias cuyo lifecycle no sea singleton:** `@Inject` cachea la primera
   resolución para siempre, así que convierte un `.transient` en singleton **en silencio**, con
   escape hatch o sin él. Eso no es un problema de testabilidad sino de semántica en producción.
3. **Adoptar el mecanismo no es adoptar su ceremonia.** Si una pieza del paquete no aporta aquí,
   se declara por qué en vez de meterla para cumplir. Un módulo de referencia que usa algo
   «porque toca» enseña peor que uno que explica por qué no lo usa.

## 5. Estructura de archivos a crear / tocar

```
Sources/Features/Movies/MoviesRoute.swift              ← [SLICE-FUTURO] fase 2: enum de rutas (Hashable)
Sources/App/Movies/MoviesModule.swift                  ← [SLICE-FUTURO] fase 1: DependencyModule, registra adapters
Sources/Features/Movies/PopularMoviesViewModel.swift   ← TOCAR: enum Intent + send(_:). SIN any Router (ver 5b)
Sources/Features/Movies/PopularMoviesView.swift        ← TOCAR: deja de poseer identidad (f-54d7ee41)
Sources/App/BaselineApp.swift                          ← TOCAR: bootstrap(container:) + Coordinator;
                                                          aquí nace CableadoRotoRepository, junto a
                                                          SinCredencialRepository que ya vive aquí
Sources/App/AppCoordinatorView.swift                   ← [SLICE-FUTURO] fase 2: Coordinator + CoordinatorView
Sources/App/Movies/MoviesRouteBuilder.swift             ← [SLICE-FUTURO] fase 2: la costura que hace G4 escribible
Sources/App/Movies/MoviesScreenStore.swift             ← TOCAR: pasa a estar justificado de verdad
Tests/UnitTests/Movies/MoviesModuleTests.swift         ← [SLICE-FUTURO] fase 1: registra lo que promete
Tests/UnitTests/Movies/MoviesRouteBuilderTests.swift    ← [SLICE-FUTURO] fase 2: G4, el closure usa el store
Tests/UnitTests/Movies/PopularMoviesViewModelTests.swift ← TOCAR: 10 llamadas a handle(_:) que la fase 3 renombra
Tests/UnitTests/Movies/MoviesScreenStoreTests.swift    ← TOCAR: handle(_:) + dos PopularMoviesViewModel(repository:)
Tests/UnitTests/SmokeTests.swift                       ← TOCAR/REVISAR: lee Container.shared y asevera tryResolve == nil
Tests/UnitTests/Movies/BootstrapTests.swift            ← [SLICE-FUTURO] fase 1: el criterio PRIMARIO de §3
```

### NO-TOUCH (contrato — el implementador NO toca esto)

```
tools/**  ·  ci/**  ·  .github/**  ·  lefthook.yml  ·  scripts/agent-hooks/**
    ← tooling compartido: exige aprobación explícita del owner (§8)
tools/drift-ratchet.json  ·  tools/mutation-ratchet.json
    ← trinquetes: solo los mueve su script, y en una sola dirección (§9)
tools/layers.conf · tools/skill-matrix.conf · tools/verify.conf
AGENTS.md · CLAUDE.md · docs/process/prds/_template.md
    ← meta-doc (§8)
Sources/Domain/**
    ← el dominio NO cambia. Si el refactor exige tocarlo, el diseño está mal:
      Domain no puede importar AppFoundation ni CoreNetworking (layers.conf:41)
iOSAppBaseline.xcodeproj/…/Package.resolved
    ← NO se bumpea el pin en este PRD (hoy: AppFoundation 0.1.1, CoreNetworking
      0.1.4). Ojo: `project.yml` los trae con `from: 0.1.0`, así que un `resolve`
      puede saltar solo dentro del rango — lo que fija el build reproducible es
      este lockfile, no el rango. Si un arreglo de los paquetes (f-8720114e)
      hace falta, es OTRO PRD.
      (La versión anterior decía `spm-pro/**`, ruta que NO existe en este repo:
      los paquetes entran por URL remota. Una prohibición sobre algo inexistente
      no prohíbe nada.)
```

## 5b. Fases entregables

> **Orden de ejecución: 3 → 1 → 2.** La columna de la derecha dice **por qué**, no cuándo.

| Fase | Entrega (mergeable) | Orden / motivo |
|---|---|---|
| **3 — Convención de intención** | `enum Action` → `Intent` + `send(_:)`, alineado con `.claude/rules/10-ios-ui.md`. Cierra `f-b6f2c1a4`. | **Primera.** Sin dependencias: es mecánica e independiente, y desactiva la colisión del `typealias Action` **antes** de la fase que mete tipos de AppFoundation en esa clase |
| **1 — DI** | `MoviesModule` + `Container` en el composition root. Sin cambio visible. Los tests registran fakes en contenedores propios. | **Segunda.** Sin dependencia técnica de las otras; va antes que la 2 porque su verificación (G3) no toca UI y deja un diff pequeño |
| **2 — Navegación (RECORTADA)** | `MoviesRoute` + `AppCoordinatorView` + `Coordinator` + `CoordinatorView` + **`MoviesRouteBuilder`** (la costura que hace G4 escribible) + **G4**. La View deja de poseer identidad; `MoviesScreenStore` pasa a estar justificado. **NO entra `any Router` en el ViewModel** — ver abajo. | **Tercera.** No depende técnicamente de la 1: es **fricción**, ambas editan `BaselineApp.swift` y se serializan para no colisionar |

**Por qué en este orden — corregido tras el design-review.** La primera versión decía que «la
navegación necesita el grafo ya armado por `Container`». **Es falso**: la fase 2 compila
perfectamente con el grafo a mano, porque `BaselineApp.repositorio()` ya devuelve
`any PopularMoviesRepository` y el store solo necesita esa factoría. Me inventé una dependencia
técnica que no existe.

La razón real es de **fricción, no de dependencia**: ambas fases editan `BaselineApp.swift`, así
que se serializan para no colisionar, y la DI va primero porque su verificación (G3) no toca UI y
deja un diff pequeño. En paralelo no, por lo mismo.

**Y la fase 3 se adelanta.** Tal como estaba, la fase 2 escribiría tests nuevos contra
`handle(_:)`/`Action` y la fase 3 los renombraría acto seguido. Hacer el renombrado **antes** es
más barato —es mecánico e independiente— y desactiva la colisión del `typealias Action` **antes**
de la fase que mete tipos de AppFoundation en esa clase. Orden final: **3 → 1 → 2**.

### Por qué `any Router` NO entra en la fase 2

Con `MoviesRoute` de un solo caso **no hay nada que empujar**: `router` entraría al ViewModel
como dependencia con **cero call sites** en `Sources/`, y su test solo podría aseverar una llamada
que el código de producto nunca hace — un test que pasa con cualquier implementación, prohibido
por AGENTS.md §5. Este repo ya pagó esto una vez: `PopularMoviesViewModel.swift:36-46` dedica once
líneas a explicar por qué `.reintentar` existe «sin call site en `Sources/`». No se reincide con
una dependencia entera.

Es §4.3 aplicado a sí mismo: adoptar el mecanismo no es adoptar su ceremonia. **El `Router` viaja
con el slice de detalle**, que es cuando hay a dónde navegar.

**La fase 3 es un renombrado con razón técnica, no estética:** `AppFoundation` declara
`public typealias Action`, y un `enum Action` anidado en un ViewModel **lo sombrea dentro de esa
clase**, así que ahí dentro no se puede anotar un closure del paquete sin escribir
`AppFoundation.Action`. `Intent` + `send(_:)` evita la colisión y coincide con lo que
`.claude/rules/10-ios-ui.md` ya decía, cerrando la contradicción sin cambiar la regla.

## 6. Modelo de datos

**Sin cambios.** No se crean, modifican ni retiran entidades, puertos ni errores de dominio.
`MoviesRoute` es un tipo de presentación y vive en `Features/`, no en `Domain/`.

## 7. Flujo de la solución

```
BaselineApp (composition root)
  ├─ bootstrap(container:onMisconfiguration:) -> any PopularMoviesRepository
  │    │  COSTURA invocable desde un test. Registra EN EL CONTENEDOR RECIBIDO —
  │    │  la app le pasa .shared, los tests el suyo propio. Sin esto, el test
  │    │  primario mutaría el global (prohibido por la skill y por G3) o
  │    │  probaría un grafo distinto del de la app.
  │    │
  │    │  onMisconfiguration: (String) -> Void
  │    │      = { AppLog.error($0); assertionFailure($0) }   ← default de PRODUCCIÓN
  │    │  La señal de mala configuración se INYECTA (6ª pasada): el default hace
  │    │  log + assert — lo que §4.1 y §13 prometen —, y el test recíproco pasa
  │    │  un ESPÍA: sin trap, y asevera el tipo devuelto Y que la señal se
  │    │  emitió. Con el assert escrito a fuego dentro, el recíproco no podía
  │    │  ejecutarse: assertionFailure atrapa el proceso en Debug, que es la
  │    │  config con la que corren los tests (project.yml), y ni Swift Testing
  │    │  ni XCTest capturan un trap in-process.
  │    │
  │    ├─ container.register(modules: [MoviesModule()])      ← fase 1
  │    │     └─ si TMDBConfiguration.live() == nil, el MÓDULO registra
  │    │        SinCredencialRepository  ← el guard de la credencial vive AQUÍ
  │    └─ tryResolve() ?? { onMisconfiguration(...); return CableadoRotoRepository() }()
  │         │                                                ← OQ-4: no crashea en release
  │         └─ la señal va AQUÍ y no en validateRegistrations: ese corre DESPUÉS
  │            del bootstrap, es un aviso adicional y NO la protección — llegaría
  │            tarde: el fallback ya habría ocurrido antes de que mirara
  ├─ #if DEBUG validateRegistrations([...])                 ← aviso ADICIONAL; no es la
  │                                                            protección (llega tarde, ver arriba)
  ├─ Coordinator<MoviesRoute>(root: .listado)               ← fase 2
  ├─ MoviesScreenStore(makePopular: { PopularMoviesViewModel(repository: ↑ lo que devolvió bootstrap) })
  └─ AppCoordinatorView(coordinator:store:)
        └─ CoordinatorView { route in ... store.popular() } ← el closure SOLO ensambla
                                     ↑
                     MoviesScreenStore memoiza: MISMA instancia siempre
```

> **Por qué el fallback es un tipo NUEVO y no `SinCredencialRepository`.** Reutilizarlo le daría
> **dos causas indistinguibles**: «falta la credencial» (estado esperado y documentado) y «el grafo
> de DI está roto» (bug). Misma pantalla, mismo copy, mismo `.unauthorized` — y con eso **G2 pasaría
> con el cableado entero roto**, además de dejar su nombre mintiendo. `CableadoRotoRepository` lanza
> el mismo error y muestra el mismo copy vago al usuario (§6: no se le cuenta la causa), pero
> **emite un log de error al construirse**: el usuario ve lo mismo, el operador distingue. Eso es
> §6 entero, no su primera mitad.
>
> **Y como el guard de la credencial vive en el módulo**, el `??` solo se dispara por cableado
> roto. Es alcanzable únicamente por bug, que es exactamente lo que debe logear.

**`AppCoordinatorView` no construye vistas: delega en `MoviesRouteBuilder`.** Esa costura es lo
que hace G4 escribible — si el closure se escribe inline (que es lo natural, y lo que sugiere el
ejemplo de `ios.md`), G4 se queda sin sujeto y la fase 2 vuelve a ser cableado sin test. La línea
de conexión queda deliberadamente trivial:

```swift
CoordinatorView(coordinator: coordinator) { MoviesRouteBuilder.view(for: $0, store: store) }
```

> **Residuo conocido, declarado en vez de disimulado:** G4 prueba el builder, no que
> `AppCoordinatorView` **le pase** ese builder a `CoordinatorView`. Un builder perfecto más un
> closure inline escrito al lado darían G4 en verde con la Trampa C viva — el mismo patrón de
> `f-ed8f24f6` («se prueba el validador y se prueba el mapeo, no el código que los conecta»), un
> nivel más arriba. Por eso la conexión es **una sola línea sin cuerpo**: el residuo no verificado
> pasa a ser «¿se llama al builder?» y no «¿qué hace el closure?».
>
> **Condición de cierre, para que no sea un finding abierto para siempre** (§1.1 exige estado
> terminal): se cierra con el **slice de detalle** — el mismo que trae el `Router` —, porque es
> cuando existe un push/pop real que lo ejercite. No «algún día»: un evento planificado.

**El `Router` no entra en este PRD** (§5b): con una sola ruta no hay a dónde navegar. Cuando entre,
el ViewModel dependerá de `any Router<MoviesRoute>` —el protocolo: seis métodos y ningún estado de
lectura—, así que no podrá saber dónde está ni resetear el root: solo emitir intención.

## 8. Anti-features (qué NO entra)

- **Ninguna pantalla nueva.** El detalle, la paginación y los pósters siguen fuera. (OQ-2 se
  resolvió como fase 2 **recortada**: no abre esa puerta.)
- **No se toca `Domain/`.** Ni entidades, ni puertos, ni `MoviesError`.
- **No se modifican los SPM.** Los defectos hallados en la auditoría (`f-8720114e`: el README que
  enseña el anti-patrón; el bug de `Container` con lifecycles cruzados) se arreglan en su repo.
- **No se activa SSL pinning.** Es decisión del owner, y pinnear contra una API de terceros
  obliga a rotar la app cada vez que ellos roten certificado.
- **No se construye el detector de omisión** (OQ-1): va en su propio PRD, después.
- **No se localiza el literal `"Películas populares"`** (OQ-6): exige crear el String Catalog y
  decidir la convención de claves. Se registra en el ledger y se cierra aparte.
- **No se usa `@Inject`** (OQ-3): no hay ninguna dependencia transversal que lo justifique hoy.

## 9. Escenarios golden (deben pasar al terminar)

| # | Escenario | Cómo se verifica |
|---|---|---|
| G1 | La app lista películas igual que antes, **en lógica** | suite existente, sin cambios. **NO cubre la UI** — ver recuadro |
| G2 | Sin credencial, la pantalla muestra el error de siempre | test existente de `SinCredencialRepository`. **Ya no basta solo**: tras OQ-4 hay dos rutas a esa pantalla, y quien distingue la buena de un cableado roto es el criterio PRIMARIO de §3, no G2 |
| G3 | El módulo de DI registra lo que promete | test nuevo, en contenedor propio, **sin tocar `Container.shared`** |
| G4 | **El closure de rutas USA el store, no construye el ViewModel inline** | test nuevo sobre el builder de rutas: invocarlo N veces con `.listado` y aseverar `construcciones == 1` en la factoría del store |
| G5 | *(retirado — ver abajo)* | |

> ⚠️ **Corrección de la versión anterior, y es un error mío que conviene dejar escrito.** Este PRD
> afirmaba que el golden «al volver del detalle el listado conserva su contenido» *«necesita una
> segunda pantalla para existir»*. **Es falso: ese test ya existe y pasa** —
> `Tests/UnitTests/Movies/MoviesScreenStoreTests.swift`, `conservaElContenido`, con la aserción
> literal «volver atrás no puede vaciar el listado (escenario golden 6)». Lo cazó el design-review.
>
> Lo que de verdad **no** está cubierto es otra cosa, y es nueva de la fase 2: que el closure de
> rutas de `CoordinatorView` **use** el store en vez de construir el ViewModel inline. Hoy no puede
> fallar porque no hay closure; en cuanto la fase 2 lo cree, ahí reaparece la Trampa C. Y
> `MoviesScreenStoreTests` no lo ve, porque prueba el store, **no a su consumidor** — el mismo
> patrón que `f-ed8f24f6`: se prueba el validador y se prueba el mapeo, no el código que los
> conecta. Eso es **G4**, y se puede escribir con una sola pantalla.

> ⚠️ **G1 no puede detectar una regresión de UI, y decirlo importa.** La suite son ocho archivos de
> ViewModel, store, DTOs, repositorio y mapeo de errores: **cero tests de vista, cero snapshot,
> cero UI tests**. Y el cambio `NavigationStack` → `CoordinatorView` **sí toca la UI**: bajo
> `CoordinatorView` la barra del sistema queda **oculta en todas las rutas** y `.navigationTitle`
> deja de hacer nada (`ios.md` §3). Por eso la equivalencia visual se verifica con un **checklist
> manual en simulador** —título visible, botón atrás, safe areas, pantalla de error, ES/EN—
> anotado aquí al cerrar la fase 2. Es evidencia declarada y barata; lo que no vale es que un ítem
> del DoD parezca automático y no lo sea.

> **G5 retirado.** Decía «si alguno lo usa, tiene `init(container:)`». Es un condicional cuyo
> antecedente será falso (OQ-3 apunta a «todo por constructor»: no hay analítica ni logger propio).
> Un golden que no dispara no es un golden: suma un check verde que no mide nada. La regla sigue
> viva donde corresponde, en `architecture/platforms/ios.md` §4.

## 10. Métricas de éxito

- Cada fila de §3 da el resultado declarado. *(No se escribe aquí cuántas son: una cuenta a mano
  al lado de la lista que cuenta caduca sola, y ya caducó dos veces en este mismo PRD.)*
- `bash tools/verify-run.sh` verde y firmado contra el diff de cada fase.
- Ningún test existente borrado sin justificación escrita en el propio test.

## 11. Rollout

Tres commits, uno por fase, cada uno con su `verify-run` y su `reviewer`. Sin feature flags: es
refactor interno y el comportamiento no cambia. Si una fase se tuerce, se revierte sola.

## 12. Riesgos

| Riesgo | Mitigación |
|---|---|
| **El `design-reviewer` no tiene consecuencia mecánica** (`f-71c669cc`): en el PRD 0001 dio seis pasadas RED y el commit pasó igual | **Declarado aquí como responsabilidad explícita del implementador:** si el design-review sale RED, se para. No hay gate que lo imponga; que esté escrito es la única red que existe hoy |
| Adoptar `Coordinator` con **una sola ruta** parece ceremonia y puede envejecer mal | ✅ **Resuelto (OQ-2): fase 2 recortada.** Entra lo que tiene call sites hoy; el `Router` viaja con el slice de detalle |
| `@Inject` sin `init(container:)` haría los tests dependientes del contenedor global | **No aplica en este PRD (OQ-3): cero usos de `@Inject`**, y §8 lo declara anti-feature. La regla queda viva en `architecture/platforms/ios.md` §4 para cuando aparezca una dependencia transversal |
| Un `reviewer` que mute código deja el árbol sucio y tumba el `verify-marker` | Pasó el 2026-08-29: se pedirá mutar en `git worktree` aparte y comprobar `git status --porcelain` antes de terminar |
| El refactor arregla el estado pero **no impide la reincidencia** | ⚠️ **Sin mitigación en este PRD, por decisión.** OQ-1 mandó el detector de omisión a otro PRD, así que `f-e008f6f` queda abierto **a propósito**: el siguiente slice puede desviarse y ningún gate lo vería. Riesgo aceptado, no cubierto |
| **La fase 1 degrada una garantía del compilador a un fallo de runtime** *(identificado en la 4ª pasada como `fatalError`; tras OQ-4 ya ni crashea: se degrada — ver §4.1)*. Hoy `repositorio() -> any PopularMoviesRepository` es total y el compilador la verifica. Con `Container`, `resolve` hace `fatalError` si falta el registro, y la trampa de la **clave por tipo estático** hace que registrar el concreto y resolver el protocolo explote **en runtime**. `validateRegistrations` es solo DEBUG. Choca con §4.1, con AGENTS.md §2 («hacer el error imposible por tipo antes que detectarlo después») y con §14.1 — y pone en riesgo la promesa escrita en `BaselineApp.swift:20-25`: *«un clon recién hecho nunca se rompe por un archivo que no está»* | ✅ **Resuelto (OQ-4, refinado en la 4ª pasada): `tryResolve` + fallback a `CableadoRotoRepository`** — un tipo NUEVO cuya señal —log + `assertionFailure` en DEBUG— entra **inyectada** por `onMisconfiguration` (§7: el default de producción la emite; el test recíproco pasa un espía, porque el assert atraparía el runner), **no** `SinCredencialRepository` (reutilizarlo era fail-silent: dos causas indistinguibles, prohibido por §6). La protección real es el test primario de §3, que invoca el bootstrap y falla si lo resuelto es el fallback; el log y el assert son diagnóstico de segunda línea |

## 13. Open Questions — **RESUELTAS por el owner (2026-08-29)**

| # | Pregunta | Decisión |
|---|---|---|
| **OQ-1** | ¿Entra el detector de OMISIÓN (`f-e008f6f`)? | ✅ **En un PRD aparte, después.** El refactor entra ya. Razón: toca `tools/`, que §8 reserva al owner, y meterlo aquí mezclaría código de app con maquinaria del harness — la misma mezcla de naturalezas que el `reviewer-gate` desaconseja con datos medidos. **Consecuencia declarada:** hasta que exista, este refactor arregla el estado pero **no la causa**; el siguiente slice puede desviarse y ningún gate lo vería. `f-e008f6f` queda abierto a propósito |
| **OQ-2** | ¿La fase 2 entra recortada, sin `any Router`? | ✅ **Sí, recortada.** Con una sola ruta el `Router` entraría con cero call sites. Viaja con el slice de detalle |
| **OQ-3** | ¿`@Inject` o constructor? | ✅ **Todo por constructor.** No hay ninguna dependencia transversal en el módulo (ni analítica ni logger propio), así que `@Inject` queda **declarado como no usado, y por qué** — que documenta mejor que usarlo por usarlo. La regla de §4.2 sigue viva para cuando aparezca una |
| **OQ-4** | ¿Qué protege el arranque en **release** si falta un registro? | ✅ **Decisión del owner: no crashear** — preserva la promesa de `BaselineApp.swift:20-25`. **Mecanismo refinado tras la 4ª pasada del design-review** (la forma original de esta acta —caer a `SinCredencialRepository`— era fail-silent y §6 lo prohíbe; el refinamiento ejecuta la decisión, no la cambia): el fallback es **`CableadoRotoRepository`**, un tipo nuevo con el mismo copy vago cuya señal —**log + `assertionFailure` en DEBUG**— entra **inyectada** por `onMisconfiguration` (§7), porque escrita a fuego el test recíproco no podía ejecutarse — un grafo mal registrado es error de programación, no input recuperable (§5). Lo que impide que llegue a release es el **test primario de §3** contra el bootstrap real; el log y el assert lo hacen diagnosticable si aun así ocurre |
| **OQ-5** | ¿Cómo se verifica la equivalencia de UI sin UI tests? | ✅ **Checklist manual en simulador**, al cerrar la fase 2: título visible, botón atrás, safe areas, pantalla de error y ES/EN, con capturas anotadas en este PRD. Es **evidencia declarada**, no automática — y eso se dice, en vez de dejar que un ítem del DoD lo parezca. Montar UI tests es un trabajo con entidad propia: su propio PRD |
| **OQ-6** | El literal `"Películas populares"`: ¿se localiza aquí? | ✅ **Al ledger, no a este PRD.** Localizarlo exige crear el String Catalog y decidir la convención de claves — un cambio con entidad propia que no debe colarse dentro de un refactor de arquitectura. §1.3 se cumple registrándolo, que es lo que §10 llama cerrar |

## 14. Mockups / referencias

No hay mockups, pero **no es cierto que no haya cambios de UI**: bajo `CoordinatorView` la barra
del sistema queda oculta en todas las rutas (§9, OQ-5). Las referencias son `architecture/platforms/ios.md` §3-§4
(navegación y DI, con el ejemplo completo y las trampas verificadas) y `domain/SKILL.md`.

## 15. Definition of Done

- [ ] Las tres fases mergeadas, cada una con `verify-run` verde firmado y `reviewer` no-RED.
- [ ] Cada fila de §3 da el resultado declarado.
- [ ] G1-G4 pasan (G5 retirado, §9); G3 y G4 son tests nuevos.
- [ ] `BootstrapTests` cubre **las dos direcciones** de §3 — incluida la recíproca (contenedor
      vacío → `CableadoRotoRepository`), que es la que impide revertir el arreglo de OQ-4 sin
      que ningún test lo vea.
- [ ] El recíproco asevera **la señal de `onMisconfiguration`**, no solo el tipo: borrar el log
      o el assert del default de producción tiene que matar un test.
- [ ] **Checklist manual de UI en simulador** (OQ-5) ejecutado al cerrar la fase 2 y sus capturas
      anotadas aquí: título, botón atrás, safe areas, pantalla de error, ES/EN. Es evidencia
      declarada, no automática.
- [ ] `bash tools/check-layers.sh` y `bash tools/check-drift.sh` sin errores nuevos.
- [ ] **Cada fase quita el `[SLICE-FUTURO]`** de las líneas de §5 que entrega, **en su mismo
      commit**. Y al cerrar el PRD: `bash tools/check-prd-tree.sh` reporta **`futuros=0`** para
      este PRD, no solo `faltan=0`.
      > Por qué se escribe así: `check-prd-tree.sh:194-197` **salta** toda línea marcada
      > `[SLICE-FUTURO]`. **Todos** los archivos nuevos la llevan, así que con la redacción anterior
      > —«sin huérfanos»— el check habría dicho `faltan=0` aunque no se creara ni un archivo. Era
      > un ítem de DoD que pasa igual haciendo el trabajo que no haciéndolo: un gate anunciado que
      > no existe (§14.4), justo lo que ese script dice cazar.
- [ ] `f-f2a4ca6e`, `f-54d7ee41` y `f-b6f2c1a4` **cerrados** con su resolución real.
- [ ] Residuo de G4 —la conexión builder → `CoordinatorView`— **registrado en el ledger** con su
      condición de cierre (el slice de detalle). §10: reportar es loguear, no mencionar en prosa.
- [ ] Las skills siguen siendo ciertas: si el refactor cambia un patrón, la skill se actualiza
      **en el mismo PR** (§Mantenimiento de `architecture/SKILL.md`).
- [ ] `docs/process/current_execution_map.md` actualizado **en el mismo commit** (feature-workflow §4.3).
- [ ] **Design-review OK** antes de `Approved` (§12).

## 16. Próximos pasos

1. `design-reviewer` sobre este PRD. Si sale RED, se corrige **el PRD, no el código** (§1.6).
2. ✅ **OQ-1 a OQ-6 resueltas por el owner (2026-08-29)** — ver §13. Falta solo `Status: Approved`.
3. **Fase 3** (el renombrado), que es la primera del orden 3 → 1 → 2.

## 17. Change log

> Una fila por pasada, la más reciente arriba. La versión anterior de esta tabla mezclaba la 2ª
> con la 3ª y contaba dos veces la 1ª — la sección cuyo único trabajo es registrar cambios
> también puede mentir, y el design-review lo cazó (F7, 5ª pasada).

| Fecha | Cambio | Quién |
|---|---|---|
| 2026-08-29 | **6ª pasada: 🔴 RED (5).** Dos arreglos de la 5ª se anulaban entre sí: el `assertionFailure` escrito a fuego en el `??` atrapa el proceso en Debug —la config de los tests—, así que el test recíproco que fija OQ-4 **no podía ejecutarse**: el runner moría antes de aseverar. La salida previsible era borrar una de las dos protecciones bloqueadas en la 4ª/5ª. Arreglo: la señal se **inyecta** (`onMisconfiguration`, default de producción = log+assert; el test pasa un espía y asevera también la señal — con lo que borrar el log o el assert ahora mata un test). Sexta instancia del mecanismo «arreglar aquí, romper allá»: esta vez entre dos arreglos de la misma pasada | agente |
| 2026-08-29 | **5ª pasada: 🔴 RED (7).** §12 y §13 —el acta del owner— seguían prescribiendo el fallback a `SinCredencialRepository` que la 4ª rechazó: quinta instancia de «corregir donde señalaron, no donde la afirmación también vivía», esta vez en el sitio con más autoridad del documento. Corregido: ambas celdas refinadas a `CableadoRotoRepository` + assert; el test **recíproco** (contenedor vacío → fallback) que fija el arreglo contra la mutación que lo revierte; `bootstrap` registra en el contenedor **recibido**; el assert va en el `??`, no en `validateRegistrations`, que corre después; la trampa de CI documentada en la fila primaria | agente |
| 2026-08-29 | **4ª pasada: 🔴 RED (7).** El fallback de OQ-4 era fail-silent (§6: nunca) e invalidaba G2. Diseño refinado: tipo propio que logea + `bootstrap(container:)` invocable desde el test primario. §4.1 declaraba la salvedad equivocada, tapándolo | agente |
| 2026-08-29 | **Owner cierra OQ-1 a OQ-6** (§13), propagadas a §7, §8, §12, §15 y §16 | owner |
| 2026-08-29 | **3ª pasada: 🟡 AMBER (8).** Un criterio **insatisfacible** — el escape de tubería que exige la tabla markdown sobrevive dentro de comillas y en ERE es literal. Tercer bug distinto en la misma tabla de greps: el compilador pasa a criterio primario y los greps a secundarios | agente |
| 2026-08-29 | **2ª pasada: 🔴 RED (9, cuatro introducidos por el arreglo de la 1ª).** El grep «endurecido» con paréntesis volvía a salir verde (`NavigationStack {` es trailing closure); el filtro anti-comentarios era un no-op; §5 seguía prescribiendo el Router que §5b excluía | agente |
| 2026-08-29 | **1ª pasada: 🔴 RED (13).** Los cuatro bloqueantes eran comprobaciones que no comprobaban: un criterio verde casando un comentario; `MoviesModule` donde `layers.conf:56` lo rechazaría; un golden imposible con una ruta única; un DoD infalsificable porque `[SLICE-FUTURO]` lo salta. Y una afirmación falsa en §9: el golden de «volver del detalle» ya existía y pasaba | agente |
| 2026-08-29 | Draft inicial, tras la reescritura de las skills y la auditoría de los dos SPM | agente |

## 18. Gaps detectados (llenar post-ship)

_Pendiente._

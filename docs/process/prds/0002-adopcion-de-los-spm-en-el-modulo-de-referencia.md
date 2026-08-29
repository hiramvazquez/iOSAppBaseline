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
| El **módulo** registra lo que promete | G3: test de la fase 1, en contenedor propio |
| El **composition root usa** el módulo | `grep -rnE '^[^/]*register\(modules:' --include="*.swift" Sources/App/` |
| Existe un `DependencyModule` | `grep -rnE '^[[:space:]]*(struct\|final class) .*: DependencyModule' --include="*.swift" Sources/App/` |
| La navegación pasa por `CoordinatorView` | `grep -rnE 'CoordinatorView[[:space:]]*[({]' --include="*.swift" Sources/ \| grep -vE ':[0-9]+:[[:space:]]*//'` |
| **Ninguna View construye un `NavigationStack`** | `! grep -rnE 'NavigationStack[[:space:]]*[({]' --include="*.swift" Sources/` |
| La suite sigue verde y firmada | `bash tools/verify-run.sh` |
| Sin regresión de capas ni drift | `bash tools/check-layers.sh` · `bash tools/check-drift.sh` |

> ⚠️ **Segunda corrección de esta tabla, y las dos veces por lo mismo.** La 1ª versión usaba
> `grep -rl "CoordinatorView\|any Router<"`, que salía verde casando un **comentario**. La 2ª la
> «endureció» exigiendo paréntesis — y volvió a salir verde, ahora por el motivo contrario:
> `BaselineApp.swift:14` es `NavigationStack {`, **trailing closure sin paréntesis**, la forma que
> SwiftUI usa siempre para un contenedor con un solo `@ViewBuilder`. `NavigationStack(` daba **cero
> matches**, el `!` lo invertía, y la condición «ninguna View construye un `NavigationStack`» se
> declaraba cumplida **con el `NavigationStack` que este PRD existe para borrar todavía en su
> sitio**. Por eso ahora el patrón es `[[:space:]]*[({]`: cubre las dos formas.
>
> Y el filtro anti-comentarios de la 2ª versión —`| grep -v "^\s*//"`— **no filtraba nada**:
> `grep -rn` emite `ruta:línea:contenido`, así que la línea empieza por `Sources/`, nunca por `//`.
> Una defensa anunciada que no existe (§14.4), escrita tres líneas debajo del recuadro que decía
> estar corrigiendo justo eso.
>
> `[[:space:]]` y no `\s`: en `tools/` hay 55 usos del primero y **cero** del segundo, y no es
> casualidad — BSD grep no define `\s` y lo degrada a la letra `s`, con lo que `^\s*struct` pasa
> a ser `^s*struct` y deja de casar cualquier declaración indentada.

## 4. Filosofía / principios

1. **Comportamiento congelado, con una salvedad declarada.** Es un refactor: el usuario no debe
   notar nada. Todo test que pasaba antes pasa después, **o se explica cuál cambió y por qué** — si
   un test codificaba una decisión y no un hecho, se cambian ambos y se justifica en el propio test.
   **La salvedad:** la fase 1 introduce una clase de fallo que hoy no existe — un registro ausente
   o bajo el tipo equivocado deja de ser un error de compilación y pasa a ser un `fatalError` en
   runtime (ver §12 y OQ-4). Decir «nada cambia» sin nombrarlo sería falso.
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
Sources/App/BaselineApp.swift                          ← TOCAR: Container + Coordinator
Sources/App/AppCoordinatorView.swift                   ← [SLICE-FUTURO] fase 2: Coordinator + CoordinatorView
Sources/App/Movies/MoviesRouteBuilder.swift             ← [SLICE-FUTURO] fase 2: la costura que hace G4 escribible
Sources/App/Movies/MoviesScreenStore.swift             ← TOCAR: pasa a estar justificado de verdad
Tests/UnitTests/Movies/MoviesModuleTests.swift         ← [SLICE-FUTURO] fase 1: registra lo que promete
Tests/UnitTests/Movies/MoviesRouteBuilderTests.swift    ← [SLICE-FUTURO] fase 2: G4, el closure usa el store
Tests/UnitTests/Movies/PopularMoviesViewModelTests.swift ← TOCAR: 10 llamadas a handle(_:) que la fase 3 renombra
Tests/UnitTests/Movies/MoviesScreenStoreTests.swift    ← TOCAR: handle(_:) + dos PopularMoviesViewModel(repository:)
Tests/UnitTests/SmokeTests.swift                       ← TOCAR/REVISAR: lee Container.shared y asevera tryResolve == nil
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

| Fase | Entrega (mergeable) | Depende de |
|---|---|---|
| **1 — DI** | `MoviesModule` + `Container` en el composition root. Sin cambio visible. Los tests registran fakes en contenedores propios. | — |
| **2 — Navegación (RECORTADA)** | `MoviesRoute` + `AppCoordinatorView` + `Coordinator` + `CoordinatorView`. La View deja de poseer identidad; `MoviesScreenStore` pasa a estar justificado. **NO entra `any Router` en el ViewModel** — ver abajo. | 1 |
| **3 — Convención de intención** | `enum Action` → `Intent` + `send(_:)`, alineado con `.claude/rules/10-ios-ui.md`. Cierra `f-b6f2c1a4`. | 2 |

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
  ├─ Container.shared.register(modules: [MoviesModule()])   ← fase 1
  ├─ #if DEBUG validateRegistrations([...])                 ← el bootstrap falla temprano
  ├─ Coordinator<MoviesRoute>(root: .listado)               ← fase 2
  └─ AppCoordinatorView(coordinator:store:)
        └─ CoordinatorView { route in ... store.popular() } ← el closure SOLO ensambla
                                     ↑
                     MoviesScreenStore memoiza: MISMA instancia siempre
```

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
> pasa a ser «¿se llama al builder?» y no «¿qué hace el closure?». Va al ledger al cerrar la fase.

**El `Router` no entra en este PRD** (§5b): con una sola ruta no hay a dónde navegar. Cuando entre,
el ViewModel dependerá de `any Router<MoviesRoute>` —el protocolo: seis métodos y ningún estado de
lectura—, así que no podrá saber dónde está ni resetear el root: solo emitir intención.

## 8. Anti-features (qué NO entra)

- **Ninguna pantalla nueva.** El detalle, la paginación y los pósters siguen fuera (salvo OQ-2).
- **No se toca `Domain/`.** Ni entidades, ni puertos, ni `MoviesError`.
- **No se modifican los SPM.** Los defectos hallados en la auditoría (`f-8720114e`: el README que
  enseña el anti-patrón; el bug de `Container` con lifecycles cruzados) se arreglan en su repo.
- **No se activa SSL pinning.** Es decisión del owner, y pinnear contra una API de terceros
  obliga a rotar la app cada vez que ellos roten certificado.
- **No se construye el detector de omisión** — ver OQ-1.

## 9. Escenarios golden (deben pasar al terminar)

| # | Escenario | Cómo se verifica |
|---|---|---|
| G1 | La app lista películas igual que antes, **en lógica** | suite existente, sin cambios. **NO cubre la UI** — ver recuadro |
| G2 | Sin credencial, la pantalla muestra el error de siempre | test existente de `SinCredencialRepository` |
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

- Cada fila de §3 da el resultado declarado (cinco comandos y un test, no seis comandos).
- `bash tools/verify-run.sh` verde y firmado contra el diff de cada fase.
- Ningún test existente borrado sin justificación escrita en el propio test.

## 11. Rollout

Tres commits, uno por fase, cada uno con su `verify-run` y su `reviewer`. Sin feature flags: es
refactor interno y el comportamiento no cambia. Si una fase se tuerce, se revierte sola.

## 12. Riesgos

| Riesgo | Mitigación |
|---|---|
| **El `design-reviewer` no tiene consecuencia mecánica** (`f-71c669cc`): en el PRD 0001 dio seis pasadas RED y el commit pasó igual | **Declarado aquí como responsabilidad explícita del implementador:** si el design-review sale RED, se para. No hay gate que lo imponga; que esté escrito es la única red que existe hoy |
| Adoptar `Coordinator` con **una sola ruta** parece ceremonia y puede envejecer mal | OQ-2 lo pone sobre la mesa en vez de decidirlo por el camino |
| `@Inject` sin `init(container:)` haría los tests dependientes del contenedor global | **Sin red mecánica en este PRD**: G5 se retiró por vacuo (§9), así que la única cobertura real es la regla de `architecture/platforms/ios.md` §4 y el criterio del `reviewer`. Declarado, no mitigado |
| Un `reviewer` que mute código deja el árbol sucio y tumba el `verify-marker` | Pasó el 2026-08-29: se pedirá mutar en `git worktree` aparte y comprobar `git status --porcelain` antes de terminar |
| El refactor arregla el estado pero **no impide la reincidencia** | OQ-1 |
| **La fase 1 degrada una garantía del compilador a un `fatalError` de runtime.** Hoy `repositorio() -> any PopularMoviesRepository` es total y el compilador la verifica. Con `Container`, `resolve` hace `fatalError` si falta el registro, y la trampa de la **clave por tipo estático** hace que registrar el concreto y resolver el protocolo explote **en runtime**. `validateRegistrations` es solo DEBUG. Choca con §4.1, con AGENTS.md §2 («hacer el error imposible por tipo antes que detectarlo después») y con §14.1 — y pone en riesgo la promesa escrita en `BaselineApp.swift:20-25`: *«un clon recién hecho nunca se rompe por un archivo que no está»* | **OQ-4.** No se da por neutro: o `tryResolve` + fallback a `SinCredencialRepository` en release (preserva la promesa del clon), o el composition root mantiene construcción tipada y `Container` se usa solo en la frontera de módulos |

## 13. Open Questions

| # | Pregunta | Por qué la decide el owner |
|---|---|---|
| **OQ-1** | ¿Entra el **detector de omisión** (`f-e008f6f`) —que comprobaría que el código USA lo que §3 prescribe— en este PRD, en otro, o no entra? | Tocaría `tools/`, y §8 exige autorización explícita. **Sin él, este refactor arregla el estado pero no la causa**: el siguiente slice puede volver a desviarse y ningún gate lo vería |
| **OQ-2** *(reformulada tras el design-review)* | ¿La fase 2 entra **recortada** —`Coordinator` + `CoordinatorView` + `MoviesRoute`, con el golden G4 del builder de rutas, y **sin** `any Router` en el ViewModel, que viaja con el slice de detalle? | La versión anterior preguntaba si la fase 2 entraba sola, apoyándose en una afirmación **falsa** (que el golden de «volver del detalle» no podía escribirse). Sí puede, y de hecho ya existe. La pregunta real es más pequeña: qué parte de la navegación tiene call sites hoy. Mi recomendación: **sí, recortada** |
| **OQ-4** *(nueva)* | ¿Qué protege el arranque en **release** si falta un registro, o se registra bajo el tipo estático equivocado? | `resolve` hace `fatalError` y `validateRegistrations` solo existe en DEBUG. Hoy esa garantía la da el compilador y la fase 1 la degrada a runtime. Afecta a la promesa de que un clon recién hecho nunca se rompe |
| **OQ-5** *(nueva)* | ¿Cómo se verifica la equivalencia de UI, si no hay UI tests? | La suite no tiene ni un test de vista, y `CoordinatorView` oculta la barra del sistema en todas las rutas. O checklist manual declarado, o se acepta el riesgo por escrito |
| **OQ-6** *(nueva)* | El literal `"Películas populares"` de `PopularMoviesView.swift:17`: ¿se localiza en este PRD o va al ledger? | No hay `Localizable.xcstrings` en el repo y AGENTS.md §2 exige String Catalog ES+EN. Las fases 2 y 3 **tocan ese archivo**, así que aplica §1.3 «el que toca, cierra» |
| **OQ-3** | ¿`@Inject` se usa en algún sitio de este módulo, o todo va por constructor? | Hoy no hay ninguna dependencia transversal (ni analítica ni logger propio). Si la respuesta es «todo por constructor», `@Inject` queda **declarado como no usado y por qué**, que es mejor documentación que usarlo por usarlo |

## 14. Mockups / referencias

No hay mockups, pero **no es cierto que no haya cambios de UI**: bajo `CoordinatorView` la barra
del sistema queda oculta en todas las rutas (§9, OQ-5). Las referencias son `architecture/platforms/ios.md` §3-§4
(navegación y DI, con el ejemplo completo y las trampas verificadas) y `domain/SKILL.md`.

## 15. Definition of Done

- [ ] Las tres fases mergeadas, cada una con `verify-run` verde firmado y `reviewer` no-RED.
- [ ] Cada fila de §3 da el resultado declarado.
- [ ] G1-G4 pasan (G5 retirado, §9); G3 y G4 son tests nuevos.
- [ ] `bash tools/check-layers.sh` y `bash tools/check-drift.sh` sin errores nuevos.
- [ ] **Cada fase quita el `[SLICE-FUTURO]`** de las líneas de §5 que entrega, **en su mismo
      commit**. Y al cerrar el PRD: `bash tools/check-prd-tree.sh` reporta **`futuros=0`** para
      este PRD, no solo `faltan=0`.
      > Por qué se escribe así: `check-prd-tree.sh:194-197` **salta** toda línea marcada
      > `[SLICE-FUTURO]`. Los cinco archivos nuevos la llevan, así que con la redacción anterior
      > —«sin huérfanos»— el check habría dicho `faltan=0` aunque no se creara ni un archivo. Era
      > un ítem de DoD que pasa igual haciendo el trabajo que no haciéndolo: un gate anunciado que
      > no existe (§14.4), justo lo que ese script dice cazar.
- [ ] `f-f2a4ca6e`, `f-54d7ee41` y `f-b6f2c1a4` **cerrados** con su resolución real.
- [ ] Las skills siguen siendo ciertas: si el refactor cambia un patrón, la skill se actualiza
      **en el mismo PR** (§Mantenimiento de `architecture/SKILL.md`).
- [ ] `docs/process/current_execution_map.md` actualizado **en el mismo commit** (feature-workflow §4.3).
- [ ] **Design-review OK** antes de `Approved` (§12).

## 16. Próximos pasos

1. `design-reviewer` sobre este PRD. Si sale RED, se corrige **el PRD, no el código** (§1.6).
2. Decisión del owner sobre **OQ-1 a OQ-6**, y `Status: Approved`. Las tres nuevas (OQ-4
   `fatalError` en release, OQ-5 verificación de UI, OQ-6 i18n) traen decisiones que la primera
   versión de este PRD ni planteaba.
3. Fase 1.

## 17. Change log

| Fecha | Cambio | Quién |
|---|---|---|
| 2026-08-29 | Draft inicial, tras la reescritura de las skills y la auditoría de los dos SPM | agente |
| 2026-08-29 | **Design-review 🔴 RED (13 hallazgos) y correcciones.** Los cuatro bloqueantes eran comprobaciones que no comprobaban: un criterio de §3 que ya salía verde casando un comentario; `MoviesModule` colocado en `Features/`, donde `layers.conf:56` lo habría rechazado; un golden (G4) imposible de escribir con una ruta única, que además contradecía la exclusión razonada de otro golden idéntico; y un ítem de DoD infalsificable porque `[SLICE-FUTURO]` lo salta. Corregido también: una afirmación **falsa** de §9 (el golden de «volver del detalle» ya existe y pasa), una dependencia entre fases **inventada**, el orden de fases (3→1→2), `spm-pro/**` en NO-TOUCH (ruta inexistente aquí), tres tests que el refactor rompe y no estaban en §5, y G5 retirado por vacuo | agente |

## 18. Gaps detectados (llenar post-ship)

_Pendiente._

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

| Condición | Comando |
|---|---|
| El composition root resuelve por `Container` | `grep -r "register(modules:" Sources/App/` |
| Existe un `DependencyModule` por feature | `grep -rl ": DependencyModule" Sources/Features/` |
| La navegación pasa por `Coordinator`/`Router` | `grep -rl "CoordinatorView\|any Router<" Sources/` |
| Ninguna View construye un `NavigationStack` | `! grep -rn "NavigationStack" Sources/` |
| La suite sigue verde y firmada | `bash tools/verify-run.sh` |
| Sin regresión de capas ni drift | `bash tools/check-layers.sh` · `bash tools/check-drift.sh` |

## 4. Filosofía / principios

1. **Comportamiento congelado.** Es un refactor: el usuario no debe notar nada. Todo test que
   pasaba antes pasa después, **o se explica cuál cambió y por qué** — si un test codificaba una
   decisión y no un hecho, se cambian ambos y se justifica en el propio test.
2. **Constructor injection primero; `@Inject` solo con escape hatch.** `@Inject` resuelve de
   `Container.shared` y cachea para siempre, así que un tipo con `@Inject` **sin `init(container:)`
   no se puede testear con un contenedor propio** — justo lo que §3 exige. Ese detalle salió de la
   auditoría del paquete, no de su README, y es la razón de que la regla no sea estilística.
3. **Adoptar el mecanismo no es adoptar su ceremonia.** Si una pieza del paquete no aporta aquí,
   se declara por qué en vez de meterla para cumplir. Un módulo de referencia que usa algo
   «porque toca» enseña peor que uno que explica por qué no lo usa.

## 5. Estructura de archivos a crear / tocar

```
Sources/Features/Movies/MoviesRoute.swift              ← [SLICE-FUTURO] fase 2: enum de rutas (Hashable)
Sources/Features/Movies/MoviesModule.swift             ← [SLICE-FUTURO] fase 1: DependencyModule, registra adapters
Sources/Features/Movies/PopularMoviesViewModel.swift   ← TOCAR: recibe any Router; enum Intent
Sources/Features/Movies/PopularMoviesView.swift        ← TOCAR: deja de poseer identidad (f-54d7ee41)
Sources/App/BaselineApp.swift                          ← TOCAR: Container + Coordinator
Sources/App/AppCoordinatorView.swift                   ← [SLICE-FUTURO] fase 2: Coordinator + CoordinatorView
Sources/App/Movies/MoviesScreenStore.swift             ← TOCAR: pasa a estar justificado de verdad
Tests/UnitTests/Movies/MoviesModuleTests.swift         ← [SLICE-FUTURO] fase 1: registra lo que promete
Tests/UnitTests/Movies/MoviesRouteTests.swift          ← [SLICE-FUTURO] fase 2: el VM emite intención, no navega
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
spm-pro/**
    ← los paquetes no se modifican aquí. Lo que haya que arreglar allí se
      registra y se publica aparte (f-8720114e ya está abierto)
```

## 5b. Fases entregables

| Fase | Entrega (mergeable) | Depende de |
|---|---|---|
| **1 — DI** | `MoviesModule` + `Container` en el composition root. Sin cambio visible. Los tests registran fakes en contenedores propios. | — |
| **2 — Navegación** | `MoviesRoute` + `AppCoordinatorView` + `Coordinator`. La View deja de poseer identidad; `MoviesScreenStore` pasa a estar justificado. | 1 |
| **3 — Convención de intención** | `enum Action` → `Intent` + `send(_:)`, alineado con `.claude/rules/10-ios-ui.md`. Cierra `f-b6f2c1a4`. | 2 |

**Por qué en este orden:** la DI no toca UI y deja la base verde; la navegación necesita el grafo
ya armado por `Container` para no arrastrar dos cambios a la vez; y el renombrado va al final
porque toca los mismos archivos que la fase 2 y hacerlo antes obligaría a tocarlos dos veces.

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

El ViewModel depende de `any Router<MoviesRoute>` —el protocolo: seis métodos y **ningún estado
de lectura**— así que no puede saber dónde está ni resetear el root: solo emitir intención. Esa
línea la impone el tipo, no la disciplina.

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
| G1 | La app lista películas exactamente igual que antes | suite existente, sin cambios |
| G2 | Sin credencial, la pantalla muestra el error de siempre | test existente de `SinCredencialRepository` |
| G3 | El módulo de DI registra lo que promete | test nuevo, en contenedor propio, **sin tocar `Container.shared`** |
| G4 | El ViewModel pide navegar y NO navega él | test nuevo con `Router` espía; asevera la intención emitida |
| G5 | Un tipo con `@Inject` es testeable con contenedor propio | si alguno lo usa, tiene `init(container:)` |

**No hay golden de «al volver del detalle el listado conserva su contenido»**, y no es un olvido:
ese escenario **necesita una segunda pantalla** para existir. Ver OQ-2, que es la decisión que
más condiciona el valor de la fase 2.

## 10. Métricas de éxito

- Los seis comandos de §3 dan el resultado declarado ahí.
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
| `@Inject` sin `init(container:)` haría los tests dependientes del contenedor global | G5 lo verifica; §4.2 lo prescribe |
| Un `reviewer` que mute código deja el árbol sucio y tumba el `verify-marker` | Pasó el 2026-08-29: se pedirá mutar en `git worktree` aparte y comprobar `git status --porcelain` antes de terminar |
| El refactor arregla el estado pero **no impide la reincidencia** | OQ-1 |

## 13. Open Questions

| # | Pregunta | Por qué la decide el owner |
|---|---|---|
| **OQ-1** | ¿Entra el **detector de omisión** (`f-e008f6f`) —que comprobaría que el código USA lo que §3 prescribe— en este PRD, en otro, o no entra? | Tocaría `tools/`, y §8 exige autorización explícita. **Sin él, este refactor arregla el estado pero no la causa**: el siguiente slice puede volver a desviarse y ningún gate lo vería |
| **OQ-2** | ¿La fase 2 entra sola, o **junto con el slice de detalle**? | Con una sola pantalla, la protección de la Trampa C (`MoviesScreenStore`) **no es verificable de extremo a extremo**: no hay a dónde navegar ni desde dónde volver. Adoptar la navegación sin nada que navegar deja ese golden sin poder escribirse |
| **OQ-3** | ¿`@Inject` se usa en algún sitio de este módulo, o todo va por constructor? | Hoy no hay ninguna dependencia transversal (ni analítica ni logger propio). Si la respuesta es «todo por constructor», `@Inject` queda **declarado como no usado y por qué**, que es mejor documentación que usarlo por usarlo |

## 14. Mockups / referencias

No aplica: cero cambios de UI. Las referencias son `architecture/platforms/ios.md` §3-§4
(navegación y DI, con el ejemplo completo y las trampas verificadas) y `domain/SKILL.md`.

## 15. Definition of Done

- [ ] Las tres fases mergeadas, cada una con `verify-run` verde firmado y `reviewer` no-RED.
- [ ] Los seis comandos de §3 dan el resultado declarado.
- [ ] G1-G5 pasan; G3 y G4 son tests nuevos.
- [ ] `bash tools/check-layers.sh` y `bash tools/check-drift.sh` sin errores nuevos.
- [ ] `bash tools/check-prd-tree.sh` sin huérfanos: el árbol de §5 coincide con lo entregado.
- [ ] `f-f2a4ca6e`, `f-54d7ee41` y `f-b6f2c1a4` **cerrados** con su resolución real.
- [ ] Las skills siguen siendo ciertas: si el refactor cambia un patrón, la skill se actualiza
      **en el mismo PR** (§Mantenimiento de `architecture/SKILL.md`).
- [ ] `docs/process/current_execution_map.md` actualizado **en el mismo commit** (feature-workflow §4.3).
- [ ] **Design-review OK** antes de `Approved` (§12).

## 16. Próximos pasos

1. `design-reviewer` sobre este PRD. Si sale RED, se corrige **el PRD, no el código** (§1.6).
2. Decisión del owner sobre OQ-1, OQ-2 y OQ-3, y `Status: Approved`.
3. Fase 1.

## 17. Change log

| Fecha | Cambio | Quién |
|---|---|---|
| 2026-08-29 | Draft inicial, tras la reescritura de las skills y la auditoría de los dos SPM | agente |

## 18. Gaps detectados (llenar post-ship)

_Pendiente._

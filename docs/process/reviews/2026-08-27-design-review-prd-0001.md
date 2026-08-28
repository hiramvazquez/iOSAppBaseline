# Design-review — PRD 0001 «Vertical de referencia: películas»

- **Fecha:** 2026-08-27
- **Revisor:** sub-agente `design-reviewer` (gate del CÓMO, §12 de `AGENTS.md`)
- **Documento:** `docs/process/prds/0001-vertical-de-referencia-peliculas.md` (Status: Draft)
- **Veredicto:** 🔴 **RED** — 29 hallazgos, 4 bloqueantes
- **Qué significa:** el design-review es un gate **distinto** del `Approved` del owner. Un RED
  aquí no dice que el PRD sea malo: dice que hay decisiones que, copiadas por cada proyecto que
  salga de esta base, enseñarían mal. Los cuatro bloqueantes se arreglan **editando el PRD**, sin
  escribir una línea de Swift.

> Se revisó contra el código real de los dos paquetes publicados, `tools/layers.conf`,
> `tools/check-layers.sh`, `tools/mutation-score.sh`, `project.yml`, `.github/workflows/gates.yml`
> y las skills del proyecto. Las afirmaciones del PRD sobre la API de los paquetes se
> contrastaron una a una contra sus fuentes.

---

## 🔴 Bloqueantes

### B1 · La «Trampa A» no ocurre como la describe, y su test no puede fallar

`BaseViewModel.performLoad` no solo tiene `catch is CancellationError`: la rama genérica lleva
`guard !Task.isCancelled, let self else { return }` antes de `setError`
(`BaseViewModel.swift:203`). En el escenario que el PRD describe —dos `onAppear`, el primero
superseded— la tarea 1 **sí** está cancelada, así que aunque escape un `MoviesError.cancelled`
**no se pinta ningún error**. AppFoundation ya lo cubre.

Consecuencia grave: **T-VM-4 pasa con o sin la mitigación**. Es el anti-patrón nº1 de
`tdd-workflow.md` y de `AGENTS.md` §5 — un test que pasa con cualquier implementación— y estaría
en el módulo que existe para enseñar a testear.

**Arreglo:** reescribir §6.5-A con el escenario que sí es real (un `MoviesError.cancelled` que
llega con la Task **viva**: invalidación de sesión de `APIService`, `URLError.cancelled` de
transporte no originado por la Task). T-VM-4 pasa a ser: *fake que lanza `MoviesError.cancelled`
sin cancelar la Task ⇒ `phase` no es `.error`*. Ese sí muere si quitas la conversión. Y añadir la
frase que hoy falta: `MoviesError` tiene caso `.cancelled` **porque** el puerto usa typed throws
(con `throws(MoviesError)` el adapter no puede relanzar `CancellationError`).

### B2 · C5 («idempotencia observable») es una garantía falsa, y el propio PRD lo demuestra

§7 y R6 dicen que *«`popular` de TMDB se reordena entre peticiones»*. Entonces «dos llamadas
seguidas con la misma página devuelven lo mismo» **no se cumple contra la fuente real**. T-C-5
pasaría solo porque `MockURLProtocol` reproduce la respuesta registrada: estaría verificando el
mock, no el contrato. Un puerto de referencia que promete algo que su única implementación real
no cumple es el peor artefacto que puede copiar un adoptante.

**Arreglo:** eliminar C5/T-C-5, o sustituirlos por una garantía verdadera: *«C5' —
`popularMovies(page:)` no tiene efectos secundarios observables»*. Y añadir a §6.3 una
**no-garantía** explícita: el contenido de una página NO es estable entre llamadas; por eso existe
el invariante de unicidad de la fase 2.

### B3 · Falta la trampa más cara: la identidad del ViewModel a través de la navegación

`CoordinatorView.body` llama `content(route)` en cada evaluación
(`CoordinatorView.swift:55-87`), y el ejemplo del README de AppFoundation —el que un agente
copiará— construye el ViewModel **dentro** de ese closure. Resultado: cada `push`/`pop` fabrica un
`PopularMoviesViewModel` nuevo, con `phase == .idle` y `movies == []`, y `onAppear` no vuelve a
dispararse porque la vista ya apareció.

Rompe directamente el escenario **golden 6** («al volver atrás el listado conserva su contenido y
su posición»). Es exactamente la clase de error que este módulo existe para hacer imposible.

**Arreglo:** §6.5 Trampa C con el mecanismo, y **decidir en el PRD** dónde vive la identidad: una
vista-pantalla envolvente que posea el ViewModel en `@State`, o que el composition root los
retenga. Fila nueva T-VM-11 y criterio de la fase 8, no un golden manual.

### B4 · `messageKey: String` + `ScreenError` = claves crudas en pantalla

`ScreenError` tiene dos inits: uno con `LocalizedStringResource` que localiza, y un
`@_disfavoredOverload init(title: String, …)` que **guarda el valor verbatim**
(`ViewPhase.swift:83-108`). Un `messageKey` es un `String` de runtime ⇒ cae siempre en el segundo
⇒ la pantalla muestra `movies.error.offline`. Es *literalmente* el síntoma que el golden 7 dice
cazar. Y las claves construidas en runtime **no las extrae** el String Catalog, así que T-D-5
verificaría un catálogo que nadie llenó.

**Arreglo:** quitar `messageKey` de `MoviesError`; `MoviesError+ScreenError.swift` pasa a ser un
`switch` **exhaustivo sin `default:`** que devuelve `ScreenError` con literales
`LocalizedStringResource`. Se gana todo a la vez: el compilador obliga a cubrir cada caso nuevo,
los literales se extraen solos al `.xcstrings`, y se usa el init que sí localiza.

> Nota: esto **contradice `domain/SKILL.md` §Errores** (`userMessageKey`). Es justo el tipo de
> `<!-- FILL -->` heredado que este módulo debe corregir en vez de propagar.

---

## 🟠 Altas (resumen accionable)

| # | Hallazgo | Arreglo |
|---|---|---|
| A1 | `MoviePage.nextPage` se calcula en el adapter, fuera del tipo ⇒ T-D-3 solo comprueba lo que el test acaba de escribir | Único constructor en Domain que deriva `nextPage`. Añadir la fila que falta: `page == 500` con `totalPages > 500` ⇒ `nextPage == nil` |
| A2 | `MockURLProtocol` es estado estático global y Swift Testing paraleliza | Prescribir `@Suite(.serialized)`, `removeAll()` en init/deinit, URLs distintas por test |
| A3 | Los tests deben correr **sin** clave de TMDB (en CI no hay `Secrets.xcconfig`) y nada lo dice | Criterio explícito en §15 + `TMDBConfiguration` con proveedor inyectable |
| A4 | `APIError` no expone `.unauthorized`/`.notFound`: son `.httpStatus` y `.custom` | El mapper decide por `apiError.statusCode` y **sin `default:`** |
| A5 | OQ-11 no es pregunta para el owner: `ScreenContainer.swift` existe y responde las tres | Cerrarla citando líneas, como se hizo con OQ-2 |
| A6 | OQ-3(b) ya está respondida: `SmokeTests.swift:3` importa AppFoundation y compila | Reducir OQ-3 a (a) y ampliar con `knownRegions`/`CFBundleLocalizations` con `es` |
| A7 | OQ-9 pregunta por permiso cuando el riesgo es viabilidad: `mutation-score.sh:104` avisa de que **typed throws** rompe el descubrimiento de mutantes | Adelantar el spike tras la fase 1; partir en OQ-9a (permiso) y OQ-9b (¿nivel 4 no disponible para este stack?) |
| A8 | Dos afirmaciones de medición sin comando que las respalde: no hay regla `*/Data/*` en `layers.conf`, y los gates no dicen cuántos archivos evaluaron | Quitar `Data/` o pedir la regla; sustituir la métrica por un **control negativo** documentado |
| A9 | Una tabla de conformidad para dos puertos distintos; C7/C8 contra el fake son casillas vacías | Dos funciones de conformidad, una por puerto; marcar C7/C8 como garantías solo del adapter |

## 🟡 Medias

`M1` `posterPath` en `Movie` contradice §4.1 del propio PRD · `M2` nadie es dueño del formateo
(año y `7,8` en ES) · `M3` R3 inventa una convención en vez de adoptar la documentada
(`#Preview` al final, f-2cc1e4c1) · `M4` OQ-12 no ve que el banner **no tiene reintento** ·
`M5` el `retry` del dominio sería código muerto · `M6` «property-based» sin generador: el
mecanismo real es `@Test(arguments:)`; fusionar T-D-1 y T-D-2 · `M7` OQ-10 es un comando, no una
decisión · `M8` las fases 5 y 9 cruzan demasiado para revisarse de una vez · **`M9` el aislamiento
de capas es por carpetas dentro de UN target y el PRD no lo dice** — lo sella `check-layers.sh`
(nivel 6), no el compilador (nivel 0); targets SPM por capa lo harían imposible por tipo · `M10`
el indicador `.inline` no aparece donde el mockup lo dibuja · `M11` la clave en `Info.plist` viaja
en claro: vale para TMDB, hay que decir que no vale para un secreto real · `M12` verificar la
regla de design system antes de la fase 5.

## 🔵 Bajas

`L1` `.withBack(title:)` no existe con esa firma · `L2` OQ-1 merece recomendación: con
`?api_key=`, **cada mock y cada `recordedRequests` llevaría la clave dentro del código de tests**
⇒ recomendar Bearer v4 · `L3` la opcionalidad de `voteAverage` la decide el fixture, no OQ-7 ·
`L4` declarar que `.cancelled` existe **porque** el puerto usa typed throws.

---

## Balance de las Open Questions

- **Sobran / resueltas por el código:** OQ-11, OQ-3(b), OQ-10. Tres de doce delegaban al owner
  algo que se contesta leyendo. El propio PRD fijó el estándar con OQ-2.
- **Mal encuadradas:** OQ-9 (permiso vs viabilidad), OQ-1 (falta la recomendación), OQ-12 (falta
  la consecuencia del banner sin reintento).
- **Legítimas:** OQ-4, OQ-5, OQ-6, OQ-7, OQ-8.
- **Faltan:** OQ-13 (¿un target o targets SPM por capa?) y OQ-14 (`knownRegions` con `es`). Y tres
  cosas que **no** son preguntas para el owner sino decisiones que el PRD debe tomar: la identidad
  del ViewModel, la serialización de las suites con `MockURLProtocol`, y la inyectabilidad de
  `TMDBConfiguration`.

## Lo que está bien y no hay que tocar

El troceo por capas con la regla «ninguna fase toca red + dominio + UI»; el gate común por fase;
la sección NO-TOUCH; OQ-2 como modelo de cómo se cierra una Open Question con cita de línea; R9 y
R10 como findings reales del harness detectados desde fuera; la decisión de `nextPage` en vez de
`totalPages`; el rechazo explícito a degradar un JSON malformado a lista vacía; y la disciplina de
anti-features.

---

## Qué pasa ahora

1. Editar el PRD para cerrar **B1–B4** (no requiere escribir Swift).
2. Atender o anotar como riesgo **A1–A9**.
3. El owner responde las Open Questions que queden vivas y decide el `Approved`.
4. Recién entonces empieza la fase 1.

**Este RED es el gate funcionando como debe.** Cazó cuatro errores de diseño antes de que
existiera una línea de código — el nivel más barato en el que se podían cazar (§14.1). Encontrarlos
en review de código habría costado ~10× más; encontrarlos cuando tres proyectos ya hubieran
copiado el módulo de referencia, incalculablemente más.

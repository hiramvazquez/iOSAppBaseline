# Design-review — PRD 0001, pasadas 2 a 6 (2026-08-28)

> Gate del CÓMO (§12), sub-agente `design-reviewer`. Distinto del `Approved` del owner.
> Pasada 1: [`2026-08-27-design-review-prd-0001.md`](2026-08-27-design-review-prd-0001.md) — 🔴 RED, 4 bloqueantes.
>
> **Por qué existe este archivo.** La 3ª pasada abrió un hallazgo (T3) que era exactamente
> este: los 26 hallazgos de la 2ª pasada vivían **solo en un hilo de conversación**. AGENTS.md
> §1.1 y §10 lo prohíben — reportar es loguear, no mencionar en prosa. Aprobar el PRD sin esto
> los habría perdido en la primera compactación de contexto.

## Veredictos

| Pasada | Fecha | Veredicto | Hallazgos | Disparador |
|---|---|---|---|---|
| 1 | 2026-08-27 | 🔴 RED | 4 bloqueantes + 29 | PRD Draft→Approved |
| 2 | 2026-08-28 | 🔴 RED | 26 (N1–N26) | OQ-4 resuelta + slice 0 escrito |
| 3 | 2026-08-28 | 🔴 RED | 13 (T1–T13) | verificación de los arreglos de la 2ª |
| 4 | 2026-08-28 | 🔴 RED | 12 (B-1…B-5, H-6…H-12) | verificación de los arreglos de la 3ª |
| 5 | 2026-08-28 | 🔴 RED | 13 (B-1…B-5, H-6…H-13) | verificación de los arreglos de la 4ª |
| 6 | 2026-08-28 | 🔴 RED | 14 (B-1…B-3, H-4…H-12, L-13, L-14) | verificación de los arreglos de la 5ª |

> 🔴 **REGLA, nacida del bloqueante B-2 de la 6ª pasada: el veredicto se escribe en ESTE archivo
> ANTES de tocar el PRD.** La 5ª pasada dejó 13 hallazgos que vivían **solo en el hilo de
> conversación** mientras el PRD y el mapa de ejecución ya citaban este archivo como «el
> historial» — y este archivo se titulaba «pasadas 2 y 3» y su tabla terminaba en la 4. Es el
> mismo defecto que motivó T3, saltando del PRD al registro de las revisiones. Sin esta regla,
> la pasada siguiente lo repite.

## Pasada 2 — los 4 bloqueantes, y su estado tras la 3ª

| # | Bloqueante | Estado |
|---|---|---|
| **N1** | §5b describía 9 fases que la ejecución abandonó; la regla «ninguna fase toca red+dominio+UI» no se cumplía | 🟠 **a medias** — decidido y escrito en §5b (la regla se abandona *para el slice 0*, con su razón), pero **no propagado** a R8, §11 y ~15 citas de «fase N» |
| **N2** | `C1` y `C2` tenían un significado en el PRD y otro distinto en el código publicado, con la misma etiqueta | 🔴 **no cerrado** — §6.3 reescrita con la regla de ids inmutables y bloques vigente/pendiente, pero **§9b sigue publicando los ids retirados** con su significado viejo |
| **N3** | El test de C5 era «llamar dos veces y comparar», la forma que la pasada 1 ya había rechazado (B2) | ✅ **cerrado** — forma prohibida y admisible escritas; aserción retirada del código con su razón |
| **N4** | El idioma fuente de los literales nunca se decidió; `ScreenError` hace `String(localized:)`, así que el literal **es** la clave del catálogo | ✅ **cerrado** — decisión `es`, con `developmentRegion` añadido a OQ-3, T-D-5 marcado como mal escrito y la deuda de i18n declarada con fecha |

**El patrón que la 3ª pasada identificó, y que conviene no repetir:** los arreglos se
escribieron como recuadro *en el punto del hallazgo* y no se propagaron a §9b, §11, §12 y §15
— que es lo que el implementador lee. Un arreglo que no se propaga deja el documento
contradiciéndose a sí mismo, que es peor que el hallazgo original.

## Hallazgos accionables → ledger

Los que exigen acción están en [`findings-ledger.md`](../findings-ledger.md):

| Ledger | Origen | Qué |
|---|---|---|
| `f-3236fb0` | T2 | El slice 0 toca la credencial y no pasa por `security-reviewer` (**OQ-16**) |
| `f-f6b72573` | T5 | C2 y C3 del puerto no pueden ser ciertas a la vez (**OQ-17**) |
| `f-31902e86` | N10/T7 | Falta idempotencia de la primera carga: `.task` re-dispara `performLoad` |
| `f-52ef5f6d` | T6 | Comentarios del adapter y del dominio afirman lo que el código no hace |
| `f-54d7ee41` | N12 | `@State private var viewModel` duplica el dueño de la identidad |

## Hallazgos que se cerraron editando el PRD

**Pasada 2:** N5 (la premisa de OQ-5(b) era falsa: `layers.conf` trabaja sobre imports y no
puede arbitrar `AsyncImage`/`URLSession`) · N6 (referencias a `UI/` obsoletas, incluida una del
DoD que era criterio verificable por comando) · N19 (`platforms/ios.md` prescribe
`userMessageKey`, la forma rechazada, y es lectura obligatoria para tocar Views) · N21 (mapa de
ejecución desincronizado, `CoreNetworking` 0.1.0 vs 0.1.3).

**Pasada 3:** T1 (§9b renumerada a `T-PG-*`/`T-DT-*`/`T-S-*`) · T9 (§6.1 y tres comentarios de
código) · T10 (filas de §9b que anunciaban defensas retiradas) · T13.

> ⚠️ **Corrección (4ª pasada, B-2): este archivo certificaba T4 como cerrado y no lo estaba.**
> R8 (§12) y §11 seguían intactos, apoyando la mitigación de un riesgo en la regla de 9 fases
> que §5b declara abandonada. La lista de arriba se contradecía con la tabla de bloqueantes de
> este mismo documento, que sí decía «N1 a medias — no propagado a R8, §11», y la contradicción
> caía del lado optimista.
>
> Esto importa más que el hallazgo en sí. Este archivo existe porque los hallazgos no pueden
> vivir solo en un hilo de conversación (T3); un registro que **certifica cierres falsos** es
> peor que no tener registro, porque se lee, se cree y nadie vuelve a comprobarlo. La regla que
> se deriva: en este documento **solo entra como cerrado lo que se verificó en el archivo**, no
> lo que se intentó cerrar.

## Pasada 4 — qué encontró

Cinco arreglos de la 3ª pasada sí cerraron y se verificaron en el archivo: la retirada de C2
ejecutada en el código, la renumeración de §9b, el borrado de `*/UI/*` en `layers.conf` con su
retractación, los comentarios de `TMDBPopularMoviesRepository` y `MoviesError` diciendo lo que
el código hace, y la columna de revisores en §5b.

El patrón se repitió por cuarta vez: **el arreglo se escribe donde se descubrió el problema y no
se propaga a las secciones que se marcan o se ejecutan.** Bloqueantes de esta pasada: B-1 (R8 y
§11 sin propagar) · B-2 (este archivo, arriba) · B-3 (el DoD seguía anclando el
`security-reviewer` a las fases 3/5/7) · **B-4** (el sweep de `Features/` se hizo en
`layers.conf` y no en `skill-matrix.conf`: `TMDBConfiguration.swift`, que lee la credencial, no
casa con ningún glob de la matriz y puede editarse sin leer `security/SKILL.md`) · B-5 (§6.1
publicaba la regla `*/UI/*` que se había borrado).

**B-4 es la lección [2026-08-28] del glob mudo cobrándose una segunda víctima el mismo día en
que se escribió**, y en otro conf. Por eso su Regla se amplió a *todo conf con globs de ruta*.

## Lo que la 3ª pasada avisó sobre los tres cambios acordados

Relevante **antes** de ejecutarlos, no después:

1. **`MoviesError = .transport(TransportError) + notFound + malformedResponse` mata
   `CaseIterable`.** Swift no lo sintetiza para enums con valores asociados. Se caen los dos
   tests de `MoviesErrorScreenErrorTests` que iteran `allCases`, y la fila T-D-4 del PRD que
   justifica `CaseIterable` explícitamente.
2. **Mata también el argumento de S1.** Hoy «ningún valor lanzado contiene la credencial» se
   sostiene *por construcción*: ningún caso tiene valores asociados de tipo `String`. Si
   `TransportError` lleva un `String`, S1 pasa a necesitar un test real. → Restricción:
   `TransportError` sin payloads `String`.
3. **`check-layers.sh` no puede vigilar dónde vive `TransportError`.** La app es **un solo
   módulo**: el detector mira imports, así que solo caza imports de paquetes externos. Un tipo
   declarado en `Sources/App/` y referenciado desde `Sources/Domain/` **compila sin que ningún
   gate lo vea**. Si `TransportError` vive fuera de `Domain/`, hay que decir qué lo detecta —
   y si no lo detecta nada, declararlo en vez de fingirlo (**OQ-18**).

## Lo que la 3ª pasada destacó como bien hecho

El cierre de OQ-4 (sospechar que la regla de capa quedaría muda, **verificarlo empíricamente
antes** de mover, arreglar `layers.conf` y confirmar con prueba de fuego). El recuadro de C5 y
su ejecución en la suite: se retiró una aserción **verde**, se escribió por qué no podía fallar,
y se dijo cuándo vuelve. Y la decisión de idioma fuente con sus tres consecuencias numeradas.


## Anexo — el plan de 9 fases (borrado del PRD el 2026-08-28)

Se conserva **aquí**, fuera del documento vivo, por la razón que dio la 4ª pasada: mientras la
tabla estuviera en el PRD seguía siendo la fuente de una veintena de citas «fase N», y una de
ellas se llevó por delante un gate de seguridad real (el DoD anclaba el `security-reviewer` a
«las fases 3, 5 y 7»).

La 5ª pasada encontró que el epitafio afirmaba que el plan «queda registrado en el change log
§17 y en el dictamen» — y no estaba en ninguno de los dos. **Se había borrado afirmando que se
preservaba**, que es exactamente §14.4 aplicado a un archivo. Este anexo hace cierta esa frase.

**No es el plan vigente.** El troceo vigente es la tabla de slices de §5b del PRD.

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


## Pasada 5 — qué encontró (13 hallazgos)

Verificaba los arreglos de la 4ª. Cinco bloqueantes:

- **B-1** — §5b se contradecía a sí misma: un párrafo presentaba la tabla de 9 fases diciendo que
  «se conserva como histórico» y el epitafio, 16 líneas más abajo, decía lo contrario. El sweep
  había seguido la cadena «fase N» y ese párrafo habla de *la tabla*.
- **B-2** — el epitafio prometía que el plan «queda registrado en el change log §17 y en el
  dictamen». No estaba en ninguno: **se borró afirmando que se preservaba**, §14.4 aplicado a un
  archivo. Arreglado recuperándolo con `git show HEAD:` → Anexo de este documento.
- **B-3** — §9b etiquetaba como «slice 0» tres tests (`T-D-1/2/3`) que fijan `PageNumber` y
  `MoviePage`, tipos que §6.3 declara inexistentes. Como el DoD exige «cada fila de §9b existe»,
  el slice 0 no podía cerrar su propio DoD. **La cita «fase N» reencarnada en «slice N»**:
  renombrar no es propagar.
- **B-4** — OQ-16, OQ-17, OQ-18 y OQ-20 se citaban desde el mapa y el ledger y **no existían en
  §13**. La regla de identificadores inmutables aplicada a las Open Questions.
- **B-5** — la cabecera se corrigió en la línea 3 y no en el bloque de estado 25 líneas más abajo.

Hallazgos: **H-6** (los diez archivos del slice 0 pasados por el matcher real: `BaselineApp.swift`
sin ninguna lectura obligatoria, dos cubiertos por accidente léxico) · **H-7** (la columna de
skills es correcta como contenido, falla como enforcement) · **H-8** (el mapa describía un defecto
ya arreglado) · **H-9** (§5 no describe el árbol entregado) · **H-10** (T-VM-11 describe un
`Coordinator` que el slice 0 no tiene) · **H-11** (el DoD exigía «ninguna ruta NO-TOUCH» sin citar
las autorizaciones) · **H-12** (§17) · **H-13** (la exención del detector es posicional, no
semántica).

## Pasada 6 — qué encontró (14 hallazgos)

La variante nueva saltó del PRD **al código publicado y a este mismo registro**:

- **B-1** — `Sources/Domain/Movies/PopularMoviesRepository.swift` **seguía publicando C2** y
  afirmando que la suite verifica cinco garantías cuando verifica una. §6.3 titula su tabla
  «Contrato VIGENTE — el publicado en \<ese archivo\>», así que el contrato y su publicación se
  contradecían. **Y la 4ª pasada de este documento certificó «la retirada de C2 ejecutada en el
  código» habiendo verificado el archivo de tests** — el mismo cierre falso que este documento se
  prohibió a sí mismo. Arreglado: el doc-comment declara ahora quién verifica cada garantía.
- **B-2** — la 5ª pasada no existía en ningún archivo (arriba).
- **B-3** — la tabla de autorizaciones NO-TOUCH **negaba** la autorización que el owner acababa de
  dar (OQ-C), y el DoD enumeraba tres rutas cuando el diff lleva cinco.
- **H-4** — la tabla de adapter de §9b tenía el defecto de B-3 de la 5ª sin arreglar, y es más
  larga: fija `MoviePage`, paginación, 404 de detalle, fixtures que no existen y `.cancelled`, un
  caso que `MoviesError` no tiene.
- **H-8** — `PopularMoviesView.swift` anunciaba en un comentario la protección que el PRD declara
  ausente. La pasada de honestidad llegó a `MoviesError` y al adapter, y no a ese archivo.
- **H-12** — la evidencia citada para OQ-C (`check-skill-matrix-doc.sh` en 0/0) **no dependía del
  cambio**: ese script compara solo el conjunto de referencias, nunca los globs, y habría dado 0/0
  igual sin las filas nuevas. La evidencia buena era la otra: la pasada con el matcher real.

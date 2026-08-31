# PRD — Detector de omisión de mecanismos prescritos

> **Tipo:** Forward · **Status:** 📝 Draft — **OQ-1 resuelta y desbloqueado** (owner, 2026-08-31). Pendientes OQ-2 y OQ-3, y el `design-reviewer`
> **Autor:** sesión de agente (Claude) · **Fecha:** 2026-08-30
> **Tracking:** `f-e008f6f` (el encargo, con el diseño primario y las cuatro lecciones dentro) · `f-da257e0c` (el bloqueante) · `f-f2a4ca6e` (el caso que lo motivó, ya cerrado) · `f-2ffc6d32` (el hueco hermano)
> **Design-review:** pendiente — se pide cuando OQ-2 y OQ-3 estén decididas. La razón para no pedirlo antes (OQ-1 en disputa: revisar un CÓMO cuyo QUÉ no está decidido gasta una pasada para nada) ya no aplica

> **Por qué esto es un PRD.** Lo decidió el owner en OQ-1 del PRD 0002 (2026-08-29): va en PRD
> aparte porque **toca `tools/`**, que §8 reserva al owner, y meterlo en el 0002 habría mezclado
> código de app con maquinaria del harness. Contra el criterio de `prd-lifecycle.md` se sostiene
> igual: es una **decisión arquitectónica reusable** — este repo es la baseline de la que salen
> los proyectos nuevos, y el detector viajaría al template y de ahí a todos los adoptantes.

---

## 1. Contexto

**Los nueve niveles del harness son de COMISIÓN.** Cada uno responde a «¿escribiste algo
prohibido?»: no importes esto, no filtres aquello, no bajes el trinquete, no rompas la capa.
**Ninguno responde a «¿dejaste de escribir algo obligatorio?»**

Eso tiene una consecuencia medida, no teórica. El slice 0 pasó los nueve niveles en verde y aun
así **el módulo de referencia no usaba la mitad de `AppFoundation`** (`f-f2a4ca6e`): cero usos de
`Coordinator`, `Router`, `Container`, `@Inject`, `DependencyModule` y `CoordinatorView`, todos
prescritos por `AGENTS.md` §3. El PRD 0002 lo arregló en tres fases. Pero arregló **el estado, no
la causa**: el siguiente slice puede desviarse igual y ningún gate lo vería. El propio PRD 0002 lo
dejó escrito en su §12 como riesgo aceptado sin mitigación, y mandó el detector aquí.

Añadido a eso: el `design-reviewer` **sí cazó por escrito** la omisión dos horas antes del commit
(H-7 de su 6ª pasada) y no impidió nada, porque ese sub-agente no deja marker (`f-71c669cc`). O
sea que el único gate que vio el problema fue el único sin consecuencia mecánica.

## 2. Problema

Un agente que **omite** un mecanismo prescrito produce código que pasa todos los gates. La
omisión es invisible por construcción: no hay línea que señalar.

El daño no se queda en un slice. Este repo es el **módulo de referencia**: lo que no se use aquí
no se usará en ninguno de los proyectos que salgan de él, y además **les enseña a no usarlo**. Un
paquete propio a medio adoptar es peor que no tenerlo — se paga su coste (indirecciones, trampas
documentadas, findings abiertos) sin cobrar su beneficio, que es exactamente lo que le pasó a
`MoviesScreenStore` antes del PRD 0002.

**Si no lo construimos:** la reincidencia queda cubierta solo por revisión humana y por un
sub-agente sin marker. Es decir, por lo único que este harness existe para no depender.

## 3. Objetivo

Un detector mecánico que **falle (exit 1) cuando un mecanismo declarado como obligatorio tiene
cero usos reales** en el ámbito donde debe usarse.

Verificable con un fixture histórico, no con una promesa:

| Árbol | Qué es | Veredicto exigido |
|---|---|---|
| `a577e3e` | antes del PRD 0002, donde `f-f2a4ca6e` verificó cero usos | **🔴 RED** |
| `HEAD` | después del PRD 0002 | **🟢 GREEN** con las filas de §13 OQ-1, ya fijadas |

## 4. Filosofía / principios

**4.1 — Existencia sobre lista curada, y el límite se DECLARA.** El detector comprueba que el
mecanismo *se usa*, nunca que *se usa bien*. Eso lo hace casi inmune a falsos positivos, que es la
condición para que sobreviva (§14.2: un detector con FP se descarta entero, y además el agente
aprende a evadirlo). Lo que no cubre se escribe en su propia salida, no se insinúa.

**4.2 — Estructura, jamás prosa. Y esto no es una precaución teórica: hay fixture.** La lección
(4) de `f-e008f6f` dice que escanear campos narrativos da 100% de falsos positivos porque
documentar un problema exige nombrarlo. En `a577e3e`, un `grep -F` ingenuo habría dado **verde**
sobre el árbol que motivó todo esto:

```
Container       → casaba con  ScreenContainer(viewModel:…)   ← OTRO tipo, subcadena
CoordinatorView → casaba con  /// `CoordinatorView` reevalúa el closure…   ← un DOC-COMMENT
                              que explica por qué el código NO lo usa
```

Las dos refinaciones —**frontera de palabra** y **quitar comentarios**— no son pulido: son la
diferencia entre el detector y un adorno, **sobre el caso exacto que lo motivó**. Un detector que
lee un comentario como si fuera un uso es un detector que aprueba la documentación de su propio
fallo.

**4.3 — Un glob que no casa con nada es exit 3, nunca 0 ni 1.** La lección del 2026-08-28
(«renombrar una carpeta apagó una regla de capa, y el gate siguió en verde») aplica literal aquí:
este detector enruta por globs de ruta, así que mover `Sources/App/` lo apagaría en silencio. La
respuesta honesta a «tu glob no casa con ningún archivo» es **«no pude mirar»** (§14.3), que avisa
en local y bloquea en CI — no «todo correcto» y tampoco «te falta el mecanismo».

## 5. Estructura de archivos a crear / tocar

```
tools/check-platform-adoption.sh          ← [SLICE-FUTURO] fase 1: el detector
tools/platform-adoption.conf              ← [SLICE-FUTURO] fase 1: la lista curada (filas fijadas en §13 OQ-1)
tools/tests/test_platform_adoption.sh     ← [SLICE-FUTURO] fase 1: su suite, con el fixture histórico
ci/run-gates.sh                           ← [SLICE-FUTURO] fase 2: TOCAR — un paso más
lefthook.yml                              ← [SLICE-FUTURO] fase 2: TOCAR — Anillo 1
docs/process/lessons_learned.md           ← TOCAR al cerrar: la lección de la clase omisión/comisión
```

### NO-TOUCH (contrato — el implementador NO toca esto)

```
tools/drift-ratchet.json · tools/mutation-ratchet.json
    ← trinquetes: solo los mueve su script y en una dirección (§9)
tools/layers.conf · tools/skill-matrix.conf · tools/verify.conf
    ← confs de OTROS gates: este detector trae el suyo, no re-usa el ajeno
AGENTS.md · CLAUDE.md
    ← meta-doc (§8). La corrección de §3 que esta OQ-1 pedía YA la hizo el owner
      (2026-08-31); el implementador de este PRD sigue sin poder tocar el archivo
Sources/** · Tests/**
    ← este PRD no toca código de app. Si el detector sale rojo sobre HEAD, eso es un
      HALLAZGO que se reporta, no un permiso para editar el producto hasta apagarlo
scripts/agent-hooks/**
    ← el cableado de Anillo 2 no entra: ver §8, anti-feature 5
```

## 5b. Fases entregables

| Fase | Entrega (mergeable) | Depende de |
|---|---|---|
| 1 | Conf + detector + suite, **sin cablear a ningún anillo**. Corre a mano y es honesto en los tres exit codes | OQ-2 |
| 2 | Cableado a Anillo 3 (`ci/run-gates.sh`) y Anillo 1 (`lefthook.yml`), con su declaración en el arranque de sesión | 1 |

> La fase 1 es mergeable sola **a propósito**: un detector nuevo que se cablea el mismo día en que
> nace no tiene ninguna ventana en la que medir su tasa de falsos positivos contra el árbol real,
> y §14.2 dice que ese número decide si el gate vive. Entre fase 1 y fase 2 se corre a mano sobre
> cada commit y se anota lo que diga.

## 6. Contrato

### 6.1 Formato del conf (`tools/platform-adoption.conf`)

Tres campos separados por ` :: `, **misma forma que `tools/layers.conf`** para que quien sepa leer
uno sepa leer el otro:

```
<simbolo-literal> :: <glob-de-ambito> :: <por-que-es-obligatorio>
```

- **`<simbolo-literal>`** es una cadena literal, **no una regex**. La frontera la pone la
  herramienta, no el autor de la fila: un match no cuenta si tiene un carácter de palabra
  (`[A-Za-z0-9_]`) pegado a un borde alfanumérico del literal. Así `Container` **no** casa con
  `ScreenContainer`, y `@Inject` o `Coordinator<` funcionan sin sintaxis extra porque `@` y `<` ya
  no son caracteres de palabra. *Decisión deliberada:* una regex por fila sería más potente y es
  justo lo que la lección (2) de `f-e008f6f` desaconseja — tras N heurísticas, marcador explícito
  antes que expresividad. Si algún día una fila necesita regex, se añade un **cuarto campo que lo
  declare**, no se reinterpreta el primero.
- **`<glob-de-ambito>`** se resuelve con `git ls-files`. Consecuencia declarada, idéntica a la
  trampa conocida de `check-prd-tree`: **un archivo nuevo no cuenta hasta el `git add`**.
- **`<por-que>`** se imprime en el fallo. Un detector que dice «falta `Coordinator<`» sin decir por
  qué obliga a leer el conf para entenderlo.

### 6.2 Contrato de exit codes (§14.3)

| Código | Significado | Cuándo |
|---|---|---|
| `0` | limpio | toda fila tiene ≥1 uso real en su ámbito |
| `1` | **omisión** | alguna fila tiene 0 usos y su glob **sí** casaba con archivos |
| `3` | **no pude mirar** | conf ausente/ilegible, fuera de un repo git, **o un glob que no casa con ningún archivo** (§4.3) |

### 6.3 Contrato de stdout

Una línea de resumen parseable, como el resto de detectores:

```
ADOPTION_SUMMARY filas=<n> omitidas=<n> globs_mudos=<n>
```

El diagnóstico accionable va a **stderr** (stdout es el canal de datos — la misma G2 que ya
respeta `check-ring3.sh`).

## 7. Flujo de la solución

1. Leer el conf; si falta o no parsea → **3**.
2. Por fila: expandir el glob con `git ls-files`. Si el conjunto es vacío → contarla en
   `globs_mudos` y salir **3** al final.
3. Sobre esos archivos, **quitar comentarios reusando el extractor `awk` de
   `check-layers.sh`** — no reimplementarlo: dos copias divergen y la que se lea será la
   desactualizada.
4. Buscar el literal con la regla de frontera de §6.1. ≥1 match → fila satisfecha.
5. Alguna fila insatisfecha → **1**, listando fila, ámbito y razón.

### Edge cases

- **Un uso que vive solo en `Tests/`.** El ámbito lo fija el glob de la fila. Que los tests usen
  `Container` no prueba que la app lo use, así que la fila del producto apunta a `Sources/**` y no
  se «ayuda» con los tests.
- **Un uso dentro de un string literal.** No se cubre: el extractor quita comentarios, no strings.
  Es un FP posible y **se declara** (§8). No se persigue con una heurística — sería la sexta.
- **Un símbolo mencionado en un comentario que explica su ausencia.** Cubierto, y es el fixture
  histórico de §4.2.
- **Renombrar `Sources/App/`.** El glob deja de casar → `globs_mudos` ≥ 1 → exit 3. No verde.

## 8. Anti-features (qué NO entra)

1. **No verifica que se use BIEN.** Un `Coordinator` mal usado pasa. Eso es del `design-reviewer` y
   del `reviewer`, y decirlo aquí es la mitad del valor del PRD.
2. **No cuenta ocurrencias ni exige densidad por módulo.** «≥1 en el ámbito» es todo el contrato.
   Exigir «cada Feature navega por el Router» es donde nacen los falsos positivos: no toda pantalla
   navega.
3. **No parsea Swift.** Sin AST, sin SourceKit. Existencia sobre lista curada.
4. **No escanea docs, PRDs, skills ni comentarios.** Solo código, con comentarios quitados.
5. **No se cablea al Anillo 2.** El `skill-reminder` excluye `tools/**` a propósito y este gate no
   tiene por qué bloquear un `Edit`; su sitio son los anillos 1 y 3.
6. **No corrige `AGENTS.md`.** La corrección que OQ-1 pedía la hizo el owner por su cuenta el 2026-08-31, en un cambio aparte; este PRD no toca el archivo (§5 NO-TOUCH).

## 9. Escenarios golden (deben pasar al terminar)

1. **El fixture histórico, que es el criterio primario.** Dado el árbol `a577e3e` —donde
   `f-f2a4ca6e` verificó cero usos— cuando se corre el detector con las filas de
   `Coordinator<`, `CoordinatorView` y `DependencyModule`, entonces sale **1** y nombra las tres.
2. **La prueba de que §4.2 no es decoración.** Dado ese mismo árbol, cuando se desactiva el
   quitado de comentarios *o* la frontera de palabra, entonces el detector pasa a **0** — o sea,
   se demuestra que sin esas dos piezas habría aprobado el árbol que motivó el PRD.
3. **Verde honesto.** Dado `HEAD`, cuando se corre con las filas que fija §13 OQ-1, entonces sale
   **0** y `ADOPTION_SUMMARY omitidas=0`.
4. **El glob mudo.** Dado un conf cuya fila apunta a `Sources/NoExiste/**`, entonces sale **3** y
   `globs_mudos=1` — nunca 0 y nunca 1.
5. **Frontera de palabra.** Dado un árbol donde el único `Container` es `ScreenContainer(`,
   entonces la fila de `Container` cuenta como **omitida**.
6. **Conf ausente.** Sin `platform-adoption.conf`, sale **3** con un mensaje que dice cómo crearlo,
   y **no** bloquea en local.

## 10. Métricas de éxito

- **Falsos positivos en la ventana entre fase 1 y fase 2: 0.** Si aparece uno, la fila se retira o
  se reescribe antes de cablear. Es el número que decide si el gate vive (§14.2).
- A 2-4 semanas: el detector ha corrido en cada commit y **no ha sido evadido ni desactivado**.
- El criterio de aceptación de cada iteración **no es «está verde»** sino que **acepta un
  subconjunto estricto de lo que aceptaba antes** (lección (1) de `f-e008f6f`).

## 11. Rollout

Fase 1 sin cablear → ventana de observación manual → fase 2 cablea a Anillo 1 y 3. Rollback:
borrar la fila ofensora del conf (el detector sigue vivo para las demás) o el paso de
`run-gates.sh`. Sin flags, sin migración de datos.

## 12. Riesgos

| Riesgo | Mitigación |
|---|---|
| **Nace verde y no vuelve a disparar nunca** — HEAD ya adoptó los mecanismos, así que el detector podría ser decorativo desde el día uno | Golden 1 y 2: se exige demostrar que se pone **rojo sobre el fixture histórico**. Un detector que no se ha visto fallar no está verificado. Su valor real es de **trinquete**: impide des-adoptar en silencio, y es el gate de los proyectos nuevos que salgan de esta baseline |
| **Mecanizar una regla en disputa** (`@Inject`) | **Conjurado**: OQ-1 se resolvió corrigiendo `AGENTS.md` §3, y la fila `@Inject` NO entra al conf. El riesgo genérico persiste para filas futuras — de ahí la ventana de §5b antes de cablear |
| **El conf se pudre**: se prescribe un mecanismo nuevo en `AGENTS.md` §3 y nadie añade su fila | ⚠️ **Sin mitigación en este PRD, y se declara.** Sería un detector del detector. Anotado en §16 |
| Los globs enmudecen al mover carpetas | §4.3: exit 3, no verde. Es la lección del 2026-08-28 aplicada por diseño |
| Un uso dentro de un string literal cuenta como uso | Declarado en §7 como FP posible conocido. No se persigue |

## 13. Open Questions

- [x] **OQ-1 — RESUELTA (owner, 2026-08-31): rama (a), y ya aplicada.** `AGENTS.md` §3 se
      corrigió al idioma que ya usaban las otras cuatro fuentes del proyecto
      (`architecture/SKILL.md` §DI, `platforms/ios.md`:373-394, `Inject.swift` del paquete y el
      código): **inyección por constructor por defecto; `@Inject` solo para dependencias
      transversales, y siempre con `init(container:)`**. `f-da257e0c` cerrado.
      **Consecuencia para el conf, que es lo que esta OQ bloqueaba:** la fila `@Inject ::
      Sources/**` que proponía `f-e008f6f` **NO entra** — exigiría lo que la regla nueva llama
      excepción. La fila de DI exige `: DependencyModule :: Sources/**` y
      `Container.shared :: Sources/App/**`, que es lo que el proyecto sí prescribe y sí hace.
      El PRD queda **desbloqueado**: pasa a `design-review` cuando OQ-2 y OQ-3 estén decididas.
- [ ] **OQ-2 — ¿el detector vive aquí o en el template?** El template lo querría (sirve a todos los
      adoptantes), pero su conf es por fuerza específico de cada proyecto. Propuesta: la herramienta
      arriba, el conf abajo, y sin conf → exit 3 con instrucciones. Decisión del owner porque
      cambia dónde se hace el trabajo.
- [ ] **OQ-3 — ¿entra `Router` como fila propia?** Hoy se registra en el contenedor pero **aún no se
      consume desde el ViewModel** (residuo declarado del PRD 0002, atado al slice de detalle). Si
      entra ahora, nace roja. Propuesta: **no entra hasta el slice de detalle**, y se anota aquí para
      que no se olvide — que es justo lo que le pasó a `f-f2a4ca6e`.

## 15. Definition of Done

- [ ] Los seis escenarios golden pasan, **el 1 y el 2 con el fixture histórico real** (`a577e3e`), no con un sandbox sintético
- [ ] **TDD**: cada rama del contrato de exit codes tiene test escrito primero. Verificado con mutación real: romper la frontera de palabra, el quitado de comentarios o el caso del glob mudo **mata un test**, y la mutación se hace en `git worktree` aparte con restauración por checksum
- [ ] `bash tools/tests/run-tests.sh` completo en verde (§8: toca `tools/`)
- [ ] `reviewer` GREEN/AMBER atendido
- [ ] El límite de §4.1 («verifica que se USE, no que se use bien») está impreso **en la salida del propio detector**, no solo en este PRD
- [ ] Cada fase quitó su `[SLICE-FUTURO]` en su commit, y al cierre `check-prd-tree` da `faltan=0 futuros=0`
- [ ] La lección de la clase (comisión vs omisión) escrita con su `Detector:`
- [ ] Sin secretos (gitleaks limpio)

## 16. Próximos pasos

- **El detector del detector** (§12): nada obliga a añadir la fila cuando `AGENTS.md` §3 prescribe
  un mecanismo nuevo. Es la misma clase que `f-3b30fcf4` y que `f-f17a5860` (nadie vigila que los
  globs de `skill-matrix.conf` no enmudezcan) — tres instancias de «el conf se pudre en silencio»
  que probablemente merecen **un** gate, no tres.
- La fila de `Router` cuando llegue el slice de detalle (OQ-3).
- Si OQ-2 sale «template», portar herramienta + suite hacia arriba.

## 17. Change log

| Fecha | Cambio | Quién |
|---|---|---|
| 2026-08-31 | **OQ-1 resuelta y aplicada** (owner): `AGENTS.md` §3 corregido al idioma que ya usaban las otras cuatro fuentes, `f-da257e0c` cerrado, y la fila `@Inject` descartada del conf. Barridas las siete frases del documento que la daban por pendiente | agente |
| 2026-08-30 | Draft inicial. Se verificaron —no se copiaron— los hechos del diseño de `f-e008f6f`, y la verificación encontró el bloqueante: `@Inject` tiene cero usos en `Sources/` y el paquete recomienda lo contrario que `AGENTS.md` §3 (`f-da257e0c`). Se añadió el fixture histórico de `a577e3e`, que además prueba que un `grep` ingenuo habría dado verde sobre el árbol que motivó el PRD | agente |

## 18. Gaps detectados (llenar post-ship)

_Pendiente._

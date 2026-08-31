# Mapa de ejecución actual

> Lo lee el agente al inicio de cada sesión (`session-start.sh` extrae "Estado actual"). Mantenlo
> al día: es la respuesta a "¿en qué estamos y qué sigue?". Una pantalla, sin historia.

## Estado actual

- **Qué es este repo:** **iOSAppBaseline** — el proyecto base del que salen los proyectos iOS
  nuevos. Tres cosas a la vez, y por eso existe: (1) instancia los dos paquetes propios
  —`AppFoundation` (arquitectura, navegación, DI, estados de pantalla) y `CoreNetworking`
  (red, pinning, reintentos)—, (2) trae el agentic-workflow-template cableado al stack, y
  (3) su app —listado y detalle de películas contra TMDB— es el **módulo de referencia**: la
  vertical que cruza todas las capas y que las skills citan en vez de describir.
- **Fase:** **vertical de películas entregada y re-arquitecturada sobre los SPM (PRD 0002, las tres fases).** Origen: Listado de populares
  (primera página) cruzando Domain → Data → Features → App, con la suite en verde
  (`bash tools/verify-run.sh`) y `check-layers`/`check-drift` sin errores. Sin paginación, sin
  detalle, sin pósters.
  Estuvo **bloqueado a propósito** hasta que el PRD 0001 pasó a `Approved` (owner, 2026-08-28): el
  `design-reviewer` pasó **varias rondas, todas 🔴 RED**, hasta cerrar los 4 bloqueantes
  originales. Cada pasada posterior encontró la misma clase de defecto —un arreglo que no se
  propaga a las secciones que se marcan o se ejecutan—, siempre de documento y nunca de código.
  **El recuento exacto no se escribe aquí a propósito**: la tabla de veredictos de
  `docs/process/reviews/2026-08-28-design-review-prd-0001.md` es la fuente, y duplicar la cifra
  ya la desalineó una vez (una cifra derivable escrita a mano caduca sola).
- **Anillo 3 CABLEADO** (`check-ring3` ✅): `origin` en GitHub y `.github/workflows/gates.yml`
  con dos jobs — los gates deterministas en Linux (`ci/run-gates.sh` con `GATES_SKIP_TESTS=1`,
  renuncia explícita: en Ubuntu no hay Xcode) y el build+tests real en macOS invocando
  `tools/verify-run.sh --ci`, el mismo gate que en local. Se reparte así porque macOS consume
  cupo de Actions a ~10× y un cupo agotado ya dejó a otro repo sin Anillo 3 una semana sin que
  nadie lo declarara. El rango del scan de secretos sale de `github.event.before` (el commit
  anterior al push), no de `origin/main`: tras el push ese ref ya es `HEAD` y el gate aprobaría
  sin escanear nada. Estado de sus ejecuciones: `gh run list --repo hiramvazquez/iOSAppBaseline`.
- **Entregado:**
  - Proyecto declarado en `project.yml` (xcodegen). El `.xcodeproj` es artefacto gitignored:
    se regenera con `xcodegen generate` y no da conflictos de merge.
  - Nivel 0 en ambos targets: Swift 6, `SWIFT_STRICT_CONCURRENCY=complete`, MainActor por
    defecto y warnings como errores.
  - Los dos SPM entran **por URL publicada y version fijada** (la versión exacta la fija
    `Package.resolved`, no esta prosa — aquí hubo un 0.1.3 escrito a mano que ya era 0.1.4), con un smoke test que los importa y los USA — un `#expect(true)`
    habria pasado con el proyecto mal cableado. El `Package.resolved` se versiona: es lo unico
    que hace que el build local y el de CI sean el mismo build.
  - Harness adoptado (caso B de `docs/ADOPTION.md`) con `verify.conf` cableado a
    `xcodegen generate && xcodebuild test`, `layers.conf` ampliado con las reglas propias,
    `project_kind: application`, preset `full` y lefthook instalado.
- **Secretos:** la clave de TMDB va en `Config/Secrets.xcconfig` (gitignored) copiando
  `Config/Secrets.example.xcconfig`. **Sin ella el proyecto compila igual** —el `#include?` es
  opcional— y falla en runtime con un mensaje claro; no rompe el build de un clon recién hecho.

## Próximo paso

0. **El Anillo 3 estuvo caído y ya no lo está (2026-08-30).** El push del PRD 0002 dejó CI en
   rojo y nadie lo vio hasta la sesión siguiente: `_con_limite` en `check-ring3.sh` prefería
   `timeout` cuando existía, así que la escalada TERM→KILL vivía solo en el fallback. **El gate
   de pre-push corre en macOS —sin `timeout`— y CI en Linux —con él—: la rama que se probaba en
   local nunca era la que corría en CI.** No era el flaky de `f-7c08518b`; era determinista y de
   plataforma, y el test nunca había estado verde en CI ni un día. Arreglado en `e779539` con
   una sola ruta portable; `f-804ebee0` cerrado con la evidencia del run, no con una afirmación.
   Queda vivo lo que ese cierre NO cierra: la **clase** en `f-3b30fcf4`, con dos instancias sin
   tocar (`tools/harness-report.sh:40`, `tools/secret-baseline.sh:66`), y la **deuda de
   propagación al template** — el archivo llegó por sync, así que el bug vive igual arriba y el
   próximo `tools/upgrade.sh` traería la versión vieja.

0b. **PRD 0003 (detector de omisión) en `Draft`, BLOQUEADO en su OQ-1.** Al verificar —en vez de
   copiar— el diseño que `f-e008f6f` traía dentro, apareció el bloqueante: la fila
   `@Inject :: Sources/**` pondría el detector **rojo sobre código correcto**, porque `Sources/`
   tiene cero `@Inject` y usa inyección por constructor, que es lo que el autor del paquete
   recomienda (`Inject.swift`: «Prefer constructor injection») mientras `AGENTS.md` §3 prescribe
   `@Inject` en los consumidores. Es `f-da257e0c`, y **lo decide el owner**: no se mecaniza una
   regla en disputa. El PRD trae además un fixture histórico (`a577e3e`) que demuestra que un
   `grep` ingenuo habría dado verde sobre el árbol que motivó todo esto.

0c. **PRD 0004 (slice de detalle) en `Draft`, con cuatro OQ para el owner.** Es el primer slice
   que RECORRE la navegación: hoy `MoviesRoute` tiene una sola ruta, el `Router` se registra pero
   nadie lo resuelve, y `CoordinatorView` está montado sin que ningún push/pop lo haya
   atravesado. Contrato y golden 6 tomados del PRD 0001 §6.3/§9, no reinventados. La verificación
   del código encontró dos cosas que el handoff no traía: **el registro del `Router` se queda sin
   consumidor** si el ViewModel lo recibe por constructor —y a un registro sin consumidor se le
   borra, no se le escribe un test (OQ-1, anotada en `f-f88eb0fd`)—, y **el PRD 0001 se
   contradice consigo mismo** sobre dónde van `overview`/`releaseDate`, con su árbol colocando
   además `MoviesModule` donde `layers.conf` lo rechaza (`f-a655520c`). Los findings atados al
   slice son **cuatro** más un residuo declarado, no cinco: el handoff contaba de más.

1. **Slice 0 commiteado y publicado.** `origin/main` incluye la vertical, los tres refactors y
   la reescritura de las skills; CI (`Gates`) pasa en verde sobre ese árbol —el estado real de
   sus ejecuciones se consulta con `gh run list --repo hiramvazquez/iOSAppBaseline`, no se
   escribe aquí—. Los 4 bloqueantes del design-review eran de documento y están cerrados:
   troceo por slices en §5b, contrato republicado en §6.3 con ids inmutables, forma prohibida
   de C5 escrita, e idioma fuente decidido (**`es`**, con `developmentRegion` en OQ-3).

   > **El hallazgo que reordenó las prioridades (2026-08-29, owner).** El módulo de referencia
   > **no usaba la mitad de `AppFoundation`**: ni `Coordinator`/`Router`, ni `Container`/`@Inject`,
   > pese a que `AGENTS.md` §3 los prescribe (`f-f2a4ca6e`). La causa raíz no fue descuido del
   > agente: `platforms/ios.md` —lectura OBLIGATORIA para tocar un ViewModel— **no mencionaba
   > ni una vez los SPM propios** y enseñaba las alternativas a mano; el agente obedeció
   > (`f-a3b6dafc`). Y el `design-reviewer` **sí lo había cazado por escrito dos horas antes
   > del commit** (H-7 de su 6ª pasada): lo que falló fue el cierre, porque ese sub-agente
   > **no deja marker**, así que seis veredictos RED no impidieron nada.
   >
   > **Hecho el 2026-08-29:** reescritas `architecture/SKILL.md`, `platforms/ios.md`,
   > `domain/SKILL.md` y `security/SKILL.md` contra una auditoría de los dos paquetes, y
   > rellenados los FILL de `process/references/**`. Las skills que gobiernan código de
   > producto quedan a cero FILL (`grep -rc FILL .agents/skills`).
   >
   > ✅ **HECHO el 2026-08-29 — PRD 0002, las tres fases** (`f-f2a4ca6e` CERRADO): el módulo de
   > referencia usa `Container` (MoviesModule + `bootstrap` con señal inyectada), `Coordinator`
   > registrado como `Router` en el contenedor, y `CoordinatorView` vía `MoviesRouteBuilder` —
   > cero `NavigationStack` a mano. Seis pasadas de design-review sobre el PRD; mutantes de
   > OQ-4 y de la Trampa C muertos; checklist de UI en simulador con datos reales. Quedan, con
   > condición de cierre atada al slice de detalle: consumir el `Router` desde el ViewModel y
   > el residuo de G4. El detector de omisión sigue en `f-e008f6f` (OQ-1: PRD aparte).
2. **Tres cambios de arquitectura acordados (2026-08-28) — los tres cerrados.**
   (a) sacar el mapeo transporte→dominio a un `TransportError` **en `CoreNetworking`** (OQ-18,
   2026-08-28) — ✅ **HECHO el 2026-08-28**, publicado como `CoreNetworking 0.1.4` (revisión
   `4d299f3634fd…`) y `Package.resolved` re-fijado. **El diseño entregado corrige el de este
   mismo párrafo**: el plan original dejaba `MoviesError` con `.transport(TransportError) +
   notFound + malformedResponse`, pero eso exige `import CoreNetworking` en
   `Sources/Domain/Movies/MoviesError.swift`, y `tools/layers.conf:41` se lo prohíbe
   explícitamente a `*/Domain/*` — el argumento de más arriba ("la regla ... lo cubre
   automáticamente") leía esa regla al revés: VIGILA la frontera, no la PERMITE. Entregado en su
   lugar: `MoviesError` **sin cambios de forma** (sigue siendo el mismo enum plano de siempre,
   `CaseIterable` intacto — `.transport(_)` nunca llegó a existir);
   `TMDBPopularMoviesRepository.mapearTransporte(_:)` traduce valor a valor desde
   `TransportError`, en `Data/`, donde el import sí está permitido. Sin payloads `String` en
   `TransportError` (verificado con test centinela) — S1 se sostiene igual que antes, por
   construcción; (b) sustituir `load()` por
   `enum Action` + `handle(_:)` en el ViewModel — ✅ **HECHO el 2026-08-28**, con la idempotencia
   de la primera carga que faltaba (`f-31902e86` cerrado), verificado con mutantes —incluido el que
   reproduce la regresión de recuperabilidad en `.empty` que la review cazó—;
   (c) sacar los DTOs y su mapeo del adapter a su propio archivo — ✅ **HECHO el 2026-08-28**, en
   `Sources/Data/Movies/TMDBDTOs.swift`, con tests de decodificación directa (sin mock de red)
   que cierran un hueco real: `vote_average` nulo no tenía cobertura en ninguna fixture existente.

   > La convención de intención quedó unificada el 2026-08-29 (fase 3 del PRD 0002, `f-b6f2c1a4`
   > cerrado): `Intent` + `send(_:)`, que es lo que `.claude/rules/10-ios-ui.md` ya prescribía.
3. **El `1.0.0` de los SPM sigue pendiente, y a proposito.** Publicarlos se adelanto a la
   vertical porque CI no puede resolver una ruta local (`Invalid local package`), pero se
   publicaron en `0.x`: estrenar antes de congelar la API sigue siendo la decision: un `1.0.0`
   etiquetado sin haberlo consumido nace obsoleto. El salto a `1.0.0` es cuando la vertical
   haya ejercitado la API entera.
4. **Anillo 3 en verde.** Los dos bloqueantes del estreno están resueltos: los paquetes
   locales (`Invalid local package`, arreglado aquí al pasar a `url:` + `from:`) y la descarga
   de gitleaks del ejemplo del template. El estado real de las ejecuciones **no se escribe
   aquí** — se consulta con `gh run list --repo hiramvazquez/iOSAppBaseline`, que es lo único
   que no caduca. La versión anterior de este punto afirmaba que CI «aún no ha pasado en
   verde» cuando llevaba tres ejecuciones en verde, y lo cazó `check-execution-map.sh` en su
   primera pasada tras el upgrade — el detector que existe precisamente por este párrafo.

## Decisiones ya tomadas (no re-litigar)

Viven en los paquetes y en `AGENTS.md` §2/§3: patrón View+ViewModel+Logic con `ScreenContainer`,
navegación por `Coordinator`, DI por `Container`, red por `APIService`, i18n ES+EN con String
Catalog, mínimo iOS 17. Lo que los paquetes no cubran se decide **una vez** y se escribe en
`docs/process/decisions/`.

## Punteros

- Reglas: `AGENTS.md` · **Bucle de verificación:** `.agents/skills/process/references/verification-loop.md`
- Lecciones: `docs/process/lessons_learned.md` (toda entrada exige `Detector:`)
- Findings: `docs/process/findings-ledger.md` (arranca vacío: los del template son deuda suya)
- Salud del harness: `bash scripts/agent-hooks/session-start.sh --report`

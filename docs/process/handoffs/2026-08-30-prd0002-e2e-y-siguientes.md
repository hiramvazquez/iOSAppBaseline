# Handoff — tras el PRD 0002 (adopción de los SPM) y el primer ensayo del revisor E2E

> Prompt de arranque para una sesión nueva sobre `iOSAppBaseline`.
> Estado verificado el 2026-08-30 sobre `5dcb575`, árbol limpio.
> El handoff anterior (`2026-08-28-slice0-a-refactors.md`) sigue siendo buena lectura de fondo;
> este lo sustituye como punto de entrada.

Retomas iOSAppBaseline en `/Users/hiram/Desktop/PROYECTOS/iOSAppBaseline`. Abre la sesión ahí
(no en agentic-workflow-template ni en spm-pro: el harness de cada repo resuelve contra su
propio directorio).

## Dónde está el trabajo

Árbol limpio en `main`, sobre `5dcb575`, con **26 commits sin pushear** (`git log --oneline
origin/main..HEAD | wc -l` para el número vivo). Lo grande, de abajo arriba:

- `be521fc` upgrade del template: 4 detectores nuevos (`check-prd-tree`, `check-version-claims`,
  `check-execution-map` con afirmaciones de estado, aviso de FILL en `skill-reminder`)
- `b73f714`…`c017407` el PRD 0002 y sus **seis pasadas de design-review** (léelas en el §17 del
  PRD: cada RED enseñó una clase de defecto distinta)
- `65b5fdb` fase 3 — `Intent` + `send(_:)`
- `483f4eb` fase 1 — `Container` + `MoviesModule` + `bootstrap(container:modules:onMisconfiguration:)`
- `3e333ba` fase 2 — `Coordinator` dueño del ciclo de vida **registrado como `Router` en el
  contenedor**, `CoordinatorView` + `MoviesRouteBuilder`, cero `NavigationStack` a mano
- `517bdc5` las correcciones del **primer ensayo del revisor E2E** (ver abajo: es un rol nuevo)

Gates en verde: `bash tools/verify-run.sh` fue la firma de cada commit de código;
`check-layers` 0, `check-drift` 0/0, `check-execution-map` 0, `check-prd-tree`
`declarados=17 faltan=0 futuros=0`. La suite del harness tiene **tests flaky de señales**
(ver Trampas). El PRD 0002 está `In progress` con TODO entregado: solo le falta el push para
`Shipped`.

Lee primero `docs/process/current_execution_map.md` y el tramo vivo de
`docs/process/lessons_learned.md` (§0 de AGENTS.md). Después, si vas a tocar el PRD 0002 o su
área: el PRD entero, cabecera y §17 incluidos — su historia ES la documentación.

## Qué hacer, en este orden

**1. El push, si el owner lo aprueba explícitamente (§7 — no lo asumas de este documento).**
26 commits. CI (`gates.yml`) ya ha pasado en verde con árboles anteriores; el estado vivo se
consulta con `gh run list --repo hiramvazquez/iOSAppBaseline`, nunca se afirma de memoria.
Ojo: el push dispara la suite del harness en pre-push (~4 min) y tiene flaky conocido — si
falla un test de señales, mira las Trampas antes de tocar nada.

**2. El PRD del detector de omisión** (`f-e008f6f`, decisión OQ-1 del owner: PRD aparte).
El finding YA CONTIENE el diseño del process-judge (conf de 3 campos como `layers.conf`,
extractor awk anti-comentarios, frontera de palabra) **y las cuatro lecciones transferibles**
del arreglo de detectores del template — criterio de subconjunto estricto, marcador explícito
tras N heurísticas fallidas, «¿el detector mira donde el dato se escribe?», narrativa=100% FP.
Léelo entero antes de escribir una línea. Toca `tools/`: autorización explícita del owner y
`bash tools/tests/run-tests.sh` obligatorio (en background, tarda).

**3. La cola del `process-judge`: 3 sesiones.** Su VERDICT la vacía. La sesión del 2026-08-29/30
tiene material denso: seis pasadas de design-review con dos rondas de arreglos que introdujeron
defectos nuevos, el fail-silent de OQ-4 que yo mismo recomendé, y el ensayo E2E.

**4. El slice de detalle es la siguiente feature natural, y NO es solo una pantalla:** tiene
**cinco findings esperándolo** con condición de cierre atada a él — consumir el `Router` desde
el ViewModel, el residuo de G4 (la conexión builder→`CoordinatorView`), el registro del Router
sin test propio (hallazgo A2 del E2E), `coordinator` let-vs-`@State`, y el stub `RepoVacio` sin
declarar. Búscalos: `bash tools/findings/findings.sh list --status open | grep -i "detalle\|router\|G4\|RepoVacio\|coordinator"`.
Necesitará PRD (§12: toca >1 módulo).

**5. Decisiones del owner pendientes, no las tomes tú:** formalizar el **revisor E2E** como
sub-agente (`.claude/agents/e2e-reviewer.md` — el primer ensayo está en el transcript de esta
sesión y dio 4 hallazgos inter-plano que ningún gate vio; el prompt que lo lanzó vale como
plantilla), y el **gate de fidelidad de skills** (compilar sus ejemplos contra los SPM —
finding en el ledger, probablemente trabajo del template).

## El rol nuevo: revisor E2E (directiva del owner, ya ensayada)

El owner pidió, literal: *«el que revisa al final debe tener contexto de todo... tipo senior
que revisa un PR»*. Se ensayó al cierre del PRD 0002 como agente general con punteros a TODA la
cadena (encargo del owner → PRD → skills → código → tests → ledger). Resultado: AMBER con 4
hallazgos **inter-plano** que ningún gate por capa había visto (el PRD negaba en §7 lo que el
código hacía; una skill mandaba los módulos de DI a la carpeta donde `layers.conf` los rechaza).
Al cerrar un PRD o fase con entregable: **lánzalo**. Y exige su honestidad simétrica: que
declare qué de lo suyo ya estaba cazado por los gates baratos.

## Trampas NUEVAS de este repo (las del handoff anterior siguen valiendo)

- **El `verify-marker` expira a los 3600s.** Si entre la firma y el commit pasa más de una
  hora, re-corre `bash tools/verify-run.sh`.
- **`verify-run` se niega si hay cambios trackeados sin stagear** — aunque no sean tuyos.
  Patrón que funcionó: `git stash push --keep-index -m "..." -- <archivos>` para apartar lo
  que va en otro commit, firmar, y `git stash pop` después.
- **`check-prd-tree` lee `git ls-files`: los archivos NUEVOS no cuentan hasta el `git add`.**
  Un `faltan=N` justo después de crear archivos es orden de operaciones, no un bug. Stagea y
  re-corre antes de diagnosticar.
- **El Info.plist compilado NO se regenera cuando cambia un `#include?` de xcconfig**
  (ledger). Síntoma: la app cae al camino sin-credencial con el token perfecto en
  `-showBuildSettings`. Arreglo: `touch Config/Info.plist`. La señal del bootstrap distingue
  en un minuto ese caso de un cableado roto — úsala.
- **Los unit tests corren HOSTED dentro de la app real**: cada corrida ejecuta
  `BaselineApp.init()` de verdad. Un grafo de DI mal registrado dispara el `assertionFailure`
  del bootstrap ANTES de que Swift Testing arranque — **mata la suite entera con un crash
  opaco** («Early unexpected exit»). Si ves eso, el diagnóstico está en el log
  (`subsystem com.hiram.iOSAppBaseline, category Bootstrap`), no en el runner.
- **`tools/upgrade.sh` re-conflictúa SIEMPRE en `tools/tests/README.md`** (deadlock conocido,
  en el ledger): la resolución correcta es idéntica a HEAD, así que no hay commit posible y el
  puntero `.template-sync` no avanza. Resolución mecánica de 1 minuto:
  `git checkout --ours tools/tests/README.md && git add` y sigue. NO edites el puntero a mano.
- **La suite del harness tiene tests FLAKY de señales y es el gate de pre-push** (ledger,
  high): dos corridas del mismo árbol pueden fallar tests distintos de `test_agent_runner.sh`.
  Antes de diagnosticar una regresión, re-corre; y jamás `--no-verify`.
- **El `design-reviewer` NO deja marker** (`f-71c669cc`): sus RED no bloquean nada
  mecánicamente. Si un PRD se apoya en ese gate, escribe en su §12 que el implementador para
  voluntariamente — es la única red que existe y ya falló una vez por no estar escrita.
- **Los `[SLICE-FUTURO]` del PRD se retiran en el MISMO commit que entrega esos archivos**
  (regla B4 del DoD del 0002); al cierre se exige `futuros=0`, no solo `faltan=0`.

## Cómo trabajar aquí — lo aprendido a golpes esta sesión

- **No escribas un id de finding de memoria, jamás.** Un id inventado (f-1a1cbb7f, sin acentos
  graves aquí a propósito: es la MENCIÓN de un fantasma, no la cita de un finding — y el
  detector de citas distingue justo por eso) circuló
  por TRES sesiones y llegó a dos commits antes de que nadie hiciera el `grep` de dos segundos.
  Si citas un id, el comando que lo verifica va en el mismo mensaje.
- **Cuando corrijas una afirmación, barre TODOS los sitios donde vive.** Siete instancias de la
  misma clase en un solo PRD («corregir donde señalaron, no donde la afirmación también
  vivía») — la séptima entre el acta del owner y el código. `grep` de la frase antes de dar por
  cerrada la corrección.
- **Prueba de bolsillo con mutación REAL, y restaura por checksum.** `shasum` antes, muta,
  mira morir el test con el mensaje esperado, restaura, `diff` de checksums. Un reviewer dejó
  una vez su mutación en el árbol y costó una corrida de simulador; los reviewers ahora mutan
  en `git worktree` aparte — pídeselo explícitamente en el prompt.
- **«Verde» no es el criterio de un arreglo de detector: «acepta un subconjunto estricto de lo
  que aceptaba antes» sí lo es.** Y tras N heurísticas fallidas sobre lenguaje natural, la
  salida es un marcador explícito, no la heurística N+1.
- **Separar por naturaleza ≠ separar por dependencia.** El aviso de naturalezas del
  reviewer-gate es bueno, pero un arreglo de doc puede ser PRECONDICIÓN del commit de
  maquinaria (le pasó a esta sesión: el detector nuevo exigía el mapa corregido). Antes de
  partir un commit, pregunta si un trozo es precondición del otro — y verifica con el detector
  staged contra el árbol que quedaría en HEAD, no contra tu working tree.
- **Los sub-agentes y los peers se equivocan igual que tú:** tres misatribuciones en una hora,
  las tres resueltas con `git log -S`/`git show`. Verifica antes de actuar sobre lo que digan
  — y acepta sus correcciones igual de rápido cuando los comandos les dan la razón.
- **El idioma de los SPM manda.** Cuando dudes de un patrón, los Previews y tests del paquete
  son el canon (los escribió su autor); las skills apuntan a ellos y documentan las trampas.
  Si la skill y el paquete divergen, es un finding — no elijas en silencio.

## Findings abiertos: consulta el número vivo con el comando

`bash tools/findings/findings.sh list --status open` (el conteo escrito a mano caduca solo;
esta sesión encontró tres cifras podridas por escribirlas).

Los que tocan lo próximo: `f-e008f6f` (el PRD del detector, con diseño y lecciones dentro),
los cinco atados al slice de detalle (grep de arriba), `f-52ef5f6d` (la decisión
`CancellationError` vs `.unknown`, sigue bloqueando paginación y caché), y los dos del
template ya avisados a sus sesiones (README de AppFoundation que enseña el anti-patrón;
`CoordinatorView` sin tests).

## Contexto entre repos

- **agentic-workflow-template** (`/Users/hiram/Desktop/PROYECTOS/agentic-workflow-template`):
  remote `template` de este repo. Sus sesiones arreglaron `check-execution-map` (v5, por
  palabras-función de prosa) y `check-finding-refs` (escanea `source`, no narrativa) DESPUÉS
  de nuestro último upgrade — **el próximo `tools/upgrade.sh` los trae** (con el re-conflicto
  conocido del README).
- **spm-pro** (`/Users/hiram/Desktop/PROYECTOS/spm-pro`): monorepo de los dos SPM. Publicar =
  `git subtree split -P CoreNetworking -b cn-only` + push del split a
  `github.com/hiramvazquez/<paquete>` + tag + re-fijar `Package.resolved` aquí. El working
  tree y el tag 0.1.4 estaban byte-idénticos al cierre.
- **El token de TMDB es de dev y el owner aceptó el riesgo** (`f-7c57fa35`, accepted): no se
  rota, no se protege con permissions.deny en ESTE repo. La propuesta estructural sigue viva
  para el template.

# Handoff — el Anillo 3 recuperado, y los dos PRD desbloqueados

> Prompt de arranque para una sesión nueva sobre `iOSAppBaseline`.
> Estado verificado el 2026-08-31 sobre `c11202b`, árbol limpio, `origin/main` al día.
> **Sustituye a `2026-08-30-prd0002-e2e-y-siguientes.md` como punto de entrada.** Ese sigue
> valiendo como lectura de fondo, pero **su paso 1 ya está hecho** y su recuento de findings
> del slice de detalle es de más (ver abajo).

Retomas iOSAppBaseline en `/Users/hiram/Desktop/PROYECTOS/iOSAppBaseline`.

> ⚠️ **Abre la sesión EN ESE DIRECTORIO, y compruébalo con `pwd` antes de nada.** La sesión
> anterior arrancó en `agentic-workflow-template` y el cambio de directorio no llegó a aplicarse:
> todo comando sin `cd` explícito leía el otro repo. Costó un diagnóstico equivocado —se citó el
> `AGENTS.md` del template creyendo que era el de aquí— y varios recuentos de findings falsos (el
> hook inyecta 65 abiertos; **aquí hay 41**). Si el estado que te inyecta el hook al arrancar no
> cuadra con `bash tools/findings/findings.sh list --status open | wc -l`, estás en el repo
> equivocado.

## Dónde está el trabajo

`main` limpio sobre `c11202b`, **0 commits sin pushear**, CI en verde (run 33414003226, los dos
jobs). Cinco commits publicados el 30-31 de agosto:

| Commit | Qué |
|---|---|
| `e779539` | **el fix del Anillo 3** — `check-ring3` deja de bifurcar por plataforma |
| `0a301cc` | PRD 0003 (detector de omisión) + cierre de `f-804ebee0` |
| `55f8c90` | PRD 0004 (slice de detalle) |
| `37d7e8f` | OQ-1 del 0004 resuelta: constructor, y borrar el registro del `Router` |
| `c11202b` | **`AGENTS.md` §3 corregido**, `f-da257e0c` cerrado |

Lee `docs/process/current_execution_map.md` (sus puntos **0, 0b, 0c y 0d** son de esta sesión) y
el tramo vivo de `lessons_learned.md`. Si vas a tocar un PRD, léelo entero.

## Lo que pasó, y por qué importa más que el arreglo

**CI llevaba en rojo desde el push del PRD 0002 y nadie lo vio hasta la sesión siguiente.** El
Anillo 3 —el backstop que justifica *todo* el fail-open local de §14.3— estuvo caído dos días.

**No era el flaky de `f-7c08518b`, que es lo que todo el mundo supuso.** `_con_limite` en
`check-ring3.sh` prefería `timeout` cuando existía y retornaba ahí; toda la escalada TERM→KILL
vivía solo en el fallback. GNU `timeout` sin `-k` manda TERM y espera al hijo, así que un
`trap "" TERM` lo ignoraba. **Linux tiene `timeout`; macOS —donde corre el gate de pre-push— no.**
La rama que se probaba en local nunca era la que corría en CI, y la de CI era la mala. El test
llevaba rojo desde `be521fc` **sin haber estado verde en CI ni un solo día**.

Tres cosas que sacar de ahí:

1. **«Verde en local» no es evidencia sobre CI** para nada que dependa de señales, procesos,
   rutas o binarios del sistema — corren en sistemas distintos.
2. **Un `command -v X` que elige implementación duplica el código bajo prueba** y reparte la
   cobertura entre plataformas sin declararlo. La clase sigue viva en `f-3b30fcf4`, con dos
   instancias sin tocar.
3. **Antes de creerte que algo es flaky, mira si alguna vez estuvo verde.** Dos comandos
   (`git show <commit>^:<archivo> | grep -c`) lo resolvieron.

## Qué hacer, en este orden

**1. Las OQ que quedan. Ninguna bloquea un PRD entero, pero sin ellas no hay `design-review`.**

- **PRD 0003** — OQ-2 (¿el detector vive aquí o en el template?) y OQ-3 (¿entra `Router` como
  fila ya? propuesta: no hasta el slice de detalle, hoy nacería roja).
- **PRD 0004** — OQ-2 (puerto nuevo, propuesto), OQ-3 (memoización del store: diccionario por
  `MovieID` con el crecimiento declarado) y OQ-4 (String Catalog fuera, mismo criterio que OQ-6).

Las cuatro llevan propuesta escrita **y el porqué**. No las decidas tú.

**2. La fase 1 del PRD 0003, si el owner autoriza `tools/` (§8).** La autorización anterior era
para el fix de `check-ring3` y está agotada. El PRD trae el diseño cerrado: conf de tres campos
como `layers.conf`, símbolo **literal** (no regex — la frontera la pone la herramienta), glob mudo
= **exit 3**, y la fase 1 **no se cablea a ningún anillo** para tener ventana en la que medir
falsos positivos.

> **Su criterio primario es un fixture histórico, y conviene entender por qué.** En `a577e3e` —el
> árbol donde `f-f2a4ca6e` verificó CERO usos— un `grep -F` ingenuo habría dado **verde**:
> `Container` casaba con `ScreenContainer(`, y `CoordinatorView` solo aparecía en un doc-comment
> que explica por qué el código **no** lo usa. La frontera de palabra y el quitado de comentarios
> no son pulido: son la diferencia entre el detector y un adorno, **sobre el caso exacto que lo
> motivó**.

**3. El slice de detalle (PRD 0004), cuando sus OQ estén cerradas.** Tres fases: contrato →
pantalla y ruta → navegación real. **Son CUATRO findings atados**, no cinco como decía el handoff
anterior: `f-f88eb0fd`, `f-a452b1de`, `f-5856bd41`, `f-996710c3`, más el residuo del `Router`
declarado *dentro de la resolución* de `f-f2a4ca6e`. `f-29c26642` es de proceso y `f-8ab6c2ad`
vive en el SPM: este slice los **ejercita**, no los cierra.

**4. ~~La deuda del template~~ — HECHA el 2026-08-31.** El fix se propagó aguas arriba
(`agentic-workflow-template@31bbb88`, publicado), así que el próximo `tools/upgrade.sh` ya **no**
traería la versión vieja de `check-ring3.sh`. Se hizo con ciclo TDD real allí —el test primero,
rojo en el propio template— y no como copia a ciegas. **Lo que sigue debiendo el template:** las
dos instancias vivas de la misma clase (`harness-report.sh:40`, `secret-baseline.sh:66`), anotadas
allí como f-1caf51c6 — **sin acentos graves a propósito: ese id vive en el ledger DEL TEMPLATE, no
en este, así que citarlo aquí sería un fantasma. Lo cazó `check-finding-refs` al escribir esto.**

> ⚠️ **El Anillo 3 del template NO ejecuta** (f-787568d2 allí, id de aquel ledger): verificado el 2026-08-31 en el
> run 33420144900 — **0 steps**, con la anotación literal de GitHub *«The job was not started
> because an Actions budget is preventing further use»*. O sea que aquel fix **no** tiene
> verificación local en Linux; la única evidencia es la corrida de CI de ESTE repo
> (run 33351758651), que el reviewer de allí comprobó bajándose el log. Si vas a tocar el
> template, cuenta con que su backstop está mudo.

**5. La cola del `process-judge`: 3 sesiones** (`cat .agents/state/judge-queue.txt`). Su VERDICT la
vacía. Necesita permiso del owner para lanzar sub-agentes.

**6. Decisiones del owner que siguen pendientes del handoff anterior:** formalizar el revisor E2E
como sub-agente (`f-ea2aea2f`) y el gate de fidelidad de skills (`f-2ffc6d32`).

## Trampas NUEVAS de esta sesión

- **El cwd de la sesión y el repo del harness pueden no ser el mismo.** Ya explicado arriba, y es
  la primera trampa por una razón: envenena todo lo demás en silencio, porque los comandos
  *funcionan*, solo que sobre el árbol equivocado.
- **`git add X && git commit` en un comando lo bloquea el `reviewer-gate`**, y con razón: el gate
  corre antes del `add`. Stagea, revisa, commitea en comandos separados.
- **Un cambio solo de docs se exime solo** de los dos markers (`review-marker` y `verify-marker`
  lo dicen en su salida). No hace falta correr el reviewer para un PRD o el ledger.
- **Tocar `docs/process/lessons_learned.md` puede romper dos tests de presupuesto de contexto**
  (>250 líneas vivas, y «lecciones archivables sin rotar»). El remedio está prescrito:
  `bash tools/lessons-rotate.sh --apply`, que mueve al archivo histórico la lección cuyo detector
  ya es un test del Anillo 3. **Commitea los dos archivos juntos.**
- **El `verify-marker` se invalida en cuanto tocas algo staged**, incluido un comentario. Si el
  reviewer te da un AMBER y lo arreglas, hay que **re-correr `verify-run` y re-pedir veredicto**.
  Se puede continuar el mismo sub-agente con su contexto en vez de arrancar otro.
- **El `reviewer` también se deja cosas.** En esta sesión dio por barridas las afirmaciones sobre
  `timeout` y quedaban dos sitios vivos; y en el barrido de `@Inject` faltaba una cuarta fuente que
  apareció al arreglar. Pídele explícitamente que barra **la frase textual**, no solo la
  afirmación estructural, y compruébalo tú.
- **`check-prd-tree` compara TODOS los PRD menos los `Shipped`/`Deprecated`** (`check-prd-tree.sh`
  :177 — sin campo `Status` compara igual, fail-closed). Lo que exime a una línea **no es el estado
  del PRD sino el marcador `[SLICE-FUTURO]` en esa línea**. Consecuencia práctica: un Draft con
  todo su árbol marcado da `faltan=0` **sin haber comprobado nada**, y el número que te dice cuánto
  no se miró es `futuros=N`. Léelo siempre junto a `faltan`; el DoD de cada PRD exige `futuros=0`
  al cierre justo por esto.

## Cómo trabajar aquí — lo aprendido a golpes esta vez

- **Verifica el diseño que heredas, no lo copies.** `f-e008f6f` traía el diseño del detector ya
  escrito por el `process-judge`, y verificarlo —en vez de implementarlo— encontró que su primera
  fila habría puesto el gate **rojo sobre código correcto**. Lo mismo con el PRD 0004: leer el
  código encontró que el registro del `Router` se queda **sin consumidor**. Los dos bloqueantes
  salieron de verificar, ninguno de escribir.
- **Cuando una spec y el código divergen, cuenta las fuentes antes de decidir quién manda.**
  `AGENTS.md` §3 prescribía `@Inject`; decían lo contrario **cuatro** fuentes — dos skills de
  lectura obligatoria, el paquete y el código. Y §3 ganaba por precedencia declarada, así que el
  agente que hacía lo correcto recibía instrucciones contradictorias.
- **Corrige donde la afirmación TAMBIÉN vive, y demuéstralo con el `grep`.** Resolver una OQ dejó
  ocho frases del PRD 0003 diciendo que seguía abierta. Un documento que se contradice a sí mismo
  es peor que el problema original.
- **Cuando corrijas un finding tuyo, corrige el diagnóstico, no solo el remedio.** `f-da257e0c`
  decía «tres fuentes contra una» y eran cuatro. La resolución lo dice.
- **Un registro sin consumidor no se testea: se borra.** Escribirle el test fijaría mecánicamente
  que existe una pieza que no hace nada — un gate protegiendo código muerto.
- **Cierra los findings que ya están resueltos.** `f-a3b6dafc` (high) llevaba abierto desde el 29
  con el trabajo hecho: siete símbolos que contaba en cero estaban en 7/5/15/6/9/5/4. Un ledger con
  findings resueltos abiertos es un ledger que nadie relee.
- **El pre-push tarda ~4,5 min** (la suite del harness) y **CI otros ~4**. Cuenta con ~10 minutos
  entre «commiteo» y «sé que está bien».

## Findings: consulta el número vivo con el comando

`bash tools/findings/findings.sh list --status open` — **38 abiertos** al cierre del 2026-08-31
(6 high, 19 medium, 13 low). El conteo escrito a mano caduca solo, y el del hook es del otro repo.

> **Patrón que apareció al agruparlos por coste, y que conviene repetir:** cuatro findings estaban
> **resueltos y nadie los había cerrado** — `f-a3b6dafc`, `f-d4b58c90`, `f-694c2009` y
> `f-b6c162d8`. Un ledger que solo crece deja de servir para priorizar, que es para lo que se usa.
> Antes de planificar sobre la cifra, vale la pena una pasada preguntando a cada finding «¿esto
> sigue siendo cierto?» — es barata y aquí devolvió un 10%.

Cerrados en esta sesión (6): `f-804ebee0` (Anillo 3, con la evidencia del run), `f-da257e0c`
(`AGENTS.md` §3), `f-a3b6dafc` (las skills), y los tres del párrafo de arriba. **`f-b6c162d8` se
cerró con alcance acotado y merece leerse**: su propuesta pedía tres cosas y solo una se
entregó — la dirección inversa se **midió antes de descartarla** (168 de 263 archivos sin
declarar, ~64% de FP, seis veces el techo de §14.2) y la convención de etiquetas se sustituyó por
el marcador `[SLICE-FUTURO]`. Lo que sigue sin cubrir, escrito en su resolución: **el archivo
entregado que nadie planeó**.

Abiertos en esta sesión: `f-3b30fcf4` (la clase de las bifurcaciones por entorno, con dos
instancias vivas) y `f-a655520c` (el PRD 0001 se contradice consigo mismo sobre dónde van
`overview`/`releaseDate`, y su árbol coloca `MoviesModule` donde `layers.conf` lo rechaza).

## Contexto entre repos

- **agentic-workflow-template** (`../agentic-workflow-template`): remote `template`. **Le debemos
  el fix de `check-ring3`** y las dos instancias de `f-3b30fcf4`. El `upgrade.sh` sigue teniendo
  el re-conflicto conocido en `tools/tests/README.md` (resolución: `git checkout --ours`).
- **spm-pro** (`../spm-pro`): monorepo de los dos SPM. `f-8ab6c2ad` (`CoordinatorView` sin tests) y
  `f-8720114e` (el README de AppFoundation enseña el anti-patrón) son suyos.
- **El token de TMDB es de dev y el owner aceptó el riesgo** (`f-7c57fa35`, accepted).

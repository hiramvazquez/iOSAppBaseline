# El bucle de verificación — cómo confiar en código que no escribió un humano

> La pregunta que responde este documento: **¿qué tiene que ser cierto para que
> podamos dar por bueno un cambio hecho por un agente sin que un humano lo lea entero?**
>
> La respuesta corta: que exista una cadena de evidencia mecánica, y que ningún
> eslabón de esa cadena lo produzca el mismo que escribió el código.

---

## Los dos principios

### 1. Cázalo en la capa más barata

Cada nivel que un defecto sube sin ser detectado multiplica ~10× el coste de arreglarlo.
Un error que el compilador podía haber cazado y que llega a un juez de IA no es un
error del agente: **es un fallo de diseño del harness.**

Corolario práctico: antes de añadir un gate nuevo, pregúntate si el nivel de abajo
podía haberlo cazado. Casi siempre podía.

### 2. El que escribe nunca es el que aprueba, y "aprobar" es presentar evidencia

Un veredicto es la salida de un comando, un exit code o un score. **Nunca** una
afirmación del modelo. Si el único artefacto de una revisión es texto que dice
"revisado, todo bien", no ha habido revisión: ha habido narración.

Esto es lo que separa este harness de un `CLAUDE.md` con buenas intenciones.

---

## La pirámide

```
 coste ↑    9  Métricas + lección→detector      escape rate, ratchets, postmortems
   de       8  Gate por evidencia                /goal, Stop hook, marker ↔ hash del diff
detección   7  Review adversarial de IA          contexto fresco, N jueces, prompt a REFUTAR
   ↑        6  Arquitectura                      imports directos + adapters medidos
   │        5  Contratos                          fake ≡ real, consumer-driven (Pact)
   │        4  CALIDAD del test                   mutation score, property-based
   │        3  Spec ejecutable                    TDD red-first, aserciones / DbC
   │        2  Patrón semántico                   Semgrep (AST, no texto)
   │        1  Determinista in-loop               formatter, lint, typecheck
 barato     0  Imposibilitar                      tipos, -Werror, exhaustividad
```

---

## Nivel 0 — Hacer el error imposible

> *Make illegal states unrepresentable.*

Tipos fuertes, null-safety, exhaustividad de `enum`, inmutabilidad por defecto,
`-Werror` / strict mode / strict concurrency.

**El compilador es el primer reviewer y el único que nunca se cansa.** Es el nivel de
mayor apalancamiento que existe y el más ignorado: un agente que no *puede expresar*
el estado inválido no lo escribe. Ninguna cantidad de review compensa una API donde
el mal uso compila.

Antes de escribir un detector para un error, pregúntate si puedes rediseñar el tipo
para que ese error no exista.

**En el harness:** `<!-- FILL -->` en `AGENTS.md §2` — activa el modo estricto de tu stack.

## Nivel 1 — Verificación determinista in-loop

Formatter, linter y typecheck **del archivo que se acaba de tocar**, con el resultado
de vuelta al agente en el mismo turno.

Es el gate de mayor ROI del harness. Sin él, un error del turno 3 se descubre en el
turno 40, con 37 turnos construidos encima y el contexto ya contaminado por trabajo
basado en una premisa falsa.

**En el harness:** `scripts/agent-hooks/post-edit-verify.sh` (`PostToolUse` → `additionalContext`).
Nunca bloquea: informar en el momento correcto ya es la mitad del trabajo.

## Nivel 2 — Patrones semánticos (AST, no texto)

**La ley del 10%:** Google midió que un analizador con más de ~10% de falsos positivos
es descartado sistemáticamente por los desarrolladores. Con agentes es peor: además de
ignorarlo, **aprenden a evadirlo**.

Por eso los detectores viven en Semgrep y no en `grep`. Un `grep -E '(==) *"[^"]+"'`
matchea el comentario que documenta el anti-patrón, el string de un test y el propio
doc. Un patrón de Semgrep matchea el nodo real del árbol sintáctico.

**En el harness:** `tools/semgrep/rules/*.yaml` + `tools/semgrep-scan.sh`.
Escala industrial de referencia: Tricorder corre 110 analizadores sobre >50.000 changes
al día en Google; Infer prueba la ausencia de null-deref y data races en Meta.

## Nivel 3 — La spec ejecutable: TDD + Design by Contract

**TDD red-first** (`AGENTS.md §5`) convierte la intención en algo comprobable *antes*
de que exista la implementación. Con agentes tiene un efecto extra: obliga a definir
el comportamiento esperado antes de que el modelo elija una implementación y luego
escriba tests que la describan.

**Aserciones / Design by Contract** es el complemento menos usado y más transferible.
Las reglas *Power of Ten* de NASA/JPL son una referencia para software crítico. En un template
multi-stack no se convierten en una cuota universal; se conserva su intención:

- expresar cada precondición e invariante real, sin aserciones decorativas
- aserciones **sin efectos secundarios**, tests booleanos
- input recuperable → tipo/error explícito; aserción → error de programación visible
- verificar **todo** valor de retorno · bucles con cota fija · scope mínimo
- compilar con todos los warnings activos y **cero** warnings

**Por qué importa tanto con agentes:** un agente que escribe aserciones produce código
que **falla ruidosamente en vez de silenciosamente**, y deja una especificación
verificable por máquina para el siguiente agente. Es la forma más barata que existe de
convertir intención en algo comprobable.

`AGENTS.md §6` exige fail-closed en authn/authz/cripto y fallos visibles en
observabilidad. Las aserciones ayudan a hacer visibles invariantes rotos; no sustituyen una
decisión de autorización segura ni una recuperación explícita.

## Nivel 4 — La calidad del test (no su existencia)

**Este es el nivel que más importa con código escrito por IA.**

La cobertura es un piso, no una meta: un test sin aserciones da 100% de cobertura y 0
de valor. La métrica real es el **mutation score** — se inyectan fallos en el código y
se mide qué porcentaje matan los tests.

> La función objetivo de un agente es *"que los tests pasen"*, y la forma más barata
> de conseguirlo es escribir tests que no comprueban nada. El mutation score es el
> único gate que distingue un test que verifica de uno que solo pasa.

**Property-based testing**: en vez de ejemplos, declaras invariantes y la herramienta
busca contraejemplos y los minimiza. La evidencia empírica es contundente — un test
property-based mata en torno a **50× más mutantes** que un test unitario promedio. Y
los agentes son mucho mejores generando propiedades que generando casos de ejemplo
interesantes.

**En el harness:** `tools/mutation-score.sh` + `tools/mutation-ratchet.json` (piso que
**solo sube**). Runners por stack: muter · PIT · Stryker · mutmut.

## Nivel 5 — Contratos

**La regla del fake:** *toda implementación fake debe pasar exactamente la misma suite
de conformidad que el adapter real.* Elimina de raíz la categoría de bug más frustrante
del testing con puertos: los tests pasan con el fake y explota en producción.

Es barato, no necesita herramientas nuevas, y encaja directo con los puertos de
repositorio de `domain/SKILL.md`.

**Consumer-driven contracts (Pact)** para fronteras entre servicios: el consumidor
declara qué necesita, y un cambio del proveedor que rompe a un consumidor **falla la
promoción**, sin levantar el sistema entero.

## Nivel 6 — Arquitectura como fitness function

Las reglas de capas son un contrato ejecutable, no un estilo. El baseline portable
verifica **dirección de imports directos**. Ciclos y complejidad requieren herramientas
específicas del stack y solo cuentan cuando su adapter está configurado y operativo.

`AGENTS.md §3` — *"el dominio no depende de UI ni de infraestructura"* — **es** una
fitness function. El harness aplica esa dirección al import directo mediante reglas
explícitas; no infiere transitividad ni afirma detectar ciclos a partir de ese check.

**En el harness:** `tools/check-layers.sh` + `tools/layers.conf` cubren imports directos;
`tools/architecture-check.sh` clasifica los adapters opt-in de ciclos y complejidad como
`operational|unsupported|missing|broken`. Ausencia de adapter no equivale a arquitectura
limpia. Equivalentes de la industria: ArchUnit, NetArchTest, JDepend.

## Nivel 7 — Review adversarial de IA

Tres condiciones para que una review de IA valga algo:

1. **Contexto fresco.** El revisor ve el diff, no el razonamiento que lo produjo.
   Un modelo que revisa su propio trabajo está sesgado hacia el enfoque que eligió.
2. **Prompt a REFUTAR, no a validar.** "Encuentra lo que está mal" produce hallazgos
   reales; "¿está bien esto?" produce confirmación.
3. **Independencia real.** Para cambios de alto riesgo, N jueces con *lentes distintas*
   (corrección / seguridad / ¿reproduce?) y decisión por mayoría. Lentes diversas
   cazan modos de fallo que la redundancia no.

⚠️ **El sesgo del revisor:** un revisor al que le pides hallazgos casi siempre reporta
alguno, aunque el trabajo esté bien, porque es lo que le pediste. Perseguir todo
hallazgo lleva a sobre-ingeniería: capas de abstracción de más, código defensivo y
tests de casos imposibles. Instruye al revisor a reportar solo lo que afecta a la
corrección o a una regla explícita del proyecto.

**En el harness:** sub-agentes `reviewer` / `security-reviewer` / `design-reviewer`
(contextos separados) · plugin `security-guidance` (3 capas automáticas) ·
`ci/ai-review.sh` (headless, cubre Codex y humanos).

## Nivel 8 — El gate por evidencia

Aquí es donde la cadena deja de depender de la palabra del modelo.

- **El marker de review lo escribe el sistema**, derivándolo del veredicto real del
  sub-agente (`SubagentStop` → `capture-review-verdict.sh`). Antes lo escribía un script
  que el modelo invocaba: el gate era decorativo.
- **El marker está ligado al `sha256` del diff staged**, no solo al tiempo. Lo que se
  revisó tiene que ser exactamente lo que se commitea.
- **Los ratchets no son editables a mano** (`permissions.deny` sobre los `*-ratchet.json`).
  Un número que se puede aflojar no es un trinquete: es una sugerencia.
- **`/goal`** cierra el bucle en runs autónomos: fijas una condición verificable y un
  modelo evaluador **independiente** la comprueba tras cada turno. Quien decide que el
  trabajo terminó no es quien lo hizo.

```
/goal los tests de test/auth pasan, `bash tools/check-drift.sh` da errors=0,
      y el reviewer emitió VERDICT: GREEN. Prueba cada punto con su salida real.
      O detente tras 20 turnos.
```

### El límite honesto de este nivel

Todo lo anterior defiende contra **error de proceso**: olvidos, atajos, reglas perdidas al
compactar. No defiende contra **intención**. Un agente con acceso a shell puede escribir el
archivo de marker a mano — la verificación mira su contenido, no su procedencia. En una máquina
de un solo usuario, un agente con Bash puede hacer lo que puede hacer el usuario, y no hay
arreglo limpio dentro de esta arquitectura (una firma HMAC no ayuda: el secreto tiene que ser
legible por el hook, que corre en el mismo entorno).

**Por eso el Anillo 3 no es redundante.** En CI el marker local no viaja y la review corre en
una máquina que el agente no controla. Un harness de un solo anillo confunde "el agente no se
equivocará" con "el agente no podrá". Son garantías distintas y necesitan mecanismos distintos.

Al diseñar un gate, declara explícitamente cuál de las dos das. Decir "infalsificable" cuando
solo tienes la primera es el mismo fallo que anunciar un gate que no está implementado (§G5):
falsa confianza, que es un modo de fallo, no un estado neutro.

### La lista de garantías se ata a su demostración

Un PRD que enumera escenarios ("golden 1–10 pasan") y una suite que los prueba son dos
documentos, y lo único que suele atarlos es que alguien lea los dos. Entonces la lista crece y
la demostración no: la casilla de "Done" sigue verde y ya no significa nada.

La regla es la misma del campo `Detector:` de las lecciones, un nivel más arriba: **la
enumeración es la fuente y algo mecánico la persigue.** En el harness lo hace
`tools/tests/test_e2e_plataformas_y_vinculo.sh` — un `test_golden_NN_…` por escenario del PRD (repartidos en los `test_e2e_*.sh`), y un test que
lee la lista del propio PRD y falla si aparece un escenario sin su test. Cuesta veinte líneas y
convierte una afirmación de la DoD en un hecho comprobable.

Corolario para las capacidades: un adapter que **declara** `read_only` no demuestra nada — la
declaración sale de su propio `case`. Lo que se prueba es el efecto observable (para un CLI, el
argv con el que se le invocó). "Instalado ≠ operativo" y "declarado ≠ demostrado" son el mismo
error en dos capas distintas.

## Nivel 9 — Métricas y el bucle de aprendizaje

**Escape rate / phase containment** — qué fracción de defectos se cazó en cada fase.
Es la única evidencia real de que se puede bajar la revisión humana. Un escape rate
plano significa que estás añadiendo ceremonia, no calidad.
→ `tools/metrics/escape-rate.sh`

**Change failure rate** (DORA) — % de despliegues que causan un fallo. Elite: 0-15%.

**Y la regla que hace que todo esto compuesto funcione:**

> ### Todo comentario de review que se repite es un bug en tu tooling.

Es la filosofía de Tricorder. El feedback recurrente de review se convierte en un
analizador. Sin este paso, las lecciones son prosa que nadie relee; con él, cada error
cometido una vez se vuelve mecánicamente imposible la segunda.

→ `tools/lesson-detector-link.sh` lo verifica: toda entrada de `lessons_learned.md`
cita un detector, o declara `n/a-manual` con su razón.

---

## Qué queda fuera (a propósito)

No están en el harness por defecto, pero son los escalones siguientes cuando el
riesgo lo justifique:

| Técnica | Cuándo vale la pena |
|---|---|
| **Fuzzing coverage-guided** | Parsers y cualquier frontera de input no confiable |
| **Simulación determinista** | Lógica concurrente o distribuida; permite reproducir un fallo exacto |
| **Fault injection / chaos** | Sistemas con dependencias que fallan de verdad |
| **Métodos formales** | El 1% crítico. AWS: TLA+/P para protocolos, bounded model checking para memory safety, Dafny para authz y cripto |

La lección de la práctica de AWS no es *"usa TLA+"*. Es: **para cada riesgo, elige la
técnica más barata que dé una garantía tipo-prueba.** Métodos formales donde el coste
de fallar es catastrófico; aserciones y property-based para todo lo demás.

---

## Cómo usar esto al revisar un cambio

Antes de dar por bueno un cambio de un agente, recorre la pirámide hacia abajo y
pregunta **en qué nivel se habría cazado cada riesgo**:

1. ¿Se podía haber hecho imposible con un tipo? (nivel 0)
2. ¿Lo caza el linter/typecheck? (nivel 1)
3. ¿Hay un patrón de Semgrep que lo cubra? (nivel 2)
4. ¿Los tests **fallan** si rompo la lógica que dicen cubrir? (niveles 3-4)
5. ¿El fake pasa la misma suite que el real? (nivel 5)
6. ¿Respeta la dirección de imports directos y qué evidencia reportan los adapters de
   ciclos/complejidad? (nivel 6)
7. ¿Lo revisó algo con contexto fresco? (nivel 7)
8. ¿La evidencia es una salida de comando o una afirmación? (nivel 8)
9. Si algo se escapó: **¿qué detector lo habría cazado, y ya existe?** (nivel 9)

La pregunta 9 es la que hace que el sistema mejore. Las otras ocho solo lo mantienen.

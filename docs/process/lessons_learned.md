# Lecciones aprendidas — no repetir

> **Antes de escribir código, lee solo hasta “Lecciones mecanizadas (índice)”.** Esa es la parte
> viva cuya regla aún depende de contexto. El índice y `lessons_archive.md` se consultan bajo
> demanda; no se cargan por defecto. Si cazas un patrón nuevo, agrégalo en el mismo cambio.

## Cómo usar este doc

- Cada entrada viva contiene un error real, la regla y el detector que lo previene.
- Una lección respaldada por un test del Anillo 3 se archiva; una manual o parcial permanece aquí.
- Las reglas duras destiladas viven en `AGENTS.md`.

### ⚠️ El campo `Detector:` es OBLIGATORIO y está verificado

`tools/lesson-detector-link.sh` (Anillo 3) **falla** si una entrada no lo tiene.

Una lección sin detector es prosa que se pierde al compactar. El ciclo obligatorio es:

```
error cometido → lección escrita → detector mecánico → error IMPOSIBLE de repetir
```

Prioridad: Semgrep AST → límites de capas → patrones de seguridad → guard barato → test de
comportamiento. Si el juicio no es mecanizable, decláralo sin fingir cobertura:

```
- **Detector:** n/a-manual — <por qué no se puede automatizar>
```

## Lecciones vivas

### [2026-08-28] Renombrar una carpeta apagó una regla de capa, y el gate siguió en verde
- **Qué pasó:** al resolver OQ-4 se movió `Sources/UI/Movies/` → `Sources/Features/Movies/`. La regla de `layers.conf` «la UI no habla HTTP» estaba escrita como glob `*/UI/*`, así que dejó de casar con ningún archivo. Un `import CoreNetworking` bajo la ruta nueva pasaba con `LAYERS_SUMMARY errors=0`. La regla no falló: dejó de existir, en silencio.
- **Causa raíz:** el aislamiento de capas de este proyecto es **convención de rutas + un glob**, no tipos ni targets separados. Un glob es un acoplamiento invisible entre la estructura de carpetas y el gate: mover la carpeta rompe el gate sin tocar el gate. Y `check-layers.sh` solo sabe responder «¿alguien importa lo que no debe?», nunca «¿alguna regla dejó de mirar?».
- **Regla:** mover o renombrar cualquier carpeta bajo `Sources/` obliga a revisar **todo conf que enrute por globs de ruta, en el mismo commit** — `tools/layers.conf`, `tools/skill-matrix.conf` y los `paths` de las reglas Semgrep. Acotarla a `layers.conf` fue justo el error: el mismo día en que se escribió esta lección, el sweep se hizo en `layers.conf` y no en `skill-matrix.conf`, y el archivo que lee la credencial de TMDB quedó sin exigir `security/SKILL.md` (4ª pasada del design-review, B-4). La regla viaja con la estructura, o la estructura se lleva el gate por delante. Y una regla que no casa con nada **se borra**, no se conserva «como red para código heredado» — eso es un gate apagado con buena conciencia.
- **Detector:** `tools/check-layers-coverage.sh` — falla (exit 1) si alguna regla propia de `layers.conf` no casa con ningún archivo, y sale **3** si no encuentra el marcador del bloque (no pude mirar ≠ todo correcto: era su propio modo de fallo). Verificado con prueba de fuego en los tres escenarios. **Cobertura parcial declarada:** hoy solo vigila `layers.conf`; para `skill-matrix.conf` y los `paths` de Semgrep la regla es manual — extender el detector a esos confs está en el ledger.
- **Área:** `tools/layers.conf` · `Sources/**`

### [2026-08-28] Un identificador de garantía se recicló, y el contrato divergió sin que nadie lo viera
- **Qué pasó:** el PRD 0001 definía `C1` como «la página devuelta es la pedida» y `C2` como «`nextPage` es `p+1`». El código publicado usaba las mismas etiquetas para cosas distintas: `C1` = «nunca devuelve `nil`», `C2` = «los ids son únicos». Dos significados vivos con el mismo nombre. Al arreglarlo en §6.3 se dejó §9b publicando todavía los viejos: la regla nueva quedó violada dentro del mismo documento, 300 líneas más abajo, en la sección que el implementador copia.
- **Causa raíz:** un identificador de contrato es lo único estable que tienen las citas cruzadas. Cuando cambia de significado en vez de retirarse, cada cita que lo menciona pasa a mentir, y no hay forma de saber cuál se refiere a qué versión.
- **Regla:** un id de garantía (`C-n`, `T-x-n`) es **inmutable**. Cuando una garantía cambia de significado se **retira** y se numera una nueva; nunca se recicla la etiqueta. Y la regla aplica a **toda cita del documento**, no solo a la sección donde se descubrió: un arreglo escrito como recuadro en el punto del hallazgo, sin propagar, deja el documento contradiciéndose a sí mismo — que es peor que el hallazgo original.
- **Detector:** n/a-manual — lo aplica el checklist del `design-reviewer` (gate del CÓMO, §12), que fue quien lo cazó en dos pasadas consecutivas. Un detector por grep necesitaría entender qué significa cada id en cada sección, y contar etiquetas sin parsear su semántica produciría ruido; un detector ruidoso se descarta entero (§14.2).
- **Área:** `docs/process/prds/**`

## Plantilla de entrada

```
### [AAAA-MM-DD] <título corto del error>
- **Qué pasó:** <síntoma observable>
- **Causa raíz:** <por qué>
- **Regla:** <qué hacer/no hacer a partir de ahora>
- **Detector:** <ruta del check que lo previene, o `n/a-manual — razón`>
- **Área:** <path o módulo>
```

## Lecciones del harness

> Estas seis salieron de construir el propio harness (PRD 0001 §18). Se dejan en el template
> porque son **universales**: le pasan a cualquiera que monte gates para agentes. Bórralas si
> montas otro sistema; consérvalas si usas este.

### [2026-08-05] Un gate anunciado pero no implementado (peor que ausente)
- **Qué pasó:** `canon-enforce.sh` estaba enteramente comentado mientras el `SessionStart` lo
  anunciaba como guardrail activo. Nadie lo habría notado: un gate que nunca dispara y uno que
  no existe se ven exactamente igual desde fuera.
- **Regla:** el health-check debe reportar lo que **NO** cubre, no solo lo que sí. La falsa
  confianza es un modo de fallo, no un estado neutro.
- **Detector:** `scripts/agent-hooks/session-start.sh` declara qué niveles de la pirámide están
  MUDOS en cada arranque
- **Área:** scripts/agent-hooks/canon-enforce.sh

### [2026-08-05] Arreglar un hallazgo introdujo uno peor
- **Qué pasó:** las cuatro rondas de review sobre este PRD produjeron una cadena: el reviewer
  señaló que semgrep no bloqueaba en local → lo arreglé → creé el deadlock de la lección
  anterior. Y antes: hice que un trinquete corrupto degradara a 0 → eso convirtió corromper el
  archivo en una forma de desactivar el gate → hubo que revertirlo, test incluido.
- **Regla:** **una corrección es un cambio, y merece el mismo escrutinio que el código original.**
  La tentación es tratarla como "solo el fix", saltarse el análisis de impacto y no escribir su
  test. En un bucle de review con agentes esto es especialmente peligroso, porque la presión por
  cerrar el hallazgo empuja al arreglo apresurado. Corolario práctico: cuando un fix cambia el
  comportamiento que un test ya fijaba, **revisa si el test codificaba una decisión, no un hecho**
  — si es lo primero, cambia ambos y explica por qué en el propio test.
- **Detector:** n/a-manual — es disciplina de proceso. La red mecánica que sí existe: `canon-enforce`
  CHECK 4 exige que los tests del harness pasen si el turno tocó los gates, y cada corrección de
  esta serie entró con su test de regresión.
- **Área:** proceso

### [2026-08-05] Confundimos "el agente no se equivocará" con "el agente no podrá"
- **Qué pasó:** el README y el PRD describían el marker de review como **infalsificable**. El
  sub-agente `reviewer`, revisando el commit que introducía el mecanismo, lo desmintió con un
  repro ejecutable: escribió el archivo de marker a mano con `source: hook` y el gate lo aceptó.
- **Causa raíz:** `check-review-marker.sh` valida el **contenido** del marker, no su
  **procedencia**. En una máquina de un solo usuario, un agente con Bash puede hacer lo que
  puede hacer el usuario. Una firma HMAC no arregla nada: el secreto tiene que ser legible por
  el hook, que corre en el mismo entorno.
- **Regla:** al diseñar un gate, **declara cuál de las dos garantías das**: ¿defiende contra
  *error de proceso* (olvidos, atajos, reglas perdidas al compactar) o contra *intención*?
  Casi siempre es la primera, y está bien — pero anunciar la segunda es falsa confianza, el
  mismo modo de fallo que un gate no implementado. La defensa contra intención es el **Anillo 3**:
  en CI el marker no viaja y la review corre en una máquina que el agente no controla. Por eso
  un harness de un solo anillo no basta.
- **Detector:** n/a-manual — es una propiedad del modelo de amenaza, no un patrón de código. La
  mitigación es documental (README §"Qué garantiza y qué no", `verification-loop.md` nivel 8,
  cabecera de `capture-review-verdict.sh`) + f-marker-spoof (del template) como owner-decision en el ledger.
- **Área:** tools/check-review-marker.sh

### [2026-08-05] Observar un script lo modificó
- **Qué pasó:** ejecutar `session-start.sh` para *verificar su salida* borró los markers de
  skills leídas a mitad de sesión, y el siguiente Edit quedó bloqueado.
- **Causa raíz:** el script mezcla "informar" con "resetear estado".
- **Regla:** un script que un humano va a ejecutar para inspeccionar debe tener un modo **sin
  efectos secundarios**. Si no lo tiene, observarlo lo altera.
- **Detector:** n/a-manual — el fix (separar `--report` de `--reset`) requiere decisión del
  owner y quedó fuera del scope del PRD 0001 (§8). Registrado en §18 G6.
- **Área:** scripts/agent-hooks/session-start.sh

### [2026-08-08] "Puro" era ambiguo: el agente revirtió el default de concurrencia del target entero
- **Qué pasó:** en el primer proyecto real, el agente detectó `SWIFT_DEFAULT_ACTOR_ISOLATION
  = MainActor` (default Xcode 26) y, leyendo "Logic puro" en la skill de arquitectura, cambió
  el default del TARGET a `nonisolated` — revirtiendo el Approachable Concurrency que la skill
  del lenguaje manda, y creando drift spec↔código desde el día cero. Informó, pero no esperó.
- **Causa raíz:** dos docs internos en tensión aparente ("MainActor por defecto" vs "Logic
  puro") + un término ambiguo ("puro") sin definición operativa. Ante el conflicto, el agente
  eligió en vez de preguntar.
- **Regla:** "puro" = puro en DEPENDENCIAS, no en aislamiento (definido ya en ambas skills);
  los defaults de build del target son decisión de OWNER; y conflicto entre docs internos =
  Open Question, jamás elección unilateral (§1.4).
- **Detector:** n/a-manual — es juicio de diseño; la prevención real es la definición
  operativa añadida a `swift-estado-del-arte.md` y `platforms/ios.md`, y el ítem del
  design-reviewer sobre decisiones de build settings.
- **Área:** .agents/skills/architecture/ · settings del target

### [2026-08-08] El doc que enseña el simulacro de secretos CONTENÍA el secreto del simulacro
- **Qué pasó:** primer commit del harness sobre un proyecto real → gitleaks bloqueó: 1 leak.
  Era `docs/ADOPTION.md` §7 — el ejemplo del "commit de prueba" traía un AWS key de formato
  real y contiguo. En el template nunca mordió porque su primer commit entró SIN el Anillo 1
  (hecho desde un entorno sin lefthook) y los diffs posteriores no tocaban esa línea: el gate
  solo ve deltas, y la adopción en un proyecto nuevo stagea TODO → primer escaneo completo.
- **Causa raíz:** doble — un doc con un patrón de secreto contiguo (contra la doctrina del
  propio `.gitleaks.toml`: "formatos obviamente inválidos o allowlist por PATH"), y la
  ceguera de "el gate solo ve deltas": lo que entra sin escanear queda invisible hasta que
  alguien lo re-stagea entero.
- **Regla:** los strings de simulacro en docs se CONSTRUYEN en runtime (`printf 'AKIA%s'
  RESTO`) — el doc nunca contiene el patrón contiguo, el archivo del drill sí. Y tras montar
  el Anillo 1 en un repo con historia, corre un escaneo COMPLETO una vez
  (`gitleaks detect --source .`), no confíes en que los deltas te cubren lo viejo.
- **Detector:** .gitleaks.toml — el propio scan del Anillo 1 sobre el staging completo (así
  se cazó); el drill de ADOPTION §7 verifica que sigue vivo.
- **Área:** docs/ADOPTION.md · flujo de adopción

### [2026-08-09] El harness solo sabía crecer: ningún mecanismo preguntaba si algo ya sobraba
- **Qué pasó:** auditando el template salió que todos sus mecanismos son monótonos crecientes.
  Cada error añade un detector, cada lección un test, cada incidente un anillo; los trinquetes
  tienen dirección fija; las lecciones se acumulaban sin caducar. No existía ningún momento del
  proceso en el que se preguntara si una defensa sigue haciendo falta.
- **Causa raíz:** se optimizó por no perder cobertura y nunca por el coste de mantenerla. Pero
  la ceremonia no es neutra: cobra tiempo de gate, tokens de contexto y fricción, y es
  exactamente lo que lleva a un equipo a desactivar el harness entero. Un gate que existía
  para un error que el modelo ya no comete es peaje puro.
- **Regla:** revisar periódicamente (mensual, no diario) qué componentes siguen siendo
  *load-bearing*. Y el matiz sin el cual el informe miente: **cero detecciones es ambiguo** —
  puede ser disuasión perfecta o gate mudo, y los datos no los distinguen. Lo desempata el
  `--selftest`: cero eventos + selftest verde = disuasión, se queda; cero eventos + sin
  selftest = nadie ha demostrado nunca que ese gate vea. Retirar es decisión del owner (§8);
  la herramienta solo hace la pregunta respondible con datos en vez de con intuición.
  Corolario simétrico: un gate que dispara CONSTANTEMENTE tampoco está bien — pide que la capa
  de arriba haga imposible ese error (§14.1).
- **Detector:** tools/metrics/gate-value.sh (ritual mensual; sale en el harness-report §5c, que
  es la superficie que el humano sí lee — una métrica que hay que recordar correr no se corre)
- **Área:** tools/metrics/ · docs/process/ · ritual de mantenimiento

### [2026-08-09] Un test verde en Linux y rojo en macOS: dependía de los PERMISOS del archivo que sobrescribía
- **Qué pasó:** cinco tests de `test_ratchets.sh` fallaban en la máquina del owner (macOS) y
  pasaban en el contenedor (Linux), con `Permission denied` **al escribir el stub**, no al
  ejecutarlo. Los tests hacían `printf '...' > tools/drift-ratchet.sh` sobre el archivo que el
  sandbox había COPIADO del repo: una redirección sobre un archivo existente hereda su modo y
  sus flags, y esos archivos habían llegado al repo por un canal que los dejó en modo 700.
- **Causa raíz:** el test dependía de una propiedad del entorno que nadie había declarado — los
  permisos del archivo copiado. Verde o rojo según la máquina es la peor clase de fallo: no
  señala un defecto real y erosiona la confianza en la suite entera, que es justo lo que hace
  que alguien acabe ignorando un rojo legítimo.
- **Regla:** un stub se **crea limpio**, nunca se sobrescribe: `rm -f` + escribir + `chmod +x`.
  Está en el helper `stub` de `run-tests.sh` para que no haya que recordarlo. Y la regla
  general: si el resultado de un test depende de algo que el test no creó, ese algo es una
  entrada no declarada. Corolario del helper: usa `printf '%b'`, no `'%s'` — con `%s` los `\n`
  se escriben literales y el stub "funciona" de formas absurdas.
- **Detector:** tools/tests/run-tests.sh (helper `stub`, usado por los 28 stubs de la suite) +
  la propia suite corriendo en el Anillo 3 de este proyecto
  (`.github/workflows/gates.yml`, job `gates` en Linux) más el pre-push local
- **Área:** tools/tests/

### [2026-08-09] La guía de adopción decía dos cosas incompatibles sobre el mismo flujo
- **Qué pasó:** `ADOPTION.md` §1 mandaba `rm -rf .git && git init` —que corta el parentesco con
  el template— y §9b prometía que el upgrade sería "un merge de 3 vías normal", que necesita
  justo ese parentesco. Un adoptante seguía el paso 1 al pie de la letra y se quedaba con un
  camino de actualización imposible.
- **Causa raíz:** las dos secciones se escribieron en momentos distintos y nadie leyó el
  documento como lo lee un adoptante: de principio a fin y haciendo lo que dice. Arreglar la
  HERRAMIENTA (el modo sync de `upgrade.sh`) no arregló el DOCUMENTO — y el documento es lo que
  la gente ejecuta.
- **Regla:** cuando un flujo tiene dos caminos posibles, la doc los nombra **los dos**, dice a
  cuál pertenece el lector y qué implica cada uno más adelante. Y al arreglar una herramienta
  por un caso de uso, se revisa qué documento prometía otra cosa sobre ese mismo caso.
- **Detector:** n/a-manual — es coherencia de prosa entre secciones, no un patrón mecanizable
  (un grep produciría ruido). La red real: `tools/tests/test_upgrade.sh` fija que AMBAS
  topologías funcionan, así que el documento puede describirlas sin mentir.
- **Área:** docs/ADOPTION.md §1 y §9b

### [2026-08-09] Un test que se cuelga es peor que un test que falla
- **Qué pasó:** al inyectar un mutante en el guard de reentrada de un ViewModel, el test entró
  en deadlock y **colgó la suite** en vez de fallarla. Hubo que repetir con
  `-test-timeouts-enabled YES`. En CI eso habría consumido el job entero sin decir nada.
- **Causa raíz:** el runner asumía que un test termina. Un rojo te dice qué pasa en segundos;
  un cuelgue no dice nada durante una hora, y encima parece "está trabajando".
- **Regla:** todo runner de tests impone un límite por test. En el harness lo hace un perro
  guardián en segundo plano (`_run_test` en `run-tests.sh`), no `timeout`: los tests son
  FUNCIONES de shell y `timeout` solo ejecuta binarios. Y ojo al detalle que colgó el primer
  intento — los hijos en background deben ir con stdout DESATADO del pipe del llamador, o la
  sustitución de comandos espera al perro guardián y el mecanismo anti-cuelgue cuelga la suite.
  En proyectos Swift: `-test-timeouts-enabled YES` en el comando de tests de AGENTS.md §2.
- **Detector:** tools/tests/run-tests.sh (`_run_test`, verificado con un test que duerme más
  que el límite: devuelve 124 y explica que se colgó)
- **Área:** tools/tests/run-tests.sh · AGENTS.md §2

### [2026-08-24] Una review acotada vale lo que valga la afirmación que la acota
- **Qué pasó:** tras una ronda AMBER cuyo único hallazgo se atendió tocando solo el ledger, se pidió
  una re-review "acotada", diciéndole al reviewer que *el delta desde entonces es solo el ledger*.
  Él miró `git diff --cached`, vio 15 archivos y 882 líneas, y **se negó a revisar**: desde su
  contexto en frío no podía distinguir "el diff staged completo" de "lo que cambió desde la ronda
  anterior", y concluyó —razonablemente— que la premisa era falsa.
- **Causa raíz:** el prompt era ambiguo entre dos sentidos de "delta", y el sub-agente arranca sin
  el historial que los desambigua. Pedir una review acotada es pedirle a alguien que confíe en un
  recorte que no puede verificar. Si la afirmación que acota es falsa —o solo suena falsa—, lo que
  sale no es una review parcial: es una review que no ocurrió.
- **Regla:** no acotes una review con una afirmación sobre lo que cambió. O le das el objeto
  completo, o le das **el medio para verificar el recorte por sí mismo** (el sha de la revisión
  anterior, para que compare él). Y celébralo cuando se niegue: un reviewer que rechaza una premisa
  que no cuadra con lo que ve está haciendo exactamente su trabajo — es la misma propiedad que hace
  que su GREEN valga algo.
- **Detector:** n/a-manual — es una regla sobre cómo se redacta un prompt de sub-agente, no sobre
  el contenido del repo; no hay artefacto en el árbol que un detector pueda inspeccionar. Vive en
  `.agents/skills/process/references/multi-agent-orchestration.md`, que es donde el que va a
  escribir ese prompt lo busca.
- **Área:** .agents/skills/process/references/multi-agent-orchestration.md

---

## Lecciones mecanizadas (índice)

> Estas ya NO dependen de tu memoria: cada una tiene un test en `tools/tests/` que corre en el
> Anillo 3, así que violarlas hace fallar la suite. Se listan para que sepas que existen; el
> relato completo (síntoma, causa raíz, racional) vive en `docs/process/lessons_archive.md`.
> Si necesitas el detalle de una, búscala ahí — no la reescribas.

- [2026-08-30] Un gate que bifurca por plataforma solo se prueba en una, y la otra es la que corre en CI — `tools/tests/test_ring3.sh`
- [2026-08-25] El gate de mayor ROI llevaba una sesión entera mudo, por el matcher — `tools/tests/test_bash_writes.sh`
- [2026-08-24] Un comentario que afirma cobertura es la afirmación MÁS peligrosa del repo — `tools/tests/test_metrics.sh`
- [2026-08-24] Cuando una lista se queda corta seis veces, el defecto es que sea una lista — `tools/tests/test_scope_superficie.sh`
- [2026-08-22] Lo que decide sobre un diff se lee de la misma fuente que el diff — `tools/tests/test_scope_kind.sh`
- [2026-08-22] Un corpus escrito por quien construye el detector confirma sus errores — `tools/tests/test_source_sets.sh`
- [2026-08-22] Un detector que casa acentos da verde a mano y rojo en el runner — `tools/tests/test_execution_map.sh`
- [2026-08-21] Una limpieza que atrapa INT/TERM y no re-lanza deja el proceso ingobernable — `tools/tests/test_source_sets.sh`
- [2026-08-21] Una lección arreglada tres veces y sin detector se repite a la cuarta — `tools/tests/test_semgrep_rules.sh`
- [2026-08-21] Anclar un grep no lo convierte en un parser: solo mueve el falso positivo — `tools/tests/test_source_sets.sh`
- [2026-08-19] La identidad del repo se infería en vez de declararse (WF-05) — `tools/tests/test_scope_kind.sh`
- [2026-08-19] Un rojo que tira el exit y el stderr convierte cualquier fallo en el fallo equivocado — `tools/tests/test_agent_runner.sh`
- [2026-08-19] Un JSONL escrito con printf es un formato solo hasta el primer valor hostil — `tools/tests/test_review_history.sh`
- [2026-08-19] El mapa canónico declaró conteos que un comando recalcula, y se pudrieron — `tools/tests/test_execution_map.sh`
- [2026-08-19] Un generador de vista estable pero no canónico sedimenta formato hasta reventar su presupuesto — `tools/tests/test_lessons_rotacion.sh`
- [2026-08-09] Las lecciones no caducaban, y eso contradecía su propio mecanismo — `tools/tests/test_lessons_rotacion.sh`
- [2026-08-14] El repo del harness eximía de review el 100% de su propio contenido — `tools/tests/test_review_marker_preset.sh`
- [2026-08-14] La regla que protege el FILL vivía en uno de los dos caminos — `tools/tests/test_upgrade.sh`
- [2026-08-14] El canal por el que llegan la mitad de los arreglos no tocaba el ledger — `tools/tests/test_upgrade.sh`
- [2026-08-14] Lo que no se puede inyectar en runtime se escribe en el prompt del rol — `tools/tests/test_verdict.sh`
- [2026-08-14] La idempotencia que corta un bucle también borra el trabajo deliberado — `tools/tests/test_verdict.sh`
- [2026-08-14] Un hook de *Stop* que reinyecta contexto se retroalimenta — `tools/tests/test_verdict.sh`
- [2026-08-14] El harness modelaba un solo eje, y KMP tiene dos — `tools/tests/test_source_sets.sh`
- [2026-08-14] El sistema guardaba QUÉ decidió el review y perdía QUÉ dijo — `tools/tests/test_verdict.sh`
- [2026-08-13] El paso del workflow que nadie ejecutaba mentía en el arranque de cada sesión — `tools/tests/test_execution_map.sh`
- [2026-08-12] El único entrypoint sin test propio era el que aprueba todo lo demás — `tools/tests/test_e2e_gates_anillo3.sh`
- [2026-08-12] Una capacidad declarada no es una capacidad demostrada — `tools/tests/test_e2e_orquestador_backlog.sh`
- [2026-08-12] Una lista de garantías sin vínculo mecánico a sus tests es prosa — `tools/tests/test_e2e_plataformas_y_vinculo.sh`
- [2026-08-12] `stat -f` de GNU no falla, y el orden del fallback ERA el bug — `tools/tests/test_shell_hygiene.sh`
- [2026-08-12] El programa embebido consumía el mismo stdin reservado para el payload — `tools/tests/test_gate_cache.sh`
- [2026-08-12] Reconciliar un archivo exige identidad no ambigua y clasificación bidireccional — `tools/tests/test_lessons_rotacion.sh`
- [2026-08-05] Un gate bloqueó editar la documentación de su propia área — `tools/tests/test_skill_reminder.sh`
- [2026-08-05] La ausencia de una herramienta se contaba como deuda técnica — `tools/tests/test_drift_aggregation.sh`
- [2026-08-05] El escape hatch de emergencia relajaba más de lo declarado — `tools/tests/test_ratchets.sh`
- [2026-08-05] Un detector heurístico era trivial de gamear — `tools/tests/test_drift_aggregation.sh`
- [2026-08-06] Las reglas de semgrep nunca habían cargado, y `--validate` decía que sí — `tools/tests/test_shell_hygiene.sh`
- [2026-08-05] Escribir el harness en español rompió tres scripts en silencio — `tools/tests/test_shell_hygiene.sh`
- [2026-08-05] Un gate no distinguía "tu código falla" de "yo no pude mirar" — `tools/tests/test_fail_closed.sh`
- [2026-08-05] Una regla implementada en dos sitios divergió en cuanto un tercero la llamó — `tools/tests/test_review_marker_preset.sh`
- [2026-08-05] El detector de secretos se bloqueó a sí mismo — `tools/tests/test_canon_enforce.sh`
- [2026-08-07] Hooks registrados sobre eventos que NO existen — `tools/tests/test_hook_events.sh`
- [2026-08-07] Dos emisores del "mismo" JSON con espaciado distinto — `tools/tests/test_findings_cli.sh`
- [2026-08-07] El fallback de `stat` que nunca corría (y solo rompía en CI) — `tools/tests/test_ratchets.sh`
- [2026-08-09] Anillo 0: dos sintaxis inertes, delatadas por la voz del propio cliente en los logs — `tools/tests/test_hook_events.sh`
- [2026-08-09] El gate del marker no conocía los commits de MERGE (el owner atascado en su propio flujo) — `tools/tests/test_review_marker_preset.sh`
- [2026-08-09] La matriz exigía leer un archivo que el tracker no sabía registrar (bucle infinito) — `tools/tests/test_skill_matrix.sh`
- [2026-08-08] El clasificador producto/meta-doc no conocía AGENTS.md (y el marker stale lo empeoró) — `tools/tests/test_review_marker_preset.sh`
- [2026-08-07] Un trinquete cuyo propio script podía aflojarlo — `tools/tests/test_ratchets.sh`
- [2026-08-09] Un merge "concluido" commiteó los marcadores de conflicto y ningún gate lo vio — `tools/tests/test_conflict_markers.sh`
- [2026-08-09] Tres gates parecían sanos y ninguno había demostrado jamás que VE — `tools/tests/test_ratchets.sh`
- [2026-08-09] Un archivo llegado por fuera de upgrade.sh revirtió un arreglo en silencio — `tools/tests/test_shell_hygiene.sh`
- [2026-08-09] El fail-open local estaba justificado por un backstop que nadie comprobaba — `tools/tests/test_ring3.sh`
- [2026-08-09] La métrica que probaba que el harness sirve no la invocaba nadie — `tools/tests/test_harness_report.sh`
- [2026-08-09] Avisar cinco veces no impidió que el problema entrara en la historia — `tools/tests/test_exec_bits.sh`
- [2026-08-09] La review llegaba a ciegas al final, y por eso cada vuelta costaba lo mismo — `tools/tests/test_verdict.sh`
- [2026-08-09] El camino de upgrade estaba roto justo para la ruta de adopción que la doc recomienda — `tools/tests/test_upgrade.sh`
- [2026-08-09] Escribí el detector de "falla a medias y dice OK" y cometí ese error dos veces seguidas — `tools/tests/test_upgrade.sh`
- [2026-08-09] Maquinaria con secciones que el template espera que personalices — `tools/tests/test_upgrade.sh`
- [2026-08-09] Pedirle ayuda al CLI del ledger corrompía el ledger — `tools/tests/test_findings_cli.sh`
- [2026-08-09] La matriz de skills solo vigilaba las tools de edición, no Bash — `tools/tests/test_bash_matrix.sh`
- [2026-08-09] El template arrastraba un secreto que disparaba su propio detector — `tools/tests/test_canon_enforce.sh`
- [2026-08-09] Sin `.semgrepignore`, el nivel 2 escaneaba copias del propio proyecto — `tools/tests/test_shell_hygiene.sh`
- [2026-08-09] Denegar la herramienta segura no impide la escritura: la empuja al camino inseguro — `tools/tests/test_hook_events.sh`
- [2026-08-10] La herramienta que reparte los arreglos no puede parchearse a sí misma — `tools/tests/test_upgrade.sh`
- [2026-08-10] Un marcador es una FORMA, no una palabra: `grep FILL` congeló media maquinaria — `tools/tests/test_upgrade.sh`
- [2026-08-10] Un literal partido a propósito lleva escrito POR QUÉ, o el siguiente lo junta — `tools/tests/test_secret_scan.sh`
- [2026-08-10] El filtro del propio verificador de lecciones se tragó una lección — `tools/tests/test_lessons_falsos_positivos.sh`
- [2026-08-10] `.claude/settings.json` es maquinaria viviendo en una carpeta de contenido — `tools/tests/test_settings_merge.sh`
- [2026-08-10] "Esto lo caza el test X" — y el test X no lo cazaba — `tools/tests/test_skill_matrix.sh`
- [2026-08-10] Un manifiesto mantenido a mano no puede vigilarse a sí mismo — `tools/tests/test_meta_fp.sh`
- [2026-08-10] Una regla de adopción que solo vive en un doc se descubre tarde — `tools/tests/test_layers.sh`
- [2026-08-10] El estado real de una historia no vive donde el selector miraba — `tools/tests/test_backlog_selection.sh`
- [2026-08-10] Un `||` que no distingue "no pude mirar" de "encontré algo" — `tools/tests/test_secret_scan.sh`
- [2026-08-10] Un gate en rojo perpetuo es peor que un gate ausente — `tools/tests/test_secret_scan.sh`
- [2026-08-10] El guard colgaba del exit code de jq, y jq cambió de opinión entre versiones — `tools/tests/test_fail_closed.sh`
- [2026-08-10] Un run puede salir con 0 y no haber terminado — `tools/tests/test_backlog_run_completion.sh`
- [2026-08-10] Se arregló un caso del parser y no se buscó el hermano — `tools/tests/test_semgrep_rules.sh`
- [2026-08-10] Un criterio de aceptación «verificado con un grep» es decoración — `tools/tests/test_backlog_criteria.sh`
- [2026-08-11] El informe de "no lo he traído" mentía, y empujaba justo al flujo que prohíbe — `tools/tests/test_upgrade.sh`
- [2026-08-11] El invariante nº1 estaba aplicado al reviewer y no a los tests — `tools/tests/test_verify_marker.sh`
- [2026-08-11] Un gate que lee TEXTO como si fuera sintaxis enseña a evadirlo — `tools/tests/test_bash_matrix.sh`
- [2026-08-11] Un hook roto dejó al agente sin poder ni diagnosticarlo — `tools/tests/test_run_hook.sh`
- [2026-08-11] Un piso de 0 no es un suelo: es una medición que nunca ocurrió — `tools/tests/test_ratchets.sh`
- [2026-08-12] "Sin cablear" y "cableado, pero el runner no termina" no son el mismo estado — `tools/tests/test_ratchets.sh`
- [2026-08-12] El archivo de tests existía; el test citado no — `tools/tests/test_lessons_detector_link.sh`
- [2026-08-12] El gestor de paquetes contesta a otra pregunta — `tools/tests/test_finding_refs.sh`
- [2026-08-12] Un id de finding que no existe LEE COMO CERRADO — `tools/tests/test_finding_refs.sh`
- [2026-08-12] La cuarta vez del mismo falso positivo no pide otra lección — `tools/tests/test_bash_matrix.sh`
- [2026-08-11] Cambiar de lanzador habría duplicado todos los hooks de todos los proyectos — `tools/tests/test_settings_merge.sh`
- [2026-08-11] La suite corría DESPUÉS del push, así que `main` se publicó en rojo — `tools/tests/test_run_hook.sh`
- [2026-08-11] Un test con fixture inventado prueba la invención, no la herramienta — `tools/tests/test_settings_merge.sh`
- [2026-08-11] Un RED sin huella hace indistinguible la remediación del reintento — `tools/tests/test_verdict.sh`
- [2026-08-11] La cola del juez premiaba dejar basura — `tools/tests/test_judge_queue.sh`
- [2026-08-12] El repo que escribe el gate era el único sin cablearlo — `tools/tests/test_verify_marker.sh`
- [2026-08-12] El detector se validó contra el único ledger que no lo iba a romper — `tools/tests/test_finding_refs.sh`
- [2026-08-12] Un fallback añadió un segundo cero a un resultado válido — `tools/tests/test_metrics.sh`
- [2026-08-12] Añadir campos al evento no migra a sus productores — `tools/tests/test_findings_cli.sh`
- [2026-08-12] Omitir una línea corrupta convirtió “no pude medir” en cero — `tools/tests/test_metrics.sh`
- [2026-08-12] Validar el prefijo de un timestamp no valida el instante — `tools/tests/test_metrics.sh`
- [2026-08-12] Normalizar los datos a UTC no basta si la ventana sigue siendo local — `tools/tests/test_metrics.sh`
- [2026-08-12] Cuantificar un descarte no reemplaza la señal de su causa — `tools/tests/test_metrics.sh`
- [2026-08-12] Una vista generada no puede convertirse en entrada de su propio generador — `tools/tests/test_lessons_rotacion.sh`

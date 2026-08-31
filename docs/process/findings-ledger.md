# Findings Ledger — vista humana

> **GENERADA — NO editar a mano.** Fuente: `tools/findings/ledger.jsonl`.
> Regenerar: `bash tools/findings/findings.sh render`.

Abiertos: **38** · Cerrados: 28 · Total: 66

## Abiertos

| id | sev | tier | área | título |
|---|---|---|---|---|
| `f-29c26642` | high | owner-decision | `docs/process/reviews/2026-08-28-design-review-prd-0001.md:180-194` | El design-reviewer SI cazo la omision de Coordinator/DI (6a pasada, H-7) y el hallazgo se evaporo |
| `f-2ffc6d32` | high | owner-decision | `.agents/skills/**` | Las skills que describen un SPM no tienen gate de fidelidad: nadie valida que digan VERDE cuando el paquete dice VERDE |
| `f-7c08518b` | high | owner-decision | `tools/tests/test_agent_runner.sh` | La suite del harness tiene tests flaky de senales que bloquean el push al azar |
| `f-8720114e` | high | owner-decision | `spm-pro/AppFoundation/README.md:144-157` | El README de AppFoundation ensena el patron que rompe la identidad de los ViewModels |
| `f-e008f6f` | high | owner-decision | `tools/ (propuesta: check-platform-adoption.sh + platform-adoption.conf)` | No hay ningun detector de OMISION: nada comprueba que el codigo use los mecanismos que AGENTS.md 3 prescribe |
| `f-ea2aea2f` | high | owner-decision | `.claude/agents/` | Falta el revisor final con contexto COMPLETO: tarea, PRD, skill, codigo y tests, como un senior ante un PR |
| `f-2db8ecf0` | medium | owner-decision | `docs/process/current_execution_map.md:56 / tools/` | Nada contrasta un diseno prescrito en docs contra layers.conf: se corrigio el caso (f-3480a974) y no la clase |
| `f-3b30fcf4` | medium | owner-decision | `tools/harness-report.sh:40 + tools/secret-baseline.sh:66 (clase; propuesta: detector de command -v que ELIGE implementacion)` | Nada vigila las bifurcaciones por entorno del harness, y hay al menos dos vivas con el mismo defecto que tumbo el Anillo 3 |
| `f-3d60d1f6` | medium | owner-decision | `Sources/Features/Movies/PopularMoviesView.swift:17` | El titulo de la pantalla es un literal en el codigo: no hay String Catalog en el repo |
| `f-3eb3a818` | medium | owner-decision | `tools/upgrade.sh` | El canal de sync entra en bucle si la resolucion de un conflicto coincide con HEAD |
| `f-52ef5f6d` | medium | auto-fix | `Sources/Data/Movies/TMDBPopularMoviesRepository.swift:35` | Decision pendiente: CancellationError prescrito vs .unknown implementado |
| `f-71c669cc` | medium | owner-decision | `scripts/agent-hooks/reviewer-gate.sh` | El veredicto del design-reviewer no tiene consecuencia mecanica: seis pasadas RED y el commit paso igual |
| `f-7b10426e` | medium | owner-decision | `Tests/UnitTests/Movies` | T-S-1 (sentinela de credencial) sin escribir: decidir escribirlo o aceptar la cobertura actual |
| `f-85c818b4` | medium | owner-decision | `AGENTS.md:5 / .agents/skills/process/references/tdd-workflow.md:18` | El paso rojo del TDD no lo observa nada, y la trayectoria muestra que no ocurrio en el slice 0 |
| `f-8ab6c2ad` | medium | owner-decision | `spm-pro/AppFoundation/Sources/AppFoundation/Navigation/Views/CoordinatorView.swift` | CoordinatorView no tiene ni un solo test, y es donde vive la trampa mas cara del paquete |
| `f-8e30ad43` | medium | auto-fix | `scripts/agent-hooks/session-end.sh:51-58` | La judge-queue encolo un SID sin trayectoria y con commits=0 la sesion que escribio el slice 0 |
| `f-a655520c` | medium | auto-fix | `docs/process/prds/0001-vertical-de-referencia-peliculas.md:367 (SS6.2) + :155 (SS5)` | El PRD 0001 se contradice consigo mismo sobre donde van overview/releaseDate, y su arbol de archivos coloca MoviesModule donde layers.conf lo rechaza |
| `f-cc4f2b3e` | medium | auto-fix | `tools/check-execution-map.sh:279` | check-execution-map: cualquier backtick vecino excusa una afirmacion de estado falsa |
| `f-db694460` | medium | owner-decision | `spm-pro/AppFoundation/Sources/AppFoundation/DependencyInjection/Container.swift` | Container: registrar transient o scoped sobre un singleton ya materializado es silenciosamente inefectivo |
| `f-e6743298` | medium | owner-decision | `spm-pro/CoreNetworking/Sources/CoreNetworking/RequestInterceptor.swift:130` | Privacidad invertida en los logs de red: la URL va private y el mensaje del servidor va public |
| `f-ee56ec3` | medium | owner-decision | `tools/check-prd-tree.sh` | check-prd-tree lee la prosa que AVISA de una ruta como si la declarara |
| `f-f17a5860` | medium | owner-decision | `tools/check-layers-coverage.sh` | Nada vigila que los globs de skill-matrix.conf no enmudezcan |
| `f-f88eb0fd` | medium | auto-fix | `Sources/App/BaselineApp.swift` | El registro del Router en BaselineApp.init no tiene test propio: la unica pieza del idioma del owner sin red |
| `f-f957b7f4` | medium | auto-fix | `Config/Debug.xcconfig:7` | El Info.plist compilado no se regenera cuando cambia un include opcional de xcconfig |
| `f-update-sin-guard` | medium | auto-fix | `tools/findings/findings.sh:242` | update bypasa el guard de terminalidad: resucita un finding cerrado y pisa su resolucion |
| `f-13afde3c` | low | auto-fix | `scripts/agent-hooks/ (capture de trayectoria)` | La trayectoria registra cd como path en 736 de 2143 Bash: el instrumento del nivel 9 es ciego al 55% del trabajo |
| `f-2c039d47` | low | owner-decision | `tools/tests/README.md` | tools/tests/README.md nombra el workflow de CI sin detector que lo mantenga cierto |
| `f-32db9901` | low | owner-decision | `CoreNetworking/Sources/CoreNetworking/SessionDelegates.swift:34` | El aviso de fallo de pinning no esta verificado: invertir su condicion silencia el log |
| `f-5529624d` | low | owner-decision | `tools/verify.conf` | El umbral real del test-timeout no esta fijado en el repo |
| `f-5856bd41` | low | owner-decision | `Sources/App/BaselineApp.swift` | coordinator en BaselineApp es let, asimetrico con store que si es @State |
| `f-6453846` | low | owner-decision | `docs/process/prds/0001-vertical-de-referencia-peliculas.md (DoST NO-TOUCH)` | El comando NO-TOUCH del DoD solo cubre el subconjunto tooling/meta del bloque |
| `f-66f86136` | low | owner-decision | `.agents/skills/architecture/platforms/` | Las skills de web y android son 10 FILL que nunca se rellenaran en un proyecto iOS |
| `f-975e3cb1` | low | auto-fix | `tools/semgrep-scan.sh:94` | semgrep-scan.sh --all revienta con TARGETS vacio bajo bash 3.2 (unbound variable) |
| `f-996710c3` | low | auto-fix | `Tests/UnitTests/Movies/MoviesRouteBuilderTests.swift:45` | RepoVacio duplica el fake canonico y no esta en el catalogo de exenciones de la conformidad |
| `f-a452b1de` | low | auto-fix | `Sources/App/AppCoordinatorView.swift:19` | Residuo declarado de G4: nada verifica que AppCoordinatorView le pase el builder a CoordinatorView |
| `f-de18ddb` | low | auto-fix | `tools/harness-report.sh:59` | El contador de FILL de harness-report cuenta los FILL-HECHO como pendientes |
| `f-e420ff1e` | low | owner-decision | `CLAUDE.md (seccion Maquinaria exclusiva de Claude Code)` | CLAUDE.md anuncia solo /goal y ya hay 5 comandos: los otros 4 son indescubribles |
| `f-e4a8a982` | low | auto-fix | `tools/check-layers-coverage.sh` | check-layers-coverage: la exencion del bloque universal es posicional, no semantica |

## Cerrados

| id | estado | resolución |
|---|---|---|
| `f-1571535f` | fixed | Resuelto en CoreNetworking 0.1.2, en esta misma sesion: NetworkingConfiguration.makeDecoder es una f |
| `f-ed8f24f6` | fixed | OBSOLETO: ya no es cierto. El commit 71e0982 (test(pinning): el delegado que decide en runtime, por  |
| `f-3236fb0` | fixed | El gate corrio el 2026-08-28: security-reviewer VERDICT AMBER, 2 findings, ninguno bloqueante, marke |
| `f-f6b72573` | fixed | OQ-17 resuelta por el owner (2026-08-28): C2 se RETIRA del contrato. El puerto NO deduplica; la unic |
| `f-31902e86` | fixed | Refactor (b), 2026-08-28. load() suelto sustituido por enum Action + handle(_:) en PopularMoviesView |
| `f-54d7ee41` | fixed | Cerrado en la fase 2 del PRD 0002 (commit 3e333ba): PopularMoviesView pasa de @State private var vie |
| `f-3480a974` | fixed | Publicado CoreNetworking 0.1.4 (github.com/hiramvazquez/CoreNetworking, tag 0.1.4, revision 4d299f36 |
| `f-bba673a7` | fixed | OQ-C autorizada por el owner (2026-08-28): */Features/* y */App/* anadidos a tools/skill-matrix.conf |
| `f-b6f2c1a4` | fixed | Cerrado por la fase 3 del PRD 0002 (commit 65b5fdb, 2026-08-29): enum Action -> Intent y handle(_:)  |
| `f-close-guard` | fixed | Guard implementado y verificado reproduciendo el error original contra el ledger real: la resolucion |
| `f-44fd100c` | fixed | Arreglado en el mismo turno. --force sin --resolution/--reason sale 2 con mensaje que dice que hace  |
| `f-6d36a878` | fixed | Test reescrito para comprobar las DOS ramas: sin --force rebota y no altera la resolucion; con --for |
| `f-a5d90bc` | fixed | Anadido test_accept_no_pisa_resolucion_previa. Verificado con mutante C (restringir el guard a cmd = |
| `f-a14d1993` | fixed | Arreglado en flag(): un token que empieza por -- deja de contar como valor. Verificado contra el led |
| `f-flag-overbroad` | fixed | Lista cerrada KNOWN_FLAGS. Las cuatro puertas de la familia verificadas contra el ledger real: close |
| `f-flag-placeholder` | fixed | Aplicado require_flag_values a resolution/reason: el mecanismo YA existia en el archivo y solo se us |
| `f-known-flags-drift` | fixed | Test test_known_flags_cubre_el_usage: extrae los flags del USAGE y exige que KNOWN_FLAGS los cubra.  |
| `f-test-id-decorativo` | fixed | Anadido test_close_id_inexistente_explica, que exige el mensaje en stderr y prohibe el traceback. Ve |
| `f-d4b58c90` | fixed | CERRADO con evidencia, 2026-08-31. El arreglo que este finding pedia era 'marcar el punto 1 como HEC |
| `f-f2a4ca6e` | fixed | CERRADO por el PRD 0002 completo (fases 3+1+2: commits 65b5fdb, 483f4eb, 3e333ba, 2026-08-29). El mo |
| `f-694c2009` | fixed | CERRADO con evidencia, 2026-08-31. Este finding pedia dos cosas y las dos estan. (1) 'Sustituir la f |
| `f-b6c162d8` | fixed | CERRADO 2026-08-31, y con el alcance exacto porque la propuesta NO se entrego entera. EL CASO ESTA M |
| `f-a3b6dafc` | fixed | CERRADO con evidencia mecanica, 2026-08-31. El trabajo se hizo el 2026-08-29 -la reescritura de las  |
| `f-1aa86bc8` | fixed | Arreglado en 43d9199. El guard dejo de ser lista negra: ahora exige que lo configurado SEA el host ( |
| `f-a168fe6d` | fixed | Arreglado en 43d9199. El test se reescribio para afirmar config == nil en vez de baseURL.scheme != h |
| `f-7c57fa35` | accepted | Decision del owner (2026-08-29, literal): "el token es de dev, no importa que se haya visto, no es u |
| `f-804ebee0` | fixed | CERRADO con evidencia de CI, no con una afirmacion. Run 33351758651 sobre e779539: los DOS jobs en v |
| `f-da257e0c` | fixed | CERRADO por decision y orden explicita del owner (2026-08-31): 'corrige el AGENTS.md tu'. Aplicada l |

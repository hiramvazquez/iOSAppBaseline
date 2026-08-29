# Findings Ledger — vista humana

> **GENERADA — NO editar a mano.** Fuente: `tools/findings/ledger.jsonl`.
> Regenerar: `bash tools/findings/findings.sh render`.

Abiertos: **14** · Cerrados: 15 · Total: 29

## Abiertos

| id | sev | tier | área | título |
|---|---|---|---|---|
| `f-ed8f24f6` | high | owner-decision | `CoreNetworking/Sources/CoreNetworking/SessionDelegates.swift` | El delegado de SSL pinning no esta verificado: invertir su condicion no rompe ningun test |
| `f-52ef5f6d` | medium | auto-fix | `Sources/Data/Movies/TMDBPopularMoviesRepository.swift:35` | Decision pendiente: CancellationError prescrito vs .unknown implementado |
| `f-54d7ee41` | medium | auto-fix | `Sources/Features/Movies/PopularMoviesView.swift:10` | @State private var viewModel duplica el dueno de la identidad |
| `f-7b10426e` | medium | owner-decision | `Tests/UnitTests/Movies` | T-S-1 (sentinela de credencial) sin escribir: decidir escribirlo o aceptar la cobertura actual |
| `f-f17a5860` | medium | owner-decision | `tools/check-layers-coverage.sh` | Nada vigila que los globs de skill-matrix.conf no enmudezcan |
| `f-update-sin-guard` | medium | auto-fix | `tools/findings/findings.sh:242` | update bypasa el guard de terminalidad: resucita un finding cerrado y pisa su resolucion |
| `f-2c039d47` | low | owner-decision | `tools/tests/README.md` | tools/tests/README.md nombra el workflow de CI sin detector que lo mantenga cierto |
| `f-32db9901` | low | owner-decision | `CoreNetworking/Sources/CoreNetworking/SessionDelegates.swift:34` | El aviso de fallo de pinning no esta verificado: invertir su condicion silencia el log |
| `f-5529624d` | low | owner-decision | `tools/verify.conf` | El umbral real del test-timeout no esta fijado en el repo |
| `f-6453846` | low | owner-decision | `docs/process/prds/0001-vertical-de-referencia-peliculas.md (DoST NO-TOUCH)` | El comando NO-TOUCH del DoD solo cubre el subconjunto tooling/meta del bloque |
| `f-975e3cb1` | low | auto-fix | `tools/semgrep-scan.sh:94` | semgrep-scan.sh --all revienta con TARGETS vacio bajo bash 3.2 (unbound variable) |
| `f-b6f2c1a4` | low | owner-decision | `.claude/rules/10-ios-ui.md + Sources/Features/Movies/PopularMoviesViewModel.swift` | Unificar el nombre de la intencion: vm.send(...) vs handle(_:) |
| `f-d4b58c90` | low | auto-fix | `docs/process/current_execution_map.md` | current_execution_map.md punto 1 describe commitear el slice 0 como pendiente, ya commiteado |
| `f-e4a8a982` | low | auto-fix | `tools/check-layers-coverage.sh` | check-layers-coverage: la exencion del bloque universal es posicional, no semantica |

## Cerrados

| id | estado | resolución |
|---|---|---|
| `f-1571535f` | fixed | Resuelto en CoreNetworking 0.1.2, en esta misma sesion: NetworkingConfiguration.makeDecoder es una f |
| `f-3236fb0` | fixed | El gate corrio el 2026-08-28: security-reviewer VERDICT AMBER, 2 findings, ninguno bloqueante, marke |
| `f-f6b72573` | fixed | OQ-17 resuelta por el owner (2026-08-28): C2 se RETIRA del contrato. El puerto NO deduplica; la unic |
| `f-31902e86` | fixed | Refactor (b), 2026-08-28. load() suelto sustituido por enum Action + handle(_:) en PopularMoviesView |
| `f-3480a974` | fixed | Publicado CoreNetworking 0.1.4 (github.com/hiramvazquez/CoreNetworking, tag 0.1.4, revision 4d299f36 |
| `f-bba673a7` | fixed | OQ-C autorizada por el owner (2026-08-28): */Features/* y */App/* anadidos a tools/skill-matrix.conf |
| `f-close-guard` | fixed | Guard implementado y verificado reproduciendo el error original contra el ledger real: la resolucion |
| `f-44fd100c` | fixed | Arreglado en el mismo turno. --force sin --resolution/--reason sale 2 con mensaje que dice que hace  |
| `f-6d36a878` | fixed | Test reescrito para comprobar las DOS ramas: sin --force rebota y no altera la resolucion; con --for |
| `f-a5d90bc` | fixed | Anadido test_accept_no_pisa_resolucion_previa. Verificado con mutante C (restringir el guard a cmd = |
| `f-a14d1993` | fixed | Arreglado en flag(): un token que empieza por -- deja de contar como valor. Verificado contra el led |
| `f-flag-overbroad` | fixed | Lista cerrada KNOWN_FLAGS. Las cuatro puertas de la familia verificadas contra el ledger real: close |
| `f-flag-placeholder` | fixed | Aplicado require_flag_values a resolution/reason: el mecanismo YA existia en el archivo y solo se us |
| `f-known-flags-drift` | fixed | Test test_known_flags_cubre_el_usage: extrae los flags del USAGE y exige que KNOWN_FLAGS los cubra.  |
| `f-test-id-decorativo` | fixed | Anadido test_close_id_inexistente_explica, que exige el mensaje en stderr y prohibe el traceback. Ve |

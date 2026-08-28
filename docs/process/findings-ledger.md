# Findings Ledger — vista humana

> **GENERADA — NO editar a mano.** Fuente: `tools/findings/ledger.jsonl`.
> Regenerar: `bash tools/findings/findings.sh render`.

Abiertos: **13** · Cerrados: 4 · Total: 17

## Abiertos

| id | sev | tier | área | título |
|---|---|---|---|---|
| `f-31902e86` | high | auto-fix | `Sources/Features/Movies/PopularMoviesView.swift:23` | Falta idempotencia de la primera carga: .task re-dispara performLoad |
| `f-ed8f24f6` | high | owner-decision | `CoreNetworking/Sources/CoreNetworking/SessionDelegates.swift` | El delegado de SSL pinning no esta verificado: invertir su condicion no rompe ningun test |
| `f-3480a974` | medium | auto-fix | `spm-pro/CoreNetworking` | TransportError va a CoreNetworking: publicar 0.1.4 y re-fijar |
| `f-52ef5f6d` | medium | auto-fix | `Sources/Data/Movies/TMDBPopularMoviesRepository.swift:35` | Decision pendiente: CancellationError prescrito vs .unknown implementado |
| `f-54d7ee41` | medium | auto-fix | `Sources/Features/Movies/PopularMoviesView.swift:10` | @State private var viewModel duplica el dueno de la identidad |
| `f-7b10426e` | medium | owner-decision | `Tests/UnitTests/Movies` | T-S-1 (sentinela de credencial) sin escribir: decidir escribirlo o aceptar la cobertura actual |
| `f-f17a5860` | medium | owner-decision | `tools/check-layers-coverage.sh` | Nada vigila que los globs de skill-matrix.conf no enmudezcan |
| `f-2c039d47` | low | owner-decision | `tools/tests/README.md` | tools/tests/README.md nombra el workflow de CI sin detector que lo mantenga cierto |
| `f-32db9901` | low | owner-decision | `CoreNetworking/Sources/CoreNetworking/SessionDelegates.swift:34` | El aviso de fallo de pinning no esta verificado: invertir su condicion silencia el log |
| `f-5529624d` | low | owner-decision | `tools/verify.conf` | El umbral real del test-timeout no esta fijado en el repo |
| `f-6453846` | low | owner-decision | `docs/process/prds/0001-vertical-de-referencia-peliculas.md (DoST NO-TOUCH)` | El comando NO-TOUCH del DoD solo cubre el subconjunto tooling/meta del bloque |
| `f-975e3cb1` | low | auto-fix | `tools/semgrep-scan.sh:94` | semgrep-scan.sh --all revienta con TARGETS vacio bajo bash 3.2 (unbound variable) |
| `f-e4a8a982` | low | auto-fix | `tools/check-layers-coverage.sh` | check-layers-coverage: la exencion del bloque universal es posicional, no semantica |

## Cerrados

| id | estado | resolución |
|---|---|---|
| `f-1571535f` | fixed | Resuelto en CoreNetworking 0.1.2, en esta misma sesion: NetworkingConfiguration.makeDecoder es una f |
| `f-3236fb0` | fixed | El gate corrio el 2026-08-28: security-reviewer VERDICT AMBER, 2 findings, ninguno bloqueante, marke |
| `f-f6b72573` | fixed | OQ-17 resuelta por el owner (2026-08-28): C2 se RETIRA del contrato. El puerto NO deduplica; la unic |
| `f-bba673a7` | fixed | OQ-C autorizada por el owner (2026-08-28): */Features/* y */App/* anadidos a tools/skill-matrix.conf |

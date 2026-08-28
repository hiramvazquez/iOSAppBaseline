# Findings Ledger — vista humana

> **GENERADA — NO editar a mano.** Fuente: `tools/findings/ledger.jsonl`.
> Regenerar: `bash tools/findings/findings.sh render`.

Abiertos: **4** · Cerrados: 1 · Total: 5

## Abiertos

| id | sev | tier | área | título |
|---|---|---|---|---|
| `f-ed8f24f6` | high | owner-decision | `CoreNetworking/Sources/CoreNetworking/SessionDelegates.swift` | El delegado de SSL pinning no esta verificado: invertir su condicion no rompe ningun test |
| `f-2c039d47` | low | owner-decision | `tools/tests/README.md` | tools/tests/README.md nombra el workflow de CI sin detector que lo mantenga cierto |
| `f-32db9901` | low | owner-decision | `CoreNetworking/Sources/CoreNetworking/SessionDelegates.swift:34` | El aviso de fallo de pinning no esta verificado: invertir su condicion silencia el log |
| `f-5529624d` | low | owner-decision | `tools/verify.conf` | El umbral real del test-timeout no esta fijado en el repo |

## Cerrados

| id | estado | resolución |
|---|---|---|
| `f-1571535f` | fixed | Resuelto en CoreNetworking 0.1.2, en esta misma sesion: NetworkingConfiguration.makeDecoder es una f |

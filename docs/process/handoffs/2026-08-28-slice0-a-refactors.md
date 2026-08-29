# Handoff — tras el slice 0 y el refactor (b)

> Prompt de arranque para una sesión nueva sobre `iOSAppBaseline`.
> Estado verificado el 2026-08-28 sobre `089a971`, árbol limpio.

Retomas iOSAppBaseline en `/Users/hiram/Desktop/PROYECTOS/iOSAppBaseline`.
Abre la sesión ahí (no en agentic-workflow-template: son repos distintos y el
harness de cada uno resuelve contra su propio directorio).

## Dónde está el trabajo

Árbol limpio en `main`, sobre `089a971`. Cuatro commits recientes:

- `73459e8` slice 0: vertical de películas TMDB cruzando Domain → Data → Features → App
- `bd43911` refactor (b): `enum Action` + `handle(_:)` con idempotencia de la primera carga
- `249a7eb` guard de terminalidad en `findings.sh` (cinco puertas de pérdida silenciosa)
- `089a971` registro del finding de `update`

Gates en verde: 24 tests de la app, 685 del harness, `check-layers` 0,
`check-drift` 0/0, `check-layers-coverage` 0 huérfanas, `check-execution-map` 0,
`lesson-detector-link` 0, `check-skill-matrix-doc` 0. PRD 0001 en `Approved`.

Lee primero `docs/process/current_execution_map.md` y el tramo vivo de
`docs/process/lessons_learned.md` (§0 de AGENTS.md).

## Qué hacer, en este orden

**1. Refactor (c) — DTOs a su propio archivo.** Sacar los DTOs de TMDB y su
mapeo de `Sources/Data/Movies/TMDBPopularMoviesRepository.swift` a un archivo
aparte. Tienen lógica de decodificación que merece test propio. Es el más
pequeño de los que quedan y cierra de paso la divergencia de §5 del PRD, que
describe un árbol de archivos distinto del entregado.

**2. Refactor (a) — `TransportError` a CoreNetworking.** Es el grande y tiene
tres trampas ya identificadas, todas en el ledger:

- `MoviesError = .transport(_) + notFound + malformedResponse` **mata
  `CaseIterable`** (Swift no lo sintetiza con valores asociados). Se caen los
  dos tests de `MoviesErrorScreenErrorTests` que iteran `allCases`, y la fila
  T-D-4 del PRD que justifica `CaseIterable`.
- **Mata el argumento de S1**: hoy "ninguna salida contiene la credencial" se
  sostiene *por construcción* porque ningún caso lleva `String` asociado. Si
  `TransportError` lleva uno, S1 necesita test real. Restricción acordada:
  **sin payloads `String`**, y `APIError.custom` arrastra el mensaje del
  servidor — no entra.
- Vive en otro repo (`/Users/hiram/Desktop/PROYECTOS/spm-pro/CoreNetworking`),
  así que implica publicar `0.1.4` y re-fijar `Package.resolved`. Decisión ya
  tomada (OQ-18): el enum va al paquete, el copy (`AppErrorConvertible`) se
  queda en la app porque está en español y es producto.

**3. `process-judge`** tiene 1 sesión en cola. Su VERDICT la vacía.

**4. El push no está hecho** y necesita aprobación explícita del owner (§7).
Estrenaría el Anillo 3: `gates.yml` nunca ha corrido.

## Trampas de este repo que costaron horas descubrir

- **`verify-run` y el `reviewer` firman `sha256(diff staged)`.** Tocar
  cualquier archivo staged mata los dos markers. Ordena el trabajo para firmar
  una sola vez al final.
- **Pero un cambio de solo `docs/` o `tools/` no exige marker de review** — el
  gate lo dice explícitamente. No encadenes ciclos de review por una línea de
  ledger.
- **Si tocas `tools/` o `ci/`, `bash tools/tests/run-tests.sh` es obligatorio**
  y tarda ~3 min. Se me olvidó una vez y el reviewer encontró 3 tests rotos.
  Lánzalo en background.
- **Cero cifras derivables en la documentación.** `check-execution-map.sh`
  bloquea si escribes "20 tests" en el mapa. Escribe el comando que lo calcula.
  La misma regla aplica a las listas a mano: en esta sesión, tres necesitaron
  detector propio (`skill-matrix.conf`, la tabla NO-TOUCH del PRD, `KNOWN_FLAGS`).
- **Tocar `tools/`, `ci/`, `AGENTS.md` o `.agents/skills/**` exige autorización
  explícita del owner**, y la ruta debe recibir fila en la tabla de
  autorizaciones de §5b del PRD. Deriva la lista con el comando del DoD, no a
  mano: ya se quedó corta dos veces.

## Cómo trabajar aquí, que es lo que más me habría servido saber

- **Verifica antes de afirmar.** Este harness castiga las afirmaciones no
  comprobadas, y con razón. Varias veces di algo por cierto (que un test
  comprobaba lo que su nombre decía, que un finding estaba cerrado, que un
  comando había fallado) y no lo estaba.
- **Al medir un exit code, no lo tomes después de un pipe** — leerás el del
  último comando del pipe. Me pasó dos veces.
- **Cada test nuevo, prueba de bolsillo**: rompe a propósito la lógica que dice
  cubrir y comprueba que muere. En esta sesión aparecieron cuatro tests que
  pasaban con cualquier implementación, y tres los escribí yo.
- **Arregla la clase, no el caso.** El patrón que más se repitió fue corregir
  el sitio donde apareció el problema sin propagarlo a las secciones que se
  marcan o se ejecutan. El design-review lo encontró seis veces seguidas.
- **Antes de inventar una comprobación, mira si ya existe.** El mejor arreglo
  de la sesión fue usar `require_flag_values`, que llevaba veinte líneas más
  arriba en el mismo archivo desde el principio.
- **Los sub-agentes se equivocan.** Uno afirmó que la tabla NO-TOUCH omitía una
  ruta; leyó medio comando. Comprueba antes de actuar sobre lo que digan.

## Findings abiertos: 14

Los que tocan lo que vas a hacer: `f-3480a974` (el trabajo del SPM),
`f-52ef5f6d` (decisión `CancellationError` vs `.unknown`, bloquea paginación y
el decorador de caché), `f-54d7ee41` (`@State` duplicando dueño de identidad),
`f-7b10426e` (sentinela T-S-1), `f-update-sin-guard` (`update` puede resucitar
un finding cerrado; el reviewer propone que deje de aceptar campos de state
machine, en vez de un sexto parche).

`bash tools/findings/findings.sh list --status open` para verlos todos.

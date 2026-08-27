# scripts/agent-hooks — gates de IA compartidos (Anillo 2)

> **Una sola implementación de los gates, tres clientes.** Cada cliente tiene un sistema de
> hooks distinto (eventos y contratos de I/O diferentes), pero la lógica de los gates vive
> **aquí, una sola vez**. Cada cliente solo aporta un wrapper delgado:
>
> - Claude → `.claude/settings.json` (contrato nativo: exit 2 + stderr / JSON por evento)
> - Cursor → `.cursor/hooks.json` → `adapters/gate-adapter.sh cursor …` (traduce a `{"permission":"deny"}`)
> - Codex → `.codex/hooks.json` → `adapters/gate-adapter.sh codex …` (traduce a `{"permissionDecision":"deny"}`)
>
> Cobertura desigual y declarada: solo Claude Code tiene SubagentStop (derivación del marker),
> Stop (canon-enforce) y SessionStart. El backstop de lo que falte en cada cliente es SIEMPRE
> el Anillo 1 (lefthook) + Anillo 3 (CI). Tras cada update de un cliente: `bash tools/validate-harness.sh`.

## La capa de normalización: `lib/io.sh`

Abstrae las diferencias entre clientes:

| Concepto | Claude | Cursor/Codex | `io.sh` lo expone como |
|---|---|---|---|
| input | stdin JSON `{tool_name, tool_input, session_id}` | stdin JSON con sus propias claves | `hook_tool`, `hook_file_path`, `hook_command`, `hook_session_id` |
| bloquear | `exit 2` + stderr (o JSON por evento, `hook_json_block`) | JSON de deny por stdout (lo emite `gate-adapter.sh`) | `hook_block "razón"` |
| permitir | `exit 0` | `{"permission":"allow"}` / `{}` (adapter) | `hook_allow` |
| detectar cliente | — | `conversation_id` presente (Cursor) | `hook_client` |

> Los gates hablan UN contrato (`exit 2` + stderr); Claude lo entiende nativo y
> `adapters/gate-adapter.sh` lo traduce al JSON propietario de Cursor/Codex. Ojo con
> `hook_json_block`: el shape correcto DEPENDE del evento (top-level `{"decision":"block"}`
> para Stop/SubagentStop, `permissionDecision` para PreToolUse) — emitir el shape equivocado
> no da error: el cliente lo ignora y el bloqueo no bloquea (`test_hook_json_shapes.sh`).

## Los gates

| Script | Evento Claude | Evento Cursor | Evento Codex | Bloquea | Qué hace |
|---|---|---|---|---|---|
| `session-start.sh` | SessionStart `startup\|clear` (con `--report`: `resume`) | — | — | no | reset markers + estado + qué niveles están MUDOS (`--report` = solo estado) |
| `inject-context.sh` | UserPromptSubmit | beforeSubmitPrompt | — | no | estado vivo por turno: findings abiertos, cola de juicio, árbol sucio |
| `skill-reminder.sh` | PreToolUse Edit\|Write | — (sin evento pre-edición denegable) | — | **sí**¹ | leer-skill-antes-de-editar; matriz en `tools/skill-matrix.conf` (excluye docs/tooling — G1) |
| `post-edit-verify.sh` | PostToolUse Edit\|Write | afterFileEdit | — | no² | **verificación in-loop**: lint/typecheck del archivo tocado → `additionalContext` |
| `track-reads.sh` | PostToolUse Read | beforeReadFile | — | no | marca skills leídas |
| `track-trajectory.sh` | PostToolUse * | afterFileEdit | PostToolUse | no | trayectoria sin secretos |
| `track-failure.sh` | PostToolUse Bash\|Edit\|Write | — | — | no | detecta el bucle de reintentos leyendo el payload real (éxito resetea la racha) |
| `reviewer-gate.sh` | PreToolUse Bash | beforeShellExecution (adapter) | PreToolUse (adapter) | **sí**¹ | git-guard de flags + gate de `git commit`: ratchet + capas + semgrep + marker |
| `capture-review-verdict.sh` | SubagentStop | — | — | — | **el invariante nº1**: deriva el marker del `VERDICT:` real del sub-agente; el juez vacía su cola |
| `canon-enforce.sh` | Stop | stop | — | **sí** | reglas irrompibles (capas, secretos, harness con tests verdes) |
| `drift-stop.sh` | Stop | stop | — | **sí** | errores nuevos de drift vs baseline de sesión |
| `post-compact.sh` | SessionStart `compact` | — | — | no | reinyecta el digest de reglas + findings tras compactar contexto (SIN resetear estado) |
| `session-end.sh` | SessionEnd | — | — | no | encola la sesión en `judge-queue` si tocó código sin juicio (solo preset `full`) |
| `adapters/gate-adapter.sh` | — | (envuelve gates) | (envuelve gates) | — | traduce exit-2/stderr al JSON de deny del cliente |

> ¹ En preset `lite` (`tools/preset`) `skill-reminder` y el marker de review **avisan** en vez de
> bloquear. Los detectores mecánicos (drift-ratchet, capas, hallazgos de semgrep) siguen **duros
> en ambos presets** — ni `lite` ni `REVIEWER_OVERRIDE` los relajan (test_ratchets.sh lo fija).
>
> ² `post-edit-verify` no bloquea NUNCA por diseño: informa en el mismo turno. Un formateador con
> una opinión no puede trabar el trabajo; para bloquear están Stop y los Anillos 1/3.
>
> Cursor no expone SubagentStop/SessionStart/SessionEnd y Codex solo PreToolUse/PostToolUse:
> para ellos el backstop de esos gates es el Anillo 1 (lefthook) + Anillo 3 (`ci/run-gates.sh`
> + `ci/ai-review.sh`), y el marker se genera con `scripts/mark-reviewer-run.sh` (auditado) o
> preset `lite`. NO existen los eventos `PostCompact` ni `PostToolUseFailure` en ningún cliente
> — estuvieron registrados y jamás dispararon (lección 2026-08-07; `test_hook_events.sh` lo fija).

## El contrato de veredicto (VERDICT)

Los sub-agentes de review (`reviewer`, `security-reviewer`, `design-reviewer`, `process-judge`)
terminan su mensaje con `VERDICT: GREEN|AMBER|RED` + `FINDINGS: n` + `SCOPE: …`. El hook
`capture-review-verdict.sh` lo parsea (`lib/verdict.sh`) y **el sistema** escribe el marker —
nunca el modelo. `tools/check-review-marker.sh` solo acepta `source: hook`, ligado al `sha256`
del diff staged. Alcance honesto: defiende contra *error de proceso*, no contra un agente
adversario con shell — para eso está el Anillo 3 (ver README raíz, "Qué garantiza y qué no").

## Telemetría (nivel 9)

`hook_log_detection <source> <rule> <area> [n] [duration_ms] [phase]` (en `lib/io.sh`) registra
cada detección en `.agents/state/metrics/detections.jsonl` (local, gitignored). Emite JSONL v2
con `event_id`, fase, commit y `triage:"unknown"`; si el gate no midió latencia,
`duration_ms` queda en `null`, nunca en un cero inventado. Los callers v1 conservan su fase por
un mapeo explícito de `source`. `tools/metrics/read-events.py` permite a los reportes consumir
mezclados eventos v1 y v2 sin reescribir el histórico: v1 queda `triage=unknown` y sin identidad.

Contrato duro: **best-effort total — la telemetría jamás rompe al gate que la llama** (devuelve
0 pase lo que pase; hay test que lo fija sin python3 en el PATH). Un evento sigue siendo
actividad, no un finding ni un true-positive; el triage se vuelve durable únicamente cuando
`findings.sh add/import --source-event <event_id>` lo enlaza al ledger.

## Tests

Los gates son código: `tools/tests/` los fija (run-tests.sh imprime el conteo real), y `test_meta_fp.sh` exige que todo
detector tenga **tests de sus falsos positivos** — la lección más cara del PRD 0001: el primer
FP de un detector casi siempre aparece en el repo del propio detector.

## Notas de portabilidad

- **Nombres de tools varían entre clientes.** `skill-reminder.sh` y `track-reads.sh` filtran por
  nombre de tool (`Edit`, `edit_file`, `search_replace`, …). <!-- FILL: ajusta los `case` a los
  nombres reales que veas en `track-trajectory` de tu cliente. -->
- **Cursor no tiene un evento pre-edición que deniegue**: el skill-reminder NO corre en Cursor;
  ahí la matriz de skills es instrucción (`.cursor/rules/`) y el backstop es el Anillo 1+3.
- **Failure-open**: todos hacen `exit 0` ante glitch. El backstop de lo que se cuele es el Anillo 3.
- **Los hooks `Stop` tienen un escape en Claude Code:** tras **8 bloqueos consecutivos** Claude
  anula el hook y cierra el turno igual. Por eso `canon-enforce`/`drift-stop` son una *red rápida*,
  no el muro final — las reglas que DEBEN cumplirse sí o sí viven también en el Anillo 1 (pre-commit)
  y el Anillo 3 (CI), que no tienen ese escape.

# ci/ — Anillo 3 (CI), obligatorio en `full` y provider-agnóstico

> **No imponemos ningún proveedor de CI.** El Anillo 3 es un único script,
> `ci/run-gates.sh`, que corre los mismos gates server-side. En preset `full` lo invocas desde
> el CI que elijas; en `lite`, no tener CI es una pérdida explícita que el arranque declara.

<!-- BEGIN GENERATED: capabilities -->
| Capacidad | Requerida en full | Requerida en lite | Proveedor | Garantía |
|---|:---:|:---:|---|---|
| `architecture_complexity` | no | no | `tools/architecture-check.sh architecture_complexity` | Complejidad ciclomática |
| `architecture_cycles` | no | no | `tools/architecture-check.sh architecture_cycles` | Detección de ciclos |
| `architecture_import_direction` | sí | sí | `tools/check-layers.sh` | Dirección de imports directos |
| `review_marker` | sí | no | `tools/check-review-marker.sh` | Evidencia de review ligada al diff |
| `ring3` | sí | no | `tools/check-ring3.sh` | Backstop de CI |
| `semgrep` | sí | sí | `tools/probe-capability.sh semgrep` | Análisis AST funcional |
| `skill_reminder` | sí | no | `scripts/agent-hooks/skill-reminder.sh` | Lectura obligatoria por path |
<!-- END GENERATED: capabilities -->

## Por qué existe

Es el **backstop independiente del cliente**. Cubre lo que los hooks locales no pueden:

- **Codex/Cursor** tienen cobertura parcial de hooks → CI cubre los eventos y veredictos que
  sus adapters locales no pueden derivar.
- Commits con `git commit --no-verify` (saltan el Anillo 1).
- Máquinas/CI sin `lefthook` instalado.

## Cómo conectarlo

Copia el ejemplo de tu proveedor desde `ci/examples/` y bórrale el `.example`:

| Proveedor | Destino |
|---|---|
| GitHub Actions | `.github/workflows/gates.yml` |
| GitLab CI | `.gitlab-ci.yml` |
| Bitbucket | `bitbucket-pipelines.yml` |
| Azure | `azure-pipelines.yml` |
| Jenkins | `Jenkinsfile` |

Todos hacen lo mismo: instalan `gitleaks` y ejecutan `bash ci/run-gates.sh`. La lógica vive en
el script, no en el YAML → cambiar de proveedor no cambia los gates.

## Qué corre `run-gates.sh` (barato → caro)

1. **tests del harness** (`tools/tests/`) — si los gates están rotos, el resto no significa nada.
2. **secret-scan** (gitleaks, historial) — obligatorio en CI.
3. **semgrep** (patrones AST) — fail-closed: aquí "no pude mirar" también falla.
4. **check-layers** — baseline de dirección sobre imports directos; no detecta ciclos.
5. **drift-ratchet** — el conteo de deuda no puede haber subido.
6. **build & tests** — `<!-- FILL: tu stack -->`.
7. **mutation-score** — informativo con piso 0; **obligatorio automáticamente** en cuanto el
   piso sube de 0 (si no, desinstalar el runner sería una forma de "aprobar").
8. **review + evidencia** — `check-review-marker --range`, `ci/ai-review.sh` (review de IA
   headless con contexto fresco: cubre Codex y commits humanos) y `lesson-detector-link.sh`
   (toda lección tiene detector).

## FAIL-CLOSED por defecto

Este es el único anillo que no depende de que el agente se porte bien, así que una herramienta
ausente **no** se lee como "gate aprobado". Renunciar a un gate es explícito y visible en la
config del CI: `AI_REVIEW_REQUIRED=0`, `GATES_REQUIRE_SEMGREP=0`, `GATES_SKIP_TESTS=1`.
(En local la política es la inversa para los fallos del propio detector — exit 3 avisa sin
bloquear — porque un typo en las reglas no puede impedir el commit que lo arregla: §14.3.)

`ci/run-gates.sh --backend <nombre>` reenvía la selección a `ci/ai-review.sh` y al
`tools/agent-runner.sh` (default: `claude`).
Cada adapter declara `review+read_only`; el backend Claude necesita su CLI y autenticación.
Todos emiten el mismo contrato `VERDICT:`: GREEN/AMBER pasan, RED falla el job.

> Recomendación: corre también un job **nocturno** con `GATES_SECRET_MODE=history` para validar
> que el scrub histórico de secretos se mantiene.

# Agentic Workflow Template

> Un **cascarón reutilizable** para trabajar con agentes de IA (Cursor, Claude Code, Codex)
> de forma disciplinada, segura y portable — en proyectos **iOS, Android, web o backend**.
>
> No es un framework de código: es una **forma de trabajar** codificada en archivos que
> los agentes leen y en *gates* que se ejecutan solos. La empresa lo clona, rellena los
> placeholders de su stack, y arranca con governance desde el día 1.

---

## Alcance real, sin marketing

Este harness aplica su propia regla —*declara lo que NO cubres*— a sí mismo. Lo que hay hoy,
medido, no prometido:

| | Estado | Qué significa al adoptarlo |
|---|---|---|
| **La maquinaria** (anillos 0–3, hooks, trinquetes, marker, ledger, selftest) | **Curtida** — validada en un proyecto real de principio a fin | Portable. No depende del lenguaje. |
| **iOS** (Swift 6 / SwiftUI / MVVM-C / Swift Testing) | **Curtido** — reglas semgrep AST, lint in-loop, capas, skills con ejemplos reales | `/adoptar` y a trabajar. |
| **Android · web · backend** | **Skeleton** — el esqueleto está, los detectores no | Adoptarlo aquí **no es rellenar FILLs**: es escribir de cero el nivel 1 (lint/typecheck in-loop), el nivel 2 (reglas AST) y el nivel 4 (runner de mutación) para tu stack. Cuenta con **una tarde larga**, no diez minutos. |

Concretamente, hoy hay reglas semgrep para `swift` y `universal`, y `post-edit-verify` está
cableado para `.swift`, `.sh` y `.json`. No se publica un conteo manual de placeholders:
`session-start` y `validate-harness` reportan el estado operativo en cada copia. Te dirán qué
niveles están MUDOS en TU proyecto — esa es la fuente de verdad, no esta tabla.

**Por qué se dice así de claro:** la lección más cara de este harness es que un gate anunciado
y no operativo es peor que uno ausente, porque compra confianza falsa. Sería incoherente
cometer ese error en el propio README.

---

## Qué resuelve

Cada equipo que adopta agentes de IA tropieza con lo mismo: el agente inventa cuando no sabe,
mete secretos en el código, ignora las convenciones, hace scope creep, y la "memoria" del
proyecto se pierde entre chats. Este template impone un **flujo de principio a fin** con
defensa en capas, y lo hace **compatible con los tres clientes que usan los devs hoy**.

## Filosofía (no negociable)

1. **El que escribe nunca es el que aprueba, y "aprobar" es presentar evidencia.** Un veredicto
   es la salida de un comando, un exit code o un score — **nunca** una afirmación del modelo.
   Los markers los escribe el sistema (hooks), no el agente.
2. **Cázalo en la capa más barata.** Tipos → lint → AST → test → mutación → review IA → humano.
   Cada nivel que sube un defecto multiplica ~10× su coste. Un error que el compilador podía
   cazar y llega a un juez de IA es un fallo de diseño del harness, no del agente.
3. **Un detector con >10% de falsos positivos es peor que no tenerlo** (ley de Tricorder). El
   equipo lo desactiva y el agente aprende a evadirlo. Preferimos 5 reglas AST exactas a 50 greps.
4. **Detectar no basta — hay que CERRAR.** Cada hallazgo llega a un estado terminal y visible
   (arreglado o aceptado-con-razón). Ver `tools/findings/`.
5. **Toda lección se convierte en un detector.** Es el único mecanismo por el que la necesidad
   de revisión humana decrece en vez de mantenerse plana.
6. **Una fuente de verdad, muchos clientes.** `AGENTS.md` es canónico; cada cliente tiene un
   adaptador delgado. Nada se duplica.
7. **El que toca, cierra.** Si tocas un módulo con findings abiertos, los resuelves o los registras.
8. **Open Question > suposición silenciosa.** Si el agente no sabe, pregunta; no inventa un default.

## La pirámide de verificación

El corazón del template. Detalle completo en
`.agents/skills/process/references/verification-loop.md`.

| # | Nivel | Implementado en |
|---|---|---|
| 9 | Métricas + lección→detector | `tools/metrics/escape-rate.sh` · `tools/lesson-detector-link.sh` |
| 8 | Gate por evidencia | `capture-review-verdict.sh` (SubagentStop) · marker ↔ `sha256(diff)` · `/goal` |
| 7 | Review adversarial de IA | sub-agentes `reviewer`/`security-reviewer` · plugin `security-guidance` · `ci/ai-review.sh` |
| 6 | Arquitectura | `tools/check-layers.sh` + `tools/layers.conf` (dirección de imports directos) |
| 5 | Contratos | suite de conformidad fake ≡ real (`domain/SKILL.md`) |
| 4 | **Calidad del test** | `tools/mutation-score.sh` + trinquete que **solo sube** |
| 3 | Spec ejecutable | TDD red-first + aserciones/DbC (`tdd-workflow.md`) |
| 2 | Patrón semántico | `tools/semgrep/rules/*.yaml` (AST, no texto) |
| 1 | Determinista in-loop | `post-edit-verify.sh` (PostToolUse → `additionalContext`) |
| 0 | Imposibilitar | tipos, `-Werror`, exhaustividad (`AGENTS.md §2`) |

> El nivel 4 es el que más importa con código escrito por IA: la función objetivo de un agente
> es *"que los tests pasen"*, y la forma más barata de conseguirlo es escribir tests que no
> comprueban nada. El mutation score es el único gate que los distingue.

## Los anillos 0–3 de enforcement (el "plus" cross-tool)

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

| Anillo | Mecanismo | Dispara en | Para qué |
|---|---|---|---|
| **0 — permisos nativos** | `permissions` de `.claude/settings.json` | Claude Code, antes de ejecutar la tool | Prohibiciones deterministas: `--no-verify`, `--force`, leer `.env`, editar trinquetes. **Ni siquiera llega a ejecutarse.** |
| **1 — git-nativo** | `lefthook.yml` | Cursor, Claude, Codex, **humano**, todo `git commit` | Secretos, trinquete de drift, capas, **marker de review**, lint. **La única capa universal.** |
| **2 — hooks de IA** | `.claude/settings.json` + `.cursor/hooks.json` + `.codex/hooks.json` → `scripts/agent-hooks/` | Claude Code (completo) / Cursor y Codex (parcial, vía `gate-adapter`) | Gates *AI-aware*: verificación in-loop, skill-antes-de-editar, reviewer-gate, **derivación del veredicto** (solo Claude), reinyección post-compactación (solo Claude). |
| **3 — CI (BYO; obligatorio en `full`)** | `ci/run-gates.sh` + `ci/ai-review.sh` desde *tu* CI | server, cada push/PR + nocturno | Backstop independiente del cliente: mutación, semgrep, **review de IA headless**. Cubre commits humanos y todo lo que los hooks de cada cliente no alcanzan. |

> **Anillo 0 es nuevo y es el más barato:** una prohibición expresable como patrón va en
> `permissions.deny`, no en prosa de `AGENTS.md`. El texto es advisory —el modelo puede
> ignorarlo o perderlo tras una compactación—; el permiso es determinista.

> **Por qué 0–3:** los permisos y hooks de IA bloquean rápido y local, pero cada cliente cubre un
> subconjunto distinto (Claude Code: todo; Codex: PreToolUse/PostToolUse vía `gate-adapter`;
> Cursor: shell/stop, sin derivación de marker). Los git hooks nativos disparan para *todos*
> los clientes y humanos, pero se pueden saltar con `--no-verify` → por eso CI es el backstop final.
>
> **Regla operativa de confianza:** ningún gate cuenta como existente hasta que lo has visto
> bloquear algo una vez. `bash tools/validate-harness.sh` verifica lo estático (eventos,
> permisos, scripts, matriz) e imprime el checklist EN VIVO — córrelo tras cada update de
> Claude Code / Cursor / Codex.
>
> **CI es "bring your own".** No imponemos GitHub. El Anillo 3 es un único script
> (`ci/run-gates.sh`) que corre los mismos gates; en preset `full` debes invocarlo desde el
> proveedor que elijas (GitHub Actions, GitLab CI, Bitbucket, Azure o Jenkins). En `lite`, operar
> sin CI es una pérdida explícita que `session-start` declara. Los YAML de `ci/examples/` son stubs.
>
> **Capa nativa de Claude Code (opcional, la más fuerte para empresa).** Para enforcement que
> NI `--no-verify` NI los flags de CLI pueden saltar, despliega `enterprise/managed-settings.example.json`
> en la ruta de OS que toque (precedencia máxima; el nombre YA desplegado es
> `managed-settings.json` y no vive en el repo). Y para bajar el coste de re-lectura, `.claude/rules/` carga la skill del
> área por path de forma nativa. Detalle en `enterprise/README.md`.

## Mapa de archivos

```
AGENTS.md                  ← FUENTE CANÓNICA (la leen Cursor, Codex, Copilot, Gemini…)
CLAUDE.md                  ← adaptador delgado: @AGENTS.md + maquinaria Claude-only
ios|android|web/AGENTS.md  ← overrides por plataforma (el más cercano gana)

.claude/
  settings.json            ← Anillo 0 (permissions) + Anillo 2 (hooks) + enabledPlugins
  agents/                  ← sub-agentes; todos emiten el contrato VERDICT:
  security-patterns.yaml   ← reglas de seguridad per-edit (coste 0 tokens)
  claude-security-guidance.md ← threat model para el revisor de contexto fresco
  rules/                   ← recordatorios cortos path-scoped (el gate duro es skill-matrix.conf)
  skills → .agents/skills
.claude/commands/           ← /adoptar (rellena los FILL entrevistándote) · /historia (idea → historia de backlog) · /goal (objetivo verificable, nivel 8) · /reconciliar (drift spec↔código)
.cursor/                   ← rules/*.mdc + hooks.json (eventos REALES de Cursor + gate-adapter)
.codex/config.toml         ← config Codex (lee AGENTS.md directo)
.codex/hooks.json          ← hooks Codex (2026): reviewer-gate vía gate-adapter

scripts/agent-hooks/       ← UNA implementación de los gates, compartida por Claude+Cursor+Codex
  run-hook.sh                ← ⭐ lanzador: `bash -n` al hook y a sus libs ANTES de ejecutarlo.
                               Sin él, un hook con marcadores de conflicto se leía como DENY y
                               dejaba al agente sin poder ni diagnosticarlo
  adapters/gate-adapter.sh   ← traduce exit-2 al JSON de deny de Cursor/Codex
  capture-review-verdict.sh  ← ⭐ SubagentStop: deriva el marker del veredicto REAL
  reviewer-gate.sh           ← PreToolUse Bash: git-guard + marker de review + capas + semgrep
  skill-reminder.sh          ← PreToolUse Edit/Write: BLOQUEA si no leíste la skill del path
  post-edit-verify.sh        ← ⭐ verificación in-loop (nivel 1 de la pirámide)
  post-compact.sh            ← reinyecta reglas tras compactar el contexto
  canon-enforce.sh · drift-stop.sh ← Stop: reglas irrompibles y drift nuevo (bloqueantes)
  session-start.sh           ← estado del proyecto + reset de markers al abrir sesión
  session-end.sh             ← encola la sesión para el process-judge si tocó código
  track-failure.sh           ← detecta al agente atascado en un bucle de reintentos
  track-reads.sh · track-trajectory.sh ← lecturas de skills y trayectoria (sin secretos)
  inject-context.sh          ← estado vivo por turno (findings abiertos, cola de juicio)
  lib/io.sh                  ← normalización Claude/Cursor + hook_log_detection (telemetría)
  lib/json.sh                ← emisor JSON único (jq → python3): un JSONL con `printf` es un
                               formato solo hasta el primer valor con comillas o CR/LF
  lib/verdict.sh · lib/skill-matrix.sh ← parseo del VERDICT y de la matriz path→skill

tools/
  preset                     ← `full` (los gates bloquean) | `lite` (avisan). Lo lee cada gate
  project.conf               ← ⭐ `project_kind` DECLARADO: qué es el producto de este repo.
                               La declaración gobierna el criterio de scope; la evidencia solo
                               verifica y una contradicción avisa (exit 3 en CI). Es tuyo: el
                               upgrade no lo pisa
  lib/scope.sh               ← fuente única de ese criterio para los dos markers de abajo
  check-layers.sh + layers.conf  ← baseline de dirección de imports directos (nivel 6)
  architecture-check.sh          ← estado explícito de ciclos/complejidad por adapter
  check-source-sets.sh           ← EL invariante de KMP: commonMain no importa plataforma
  semgrep/rules/ + semgrep-scan.sh ← detectores AST (nivel 2; exit 3 = "no pude mirar")
  gate-cache.sh                 ← reutiliza solo Semgrep staged 0/0 con identidad completa + TTL
  mutation-score.sh + mutation-ratchet.json ← calidad del test (nivel 4) — SOLO SUBE
  check-review-marker.sh     ← verificación local de review en git hooks/adapters
  verify-run.sh + verify.conf + check-verify-marker.sh
                             ← ⭐ el MISMO invariante, para los TESTS: firma el diff staged solo
                               si el comando de verify.conf salió 0. Antes se podía commitear
                               un árbol que nadie llegó a compilar, con todo en verde
  agent-runner.sh + agent-backends/ ← boundary portable (`run` / `review`) para invocar un
                               sub-agente sin atarse a un cliente; backends intercambiables
  capabilities.json + render-capabilities.sh ← manifiesto de capacidades: GENERA los bloques
                               `<!-- GENERATED -->` de esta doc y falla si divergen del manifiesto
  probe-capability.sh        ← ausente / roto / operativo son tres hechos distintos, y se dicen
                               distinto (un binario instalado no es un detector que funcione)
  drift-ratchet.json + drift-ratchet.sh + check-drift.sh ← trinquete de deuda — SOLO BAJA
  lesson-detector-link.sh    ← toda lección tiene detector, y el detector (archivo Y test) existe
  check-finding-refs.sh      ← un id de finding citado en la doc resuelve contra el ledger
  check-execution-map.sh     ← el mapa canónico no declara cifras que un comando recalcula
                               (una cifra derivable en doc vivo es una mentira futura garantizada)
  check-skill-matrix-doc.sh  ← la tabla de AGENTS.md §11 y skill-matrix.conf no divergen
  check-version-claims.sh    ← declarar una herramienta incapaz por versión exige citar el
                               repositorio: `brew` sirve el último RELEASE, no lo que soporta
                               el proyecto (nos costó dar el nivel 4 por imposible durante semanas)
  skill-matrix.conf          ← FUENTE ÚNICA de la matriz path→skill (la lee skill-reminder)
  secret-scan.sh + secret-baseline.sh ← secretos sin depender de que gitleaks esté instalado
  upgrade.sh                 ← trae mejoras del template a tu proyecto (merge 3-vías + verificación)
  validate-harness.sh        ← ¿los gates EXISTEN de verdad? estático + checklist en vivo
  harness-report.sh          ← empaqueta la evidencia dispersa en UN markdown pegable
  findings/findings.sh       ← CLI del ledger (bash+python3, único runtime)
  metrics/escape-rate.sh     ← contención por fase: ¿puedo bajar la revisión humana?
  tests/                     ← suite de shell de los propios gates (el total real lo imprime
                               run-tests.sh; no se mantiene un conteo manual)
                               (⅓ son casos de FALSO POSITIVO; test_meta_fp lo exige)

ci/run-gates.sh + ci/ai-review.sh + ci/examples/ ← Anillo 3 (provider-agnóstico)
lefthook.yml + .gitleaks.toml                    ← Anillo 1
.agents/skills/            ← base de conocimiento; el enforcement portable lo da
                             skill-matrix.conf + skill-reminder (paths nativos son cliente-específicos)
backlog/                   ← historias de usuario tipo Jira → tools/backlog/run.sh las
                             trabaja una a una en ramas story/NNNN (PRD 0003; merge = humano)
docs/PLAYBOOK.md           ← el día a día del programador: los 4 flujos + qué hacer si un gate bloquea
docs/ONBOARDING-IA.md      ← runbook para el AGENTE que estrena el harness: "lee esto y guíame"
docs/EXAMPLES.md           ← 4 escenarios iOS end-to-end: bug, feature con PRD, /goal, backlog
docs/process/              ← PRDs, lessons (con detector obligatorio), execution map, ledger
.claude-plugin/            ← (opcional) plugin.json + marketplace.json
enterprise/                ← (opcional) managed-settings.example.json: enforcement NO anulable
```

## El invariante que sostiene todo

```
Agent(reviewer) ──► emite "VERDICT: GREEN"
                        │
              SubagentStop hook  ← el SISTEMA lee el mensaje final real
                        │
              escribe marker {verdict, head, sha256(diff staged), source: hook}
                        │
git commit ──► Anillo 1 valida el marker; Anillo 2 lo deriva donde el cliente lo soporta
```

Antes, el marker lo escribía un script que **el modelo** invocaba: un agente que quería
commitear solo tenía que ejecutarlo. El gate de review era decorativo. Ahora la evidencia la
produce el sistema a partir del veredicto real, y está ligada al hash del diff exacto que se
va a commitear.

**Y el mismo invariante para los TESTS, no solo para el reviewer.** Durante meses ninguna
ejecución de build o de tests se ligaba a ese diff, así que se podía commitear un árbol que
**nadie llegó a compilar** con todo en verde: el reviewer no compila, los trinquetes no
compilan y las capas tampoco. `tools/verify-run.sh` ejecuta el comando de `tools/verify.conf`
—fuente única, compartida con el Anillo 3— y **solo si sale 0** firma ese mismo
`sha256(diff staged)`; `tools/check-verify-marker.sh` lo exige. El flujo es el que ya pedía el
review: **stagea → verifica → commitea**.

### Qué garantiza y qué no

**Defiende contra error de proceso** — el agente que se olvida de invocar al reviewer, que da
por buena su propia revisión, o que pierde la regla tras compactar el contexto. Es el caso
abrumadoramente común y antes no estaba cubierto.

**No defiende contra intención.** Un agente con acceso a Bash puede escribir el archivo de
marker a mano: `check-review-marker.sh` valida su *contenido*, no su *procedencia*. En una
máquina de un solo usuario, un agente con shell puede hacer lo que puede hacer el usuario.

**La defensa contra intención es el Anillo 3.** En CI el marker local no viaja, y
`ci/ai-review.sh` corre una review independiente en una máquina que el agente no controla. Esa
es la razón real de que existan capas 0–3 y no una sola.

> Este límite lo encontró el sub-agente `reviewer` revisando el commit que introdujo el
> mecanismo, con un repro ejecutable. La versión inicial de este README decía "infalsificable".
> Está en `docs/process/lessons_learned.md` y en el PRD 0001 §18 G9.

## Battle-tested against itself

Este harness **se construyó bajo sus propias reglas**, y el historial de git es la demo — cada
afirmación de abajo es un commit que puedes leer:

- **Los gates bloquearon a su propio autor.** El agente que implementó el harness dio el
  trabajo por terminado **seis veces**, y en las seis una capa de verificación encontró fallos
  reales: el sub-agente `reviewer` acumuló **17 hallazgos en 7 rondas** (entre ellos, refutar
  con un repro ejecutable la afirmación de que el marker era "infalsificable" — `3b66e7e`), y
  `canon-enforce` bloqueó un cierre de turno en vivo.
- **Los detectores se detectaron a sí mismos.** Tres veces: `skill-reminder` bloqueó editar la
  documentación de su propia área, el detector de secretos marcó como secreto al archivo que
  define qué es un secreto, y el linter de shell matcheó sus propios comentarios. De ahí la
  regla mecanizada en `test_meta_fp.sh`: *el primer falso positivo de un detector casi siempre
  aparece en el repo del propio detector* — y por eso ~⅓ de la suite son casos de falso
  positivo.
- **El fail-closed encontró reglas muertas.** La primera vez que semgrep corrió de verdad,
  reveló que **ninguna de las 6 reglas había cargado jamás** (3 errores que `--validate` no
  detecta) — y el contrato de exit codes recién introducido lo convirtió en aviso en vez de en
  silencio (`90621c4`).
- **Arreglar un hallazgo introdujo uno peor, tres veces** — incluido un deadlock donde un typo
  en las reglas habría bloqueado hasta el commit que lo arreglaba (`4f48c49`, resuelto con la
  distinción exit 1 "tu código falla" vs exit 3 "no pude mirar"), y un `grep` sin `-F` que
  trataba datos como patrones (`9060635`, con test verificado por mutación manual).
- **Findings y lecciones son evidencia calculada, no conteos copiados.**
  `bash tools/findings/findings.sh list --status open` muestra la deuda vigente y
  `bash tools/lesson-detector-link.sh` verifica tanto el tramo vivo como el archivo histórico.
  Las lecciones mecanizadas salen del contexto obligatorio mediante `lessons-rotate.sh` sin
  perder su detector ni su trazabilidad.

Ningún proceso produce cero errores. Este produce errores **que se detectan, se cierran y se
vuelven imposibles de repetir** — que es la única promesa honesta que un harness puede hacer.

## Relación con spec-driven development (SDD)

Este template es **un harness SDD hecho a medida** con governance mecánica encima: su flujo
PRD → design-review → implementación → reviewer → judge es la misma familia que **GitHub Spec Kit**
(`/speckit.constitution|specify|plan|tasks|implement`) y **AWS Kiro** (Requirements → Design → Tasks).
Mapeo casi 1:1: `AGENTS.md` ≈ *constitution* · PRD ≈ *specify* · design-review ≈ *plan* ·
sub-agentes ≈ *tasks/implement* · reviewer/judge ≈ *analyze*. La diferencia: aquí el enforcement
(anillos 0–3, drift-ratchet, findings-ledger, reviewer-gate) es **mecánico y cross-tool**, algo que
Spec Kit no trae. Si ya usas Spec Kit, adopta su vocabulario de comandos y monta estos gates encima.

## Cómo se adopta

Ver **`docs/ADOPTION.md`**. En corto: clona → corre `scripts/bootstrap.sh` → rellena los
`<!-- FILL: ... -->` de tu stack → `lefthook install` → empieza a trabajar.

## Convenciones de placeholders

- `<!-- FILL: ... -->` — la empresa DEBE completarlo con su stack (arquitectura, navegación, DI…).
- `<!-- OPINIÓN: ... -->` — mi recomendación por defecto; bórrala o cámbiala.
- `<PROJECT>` / `<project>` — reemplaza por el nombre real (hay un script que lo hace).
- `<PLATFORM>` — `ios` | `android` | `web` | `backend`.

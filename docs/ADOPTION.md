# Adopción del template

> Cómo una empresa (o un proyecto personal) clona este cascarón y lo deja operativo.
> Tiempo estimado: ~30-60 min para el setup mecánico + el tiempo de rellenar las skills
> de tu stack (eso es trabajo de ingeniería real, no mecánico).

---

## 0. Pre-requisitos

| Herramienta | Para qué | Obligatoria |
|---|---|---|
| `git` | todo | sí |
| [`lefthook`](https://github.com/evilmartians/lefthook) | Anillo 1 (git hooks) | sí |
| [`gitleaks`](https://github.com/gitleaks/gitleaks) | secret-scan | sí |
| [`semgrep`](https://semgrep.dev) | detectores AST (nivel 2 de la pirámide) | sí — sin él el nivel 2 está MUDO (local avisa, CI bloquea) |
| `python3` | `tools/findings/findings.sh` (ledger) + utilidades | sí (viene en macOS/Linux) |
| `jq` | hooks de IA (parsing JSON) | sí para el Anillo 2 |
| Runner de mutación (muter/Stryker/PIT/mutmut) | nivel 4: calidad real de los tests | recomendada — sin él nada distingue un test real de uno decorativo |
| Tu CI (GitHub/GitLab/…) | Anillo 3 | sí en `full`; pérdida explícita en `lite` |

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

> `bash scripts/agent-hooks/session-start.sh` (o abrir cualquier sesión de Claude/Cursor) te
> dice **qué niveles de la pirámide están MUDOS** en tu máquina. Confía en ese reporte, no en
> tu memoria: un gate anunciado y no operativo es peor que uno ausente.

### macOS: permisos de carpeta (léelo si tu repo vive en Escritorio/Documentos)

macOS protege `~/Desktop`, `~/Documents` y `~/Downloads` a nivel de aplicación (TCC). Si el
proyecto vive ahí y la app que corre tu agente no tiene permiso, el shell recibe
`Operation not permitted` en TODO — hasta `ls` sobre su propio directorio — y el síntoma
confunde a propósito: parece un sandbox del harness y no lo es (vivido el 2026-08-26,
f-237347df (del template)). Tres cosas que saber:

1. **Remedio:** Ajustes del Sistema → Privacidad y seguridad → *Acceso total al disco* (o
   *Archivos y carpetas* → Escritorio) para la app del agente — y **reinicia la app**: los
   cambios de TCC no aplican a procesos ya vivos.
2. **Abrir la sesión directamente en la carpeta del proyecto** concede el permiso por el flujo
   normal; un cambio de directorio en caliente hacia otra carpeta protegida NO dispara el
   prompt del sistema y deja al shell ciego.
3. La alternativa sin tocar permisos: mover el repo fuera de las carpetas protegidas
   (p. ej. `~/code/`).

## 1. Traer el harness a tu proyecto

**Elige tu caso — y ten claro qué implica cada uno para los upgrades futuros**, porque hasta
hoy este documento decía una cosa aquí y la contraria en §9b, y el adoptante se quedaba con un
camino de actualización que no podía funcionar.

**Caso A — proyecto NUEVO, desde el template.** Conserva el parentesco: es lo que permite que
`upgrade.sh` haga un merge de 3 vías de verdad, donde git funde solo lo que no choca.

```bash
git clone <este-template> mi-proyecto && cd mi-proyecto
git remote rename origin template          # NO `rm -rf .git`: eso corta el parentesco
git remote add origin <tu-repo-nuevo>
bash scripts/bootstrap.sh                  # reemplaza <PROJECT>, plataformas, preset full/lite
```

**Caso B — proyecto que YA EXISTE** (lo normal: la app existe antes que el harness). Copia el
harness dentro y registra el template como remote. Los dos repos no comparten historia, así que
`upgrade.sh` entrará en **MODO SYNC** — trae la maquinaria, nunca toca tu contenido, y registra
el SHA sincronizado para aplicar solo el delta la próxima vez.

```bash
cd mi-proyecto-existente
git clone --depth 1 <este-template> /tmp/awt && rm -rf /tmp/awt/.git
cp -R /tmp/awt/. .                         # revisa el diff antes de commitear
git remote add template <este-template>
bash scripts/bootstrap.sh
```

> Si hiciste `rm -rf .git && git init` (lo que decía la versión anterior de esta guía), no has
> roto nada: estás en el Caso B y el modo sync te cubre. Solo añade el remote `template`.

## 2. Instalar los gates locales

```bash
lefthook install                 # Anillo 1 — activa pre-commit / pre-push
gitleaks version                 # verifica que está en PATH
bash tools/validate-harness.sh   # ¿los gates EXISTEN de verdad? (estático + checklist en vivo)
```

> **Regla de confianza:** ningún gate cuenta como existente hasta que lo has visto bloquear
> algo una vez. `validate-harness` verifica eventos, permisos, scripts y matriz en estático,
> e imprime el checklist de lo que solo una sesión real puede probar. Repítelo tras cada
> update de Claude Code / Cursor / Codex — sus contratos de hooks versionan rápido.

## 3. Elegir tu(s) cliente(s) de IA

Todos leen `AGENTS.md` (la fuente canónica). Solo activas el adaptador de los que uses:

- **Claude Code** — el cliente de primera clase (único con la historia completa): `CLAUDE.md`
  (importa `AGENTS.md`) + `.claude/settings.json` (Anillo 0 + hooks) + `.claude/agents/`
  (sub-agentes) + `.claude/commands/goal.md` + `.claude/rules/`.
- **Codex** — lee `AGENTS.md` directo, y desde 2026 **sí tiene hooks** (PreToolUse/PostToolUse):
  `.codex/hooks.json` conecta el reviewer-gate vía `gate-adapter.sh` (requiere
  `[features] codex_hooks = true`, ver `.codex/config.toml`). Sin Stop/SubagentStop: el marker
  de review se genera con `scripts/mark-reviewer-run.sh` (auditado) o preset `lite`; el
  backstop es Anillo 1 + 3.
- **Cursor** — lee `AGENTS.md` + `.cursor/rules/*.mdc`; `.cursor/hooks.json` da
  reviewer-gate (vía adapter), verificación in-loop y canon-enforce. Sin evento pre-edición
  denegable ni SubagentStop: skill-reminder es instrucción ahí, y el marker igual que en Codex.
- **Gemini CLI** — NO lee `AGENTS.md` por defecto: añade `context.fileName: ["AGENTS.md", "GEMINI.md"]`
  en su `settings.json`. (Tiene hooks desde v0.26 con contrato similar a Claude; wrapper
  pendiente — si lo usas, calca el patrón de `.codex/hooks.json`.)

> Puedes borrar los directorios de los clientes que NO uses. El `AGENTS.md` y el Anillo 1
> siguen funcionando igual.

## 4. Rellenar lo que es TUYO (el trabajo de verdad)

> **Atajo recomendado:** en una sesión de Claude Code, `/adoptar <explica tu stack>` — te
> entrevista (una sola tanda), rellena los FILL en el orden de impacto de abajo, deja como
> OPEN QUESTION lo que no sepas (jamás un default inventado), y al final te enseña con
> `session-start --report` qué niveles dejaron de estar MUDOS. Lo que sigue es el mismo
> proceso a mano.

Busca todos los marcadores y resuélvelos:

```bash
grep -rn "FILL:" . --include="*.md" --include="*.yml" --include="*.toml" --include="*.sh"
```

Prioridad de relleno (en orden de impacto — es la pirámide de
`.agents/skills/process/references/verification-loop.md` de abajo arriba):

1. `AGENTS.md` §2 — stack, build, tests, lint **y el modo estricto (nivel 0)**. Sin esto el
   agente vuela a ciegas y el compilador no te defiende de nada.
2. `scripts/agent-hooks/post-edit-verify.sh` §FILL — **el gate de mayor ROI**: lint/typecheck
   del archivo tocado, de vuelta al agente en el mismo turno. Media hora de trabajo, cambia
   el bucle entero.
3. `tools/mutation-score.sh` §FILL — el runner de mutación de tu stack, y una primera
   medición (`--update` fija el piso, que a partir de ahí SOLO sube). Es lo único que
   distingue un test que verifica de uno escrito para pasar.
4. `.agents/skills/architecture/SKILL.md` + `platforms/<tu-plataforma>.md` + `domain/SKILL.md`.
5. `tools/layers.conf` — reglas de dirección sobre imports directos de TUS rutas. Este baseline
   no demuestra ciclos ni dependencias transitivas.
   Para ciclos/complejidad, copia `tools/architecture.conf.example` a
   `tools/architecture.conf`: declara `unsupported` con razón o configura un adapter cuyo probe
   emita el marker exacto. Ausencia = `missing`; exit roto/marker ausente = `broken`.
   ⚠️  **Se AMPLÍA, no se reescribe.** Conserva los globs universales que trae
   (`*/Domain/*`, `*/domain/*`…) y añade los tuyos debajo. Sustituirlos rompe cinco tests
   del propio harness, que copian este conf a un sandbox con rutas genéricas (`src/Domain/`)
   — y el fallo aparece lejos del cambio, en la suite, no en tu proyecto.
   Ya no depende de que leas esto: `test_layers.sh::test_layers_conf_conserva_los_globs_universales`
   falla con la causa en el mensaje. Una regla de adopción que solo vive en un doc la
   descubre el adoptante *después* de perder la tarde; con detector, la descubre al minuto.
6. `tools/semgrep/rules/` — tus anti-patrones como reglas AST. **Ejecuta el scan una vez**
   (`bash tools/semgrep-scan.sh`): `--validate` solo valida el YAML, no el parseo por
   lenguaje — nos pasó (PRD 0001 §18 G15).
   El modo `--staged` reutiliza únicamente resultados totalmente limpios (`0 errors/0 warns`)
   durante 300 s. La identidad incluye diff, HEAD, targets, reglas, scanner, binario+versión y
   plataforma; `GATE_CACHE_TTL_SECONDS` ajusta el TTL. Corrupción/miss ejecuta Semgrep, un target
   con cambios no stageados desactiva el caché y exits 1/3 jamás se guardan. El modo `--all` y
   CI no sustituyen evidencia con esta optimización local.
7. `docs/process/current_execution_map.md` — estado del proyecto.
8. `CODEOWNERS` — sustituye los `@owner`.

> Mi opinión por defecto vive en `<!-- OPINIÓN: ... -->`. Acéptala o cámbiala; no es ley.

## 5. Conectar CI — OBLIGATORIO en preset `full` (AGENTS.md §14.4)

> Esto **era** "opcional" y era una contradicción con la propia doctrina. §14.3 justifica que
> un detector roto no bloquee en local diciendo *"CI sí lo bloqueará"*. Sin CI, esa frase es
> falsa: cada exit 3 pasa a ser **fail-open definitivo**. No te quedas "con dos anillos de
> tres": te quedas con dos anillos y con un razonamiento roto en los otros niveles, que es
> peor, porque el razonamiento no se nota que está roto.

Necesitas **las dos** cosas — sin remoto ningún CI puede ejecutarse:

```bash
git remote add origin <url-de-tu-repo>
git push -u origin HEAD
cp ci/examples/github-actions.yml.example .github/workflows/gates.yml
```

```bash
# GitLab:    cp ci/examples/gitlab-ci.yml.example         .gitlab-ci.yml
# Bitbucket: cp ci/examples/bitbucket-pipelines.yml.example bitbucket-pipelines.yml
```

Todos invocan el mismo `ci/run-gates.sh`, que por defecto cierra el fail-open
(`GATES_REQUIRE_SEMGREP=1`, y mutación auto-escalada en cuanto el piso supera 0).

Verifícalo: `bash tools/check-ring3.sh` — y en la primera ejecución **abre la pestaña de
Actions de tu proveedor y mira que el run pasa en verde**. Un workflow cableado que falla en
rojo desde hace semanas es otra vez el mismo modo de fallo: nadie lo mira, y parece cubierto.

Si de verdad vas a trabajar sin CI, cambia a preset `lite` (`echo lite > tools/preset`) para
que el harness deje de prometerte un backstop que no tienes. La pérdida está declarada en
cada `SessionStart`, que es la única forma honesta de operar sin él.

## 5b. (Opcional, empresa) Enforcement nativo no anulable + distribución como plugin

- **`enterprise/managed-settings.json`** — capa de precedencia máxima de Claude Code (ni `--no-verify`
  ni flags de CLI la saltan; bloquea force-push, `--no-verify`, lectura de secretos). Despliégala por
  MDM/Ansible a la ruta de OS. Detalle: `enterprise/README.md`.
- **`.claude/rules/`** — reglas path-scoped nativas (espejo de §11) que cargan la skill del área sin el
  coste de re-lectura forzada del hook. Ya vienen para iOS; ajústalas a tus paths.
- **Distribución como plugin** — publica `.claude-plugin/` en un marketplace interno; los devs hacen
  `/plugin install` en vez de clonar. Útil con muchos repos. Valida con `claude plugin validate .`.

## 6. Baseline de secretos (solo si el repo ya tiene historial)

```bash
bash tools/secret-baseline.sh
bash tools/secret-baseline.sh --show
git add .gitleaks-baseline.json
```

Rota cualquier credencial aún válida **antes** de escribir el baseline. Silenciar una
credencial viva es peor que no tener el gate: te deja creyendo que estás cubierto. El baseline
es **deuda**, no exención: encógelo con el tiempo.

**Si clonaste este template, tienes un hallazgo heredado y es esperable.** El commit de
scaffold contiene el literal del simulacro del §7 — una clave falsa que es *detectable a
propósito*, porque si no lo fuera el §7 no probaría nada. No se arregla con un allowlist de ese
valor: dejaría mudos el propio simulacro y el selftest de `validate-harness`, que lo usan para
demostrar que el detector VE (lo fija
`test_secret_scan.sh::test_el_valor_del_simulacro_nunca_se_allowlistea`). Tampoco reescribiendo
el historial: cambiaría todos los SHAs y rompería el remote `template` y el registro
`tools/.template-sync` de cada proyecto. Va al baseline, que es donde va la deuda declarada.

> **Y por eso el paso 2 de CI escanea el RANGO del cambio, no el historial.** Preguntar "¿queda
> algo enterrado de antes?" en cada PR deja el gate en rojo perpetuo por un hallazgo antiguo —
> y un gate siempre rojo es peor que uno ausente: se aprende a ignorar, y con él se ignora el
> rojo del día que importa. El historial se escanea aquí (una vez) y en un job **programado**
> con `GATES_SECRET_MODE=history`. El secreto que entra hoy lo cazan igual el Anillo 1 y el
> escaneo del rango.

## 7. Primer commit de prueba

```bash
# El string se CONSTRUYE en runtime (printf) a propósito: si este doc contuviera
# el patrón contiguo, el propio scan lo cazaría — nos pasó en el primer proyecto
# real: el ejemplo del simulacro ERA el secreto que bloqueó el commit del harness.
printf 'aws_secret_access_key = "AKIA%s"\n' 1234567890ABCDEF > leak.txt
git add leak.txt && git commit -m "test"   # debe FALLAR por gitleaks
rm leak.txt && git reset leak.txt 2>/dev/null
```

Si el commit se bloquea, el Anillo 1 está vivo.

## 8. Entender el flujo de review (el corazón del harness)

Con preset `full`, un commit de código de producto exige que el sub-agente `reviewer` haya
revisado **ese diff exacto**. El orden importa — el marker liga `sha256(diff staged)`:

1. **Stagea primero** (`git add …`). Lo que no está staged no queda ligado al marker.
2. El agente (o tú) invoca el sub-agente `reviewer` sobre el diff staged.
3. El reviewer termina con `VERDICT: GREEN|AMBER|RED` — y **el hook** `SubagentStop` escribe el
   marker a partir de ese veredicto real, ligado al `sha256` del diff. El modelo no puede
   escribirlo (un marker manual se rechaza; `source: hook` es obligatorio).
4. `git commit` **en un comando aparte** pasa los gates (capas, semgrep, secretos, trinquete,
   marker). `git add X && git commit` en una línea o `commit -a/-am` se RECHAZAN: stagean
   después de la validación y se commitearía contenido distinto del revisado.
5. Si cambias lo staged después de la review, el marker caduca. Re-revisa.

Escape auditado para emergencias: `REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON="..."` —
relaja **solo el marker** (juicio humano), jamás un trinquete o las capas.

## 9. El bucle que hace que esto mejore solo

- Los gates registran cada detección → `bash tools/metrics/gate-value.sh` mide actividad/latencia;
  `bash tools/metrics/escape-rate.sh` cuenta los findings promovidos y te dice en qué
  fase se caza cada defecto. **La tendencia de ese número es la única evidencia real de que
  puedes bajar la revisión humana.**
- Todo hallazgo va al ledger: `bash tools/findings/findings.sh add|close|list`.
- Toda lección de `docs/process/lessons_learned.md` exige su campo `Detector:` (verificado en
  CI): error cometido → lección → detector → **imposible repetirlo**. Ese es el mecanismo
  completo; sin el tercer paso, las lecciones son prosa.
- Ejecuta periódicamente `bash tools/lessons-rotate.sh --apply`: mueve al archivo histórico solo
  las lecciones respaldadas por tests del Anillo 3, conserva las manuales/parciales y regenera
  un índice único. Al iniciar, lee únicamente el tramo vivo anterior a ese índice.
- Las sesiones que tocan código quedan encoladas para el `process-judge` hasta que su
  veredicto las cierra (visible en cada turno).

- **Trabajo desatendido**: escribe historias en `backlog/` (formato `_template.md`, con
  criterios de aceptación Dado/cuando/entonces) y `bash tools/backlog/run.sh` las trabaja una
  a una en ramas `story/NNNN` que TÚ revisas antes de mergear. Detalle: `backlog/README.md`.

## 9b. Mantenerse actualizado con el template (sin perder lo tuyo)

El modelo mental: tu proyecto **nació de un clone** del template y ambos evolucionan. Tus
rellenos (FILLs, skills, confs) viven **commiteados en tu historial**, así que traer
novedades no los "marca como modificados": es un **merge de 3 vías** normal — git funde solo
todo lo que no choque, y solo pide tu juicio donde ambos tocasteis las mismas líneas.

```bash
bash tools/upgrade.sh https://github.com/<tu-usuario>/agentic-workflow-template.git  # 1ª vez
bash tools/upgrade.sh                                                                # después
```

El script: exige árbol limpio → fetch → te enseña qué commits nuevos hay → merge → y **no da
el upgrade por bueno hasta que la suite del harness y `validate-harness` pasan** (si fallan,
te deja la decisión: arreglar o `git reset --hard ORIG_HEAD`). Si hay conflictos, te los
lista **clasificados**: en *maquinaria* (`scripts/`, `tools/*.sh`, `ci/`) suele ganar el
template; en *contenido tuyo* (`AGENTS.md` §2-3, `.agents/skills/`, `*.conf`, ratchets,
`docs/process/`, `backlog/`) suele ganar tu versión.

Dos hábitos que reducen los conflictos a casi cero: (1) tus rellenos van en las **zonas
FILL** y en archivos de contenido — la maquinaria no se toca sin necesidad (§8 ya lo pide),
así el template puede mejorar sus scripts sin chocar contigo; (2) al revés, cuando en un
proyecto descubras una mejora **del harness en sí** (un gate, un fix de script), llévala al
repo del template y bájala a tus proyectos vía `upgrade.sh` — no la dejes divergir en uno solo.

## 10. Cómo se ve el día a día (empieza por aquí)

**`docs/PLAYBOOK.md`** — el manual de USO del programador, de inicio a fin: los cuatro flujos
(bug interactivo, feature con PRD, backlog desatendido, `/goal`), la tabla de "qué hacer
cuando un gate te bloquea" y la chuleta de comandos. Empieza por ahí.

**`docs/EXAMPLES.md`** — 4 escenarios end-to-end en iOS con los prompts literales y qué hace
cada gate: un bug con el flow corto, una feature mediana con PRD + design-review, un run
autónomo con `/goal`, y el backlog de historias. Es la mejor forma de entender el método
antes de escribir tu primera línea.

Listo. El detalle conceptual de por qué cada pieza existe: 
`.agents/skills/process/references/verification-loop.md`.

# <PROJECT> — Claude Code

> **Adaptador delgado.** La fuente canónica de reglas es `AGENTS.md`. Este archivo solo
> la importa y añade la maquinaria que es exclusiva de Claude Code (skills, sub-agentes,
> hooks vía `settings.json`). NO dupliques reglas aquí — si una regla es de producto, va en
> `AGENTS.md` para que TODOS los clientes la vean.
>
> Alternativa equivalente: `rm CLAUDE.md && ln -s AGENTS.md CLAUDE.md` (symlink). Usamos el
> import porque permite añadir la sección Claude-only de abajo.

@AGENTS.md

---

## Maquinaria exclusiva de Claude Code

- **Skills:** `.claude/skills` es un symlink a `.agents/skills` (la base compartida). Cárgalas según la matriz §11 de `AGENTS.md` (fuente única: `tools/skill-matrix.conf`).
- **Sub-agentes:** viven en `.claude/agents/*.md`. Invócalos con la tool `Agent` según su `description`. Catálogo en `.claude/agents/README.md`.
- **Comandos:** `/goal <objetivo>` fija condiciones verificables y delega el cierre en el `reviewer` (nivel 8).
- **Hooks (Anillo 2):** definidos en `.claude/settings.json`. Todos se invocan a través de
  `scripts/agent-hooks/run-hook.sh`, que comprueba con `bash -n` que el hook y sus libs parsean
  **antes** de ejecutarlos: si no parsean, avisa por stderr y deja pasar. Sin ese lanzador, un
  hook con marcadores de conflicto se leía como DENY y dejaba al agente sin poder ejecutar nada
  —ni el `git status` con el que diagnosticarlo—. Llaman a los scripts compartidos en
  `scripts/agent-hooks/`:
  - `SessionStart(startup|clear)` → resetea markers + imprime estado. `(resume)` → solo estado. `(compact)` → reinyecta el digest de reglas + findings (`post-compact.sh`) SIN resetear nada.
  - `PreToolUse Edit|Write` → `skill-reminder` (BLOQUEA si no leíste la skill requerida — matriz en `tools/skill-matrix.conf`).
  - `PreToolUse Bash` → `reviewer-gate` (git-guard de flags prohibidos + BLOQUEA `git commit` sin review reciente + drift-ratchet + capas + semgrep).
  - `PostToolUse Read` → registra lecturas de skills. `PostToolUse Bash|Edit|Write` → detector de atasco (racha de fallos del payload real). `PostToolUse *` → captura trayectoria (sin secretos).
  - `SubagentStop` → deriva el marker del `VERDICT:` real del sub-agente (el invariante nº1).
  - `Stop` → `canon-enforce` + `drift-stop` (bloquean si introdujiste violaciones/errores nuevos).

> Los mismos scripts los reusan Cursor (`.cursor/hooks.json`) y Codex (`.codex/hooks.json`) vía
> `scripts/agent-hooks/adapters/gate-adapter.sh`, que traduce el contrato exit-2/stderr al JSON
> de deny de cada cliente. La lógica vive una sola vez en `scripts/agent-hooks/`.
>
> Tras cada update de Claude Code: `bash tools/validate-harness.sh` — los contratos de hooks
> versionan rápido y un hook sobre un evento renombrado falla hacia el silencio.

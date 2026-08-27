# Mapa de documentación — dónde vive cada cosa

| Artefacto | Ruta | Para qué |
|---|---|---|
| Reglas canónicas | `AGENTS.md` (+ anidados por plataforma) | la fuente de verdad de las reglas |
| Adaptador Claude | `CLAUDE.md` | importa AGENTS.md + maquinaria Claude |
| Skills | `.agents/skills/<área>/SKILL.md` + `references/` | conocimiento cargable por área |
| PRDs | `docs/process/prds/NNNN-*.md` | specs de feature (template `_template.md`) |
| ADRs | `docs/process/decisions/` | decisiones arquitectónicas reusables (1 página) |
| Lecciones vivas | `docs/process/lessons_learned.md` hasta el índice | leer antes de codear |
| Histórico mecanizado | `docs/process/lessons_archive.md` | consultar bajo demanda; no cargar al inicio |
| Estado del proyecto | `docs/process/current_execution_map.md` | fase actual + próximo paso |
| Findings ledger | `tools/findings/ledger.jsonl` → `docs/process/findings-ledger.md` | inventario de hallazgos con estado terminal |
| Reportes de calidad | `docs/process/reviews/<fecha>-*.{md,html}` | salidas del `process-judge` |
| Sub-agentes | `.claude/agents/*.md` (↔ `.cursor/agents`) | roles especializados |
| Backlog de historias | `backlog/NNNN-*.md` (template `_template.md`) | cola de trabajo declarativa — `tools/backlog/run.sh` las trabaja en ramas `story/NNNN` (PRD 0003) |
| Ejemplos de uso | `docs/EXAMPLES.md` | 4 escenarios end-to-end (bug, feature+PRD, /goal, backlog) con prompts literales |

## Reglas de oro del mapa

- Cada doc enlaza a los demás (no islas).
- Un dato vive en **un solo lugar**; los demás lo referencian (evita drift).
- El racional aún vivo va en `lessons_learned.md`; el mecanizado, en `lessons_archive.md`.
  Ninguno infla `AGENTS.md`, que se mantiene terso.
- <!-- FILL: añade aquí los docs propios de tu org (runbooks, security baseline, etc.). -->

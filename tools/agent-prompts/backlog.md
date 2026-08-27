Trabaja la historia adjunta de principio a fin dentro del worktree actual.
AGENTS.md es la fuente canónica: lee sus lecciones y la skill aplicable antes de editar.
Antes de programar, acuerda con el sub-agente reviewer un contrato `CONTRACT: READY`,
guárdalo en `## Contrato de review` de la historia y commitéalo sin fingir un veredicto.
Respeta TDD red-first, el `scope: |` del frontmatter y los gates del repositorio.
Antes de cada commit de producto invoca al reviewer y atiende su veredicto real.
Usa commits atómicos con el formato del proyecto y `Part of STORY-<id>`.
No hagas push, merge, amend, `--no-verify` ni cambies otras ramas.
Si algo es ambiguo o imposible, documenta el bloqueo; no inventes el contrato.
Completa cada criterio con `ruta::test` o `n/a-manual — razón` en su verificación.
No termines con cambios sin commitear ni procesos en vuelo.

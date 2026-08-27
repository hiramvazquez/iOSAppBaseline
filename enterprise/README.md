# enterprise/ — enforcement org-wide nativo de Claude Code (opcional)

> El Anillo 1 (lefthook) y el Anillo 2 (hooks) son potentes, pero **se pueden saltar**
> (`--no-verify`, desinstalar lefthook, o el auto-override de 8 bloqueos del hook `Stop`).
> Para enforcement **no anulable** en máquinas de la empresa, Claude Code ofrece
> `managed-settings.json`: la capa de MAYOR precedencia — ni los flags de CLI ni los settings
> de proyecto/usuario la sobrescriben. Esto **cierra el hueco** de los anillos para usuarios de Claude Code.

## Qué hace el ejemplo (`managed-settings.example.json`)

- **`permissions.deny`** bloquea de raíz: `git push --force`, `git commit --no-verify`
  (vuelve **inevitable** el Anillo 1), y la lectura de archivos de secretos (`.env`, `*.pem`, …).
- **`disableBypassPermissionsMode: "disable"`** impide que el usuario active el modo que se salta los permisos.

> Opcionales que puedes añadir (ver docs): `allowManagedHooksOnly` (solo hooks gestionados),
> `strictPluginOnlyCustomization` (skills/agents/hooks solo vía plugins/managed),
> `sandbox.*` (aislamiento OS de Bash), `claudeMd` (instrucciones de org embebidas).

## Cómo desplegarlo (lo hace IT/DevOps, NO va al repo)

Copia el archivo (sin el `_comment`) a la ruta de OS y distribúyelo por MDM / Group Policy / Ansible:

| OS | Ruta |
|---|---|
| macOS | `/Library/Application Support/ClaudeCode/managed-settings.json` |
| Linux / WSL | `/etc/claude-code/managed-settings.json` |
| Windows | `C:\Program Files\ClaudeCode\managed-settings.json` |

## Distribución del tooling como plugin (opcional)

Para empresas con **muchos repos**, en vez de que cada quien clone este template, puedes publicar
las skills + sub-agentes como **plugin** vía un marketplace interno (ver `.claude-plugin/`). Los devs
lo instalan con `/plugin install` y reciben actualizaciones versionadas. El scaffold del proyecto
(AGENTS.md, CI, lefthook) sigue viviendo en cada repo; el plugin distribuye solo el tooling de agentes.

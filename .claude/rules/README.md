# `.claude/rules/` — reglas path-scoped nativas

> **Estado: complementario, no primario.** Desde que las skills declaran `paths:` en su
> frontmatter (`.agents/skills/*/SKILL.md`), la carga automática por glob la hace la propia
> skill. Estos archivos ya no son la vía principal.

## Cuándo sigue valiendo la pena un archivo aquí

Para **recordatorios de una línea** que no justifican abrir una skill entera: el destilado
accionable de 3-4 reglas que el agente debe tener presente al tocar ese path, sin cargar la
referencia completa.

Es la diferencia entre *"recuerda que la navegación vive en el Coordinator"* (regla) y
*"así es como funciona nuestro sistema de navegación"* (skill).

## Cuándo NO

- **Duplicar el contenido de una skill.** Si la información completa vive en la skill, pon
  `paths:` en su frontmatter y borra el archivo de aquí. Dos copias divergen — y la que el
  agente lea será la desactualizada.
- **Reglas que deben BLOQUEAR.** Esto es contexto, no enforcement. Lo que debe impedir una
  acción va a `permissions.deny` (Anillo 0), a un hook (Anillo 2) o a un detector (`tools/`).

## Los tres mecanismos, y cuál usar

| Mecanismo | Qué hace | Coste |
|---|---|---|
| `paths:` en el frontmatter de una skill | Carga la skill sola al tocar un archivo que casa | El de la skill, solo cuando aplica |
| `.claude/rules/*.md` (esto) | Inyecta un recordatorio corto por path | Muy bajo |
| Hook `skill-reminder` | **BLOQUEA** el Edit si no leíste la referencia | 0 hasta que se dispara |

Los tres son complementarios: `paths:` y las rules son el camino feliz; el hook es el gate
duro que hace que el camino feliz no sea opcional.

> `skill-reminder` excluye `docs/`, `tools/`, `scripts/`, `.agents/` y `.claude/` — editar la
> documentación de un área no es editar el código de esa área. Esa exclusión está fijada por
> `tools/tests/test_skill_reminder.sh`; era un falso positivo real (editar la skill de dominio
> exigía leer la skill de dominio) y un gate con falsos positivos se acaba desactivando entero.

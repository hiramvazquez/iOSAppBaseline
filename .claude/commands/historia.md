---
description: Redacta una historia de backlog lista para el runner — entrevista corta, criterios verificables, y el archivo en backlog/NNNN-slug.md con status ready.
---

# /historia — de idea suelta a historia trabajable

Idea del owner:

$ARGUMENTS

## Qué hacer

La calidad del run desatendido es proporcional a la historia (backlog/README.md): tu trabajo
aquí es convertir la idea de arriba en un contrato verificable, no en prosa bonita.

1. **Lee `backlog/_template.md`** — ese es el formato, campo a campo.
2. **Entrevista corta (solo lo que NO puedas deducir del código).** Pregunta de una vez, en
   un solo mensaje, lo que falte de: rol/valor (¿para quién y para qué?), estado inicial y
   resultado observable de cada escenario, casos de error que importan, qué queda FUERA de
   scope, qué archivos/módulos puede tocar, y dependencias de otras historias. Si la idea ya
   lo trae, no preguntes por preguntar.
3. **Regla de tamaño — decide ANTES de redactar si es UNA historia o una CADENA.** Una
   historia debe caber cómoda en una sesión de agente que arranca con contexto 0. Heurística:
   si la idea toca red + dominio + UI a la vez, o su scope pasa de ~5-6 archivos, NO es una
   historia — es una cadena de historias encadenadas con `depends_on`, cada una mergeable por
   sí sola. Ejemplo real: "integrar login" no es una historia; son tres: (1) puerto de auth +
   modelos request/response + fake con suite de conformidad, (2) `LoginLogic` con TDD contra
   el fake + manejo de errores tipados, (3) `LoginViewModel` + View + validaciones de input
   — cada una con sus propios tests/mocks. El runner trabaja una por invocación y el merge
   humano de cada una desbloquea la siguiente: así ningún run agota el contexto a mitad de
   una capa. Si troceas, escribe TODOS los archivos de la cadena en esta misma pasada.
4. **Redacta los criterios de aceptación en Dado/cuando/entonces VERIFICABLES.** La prueba de
   cada criterio: ¿un test puede fallar por él? Incluye happy si existe y cada rama observable,
   recuperación, permiso o límite aplicable
   (AGENTS.md §5). Un criterio que no se puede convertir en test que falla NO es un criterio —
   reformúlalo o pregunta.
5. **Escribe el archivo** `backlog/NNNN-<slug>.md`: NNNN = siguiente número libre (mira
   `backlog/`), slug corto en kebab-case. Frontmatter completo: `status: ready`, `base`,
   `scope` (rutas explícitas — es la defensa contra el scope creep §8), `depends_on` si aplica.
6. **Autovalida antes de terminar** (los mismos guards del runner, para no descubrirlos en
   `blocked`): el archivo contiene "Criterios de aceptación" y al menos un "Dado ";
   el frontmatter parsea; el scope no está vacío.
7. Termina mostrando la historia completa (o la cadena entera) y recuerda: se dispara con
   `bash tools/backlog/run.sh` (o queda en cola para el próximo ciclo), y el merge de la rama
   `story/NNNN-<slug>` resultante es SIEMPRE del owner.

> No inventes contexto de negocio que el owner no dio — Open Question > suposición silenciosa
> (§1.4). Una historia con un hueco inventado produce una rama entera que hay que tirar.

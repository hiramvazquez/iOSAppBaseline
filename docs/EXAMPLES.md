# Ejemplos de uso — cómo trabajaría yo un proyecto iOS con este harness

> Cuatro escenarios reales, de menor a mayor autonomía, con los prompts literales y lo que
> hace cada gate por detrás. Asume el template ya adoptado (`ADOPTION.md`): stack rellenado,
> `lefthook install` hecho, skills de arquitectura/dominio escritas.

---

## Escenario 1 — Bug pequeño (flow corto, ~15 min, tú mirando)

**La situación:** el total del carrito muestra los precios sin IVA.

**El prompt** (nota: síntoma + dónde mirar + qué es "arreglado" — no la solución):

```
Bug: el total del carrito sale sin IVA. Usuarios de ES esperan IVA incluido.
La lógica vive en Domain/Cart/. Reproduce el bug con un test que falle,
arréglalo, y pasa por el reviewer antes de commitear.
```

**Lo que pasa, gate a gate:**

1. Al intentar editar `CartTotalLogic.swift`, `skill-reminder` **bloquea** hasta que el
   agente lee `domain/SKILL.md` + `tdd-workflow.md` — no puede saltarse el estudio.
2. Escribe `cartTotal_conIVA_esBrutoNoNeto()` 🔴, lo ve fallar, implementa 🟢, refactor ♻️.
3. `post-edit-verify` le devuelve el lint/typecheck del archivo **en el mismo turno**.
4. Invoca al sub-agente `reviewer` → este corre los checks mecánicos y emite
   `VERDICT: GREEN` → **el hook** escribe el marker ligado al sha del diff.
5. `git commit` pasa lefthook: capas, semgrep, secretos, trinquete, marker. Fin.

**Tu papel:** leer el resumen + la salida real de los tests. Nada más.

---

## Escenario 2 — Feature mediana con PRD (el ciclo completo, 1-3 días)

**La situación:** quieres compartir notas entre usuarios — toca schema, contrato de API,
tres capas y decisiones de privacy. Por §12, esto es PRD obligatorio.

**Fase A — el QUÉ (30-60 min, la mejor inversión de todas):**

```
Quiero que los usuarios compartan notas con otros usuarios, con permisos de
solo-lectura o edición. Entrevístame con AskUserQuestion sobre edge cases,
privacy y trade-offs — pregunta lo difícil, no lo obvio. Después escribe el
PRD con docs/process/prds/_template.md.
```

La entrevista te saca lo que no habías pensado (¿revocar un share borra las ediciones del
otro? ¿qué pasa si comparto con alguien sin cuenta?). El PRD fija **anti-features** y
**escenarios golden** — tu scope queda blindado por escrito.

**Fase B — el gate de diseño (antes del primer commit):**

```
Pasa el PRD 0004 por el design-reviewer.
```

El `design-reviewer` critica el CÓMO con lente senior (¿escala? ¿multi-idioma? ¿testeable?
¿RLS por fila?) y **propone arreglos al PRD, no al código** — los errores de enfoque se
corrigen donde cuestan 10×  menos. Su veredicto queda registrado por el hook. Tú das el
`Approved` (son dos gates distintos, §12).

**Fase C — implementación (sesión fresca, tú casi ausente):**

```
Implementa el PRD 0004. Handshake primero: resume en ≤8 puntos qué vas a
hacer, qué archivos tocas y cuáles NO, y tus Open Questions bloqueantes.
```

El handshake (§ feature-workflow 2.0) te da 2 minutos de veto barato. Después: TDD por
escenario golden, suite de conformidad fake≡real para el puerto nuevo (regla dura de
`domain/SKILL.md`), drift policy §9 al tocar el contrato compartido, y `security-reviewer`
además del `reviewer` porque toca datos de usuarios (su RED **no** se compensa con el GREEN
del otro).

**Fase D — cierre:** escenarios golden a mano, DoD del PRD marcado, y al cerrar la sesión la
cola del `process-judge` te recuerda el juicio de trayectoria. `git push` solo con tu OK (§7).

---

## Escenario 3 — Run autónomo con `/goal` (horas sin mirar)

**La situación:** migrar 30 pantallas de navegación por closures al Coordinator. Mecánico,
largo, aburrido — ideal para no mirarlo.

```
/goal las 30 Views bajo ios/Sources/UI/ navegan vía Coordinator (cero
NavigationStack fuera de Coordinator/App — pruébalo con la salida de
`bash tools/check-drift.sh`), la suite completa pasa, y el reviewer emitió
VERDICT GREEN. Demuestra cada punto con salida real de comandos. O detente
a los 40 turnos.
```

Por qué funciona sin ti: **quien decide que terminó no es quien trabaja** (un evaluador
independiente comprueba la condición tras cada turno), y la condición exige **evidencia
ejecutable**, no afirmaciones. Mientras tanto: `canon-enforce` bloquea cierres con
violaciones, `track-failure` corta los bucles de reintento, `post-compact` reinyecta las
reglas cuando el contexto se compacta, y el commit final exige el VERDICT real.

---

## Escenario 4 — El backlog: historias tipo Jira → ramas listas para review

**La situación objetivo:** tú solo escribes historias; las ramas aparecen solas.

1. Escribes `backlog/0007-exportar-pdf.md` con el formato de `backlog/_template.md` — los
   **criterios de aceptación Dado/cuando/entonces son obligatorios**: son el contrato que se
   convierte en tests. Sin ellos, el runner la marca `blocked` y no improvisa (§1.4).
2. Un schedule (cron, scheduled task de Claude Code, o el bucle supervisado de `backlog/README.md`) ejecuta
   `bash tools/backlog/run.sh`: toma la primera `ready` sin dependencias pendientes, crea
   `story/0007-exportar-pdf` desde `develop`, y trabaja la historia en headless **con todos
   los gates activos dentro**.
3. La historia queda `in-review` y la rama esperándote. Revisas un diff que **ya pasó** TDD,
   capas, semgrep, secretos y el VERDICT del reviewer — tu review es la última capa, no la
   primera. Merge → `done` → se desbloquean las historias que dependían de ella.
4. Los ejemplos `backlog/0001-*` y `0002-*` muestran una historia simple (lógica pura + una
   vista) y una compleja (tres capas + migración + dependencia entre historias).

Detalle completo, opciones de schedule y el nivel de madurez honesto: `backlog/README.md`.

---

## Las tres reglas de oro del operador humano

1. **Describe síntomas y criterios, no soluciones.** El QUÉ verificable es tu trabajo; el
   CÓMO disciplinado es del harness.
2. **Nunca aceptes "terminé": pide la evidencia.** La salida del reviewer, de los tests, del
   check-drift. (Durante la construcción de este template, el autor declaró "terminado" seis
   veces — y las seis, los gates encontraron fallos. Está en el README, con commits.)
3. **Todo lo que corrijas dos veces, conviértelo en regla o detector** (`lessons_learned.md`
   exige el campo Detector). Así la revisión humana DECRECE — que es el objetivo de todo esto.

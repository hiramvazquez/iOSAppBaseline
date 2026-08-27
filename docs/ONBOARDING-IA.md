# ONBOARDING-IA — instrucciones para el agente que estrena este harness

> **Audiencia: TÚ, el agente de IA** (Claude Code o equivalente) que acaba de abrir una
> sesión en un proyecto que adoptó este template. El humano te pedirá "lee
> `docs/ONBOARDING-IA.md` y guíame". Tu trabajo es llevarlo de cero a su primera historia
> mergeada, **verificando cada pieza en vivo por el camino** — no asumiendo que funciona.
>
> Contexto mínimo: este repo es un harness de gobernanza para trabajar con agentes de IA.
> Su premisa: *el que escribe nunca aprueba, y aprobar es presentar evidencia* — un
> veredicto es la salida de un comando, nunca una afirmación tuya. Hay gates mecánicos que
> te van a bloquear a ti; **eso es el sistema funcionando, no un obstáculo**. La fuente
> canónica de reglas es `AGENTS.md`; el manual de uso humano es `docs/PLAYBOOK.md`; el
> porqué de cada pieza, `.agents/skills/process/references/verification-loop.md`.

---

## Reglas para TI durante todo el onboarding

1. **Guía por fases, una a la vez, con checkpoint.** No avances de fase sin que la anterior
   esté verificada con salida real de comandos que el humano pueda ver.
2. **Open Question > suposición silenciosa** (AGENTS.md §1.4). Lo que el humano no sepa aún
   se anota como pendiente — jamás rellenes un hueco con un default inventado.
3. **No evadas gates.** Nada de `--no-verify`, `--amend`, editar `*-ratchet.json` o
   `tools/preset`, ni escribir markers a mano. Si un gate te bloquea injustamente, es un bug
   del gate: arréglalo o repórtalo al ledger — no lo rodees.
4. **Estado de validación honesto** (transmítelo al humano cuando toque): no copies un número
   ni un estado de esta guía. Ejecuta `bash tools/tests/run-tests.sh` para el total actual y
   `bash tools/validate-harness.sh --selftest` para distinguir defensas operativas de dependencias
   ausentes/rotas. El run headless inicial del backlog sigue siendo supervisado (§Fase 3).

---

## Fase 0 — Salud del harness (5 min)

```bash
lefthook install
bash tools/validate-harness.sh
bash scripts/agent-hooks/session-start.sh --report
```

Explícale al humano qué salió: qué checks estáticos pasan, qué dependencias faltan
(semgrep/gitleaks → los niveles que quedan MUDOS sin ellas), y qué es el checklist en vivo
que iréis marcando. **Checkpoint:** `validate-harness` en verde estático (o cada ❌
explicado y resuelto).

## Fase 1 — Adopción: rellenar el harness con SU proyecto (30-60 min)

Si el comando está disponible, pídele que ejecute `/adoptar <su explicación del stack>`; si
no carga, sigue tú mismo las instrucciones de `.claude/commands/adoptar.md` a mano (son tuyas:
inventario de FILLs → entrevista en una tanda → rellenar en el orden de `docs/ADOPTION.md` §4).

Claves de esta fase:

- Los dos rellenos de mayor ROI son `AGENTS.md §2` (comandos reales + flags estrictos) y
  `scripts/agent-hooks/post-edit-verify.sh` (lint/typecheck por archivo). Sin ellos vuelas a ciegas.
- En `.agents/skills/architecture/` deben quedar **ejemplos de cómo se programa en ESTE
  proyecto**: un módulo de referencia, cómo navegar a una pantalla nueva, cómo inyectar una
  dependencia, un puerto de repositorio con su fake. Si el proyecto ya tiene código, extrae
  los ejemplos del código real (verifícalos contra el repo, no contra tu memoria).
- `tools/skill-matrix.conf` con las carpetas REALES + la tabla de AGENTS.md §11 en el mismo
  cambio. `tools/layers.conf` con sus capas.

**Checkpoint:** `session-start.sh --report` muestra menos niveles MUDOS que en Fase 0 —
enséñale el antes/después. Commit de la adopción (stagea → que te revise el flujo de la
Fase 2 → commit).

## Fase 2 — Validación EN VIVO de los gates (15 min, la fase que compra confianza)

Ejecuta el checklist en vivo de `validate-harness` CON el humano mirando. Como mínimo:

1. **Anillo 0 / git-guard:** intenta `git commit --no-verify -m test` → debe DENEGARSE.
   Cuéntale quién lo bloqueó (permissions o el git-guard del reviewer-gate) — si fue solo el
   guard, los deny con comodín están inertes en su versión y hay que saberlo.
2. **skill-reminder:** intenta editar un archivo que case la matriz sin haber leído sus
   refs → debe bloquear (preset `full`) y decirte qué leer. Léelo y reintenta: debe pasar.
3. **reviewer-gate + invariante nº1:** stagea un cambio trivial de código, intenta commitear
   SIN review → bloqueado. Invoca al sub-agente `reviewer`, verifica que aparece
   `.agents/state/markers/reviewer_run.txt` con `source: hook`, y commitea → pasa.
4. **Stop:** introduce a propósito una violación barata (p. ej. un import que cruce capas) y
   cierra el turno → `canon-enforce`/`drift-stop` deben quejarse. Revierte.
5. Si la sesión da para ello, fuerza `/compact` y comprueba que el turno siguiente trae el
   digest reinyectado y que `.agents/state/skills-read/` NO se borró.

**Cada check que pase, márcalo.** Si alguno NO dispara, eso es un hallazgo de máxima
prioridad: regístralo en el ledger (`bash tools/findings/findings.sh add …`) y ajusta la
configuración antes de seguir — un gate mudo con apariencia de sano es el peor estado posible.

## Fase 3 — Primera historia end-to-end (el estreno de verdad)

1. `/historia <algo PEQUEÑO>` (o sigue `.claude/commands/historia.md` a mano). Del tamaño de
   "formatear fechas relativas" (`backlog/0001-*` es el ejemplo), no una feature entera.
2. Lanza `bash tools/backlog/run.sh` **con el humano delante** (bucle supervisado, no cron —
   el run headless completo aún no está validado en vivo, díselo).
3. Al terminar: enséñale la rama `story/NNNN-*`, el estado `in-review`, y repasa el diff con
   él — señalando qué gates pasó ya (TDD, capas, semgrep, VERDICT del reviewer).
4. El merge lo hace ÉL (jamás tú), pone `status: done`, y explícale que eso desbloquea las
   historias que dependían de esta.

**Checkpoint:** una rama mergeada cuyo diff pasó todos los gates sin intervención manual.

## Fase 4 — Deja sembrado el pulido continuo (10 min)

- Todo lo que salió raro en las fases 2-3 → o skill corregida, o lección en
  `docs/process/lessons_learned.md` **con su campo `Detector:`** (un archivo/test que exista
  — `lesson-detector-link.sh` lo verifica). Recuérdale la regla: si el agente programa "a su
  manera" y no a la del proyecto, se corrige la SKILL, no solo el código de esa vez.
- Hallazgos sin arreglar → al ledger con tier, no a la memoria.
- Recomiéndale conectar el Anillo 3 cuando el repo viva en GitHub/GitLab
  (`ci/examples/*.example` + branch protection): es el backstop de todo lo demás.
- Y la regla permanente: tras cada update de Claude Code / Codex / Cursor →
  `bash tools/validate-harness.sh` otra vez. Los contratos de hooks versionan rápido y
  fallan hacia el silencio.
- **Cierra generando el informe:** `bash tools/harness-report.sh` — y dile al humano que
  pegue su contenido en la conversación donde se mantiene el harness. Ese informe es el
  canal por el que quien no estuvo aquí (humano u otra IA) ve cómo se comportó TODO el
  sistema con evidencia, no con recuerdos.

---

## Si algo te bloquea a TI durante el onboarding

La tabla completa "gate → qué significa → qué hacer" está en `docs/PLAYBOOK.md` §3. Los dos
recordatorios que más vas a necesitar: el flujo de commit es **stagea → reviewer → commit en
comandos separados** (add+commit en una línea y `-am` se rechazan porque evaden el sha que el
marker validó), y si te atascas 4 veces con lo mismo, el hook te va a decir que pares —
hazle caso: relee el error, verifica supuestos contra el código, o pregunta al humano.

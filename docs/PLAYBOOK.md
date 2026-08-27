# PLAYBOOK — el día a día del programador, de inicio a fin

> **Este es el manual de USO.** Qué haces tú, qué hace el harness, y qué hacer cuando algo
> bloquea. El *porqué* de cada pieza vive en `verification-loop.md`; los escenarios narrados
> con prompts literales, en `EXAMPLES.md`; el setup inicial, en `ADOPTION.md`. Aquí solo el
> flujo de trabajo.

---

## 0. Una sola vez (o tras cada update de tu cliente de IA)

```bash
lefthook install                  # Anillo 1 — sin esto, git commit NO tiene gates
bash tools/validate-harness.sh    # ¿los gates EXISTEN de verdad? + checklist en vivo
cat tools/preset                  # full = gates bloquean · lite = skill/marker avisan
```

Regla de confianza: **ningún gate cuenta como existente hasta que lo has visto bloquear algo
una vez.** El checklist en vivo de `validate-harness` es exactamente eso.

## 1. Al abrir una sesión (Claude Code)

No haces nada: `SessionStart` imprime el estado — branch, fase del proyecto, **qué niveles de
la pirámide están MUDOS en tu máquina**, findings abiertos, y si el Anillo 1 está dormido.
**Léelo.** Si dice que algo está MUDO, esa protección no existe hoy, por mucho que el
README la anuncie. En cada turno, `UserPromptSubmit` te inyecta el estado vivo (findings,
árbol sucio, cola de juicio) — no hace falta pedirlo.

## 2. Los cuatro flujos (elige por tamaño)

### 2a. Bug / cambio pequeño → sesión interactiva normal

1. Pides el fix. El harness te acompaña solo: `skill-reminder` te obliga a leer la skill del
   área antes del primer Edit; `post-edit-verify` le devuelve al agente el lint/typecheck de
   cada archivo tocado en el mismo turno; TDD manda (primero el test que reproduce el bug).
2. **Stagea → reviewer → commit, en ese orden y en comandos separados:**

```bash
git add <archivos>            # 1. stagea PRIMERO (el marker liga el sha de esto)
# 2. invoca al sub-agente reviewer sobre el diff staged (pídeselo al agente)
git commit -m "fix(area): …"  # 3. comando APARTE — add+commit en una línea se rechaza
```

   El `VERDICT: GREEN|AMBER` del reviewer lo convierte el **sistema** en marker
   (SubagentStop); un marker escrito a mano se rechaza. Si cambias lo staged después de la
   review, caduca — re-revisa.
3. Al cerrar el turno, `canon-enforce` + `drift-stop` bloquean si dejaste violaciones o
   errores nuevos. Eso es todo el ceremonial.

### 2b. Feature mediana/grande → PRD primero

Criterio "mediana/grande" (AGENTS.md §12): ≥2 de {>3 días, >1 módulo, cambia schema/API,
decisión de seguridad/privacidad, decisión arquitectónica reusable}.

1. Sub-agente `prd-writer` → borrador en `docs/process/prds/NNNN-*.md`. Tú lo apruebas (el QUÉ).
2. Sub-agente `design-reviewer` → gate del CÓMO (no salteable en arquitectura/PHI).
3. Implementación por fases = flujo 2a repetido. El PRD es el scope: lo que no lista, no se toca (§8).

### 2c. Trabajo desatendido → el backlog (pegas la historia, se dispara todo)

El flujo "historia → comando → rama lista para tu review":

```bash
# 1. Escribe la historia (o mejor: /historia en Claude Code te la redacta y valida)
$EDITOR backlog/0007-exportar-pdf.md      # formato _template.md, status: ready

# 2. Dispara (trabaja en un WORKTREE aislado: tu checkout no cambia de rama,
#    tu árbol sucio no estorba, y una historia in-review no se re-trabaja)
bash tools/backlog/run.sh                 # una historia, ahora
# …o en ciclo: cron / scheduled task / while bash tools/backlog/run.sh; do sleep 60; done

# 3. Te llega una rama story/0007-exportar-pdf con la historia en in-review:
git diff develop...story/0007-exportar-pdf   # revisas un diff que YA pasó todos los gates
git checkout develop && git merge story/0007-exportar-pdf
sed -i '' 's/^status: .*/status: done/' backlog/0007-*.md   # done ⇒ desbloquea dependientes
```

**Tu palanca es la historia, no supervisar el teclado.** Criterios de aceptación
Dado/cuando/entonces verificables → el agente los convierte en tests y los gates hacen el
resto. Sin criterios → `blocked` automático, no improvisación. El runner jamás pushea ni
mergea; `blocked` con rc≠0 te deja la rama para inspección. Primera historia real: lánzala
con el bucle supervisado mirando (ver `backlog/README.md`), y empieza con historias pequeñas.

### 2d. Objetivo autónomo dentro de una sesión → `/goal`

```
/goal los tests de test/auth pasan, `bash tools/check-drift.sh` da errors=0. Máx 20 turnos.
```

El agente descompone en condiciones verificables, no puede declarar "terminado" sin pegar la
salida real de cada comando, y el cierre lo firma el `reviewer` — no él mismo.

## 3. Cuando un gate te bloquea (tabla de supervivencia)

| Te bloqueó | Significa | Qué hacer |
|---|---|---|
| `skill-reminder` | vas a editar un área sin haber leído su skill | lee las refs que lista (tool Read) y reintenta. La matriz vive en `tools/skill-matrix.conf` |
| `git-guard` | `--no-verify` / `--amend` / `--force` / `reset --hard` | no se hace. Si un gate te bloquea injustamente, arregla el gate |
| reviewer-gate: marker ausente/caducado | commiteas sin review del diff staged exacto | stagea → invoca `reviewer` → commit aparte. Emergencia real: `REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON="…"` (queda auditado) |
| reviewer-gate: `add && commit` o `-am` | evadirías el sha que el marker validó | sepáralo en dos comandos / stagea explícito |
| `drift-ratchet` | metiste MÁS errores/warns que el techo | baja la deuda que introdujiste. El techo no se sube — ni con override, ni con `--update` |
| `check-layers` | un import cruza capas prohibidas | invierte la dependencia o mueve el archivo. Es contrato, no estilo |
| semgrep exit 1 | patrón AST prohibido en lo staged | arréglalo; la regla te dice cuál y dónde |
| semgrep exit 3 (aviso) | **el detector no pudo mirar** — nivel 2 MUDO | commit pasa en local; CI bloqueará. Arregla el scanner pronto |
| `canon-enforce` (Stop) | secreto/capa/harness roto en el árbol | se arregla EN ese turno; no admite "luego" |
| `drift-stop` (Stop) | errores nuevos vs el baseline de tu sesión | corrígelos antes de cerrar el turno |
| 🔁 atasco (aviso) | 4 fallos seguidos del mismo comando | para: relee el error, verifica supuestos contra el código, o pregunta |

**Lo que jamás haces:** `--no-verify`, `--amend` sin orden del owner, editar
`*-ratchet.json` / `tools/preset` a mano, escribir el marker a mano. Todo eso está denegado
por diseño, y evadirlo con shell solo engaña al anillo local — en CI no cuela.

## 4. Cierre de ciclo (lo que hace que esto mejore solo)

- **Hallazgo que no arreglas ahora** → al ledger, no a la memoria:
  `bash tools/findings/findings.sh add --title "…" --area "file:línea" --tier owner-decision`.
  El estado vivo te lo re-enseña cada turno hasta que lo cierres (`close`/`accept`).
- **Error nuevo cometido** → entrada en `docs/process/lessons_learned.md` **con su
  `Detector:`** (un archivo/test que exista — se verifica). Lección sin detector = prosa.
- **Preset `full` (equipo):** las sesiones que tocan código quedan en la cola del
  `process-judge` hasta que su veredicto las cierra. En `lite` no hay cola.
- **De vez en cuando:** `bash tools/metrics/escape-rate.sh --days 30` — en qué fase se caza cada
  defecto. Esa tendencia es la única evidencia real de que puedes delegar más.

## 5. Chuleta

```bash
bash scripts/agent-hooks/session-start.sh --report   # estado sin efectos secundarios
bash tools/validate-harness.sh                       # salud del harness (+ --full con suite)
bash tools/tests/run-tests.sh                        # la suite del harness
bash tools/check-drift.sh                            # deuda actual (capas+semgrep+estructura)
bash tools/drift-ratchet.sh --update                 # bajar el techo tras mejorar (solo baja)
bash tools/mutation-score.sh --update                # subir el piso tras mejorar (solo sube)
bash tools/backlog/run.sh                            # trabajar la siguiente historia ready
bash tools/findings/findings.sh list --status open   # qué está abierto
bash tools/upgrade.sh                                # traer mejoras del template (merge verificado)
bash tools/harness-report.sh                         # informe pegable de cómo se comportó todo
```

---
description: Detecta el drift entre lo que la spec AFIRMA (PRDs, AGENTS.md, skills) y lo que el código ES — con evidencia, y cada divergencia al ledger. La versión mecánica-asistida del reconcile de spec-driven development.
---

# /reconciliar — ¿la spec y el código siguen contando la misma historia?

Área o PRD a reconciliar (vacío = todo lo razonable en una pasada):

$ARGUMENTS

## Por qué existe

El drift doc↔código es el óxido de todo proyecto con agentes: el PRD dice "el detalle
muestra rating", el código lo quitó hace tres sprints, y el siguiente agente que lea el PRD
lo re-implementa o razona sobre un mundo que ya no existe. Este comando lo caza a tiempo.
No confundir con `tools/check-drift.sh` (drift *mecánico*: capas, tamaños, patrones) — esto
es drift *semántico*: afirmaciones de la spec que el código ya no cumple, y realidades del
código que la spec no registra.

## Qué hacer

1. **Inventario de afirmaciones verificables.** Recorre, en este orden:
   - PRDs en `Shipped`/`In progress` (`docs/process/prds/`): escenarios golden, estructura
     de archivos (§5), fases (§5b), anti-features ("qué NO entra" — ¿entró?).
   - `AGENTS.md` §2-3: ¿los comandos de build/test funcionan? ¿el patrón de pantalla y la
     navegación descritos son los que el código usa?
   - `.agents/skills/`: el mapa de utilidades de `domain/SKILL.md` (¿existen esas
     utilidades? ¿hay utilidades nuevas que no están en el mapa?), los ejemplos de
     `architecture/` (¿siguen compilando conceptualmente con el código real?).
   - `docs/process/current_execution_map.md`: ¿la fase que declara es la real?
2. **Verifica cada afirmación CONTRA EL CÓDIGO, con evidencia.** Grep/Read/ejecución real —
   nunca de memoria. Cada verificación termina en uno de tres estados: ✅ coincide ·
   ❌ la spec afirma algo que el código no cumple · 👻 el código tiene algo que la spec
   no registra.
3. **Cada ❌ y cada 👻 relevante va AL LEDGER**, no a prosa:
   `bash tools/findings/findings.sh add --title "drift spec↔código: …" --area "<doc>:<sección> vs <archivo>" --source reconciliar --tier owner-decision`
   — el owner decide la dirección del arreglo: ¿se corrige la spec (el código tenía razón)
   o el código (la spec era el contrato)? NO decidas eso tú; es exactamente el tipo de
   decisión de producto que §1.4 te prohíbe improvisar.
4. **Excepción barata:** si el arreglo es objetivamente trivial y unidireccional (un nombre
   de archivo que cambió en §5, un comando de build actualizado), corrige la spec
   directamente en el mismo turno y lístalo como "auto-corregido" — burocratizar lo obvio
   mata el hábito de reconciliar.
5. **Cierra con un resumen ejecutivo:** N afirmaciones verificadas · ✅/❌/👻 · qué quedó en
   el ledger · y tu recomendación de cadencia (tras cada PRD shipped, o mensual).

> Reglas de siempre: solo lectura + ledger (no refactorices "de paso", §8); evidencia real
> pegada, no resumida; si una afirmación no es verificable mecánicamente, dilo — una spec
> inverificable es un finding en sí misma.

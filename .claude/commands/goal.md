---
description: Fija un objetivo con condiciones VERIFICABLES; el cierre lo decide la evidencia (y el reviewer), no tu propia sensación de "terminado".
---

# /goal — gate por evidencia (nivel 8 de la pirámide)

Objetivo declarado por el owner:

$ARGUMENTS

## Contrato (no negociable)

1. **Descompón el objetivo en condiciones VERIFICABLES.** Cada una debe poder
   probarse con la salida real de un comando, un exit code o un archivo
   existente. Si una condición no es verificable mecánicamente, decláralo y
   pide al owner que la reformule — no la des por buena "a ojo".
2. **Anuncia la lista de condiciones AHORA**, antes de empezar a trabajar,
   junto con el comando exacto que probará cada una.
3. Si el objetivo incluye un límite de turnos/tiempo, respétalo: al llegar al
   límite, PARA y reporta el estado real (qué condiciones pasan, cuáles no).
4. **Prohibido declarar el objetivo cumplido sin pegar la evidencia**: la
   salida real (no resumida, no parafraseada) del comando de cada condición,
   obtenida en ese momento — no de memoria, no de una ejecución vieja.
5. **El cierre no es tuyo.** Cuando creas que todas las condiciones pasan,
   invoca al sub-agente `reviewer` pasándole la lista de condiciones y la
   evidencia. Su `VERDICT:` es el veredicto — el hook `SubagentStop` lo
   convierte en marker. *El que escribe nunca es el que aprueba* (AGENTS.md §14).
6. Si una condición falla 4 veces seguidas con el mismo enfoque, para y
   pregunta (Open Question > suposición silenciosa, AGENTS.md §1.4).

> Anti-patrón que este comando existe para impedir: "ya está, los tests pasan"
> sin haberlos corrido en este turno. Un veredicto es la salida de un comando,
> nunca una afirmación del modelo.

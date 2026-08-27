---
description: Rellena el template para TU proyecto — entrevista sobre tu stack (arquitectura, navegación, DI, comandos) y completa los FILL en orden de impacto, verificando al final qué niveles dejaron de estar MUDOS.
---

# /adoptar — de cascarón a harness de TU proyecto

Contexto que da el owner (stack, plataforma, decisiones ya tomadas — puede venir vacío):

$ARGUMENTS

## Qué hacer

Eres el agente de adopción. Tu trabajo es convertir la explicación del owner en los archivos
rellenados que los demás agentes (y los gates) van a obedecer. El mapa de qué rellenar y en
qué orden vive en `docs/ADOPTION.md` §4 — síguelo; no inventes otro orden.

1. **Inventario primero.** Corre `grep -rn "FILL:" . --include="*.md" --include="*.yml"
   --include="*.toml" --include="*.sh" --include="*.conf"` y
   `bash scripts/agent-hooks/session-start.sh --report` para saber qué falta y qué niveles
   están MUDOS hoy. Muestra el resumen al owner antes de preguntar nada.
2. **Entrevista en UNA tanda** (solo lo que $ARGUMENTS no cubra y no puedas deducir del
   código si ya existe). Lo mínimo imprescindible, en orden de impacto:
   - Plataforma(s) y lenguaje/versión · comandos REALES de build, test y lint
   - **Flags de modo estricto** (nivel 0): warnings-as-errors, strict concurrency, etc.
   - Patrón de pantalla/módulo (¿View+ViewModel+Logic? ¿MVVM? ¿Clean?), **navegación**
     (¿Coordinator? ¿Router? ¿NavigationStack?) y **DI** (¿constructor? ¿contenedor? ¿cuál?)
   - Carpetas reales del código (para `skill-matrix.conf`, `layers.conf` y `DRIFT_SRC_DIRS`)
   - Backend/DB e idiomas (i18n) · runner de mutación disponible (muter/Stryker/mutmut/…)
3. **Rellena, en este orden** (es la pirámide de abajo arriba — cada paso desmuta un nivel):
   1. `AGENTS.md` §2 (stack+comandos+estricto) y §3 (arquitectura/navegación/DI)
   2. `scripts/agent-hooks/post-edit-verify.sh` — el lint/typecheck real por archivo
   3. `tools/mutation-score.sh` — el runner de mutación; si existe, corre `--update` para
      fijar el primer piso
   4. `.agents/skills/architecture/SKILL.md` + `platforms/<plataforma>.md` +
      `domain/SKILL.md` — aquí van los EJEMPLOS de cómo se programa en este proyecto:
      un módulo de referencia (View+ViewModel+Logic o equivalente), cómo se navega a una
      pantalla nueva, cómo se inyecta una dependencia, cómo se define un puerto de
      repositorio con su fake. Ejemplos REALES del repo si ya hay código; canónicos si no.
   5. `tools/skill-matrix.conf` (globs de TUS carpetas — y la tabla humana de AGENTS.md §11
      en el mismo cambio) · `tools/layers.conf` · `.gitignore` (bloque de tu plataforma)
   6. `scripts/agent-hooks/canon-enforce.sh` §CHECK 5 y `tools/semgrep/rules/` SOLO si el
      owner ya tiene anti-patrones claros — no inventes reglas ruidosas (ley del 10%, §14)
   7. **`ci/run-gates.sh` paso 6 (build+tests reales) y el ANILLO 3** — este paso cierra la
      pirámide y no es opcional en preset `full` (§14.4). Comprueba con
      `bash tools/check-ring3.sh`; si falta, dile al owner exactamente qué le toca a él
      (`git remote add` + `git push`) y copia tú el workflow desde `ci/examples/`.
      Sin Anillo 3, todo exit 3 de cualquier detector es fail-open DEFINITIVO: el paso 3.7
      no es "el último de la lista", es el que hace ciertos a los otros seis.
4. **Regla de honestidad:** lo que el owner no sepa aún, se deja como FILL con una nota
   `<!-- OPEN QUESTION: … -->` — jamás un default inventado en silencio (§1.4). Menos
   relleno correcto > más relleno inventado.
5. **Verifica y muestra evidencia:** `bash tools/validate-harness.sh` +
   `bash scripts/agent-hooks/session-start.sh --report`. Enseña el antes/después de los
   niveles MUDOS. Los que sigan mudos, listados con qué falta para activarlos.
6. Cierra recordando el pulido continuo: cada vez que el agente programe algo "a su manera"
   y no a la del proyecto, eso es una skill incompleta — se corrige la skill (o se añade la
   lección con detector), no solo el código de esa vez. Así es como el harness aprende tu
   estilo (`docs/PLAYBOOK.md` §4).

> Scope: este comando toca meta-doc y tooling con aprobación implícita del owner que lo
> invoca (§8). No toca código de producto.

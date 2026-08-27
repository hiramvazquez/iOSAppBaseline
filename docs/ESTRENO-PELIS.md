# Estreno: app de pelis (lista + detalle) — el guión

> El primer proyecto real del harness: una app iOS desde 0 que consume una URL pública de
> películas, con lista y detalle, arquitectura de referencia (SwiftUI + MVVM-C + dominio
> puro) y TODO el flujo del template ejercitado de punta a punta. Este doc es TU guión;
> el del agente es `ONBOARDING-IA.md`. Bórralo del template cuando el estreno termine —
> lo que valga la pena quedará en lessons/skills.

## Paso 0 — El lienzo (tú, ~10 min)

1. Crea el proyecto Xcode: App SwiftUI, iOS 17+, Swift Testing como framework de tests.
2. Trae el template encima del proyecto (desde la carpeta del proyecto):
   `git init && git branch -m develop` si Xcode no lo hizo · copia el contenido del
   template (o clona y mueve) · `bash scripts/bootstrap.sh` · `lefthook install` ·
   `bash tools/validate-harness.sh`.
3. `tools/preset` → decide: `full` para vivir la experiencia completa de gates (mi voto
   para el estreno: quieres VERLOS bloquear), `lite` si prefieres fricción mínima.
4. Ten a mano: la URL pública del listado + un ejemplo real de response JSON.

## Paso 1 — Adopción guiada (el agente, contigo)

Abre `claude` en el proyecto y dile: **"lee docs/ONBOARDING-IA.md y guíame"** — hará las
fases 0-2 (salud, adopción, validación en vivo de los gates). En la entrevista de
`/adoptar`, tu input clave para esta app:

> iOS 17+, Swift 6.2, SwiftUI, Swift Testing. Patrón View + @Observable @MainActor
> ViewModel + Logic puro. Navegación: Coordinator con NavigationStack. DI por constructor
> con composition root en App. Red: URLSession async/await detrás de puertos del dominio.
> Sin dependencias de terceros. Build/test: (tu scheme real).

## Paso 2 — La cadena de historias (la prueba de fuego del troceo)

Dale a `/historia` la idea COMPLETA y observa si el comando la trocea solo — es su regla
de tamaño en acción. La idea, tal cual:

> App de películas contra <TU-URL>: pantalla de lista (poster, título, año) y pantalla de
> detalle al tocar una (poster grande, sinopsis, rating). Estados de carga/error/vacío.
> Aquí tienes un response de ejemplo: <PEGA EL JSON>

**Lo que DEBE salir** (si sale una sola historia gigante, es un hallazgo — me lo cuentas):
una cadena tipo `0001` puerto `MoviesPort` + modelos + `FakeMoviesRepository` con suite de
conformidad → `0002` (dep 0001) `MoviesListLogic` + `MovieDetailLogic` con TDD contra el
fake → `0003` (dep 0002) `MoviesListViewModel` + View con estados loading/content/error/
empty (spies para el orden) → `0004` (dep 0003) detalle + navegación vía Coordinator +
`URLSessionMoviesRepository` real pasando la MISMA suite de conformidad que el fake.

## Paso 3 — El bucle (una historia cada vez, tú mirando)

```bash
bash tools/backlog/run.sh        # trabaja la primera en un worktree aislado
git diff develop...story/0001-…  # revisas un diff que YA pasó todos los gates
git merge story/0001-… && sed -i '' 's/^status: .*/status: done/' backlog/0001-*.md
git add backlog && git commit -m "chore(backlog): 0001 done"
bash tools/backlog/run.sh        # la 0002 se desbloqueó sola — repite
```

Primera historia con el run supervisado (tú delante), como pide `backlog/README.md`.
Mientras el agente trabaja, tu checkout queda LIBRE — el worktree aísla.

## El botín del estreno (cómo me lo traes — mecánico, no de memoria)

**El comando que lo empaqueta todo:**

```bash
bash tools/harness-report.sh
```

Genera UN markdown pegable (acotado + secretos redactados) con: entorno y versiones, salud
del harness, los logs de los últimos runs del backlog (cada `run.sh` deja el suyo en
`.agents/state/backlog/` automáticamente), la telemetría de qué gate detectó qué, atascos,
overrides, findings abiertos y el estado de las ramas. **Pega su contenido completo en
nuestra conversación** después de cada historia (o al final del día) — con eso yo veo cómo
se comportó el sistema real y arreglamos con evidencia.

**Lo que el informe NO captura y tu ojo sí** (anótalo aparte):

- ¿`/historia` troceó solo la idea o hubo que empujarlo? ¿`/adoptar` dejó niveles MUDOS sin avisar?
- Cada gate que bloquee: ¿fue justo? Los injustos son oro (ley del 10%).
- ¿El agente usó Swift 6.2 de verdad (actors, @Observable, Swift Testing) o "Swift viejo"
  pese a `swift-estado-del-arte.md`? ¿Respetó el orden con spies sin que se lo pidieras?
- Los checks en vivo del `validate-harness` que fallen: máxima prioridad — gates presuntos.

Todo eso vuelve a esta conversación → lessons con detector → el harness sale del estreno
mejor de lo que entró. Esa es la única métrica del éxito que importa.

## Criterios de graduación (cuándo Pelis cumplió su misión)

El estreno NO es "terminar la app" — es ver cada pieza del harness funcionar en vivo una
vez. Pelis se gradúa (y se abre el siguiente proyecto) cuando TODO esto haya ocurrido:

- [ ] **El camino GREEN completo**: reviewer emite `VERDICT: GREEN` → SubagentStop escribe
      el marker (`source: hook`) → `git commit` pasa los 3 anillos. (El camino RED ya está
      visto: 28 veces. Falta ver la puerta ABRIRSE.)
- [ ] **`/historia` trocea solo** una idea multi-capa en cadena con `depends_on`.
- [ ] **Una historia end-to-end**: `run.sh` en worktree → TDD dentro → `in-review` → tu
      merge → `done` desbloquea la siguiente. Al menos UNA vez de punta a punta.
- [ ] **Anillo 0 y semgrep/SwiftUI**: findings con evidencia en el ledger (ya casi) y fix
      upstream aplicado + bajado vía `upgrade.sh` — el primer upgrade real de un proyecto vivo.
- [ ] **`harness-report` final** pegado en la conversación de mejora, con el balance.

Lo que quede sin ver al graduarse, se declara — no se presume. La app de pelis en sí puede
quedar a medias sin culpa: era el campo de tiro, no el objetivo.

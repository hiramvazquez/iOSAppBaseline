# <PROJECT> — Reglas de trabajo con agentes (FUENTE CANÓNICA)

> Este archivo es la **única fuente de verdad** de las reglas del proyecto para agentes de IA.
> Lo leen nativamente **Cursor, Codex, Copilot, Gemini y otros**. Claude Code lo recibe vía
> `CLAUDE.md` (que hace `@AGENTS.md`). Si una regla aquí choca con cualquier otra fuente, **gana esta**.
>
> Mantenlo **terso**. El detalle vive en `.agents/skills/` y en `docs/process/`. El racional
> histórico / post-mortems mecanizados van en `docs/process/lessons_archive.md`, NO aquí.

---

## 0. Antes de escribir código

1. Lee la parte viva de `docs/process/lessons_learned.md` — detente en “Lecciones mecanizadas
   (índice)”. El índice y `lessons_archive.md` se consultan solo si una señal relevante exige
   su racional; el histórico no se carga por defecto. Si cazas un patrón nuevo, agrégalo aquí.
2. Lee `docs/process/current_execution_map.md` — fase actual y próximo paso.
3. Carga **solo** la skill del área que tocas (ver §11 matriz path→lectura).
4. Si la skill no cubre tu caso: **NO improvises** — pregunta al owner y actualiza la skill antes de seguir.
5. Feature mediana/grande → **PRD obligatorio antes del primer commit** (§12).

## 1. Las reglas de oro (filosofía no negociable)

1. **Detectar no basta — CERRAR.** Cada hallazgo llega a estado terminal y visible (`tools/findings/`).
2. **Defensa en capas.** Detector mecánico + design-review + reviewer + juez + lecciones. Ninguno solo basta.
3. **El que toca, cierra.** Tocas un módulo con findings abiertos → los arreglas o los registras, en el mismo PR.
4. **Open Question > suposición silenciosa.** Si no sabes (una columna, un catálogo, un contrato), preguntas; no inventas un default.
5. **Scope = lo explícitamente pedido.** Nada de "aprovechar el viaje" para refactorizar lo de al lado (§8).

## 2. Stack y comandos

- **Plataformas:** iOS 17+ (SwiftUI). macOS no es objetivo de la app; los SPM propios sí
  compilan en macOS para que su suite corra sin simulador.
- **Lenguajes / versiones:** Swift 6 (language mode 6), toolchain Xcode 26.6 / Swift 6.3.
- **Build:** `xcodegen generate && xcodebuild build -scheme iOSAppBaseline -destination "platform=iOS Simulator,name=iPhone 17"`
- **Tests:** `bash tools/verify-run.sh` (firma la evidencia contra el diff staged) — el comando
  crudo vive en `tools/verify.conf`, fuente única.
- **Lint/format:** `swift-format` de la toolchain de Xcode (`xcrun swift-format`). No hay
  SwiftLint: el modo estricto del compilador cubre lo que importa y un segundo linter con
  reglas propias sería otra fuente de verdad que mantener.
- **Backend/DB:** ninguno propio. Datos de **TMDB** (API pública REST). Sin persistencia local
  por ahora — cuando la haya, es decisión de arquitectura y va a `docs/process/decisions/`.
- **Idiomas de la app (i18n):** **ES + EN**. Ningún texto visible se escribe en el código:
  String Catalog. Y jamás se ramifica lógica sobre texto natural (§3).
- **Modo estricto (nivel 0 — OBLIGATORIO):** en `project.yml`, aplicado a los dos targets:
  `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` · `SWIFT_STRICT_CONCURRENCY=complete` ·
  `SWIFT_APPROACHABLE_CONCURRENCY=YES` · `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`.
  Los SPM propios llevan lo equivalente en su `Package.swift`.
  El compilador es el primer reviewer y el único que no se cansa: un agente que **no puede
  expresar** el estado inválido no lo escribe. Ningún gate posterior compensa una API donde el
  mal uso compila. Prioriza hacer el error imposible por tipo antes que detectarlo después.

## 3. Arquitectura (capas + límites)

> **Las decisiones de arquitectura de este proyecto están TOMADAS Y COMPILADAS** en los dos
> paquetes propios: `AppFoundation` (arquitectura, navegación, DI, estados de pantalla) y
> `CoreNetworking` (red, pinning, reintentos). No se re-litigan por pantalla: se citan. Lo que
> los paquetes no cubran se decide una vez y se escribe en `docs/process/decisions/`.

- **Patrón de pantalla/módulo:** **View + ViewModel + Logic pura**. La vista se monta SIEMPRE
  dentro de `ScreenContainer` (AppFoundation), que pinta carga / error / vacío / contenido a
  partir del estado del ViewModel — una pantalla no reimplementa esos cuatro estados. El
  ViewModel hereda de `BaseViewModel` (`@Observable`) y ORQUESTA; la lógica de negocio
  testeable vive aparte, en tipos puros sin dependencias de UI ni de red.
- **Navegación:** `Coordinator` + `Router` de AppFoundation. Las vistas NO navegan: piden al
  router. Una capa modal por host (el estado no modela lo que SwiftUI no puede renderizar).
- **Inyección de dependencias:** `Container` de AppFoundation (`Container.shared` inmutable) con
  `@Inject` en los consumidores; los tests registran fakes en contenedores propios, nunca
  mutando el global.
- **Red:** todo acceso HTTP pasa por `APIService` de CoreNetworking con su `NetworkingConfiguration`
  inyectada. Nada de `URLSession` suelto en la app.
- **Dominio aislado:** las entidades, puertos de repositorio y errores de dominio NO dependen de UI ni de infraestructura (DB/SDK).
- **i18n:** NUNCA ramifiques lógica sobre texto en lenguaje natural (`if texto == "diaria"`). Eso rompe en otros idiomas — clasifica en el servidor/LLM o con tablas keyed por idioma.

## 4. Límites de tamaño (soft = revisar / hard = dividir en el mismo PR)

<!-- OPINIÓN: defaults razonables; ajusta a tu lenguaje. -->

| Tipo | Soft | Hard |
|---|---:|---:|
| Archivo | 200 | 400 |
| Función | 40 | 60 |
| Clase orquestadora (ViewModel/Controller) | 150 | 250 |

## 5. TDD obligatorio + aserciones (🔴 red → 🟢 green → ♻️ refactor)

**Ninguna lógica/orquestación nueva sin un test que falle PRIMERO.** Ciclo: escribe el test y
míralo fallar → implementación mínima que lo pasa → refactor en verde. La matriz de tests sale
del contrato y el riesgo: happy path si existe + cada rama que cambie comportamiento observable,
recuperación, permisos o límites. No inventes casos para cumplir una cuota. Bug fix = primero un
test que reproduce el bug (falla), luego el fix. Antes de marcar terminado: tests del área + build verde + `bash tools/check-drift.sh`
sin errores nuevos. Playbook + ejemplos iOS: `.agents/skills/process/references/tdd-workflow.md`.

- **Un test que pasa con cualquier implementación no es un test.** La prueba de bolsillo: *si
  rompo a propósito la lógica que dice cubrir, ¿falla?* El veredicto mecánico lo da el
  **mutation score** (`tools/mutation-score.sh`), cuyo piso **solo sube**. Es el gate que
  distingue un test que verifica de uno escrito para que pase.
- **Aserciones / Design by Contract:** toda frontera pública expresa las precondiciones e
  invariantes que realmente tiene; una función sin precondición no inventa dos. Las aserciones
  son para errores de programación/invariantes, sin efectos secundarios. Input recuperable se
  valida con tipos/errores explícitos, no con un crash. Prioriza siempre hacer el estado inválido
  **imposible por tipo** antes que verificarlo en runtime.
  *Mecanismo (declarado, no implícito):* la valida el **checklist del `reviewer`** (ítem DbC) y
  la mide indirectamente el **mutation score** — un contrato sin verificar deja mutantes vivos.
  NO hay detector por grep a propósito: contar aserciones sin un parser real por lenguaje
  produciría ruido, y un detector ruidoso se descarta entero (ley del 10%, §14).
- **Invariantes → property-based tests.** Si la regla vale para todos los valores, no la
  compruebes con tres ejemplos.
- **Todo fake pasa la MISMA suite de conformidad que el adapter real** (`domain/SKILL.md`).

## 6. Seguridad (gate de cada commit)

> El Anillo 1 (`lefthook` + `gitleaks`) bloquea secretos mecánicamente. Estas reglas son lo
> que el scanner no ve y el `security-reviewer` sí. Detalle en `.agents/skills/security/SKILL.md`.

- **Cero secretos en código.** API keys, tokens, claves privadas, connection strings → variables de entorno / secret manager. Nunca hardcoded, nunca en commits.
- **Cero secretos en logs / telemetría / mensajes de error** que lleguen al cliente.
- **Datos sensibles (PII/PHI) al almacenamiento seguro** de la plataforma (Keychain/Keystore/cifrado), nunca a almacenamiento en claro (UserDefaults/SharedPreferences/localStorage planos).
- **DB:** RLS/authz por fila donde aplique; cifrado at-rest (default del proveedor) verificado; sin tablas sensibles sin política de acceso.
- **Dependencias:** sin paquetes no auditados para manejar secretos/cripto; revisa el lockfile.
- **Authn/authz, cripto y validación sensible fallan cerradas:** ante error o duda, deniega;
  nunca continúes con permisos/defaults permisivos. Los fallos de observabilidad se hacen
  visibles (sin datos sensibles) y solo pueden preservar la operación principal si hacerlo
  sigue siendo seguro. Fail-silent nunca.

## 7. Convenciones Git (duras)

- Jamás `git commit --amend` sin orden explícita del owner. Jamás `--no-verify`, `--force` a main, ni `git add -A` con cambios fuera de scope.
- Un cambio coherente = un commit. `git push` solo con aprobación explícita del owner.
- Formato de mensaje: `<tipo>(<área>): <qué hizo>` — tipos: feat/fix/refactor/docs/chore/sec/test.

## 8. Disciplina de scope

El agente que ejecuta una tarea/PRD tiene scope **limitado a lo que el PRD/prompt lista explícitamente**.
Prohibido sin aprobación del owner: tocar tooling compartido (`tools/`, `ci/`, `lefthook.yml`),
meta-doc (este archivo, `.agents/skills/**`, `_template.md`), o refactorizar archivos fuera de scope.
**Errores preexistentes: se reportan al ledger, NO se silencian ni se "arreglan de paso".**

## 9. Drift policy + trinquetes

- Cambio que toca un **enum/contrato compartido** o un **puerto de repositorio** → actualiza
  todas las capas afectadas + su doc en el **mismo PR**.
- **Los trinquetes tienen una dirección fija y no se editan a mano.** Solo los actualiza su
  propio script; están en `permissions.deny` de escritura a propósito. Un número que se puede
  aflojar no es un trinquete: es una sugerencia.

| Archivo | Métrica | Dirección | Actualiza con |
|---|---|---|---|
| `tools/drift-ratchet.json` | errores + warnings | **solo baja** | `tools/drift-ratchet.sh --update` |
| `tools/mutation-ratchet.json` | mutation score | **solo sube** | `tools/mutation-score.sh --update` |

- Ni el preset `lite` ni `REVIEWER_OVERRIDE` relajan un trinquete. Ese override existe para el
  **marker de review** (juicio humano), nunca para un detector mecánico. Está fijado por
  `tools/tests/test_ratchets.sh`.

## 10. Cero-deuda-nueva (ownership de findings)

"No es mío, lo dejo" está **prohibido**. Cualquier gap que detectes (incluido uno preexistente)
se resuelve en el mismo turno: o lo arreglas, o lo **registras en el ledger** con tier+área
(`tools/findings/`). Reportar = loguear al ledger, no solo mencionarlo en prosa.

**Y toda lección aprendida se convierte en un detector.** `docs/process/lessons_learned.md`
exige el campo `Detector:` y `tools/lesson-detector-link.sh` lo verifica en CI; cuando ese
detector es un test del Anillo 3, `tools/lessons-rotate.sh --apply` mueve el racional al archivo
histórico y conserva un índice compacto. Sin detector,
las lecciones son prosa que nadie relee y que el agente pierde en la primera compactación.
Con él, cada error cometido una vez se vuelve mecánicamente imposible la segunda — que es el
único mecanismo por el que la necesidad de revisión humana **decrece** en vez de mantenerse
plana. Excepción legítima y explícita: `n/a-manual — <razón>`.

## 11. Skills enforcement — matriz path → lectura obligatoria

Antes de editar un archivo, debes haber leído la referencia que aplica. La **fuente única**
de la matriz es `tools/skill-matrix.conf` — el hook `skill-reminder` (Anillo 2) la lee en
runtime y bloquea. Esta tabla es la **vista humana** de ese conf: si cambias el conf,
actualiza la tabla en el mismo commit (antes la matriz vivía en cinco sitios y divergía;
`test_skill_matrix.sh` fija que toda ref citada exista).

<!-- iOS de referencia. Ajusta los globs a tus carpetas reales si difieren. -->

| Path que vas a editar | Reference obligatorio |
|---|---|
| `**/*View*.swift`, `**/*Screen*.swift` | `architecture/SKILL.md` + `architecture/platforms/ios.md` |
| `**/*ViewModel*.swift`, `**/*Logic*.swift`, `**/*UseCase*.swift` | `architecture/SKILL.md` + `domain/SKILL.md` + `process/references/tdd-workflow.md` + `platforms/swift-estado-del-arte.md` |
| `**/Domain/**` | `.agents/skills/domain/SKILL.md` + `process/references/tdd-workflow.md` |
| `**/Data/**`, `<migraciones-db>/**` | `domain/SKILL.md` (puertos) + `security/SKILL.md` |
| `docs/process/prds/[0-9]*.md` | `process/references/prd-lifecycle.md` + `feature-workflow.md` |

**Esta tabla es exactamente el conf, ni una fila más.** La coherencia entre ambos la verifica
`tools/check-skill-matrix-doc.sh` comparando el conjunto de referencias de los dos lados; si
añades una lectura obligatoria aquí y no al conf, falla. Y falla *en esa dirección a propósito*:
una fila aquí sin respaldo en el conf es una defensa **anunciada que no existe**, que es el
único pecado que este harness no comete (§14.4).

> Tocar `tools/**`, `ci/**` o `scripts/agent-hooks/**` **no** está en la tabla, y no es un
> olvido: `skill-reminder` excluye esas rutas a propósito (editar la doc o el tooling de un área
> no es editar el código de ese área — era un falso positivo real, fijado por
> `test_skill_reminder.sh`). Su gate es otro y es más fuerte: §8 exige **aprobación explícita del
> owner** para tocar tooling compartido. La lectura recomendada antes de hacerlo sigue siendo
> `process/references/verification-loop.md`, pero es una recomendación, no un bloqueo — y
> decirlo así es la diferencia entre documentar un gate y fingirlo.

> El **gate duro** es el hook `skill-reminder` (lee `tools/skill-matrix.conf`). Como camino
> feliz, `.claude/rules/*.md` puede inyectar recordatorios por path en Claude Code. Nota
> honesta: la carga automática por `paths:` en el frontmatter de una skill NO es parte del
> estándar portable de skills (agentskills) — no dependas de ella para clientes distintos
> de Claude Code; el conf + el hook son lo que de verdad se cumple.

## 12. PRD obligatorio para features medianas/grandes

Criterio "mediano/grande" (≥2 de): >3 días dev · >1 módulo · cambia schema · cambia contrato
de API · decisión de privacy/security/pricing · decisión arquitectónica reusable.
Flujo completo en `.agents/skills/process/references/feature-workflow.md`. Template:
`docs/process/prds/_template.md`. **El design-review del CÓMO (sub-agente `design-reviewer`)
es un gate distinto del "Approved" del owner** — no es salteable para cambios de arquitectura o PHI.

## 13. Reviewer-gate pre-commit

Todo commit que toque código de producto requiere ejecución previa del sub-agente `reviewer`.

**El veredicto no lo emite el modelo, lo deriva el sistema.** El `reviewer` termina su mensaje
con `VERDICT: GREEN|AMBER|RED`, y el hook `SubagentStop` escribe el marker a partir de esa línea
real. `tools/check-review-marker.sh` solo acepta markers con `source: hook`; un marker escrito a
mano se rechaza. (`scripts/mark-reviewer-run.sh` existe solo como fallback para clientes sin
hooks, y queda auditado.)

Lo verifican los **tres anillos**: `lefthook` (Anillo 1, cubre humanos y cualquier cliente),
`reviewer-gate` (Anillo 2 — en Claude Code nativo; en Cursor y Codex vía
`scripts/agent-hooks/adapters/gate-adapter.sh`) y `ci/run-gates.sh` + `ci/ai-review.sh`
(Anillo 3). **Flujo que el gate exige:** stagea → invoca al `reviewer` → commitea en un
comando aparte. El marker liga `sha256(diff staged)`: `git add X && git commit` en una línea
o `commit -a/-am` evaden esa validación y el gate los rechaza. Override de emergencia auditado:
`REVIEWER_OVERRIDE=1 REVIEWER_OVERRIDE_REASON="..." git commit ...` — **relaja el marker, nunca
un trinquete** (§9).

**Y el mismo invariante para los TESTS, no solo para el reviewer.** El marker de review se liga a
`sha256(diff staged)`; durante meses ninguna ejecución de build o de tests se ligaba a ese mismo
diff, así que se podía commitear un árbol que **nadie llegó a compilar** con todo en verde — el
reviewer no compila, los trinquetes no compilan y las capas no compilan. `tools/verify-run.sh`
ejecuta el comando de `tools/verify.conf` (fuente única, compartida con el paso 6 del Anillo 3) y,
solo si sale 0, firma ese diff; `tools/check-verify-marker.sh` lo exige. Flujo: **stagea →
`bash tools/verify-run.sh` → commitea**, el mismo que ya pedía el review. Override auditado:
`VERIFY_OVERRIDE=1 VERIFY_OVERRIDE_REASON="..."`.

**Presets:** con `tools/preset = lite` (uso personal) este gate y el `skill-reminder` AVISAN en vez
de bloquear; los trinquetes, las capas y `canon-enforce` siguen duros. `full` (equipo) es el default.

## 14. El bucle de verificación (cómo sabemos que el código está bien)

Referencia completa: **`.agents/skills/process/references/verification-loop.md`**.

Dos principios que gobiernan todo lo demás:

1. **Cázalo en la capa más barata.** Cada nivel que un defecto sube sin detectarse multiplica
   ~10× el coste. Un error que el compilador podía cazar y que llega a un juez de IA no es un
   error del agente: es un fallo de diseño del harness.
2. **El que escribe nunca es el que aprueba, y "aprobar" es presentar evidencia.** Un veredicto
   es la salida de un comando, un exit code o un score — nunca una afirmación del modelo.

```
9 Métricas + lección→detector     8 Gate por evidencia      7 Review adversarial de IA
6 Arquitectura (imports directos; ciclos si hay adapter) 5 Contratos (fake ≡ real) 4 CALIDAD del test (mutación)
3 Spec ejecutable (TDD + DbC)     2 Patrón AST (Semgrep)    1 Lint/typecheck in-loop
0 Imposibilitar (tipos)
```

**La ley del 10% (§14.2):** un detector con más de ~10% de falsos positivos se descarta — y un
agente además aprende a evadirlo. Por eso los patrones van en Semgrep (AST) y no en `grep`.
Prefiere 5 reglas exactas a 50 ruidosas.

**El contrato de exit codes de los detectores (§14.3):** `0` = limpio · `1` = tu código tiene
un problema (bloquea, sin excepción) · `3` = **el detector no pudo mirar** (ausente, reglas
rotas, crash). El 3 AVISA en local y BLOQUEA en CI (`GATES_REQUIRE_*=1`): bloquear en local
crearía un deadlock — un typo en las reglas impediría hasta el commit que lo arregla — pero
tratarlo como éxito convertiría un scanner roto en luz verde permanente. Corolario: **un bug
del hook nunca debe trabar el commit en local; un gate que no corrió nunca debe parecer un
gate que pasó.**

**§14.4 — El Anillo 3 es OBLIGATORIO en preset `full`, y esto no es burocracia: es lo que
hace verdadera la frase anterior.** Todo el fail-open local de §14.3 está justificado *por*
la existencia del backstop. Sin Anillo 3, un exit 3 no es "avisa y luego CI bloquea": es
**fail-open definitivo y silencioso**, y el razonamiento de todos los niveles se cae con él.
Lo verifica `tools/check-ring3.sh` (remoto + config de CI que ejecute los gates), y lo exige
`validate-harness` en `full`. En `lite` no bloquea, pero se DECLARA en cada arranque de
sesión — porque el pecado que este harness no comete es anunciar una defensa que no existe.

## 15. Cómo entrar a una sesión nueva

1. Lee este archivo. 2. Lee `docs/process/current_execution_map.md`. 3. Lee solo el tramo vivo de
`lessons_learned.md` (§0). 4. Carga la skill del área (§11). 5. Abre el PRD/ADR relevante.
6. **Verifica los hechos contra el código/DB antes de editar.**

> Si estás retomando tras una compactación de contexto: el hook `SessionStart(source: compact)`
> te reinyecta el digest de reglas y los findings abiertos (Claude re-inyecta solo el CLAUDE.md
> raíz; el resto lo repone `post-compact.sh`). Si algo de §11 no lo recuerdas con precisión,
> reléelo — el `skill-reminder` te lo exigirá de todas formas.

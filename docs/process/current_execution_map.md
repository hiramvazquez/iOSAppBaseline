# Mapa de ejecución actual

> Lo lee el agente al inicio de cada sesión (`session-start.sh` extrae "Estado actual"). Mantenlo
> al día: es la respuesta a "¿en qué estamos y qué sigue?". Una pantalla, sin historia.

## Estado actual

- **Qué es este repo:** **iOSAppBaseline** — el proyecto base del que salen los proyectos iOS
  nuevos. Tres cosas a la vez, y por eso existe: (1) instancia los dos paquetes propios
  —`AppFoundation` (arquitectura, navegación, DI, estados de pantalla) y `CoreNetworking`
  (red, pinning, reintentos)—, (2) trae el agentic-workflow-template cableado al stack, y
  (3) su app —listado y detalle de películas contra TMDB— es el **módulo de referencia**: la
  vertical que cruza todas las capas y que las skills citan en vez de describir.
- **Fase:** arranque. Esqueleto y harness listos y verificados; la vertical de películas es lo
  siguiente y aún no existe.
- **Anillo 3 CABLEADO** (`check-ring3` ✅): `origin` en GitHub y `.github/workflows/gates.yml`
  con dos jobs — los gates deterministas en Linux (`ci/run-gates.sh` con `GATES_SKIP_TESTS=1`,
  renuncia explícita: en Ubuntu no hay Xcode) y el build+tests real en macOS invocando
  `tools/verify-run.sh --ci`, el mismo gate que en local. Se reparte así porque macOS consume
  cupo de Actions a ~10× y un cupo agotado ya dejó a otro repo sin Anillo 3 una semana sin que
  nadie lo declarara. El rango del scan de secretos sale de `github.event.before` (el commit
  anterior al push), no de `origin/main`: tras el push ese ref ya es `HEAD` y el gate aprobaría
  sin escanear nada. **Aún no ha corrido nunca**: su primera ejecución es el push que lo estrena.
- **Entregado:**
  - Proyecto declarado en `project.yml` (xcodegen). El `.xcodeproj` es artefacto gitignored:
    se regenera con `xcodegen generate` y no da conflictos de merge.
  - Nivel 0 en ambos targets: Swift 6, `SWIFT_STRICT_CONCURRENCY=complete`, MainActor por
    defecto y warnings como errores.
  - Los dos SPM enlazados **por ruta local** (`../spm-pro/…`) mientras su API se estabiliza, con
    un smoke test que los importa y los USA — un `#expect(true)` habría pasado con el proyecto
    mal cableado.
  - Harness adoptado (caso B de `docs/ADOPTION.md`) con `verify.conf` cableado a
    `xcodegen generate && xcodebuild test`, `layers.conf` ampliado con las reglas propias,
    `project_kind: application`, preset `full` y lefthook instalado.
- **Secretos:** la clave de TMDB va en `Config/Secrets.xcconfig` (gitignored) copiando
  `Config/Secrets.example.xcconfig`. **Sin ella el proyecto compila igual** —el `#include?` es
  opcional— y falla en runtime con un mensaje claro; no rompe el build de un clon recién hecho.

## Próximo paso

1. **La vertical de referencia (TDD):** dominio (entidad `Movie`, puerto de repositorio, errores
   tipados) → adapter TMDB sobre `APIService` con su suite de conformidad compartida con el fake
   → ViewModel sobre `BaseViewModel` → pantallas dentro de `ScreenContainer` con navegación por
   `Coordinator`. Cada capa con su test rojo-primero.
2. **Publicar los SPM:** cuando la vertical demuestre que su API es cómoda de consumir, van a
   repos públicos con tag `1.0.0` y aquí cambia **una línea** de `project.yml`: `path:` → `url:`
   + `from:`. Estrenar antes de etiquetar es deliberado: un 1.0.0 publicado sin haberlo usado
   nace obsoleto.

## Decisiones ya tomadas (no re-litigar)

Viven en los paquetes y en `AGENTS.md` §2/§3: patrón View+ViewModel+Logic con `ScreenContainer`,
navegación por `Coordinator`, DI por `Container`, red por `APIService`, i18n ES+EN con String
Catalog, mínimo iOS 17. Lo que los paquetes no cubran se decide **una vez** y se escribe en
`docs/process/decisions/`.

## Punteros

- Reglas: `AGENTS.md` · **Bucle de verificación:** `.agents/skills/process/references/verification-loop.md`
- Lecciones: `docs/process/lessons_learned.md` (toda entrada exige `Detector:`)
- Findings: `docs/process/findings-ledger.md` (arranca vacío: los del template son deuda suya)
- Salud del harness: `bash scripts/agent-hooks/session-start.sh --report`

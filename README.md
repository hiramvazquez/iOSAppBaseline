# iOSAppBaseline

Proyecto base del que salen los proyectos iOS nuevos. Tres cosas a la vez, y por eso existe:

1. **Instancia dos paquetes propios** — `AppFoundation` (arquitectura, navegación, DI, estados de
   pantalla) y `CoreNetworking` (red, SSL pinning, reintentos).
2. **Trae el harness agéntico cableado al stack**: los gates que verifican el código que escribe
   una IA, atados a este build concreto y no a un ejemplo.
3. **Su app es el módulo de referencia**: un listado y detalle de películas contra TMDB — la
   vertical que cruza todas las capas y que las skills citan en vez de describir.

## Requisitos

| Herramienta | Para qué |
|---|---|
| Xcode 26+ | Swift 6, iOS 17+ |
| [`xcodegen`](https://github.com/yonaskolb/XcodeGen) | genera el `.xcodeproj` desde `project.yml` |
| [`lefthook`](https://github.com/evilmartians/lefthook) | gates de pre-commit y pre-push |
| [`gitleaks`](https://github.com/gitleaks/gitleaks) | escaneo de secretos |
| [`semgrep`](https://semgrep.dev) | detectores AST |

## Arrancar

```bash
brew install xcodegen lefthook gitleaks semgrep
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # pon tu clave de TMDB
lefthook install
xcodegen generate && open iOSAppBaseline.xcodeproj
```

La clave de TMDB se saca en [themoviedb.org/settings/api](https://www.themoviedb.org/settings/api).
Sin ella el proyecto **compila igual** —el `#include?` del xcconfig es opcional— y falla en runtime
con un mensaje claro: un clon recién hecho nunca se rompe por un archivo que no está.

## Cómo está montado

- **El `.xcodeproj` no se versiona.** La fuente de verdad es `project.yml`; el proyecto se regenera
  con `xcodegen generate`. Sin `pbxproj` en el repo no hay conflictos de merge en el archivo que
  nadie sabe revisar.
- **Nivel 0 en ambos targets:** Swift 6, `SWIFT_STRICT_CONCURRENCY=complete`, aislamiento
  `MainActor` por defecto y warnings como errores. El compilador es el primer revisor.
- **Los paquetes entran por URL con versión** (`from: 0.1.0`; el lockfile fija hoy
  AppFoundation 0.1.1 y CoreNetworking 0.1.0). Siguen en `0.x` a propósito:
  esta app es la primera que los consume de verdad, y hasta que la vertical de referencia
  ejercite su API entera no se congela un `1.0.0` del que ya no se puede salir.

## Verificar

```bash
bash tools/verify-run.sh
```

Genera el proyecto, corre la suite en el simulador y **firma la evidencia contra el diff que vas a
commitear**. El comando concreto vive en `tools/verify.conf`, fuente única compartida con CI: local
y servidor no pueden divergir porque leen el mismo archivo.

## Capacidades del harness

<!-- BEGIN GENERATED: capabilities -->
| Capacidad | Requerida en full | Requerida en lite | Proveedor | Garantía |
|---|:---:|:---:|---|---|
| `architecture_complexity` | no | no | `tools/architecture-check.sh architecture_complexity` | Complejidad ciclomática |
| `architecture_cycles` | no | no | `tools/architecture-check.sh architecture_cycles` | Detección de ciclos |
| `architecture_import_direction` | sí | sí | `tools/check-layers.sh` | Dirección de imports directos |
| `review_marker` | sí | no | `tools/check-review-marker.sh` | Evidencia de review ligada al diff |
| `ring3` | sí | no | `tools/check-ring3.sh` | Backstop de CI |
| `semgrep` | sí | sí | `tools/probe-capability.sh semgrep` | Análisis AST funcional |
| `skill_reminder` | sí | no | `scripts/agent-hooks/skill-reminder.sh` | Lectura obligatoria por path |
<!-- END GENERATED: capabilities -->

## Las reglas

`AGENTS.md` es la fuente canónica: stack, arquitectura, límites, TDD y el bucle de verificación.
Lo leen Claude Code, Cursor, Codex y demás. El estado vivo del proyecto —qué se hizo y qué sigue—
está en `docs/process/current_execution_map.md`.

**Las decisiones de arquitectura ya están tomadas y compiladas** en los dos paquetes. No se
re-litigan por pantalla: se citan. Lo que los paquetes no cubran se decide una vez y se escribe en
`docs/process/decisions/`.

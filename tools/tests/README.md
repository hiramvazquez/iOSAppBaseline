# tools/tests — los tests del propio harness

> Los gates son código, y código con lógica de decisión sin test es deuda (AGENTS.md §5).
> Esta suite (`bash tools/tests/run-tests.sh` imprime el conteo real — no lo hardcodees aquí,
> ya se pudrió dos veces) fija el COMPORTAMIENTO de los gates. Corre en cada push vía
> `.github/workflows/harness-ci.yml` en Linux **y** macOS — la diferencia de OS es un
> detector en sí misma (cazó el bug de `stat -f/-c` que rechazaba markers válidos en CI):
> corre los scripts reales en repos git desechables y verifica exit codes, salidas y archivos
> producidos — nunca detalles de implementación.

## Qué valida cada capa (sé honesto sobre el alcance)

| Capa | ¿Validada? | Cómo |
|---|---|---|
| **Maquinaria mecánica** (gates, trinquetes, CLIs, parsers) | ✅ automática | esta suite, en cada commit (canon-enforce CHECK 4) y en CI (paso 1 de run-gates) |
| **Integración con Claude Code** (eventos, payloads, wiring de settings.json) | ✅ empírica, ❌ no automatizable desde bash | validada en vivo durante la construcción (commits reales por los gates, VERDICT RED y GREEN con invocaciones reales del reviewer). Si el shape de un evento cambiara, lo delata el comportamiento **fail-closed** (sin marker → commit bloqueado), no un test rojo |
| **Cursor en vivo** | ❌ pendiente | `hooks.json` escrito según su doc; primer adoptante con Cursor lo confirma |
| **`ai-review.sh` con `claude` real en CI** | 🟡 parcial | todas sus ramas de fallo testeadas; la review headless completa requiere runner con API key |
| **`PostCompact` / `PostToolUseFailure` en vivo** | ❌ pendiente | nunca dispararon aún; fail-open por diseño (si no corren, nada se rompe — se pierde la ayuda) |
| **El stack del adoptante** | por diseño, suyo | los `<!-- FILL -->`; `session-start` reporta qué niveles quedan MUDOS |

## Los tres contratos que la suite fija

1. **Detección**: lo malo bloquea (secretos, capas, hallazgos AST, marker inválido…).
2. **Falsos positivos** (~⅓ de la suite, exigido por `test_meta_fp.sh`): lo legítimo pasa —
   docs sin review, deuda preexistente, archivo limpio en silencio, detector roto sin deadlock.
   La lección que lo motivó: *el primer FP de un detector aparece en el repo del propio detector*.
3. **Semántica de fallo**: evidencia ausente/corrupta jamás se lee como aprobación ("no pude
   mirar" ≠ "está limpio"), y la telemetría jamás rompe al gate que la llama.

## Cómo escribir un test nuevo

- Archivo `test_<área>.sh` con funciones `test_*` (el runner las descubre; aserciones
  `assert_eq/assert_contains/assert_exit` y `with_temp_repo` disponibles).
- Sandbox propio: copia los scripts a un repo temporal — los hooks derivan `PROJECT_ROOT`
  de su dirname, así que funcionan copiados.
- **Escribe el caso de falso positivo el mismo día** y márcalo con "FALSO POSITIVO" —
  `test_meta_fp.sh` exige que el archivo lo tenga, y añade tu detector a su manifiesto.
- Prueba de calidad del test: rompe el fix a propósito y confirma que el test FALLA
  (mutación manual — `test_el_sid_es_dato_no_patron` nació así).

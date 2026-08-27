---
id: NNNN
titulo: <verbo + resultado, como el summary de un ticket>
status: ready        # ready | in-progress | in-review | done | blocked | ejemplo
depends_on: []       # ids que deben estar DONE (= mergeados a la base) antes: [0001, 0002]
base: develop        # rama desde la que se crea story/NNNN-<slug>
scope: |             # ÚNICA allowlist mecánica de lo que PUEDE tocar (§8)
  <rutas o globs>
---

# <mismo título>

## Historia
Como <rol> quiero <acción> para <valor>.

## Contexto
<Lo que el agente no puede deducir del código: decisiones ya tomadas, enlaces
a PRD/diseño, por qué ahora. 3-6 líneas.>

## Criterios de aceptación
<!-- OBLIGATORIOS y en formato verificable. Son los escenarios golden: cada uno
     se convierte PRIMERO en un test que falla (TDD §5). El runner BLOQUEA la
     historia si faltan — sin contrato verificable no se trabaja (§1.4). -->
1. Dado <estado inicial> cuando <acción> entonces <resultado observable>.
2. Dado <caso de error> cuando <acción> entonces <manejo esperado>.

## Verificación de criterios
<!-- Lo rellena el agente ANTES de cerrar; el runner lo comprueba y BLOQUEA.
     Una línea por criterio, con el test que lo fija:
       1. Tests/FooTests.swift::testCargaOk
       2. n/a-manual — <por qué este criterio no es mecanizable>
     Mismo mecanismo que el `Detector:` de las lecciones: «verificado» no es una
     frase en el informe del run, es un test que falla si dejas de cumplirlo.
     Ojo a los criterios NEGATIVOS ("X NO ocurre"): son los que más acaban
     dados por buenos con un grep que encuentra cero y no impide nada. -->
1.
2.

## Fuera de scope
- <Lo que NO entra, explícito. Esta prosa orienta, pero NO amplía `scope: |`.>

## Notas técnicas (opcional)
<Pistas, no órdenes: patrón a seguir, archivo de referencia, gotchas.>

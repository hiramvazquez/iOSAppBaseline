# Corpus de prosa AJENA para los checks del ledger

> El fixture BUENO es el que importa. Es el guard de falsos positivos de los dos
> detectores que leen prosa (`check-version-claims.sh`, `check-finding-refs.sh`),
> y existe por una lección concreta y cara.

`check-version-claims.sh` se validó contra el ledger del template: 38 entradas,
disparó en 1, y era la defectuosa. Parecía cirugía. El primer adoptante lo corrió
contra el suyo —61 entradas, prosa española densa, historias y criterios
numerados— y disparó 3 veces con **2 falsos positivos: 67%**, muy por encima del
10% que el propio detector cita como criterio de diseño.

Las dos causas eran invisibles desde dentro:

- `<palabra> <número>` casa sin parar en prosa española real: *criterio 6*,
  *la 0006*, *Los 3 únicos casts*, *nivel 4*.
- `tiene` estaba en la lista de verbos de incapacidad, y en español **"no tiene"
  es CARECER**, no "no soporta": *no tiene test*, *no tiene alternativa*.

De ahí la regla que este directorio mecaniza:

> **"Contra el artefacto real" incluye el artefacto real de OTRO.** Un detector
> que lee prosa se valida contra prosa que no escribiste tú. Quien escribe el
> detector escribe, sin querer, el corpus que lo aprueba.

## Los dos archivos

| Archivo | Qué es | Qué debe pasar |
|---|---|---|
| `ledger-bueno.jsonl` | prosa real de un adoptante, densa en números y en negaciones que NO son de soporte | **cero** hallazgos |
| `ledger-malo.jsonl` | una afirmación de no-existencia por cada forma que el detector caza | dispara en **todas** |

Las entradas marcadas `[adoptante]` son texto REAL, copiado literal del informe
del proyecto que las produjo. No las reescribas para que "queden mejor": su valor
está justamente en no haberlas escrito nosotros.

Al añadir una forma nueva al detector, añade su caso a `ledger-malo.jsonl`; al
arreglar un falso positivo, añade el texto que lo produjo a `ledger-bueno.jsonl`.
Los fija `tools/tests/test_finding_refs.sh`.

## El caso que va en el corpus MALO aunque parezca del bueno

La fila **f-malo-citada-como-ejemplo** del corpus malo es un hallazgo que **cita**
una afirmación de versión como ejemplo (*el informe afirmaba "muter 16 no parsea typed throws"*). Se propuso
como caso del corpus bueno —citar ≠ afirmar— invocando dos precedentes reales de
este harness: el git-guard no se dispara con `grep "git commit --no-verify" doc.md`,
y la matriz de Bash desnuda las cadenas entrecomilladas antes de analizar.

**Va en el malo, y el porqué es la parte que hay que conservar.** Esos dos
precedentes se apoyan en una gramática EXTERNA y autoritativa: el shell no ejecuta
lo que va entre comillas, y quien lo dice no es nuestro criterio sino el parser de
bash. En prosa no existe esa gramática. Las comillas son una convención de estilo,
así que exentar lo entrecomillado no sería leer mejor: sería **regalar una primitiva
de evasión** — envuelve la afirmación en comillas y pasa. Un detector evadible con
un truco de formato enseña el truco (ley del 10%, §14.2).

Y hay una razón más fuerte, empírica: quien encontró el caso lo resolvió **citando
la fuente**, no pidiendo la excepción. Le costó una URL. Eso es el detector
funcionando, no molestando — una afirmación de versión que aparece en el ledger sin
adjudicar sigue siendo una afirmación sin adjudicar, la enmarque quien la enmarque.

La regla general que deja, y vale más allá de aquí:

> **"Texto ≠ sintaxis" solo se puede mecanizar cuando existe un parser que lo
> dictamine.** Sin esa gramática externa, la misma distinción se convierte en una
> convención que el evaluado controla — y un gate cuyo criterio controla el evaluado
> no es un gate.

*(Nota de escribir esto: el párrafo de arriba nombraba la fila entre acentos graves y
`check-finding-refs` lo cazó al instante — un id que no está en el ledger. Tercera vez en
un día que un detector se dispara con el texto que lo explica. Se quitaron los acentos, que
es lo que su propio mensaje recomienda: la fila de un fixture no es un hallazgo, y citarla
como si lo fuera era el error. Exentar este archivo habría sido justo lo contrario de lo
que dice el párrafo.)*

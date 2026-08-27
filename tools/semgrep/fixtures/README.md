# `tools/semgrep/fixtures/` — el corpus contra el que se prueban las reglas

Dos archivos por lenguaje y una regla de oro:

- **`*-malo.*`** contiene, una por una, las formas que cada regla DEBE cazar.
- **`*-bueno.*`** contiene las formas seguras que se le parecen y que la regla
  NO puede tocar. Este es el importante: es el guard de falsos positivos del
  nivel 2 entero.

Los verifica `tools/tests/test_semgrep_rules.sh` corriendo semgrep de verdad
contra ambos. Existen porque una regla se pasó de lista durante semanas
(`swift-force-cast` marcaba el `as?` seguro igual que el `as!` peligroso, porque
el parser de Swift los normaliza al mismo nodo) y lo único que había era un
comentario diciendo que las reglas «se ejecutaron contra fixtures reales antes
de commitearse». Una comprobación manual hecha una vez no es un detector.

Al añadir una regla: añade su caso malo Y su caso bueno en el mismo commit.
Si no se te ocurre ninguna forma segura parecida a la que cazas, mira más
fuerte — casi siempre existe, y es la que va a bloquear a alguien.

> Estos archivos están en `.semgrepignore`: son código escrito para ser
> detectado, así que no pueden contar en el scan normal ni inflar el trinquete.
> Se escanean únicamente desde su test, que monta un sandbox sin ese ignore.

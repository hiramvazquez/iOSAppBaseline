# Decisiones de arquitectura (ADRs)

> Una decisión reusable = un archivo de **una página**. Más ligero que un PRD; para cuando eliges
> un approach que afectará a otros (no es una feature, es un "cómo lo hacemos de ahora en más").

## Cuándo escribir un ADR

- Eliges entre 2+ approaches con trade-offs (caché, navegación, estrategia de errores, etc.).
- Rompes o cambias una regla de `AGENTS.md` con justificación.
- Una convención nueva que el equipo seguirá.

## Formato (`NNNN-titulo.md`)

```
# ADR NNNN — <título>
Fecha · Status: [Propuesto | Aceptado | Reemplazado por NNNN]

## Contexto
[El problema y las fuerzas en juego.]

## Decisión
[Lo que decidimos hacer.]

## Alternativas consideradas
[Qué más evaluamos y por qué no.]

## Consecuencias
[Lo que ganamos, lo que sacrificamos, qué se vuelve más difícil.]
```

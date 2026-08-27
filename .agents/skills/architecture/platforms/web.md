# Arquitectura — específico Web

> Rellena con las decisiones reales de tu app web. Mi opinión por defecto abajo.

## Patrón de componente
<!-- FILL -->
<!-- OPINIÓN: Componente de presentación (tonto) + hook/container (estado) + service (lógica/datos).
     La lógica de negocio NO vive en el componente. Estado de servidor vs cliente explícito
     (ej. React Query/SWR para servidor, store local para cliente). -->

## Routing / data-fetching
<!-- FILL -->
<!-- OPINIÓN: routing del framework (file-based si aplica); fetch en el borde server cuando se pueda. -->

## DI / composición
<!-- FILL -->
<!-- OPINIÓN: inyección por props/context; evita singletons globales mutables. -->

## Estado / carga / error
<!-- FILL -->
<!-- OPINIÓN: estados loading/empty/error/content explícitos; boundary de error por ruta. -->

## Theming / tokens
<!-- FILL -->
<!-- OPINIÓN: design tokens vía CSS vars / theme; nada de valores mágicos en componentes. -->

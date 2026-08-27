# Arquitectura — específico Android

> Rellena con las decisiones reales de tu app Android. Mi opinión por defecto abajo.

## Patrón de pantalla
<!-- FILL -->
<!-- OPINIÓN: Composable + ViewModel + UseCase. UI declarativa, ViewModel expone UiState
     inmutable, UseCase tiene la regla de negocio pura y testeable. MVI si el flujo es complejo. -->

## Navegación
<!-- FILL -->
<!-- OPINIÓN: Navigation Compose con un grafo central; las pantallas emiten eventos de navegación,
     no construyen destinos a mano. -->

## DI
<!-- FILL -->
<!-- OPINIÓN: Hilt (o Koin) con scopes claros; nada de service locator global en la lógica. -->

## Estado / carga / error
<!-- FILL -->
<!-- OPINIÓN: sealed UiState (Loading/Empty/Content/Error) colectado con un contenedor común. -->

## Theming
<!-- FILL -->
<!-- OPINIÓN: tokens en el theme (MaterialTheme/design tokens); cero colores hardcoded en Composables. -->

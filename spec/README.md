# spec/ — Contexto de implementación

Documentación de apoyo para los agentes que implementan el consumidor de eventos, la API y el
agente conversacional **contra el esquema de este repositorio**.

## Orden de lectura sugerido

1. [`01-arquitectura.md`](01-arquitectura.md) — qué se construye y cómo encaja todo.
2. [`02-modelo-de-datos.md`](02-modelo-de-datos.md) — el esquema completo.
3. [`03-flujo-eventos.md`](03-flujo-eventos.md) — qué hacer con cada evento.
4. [`04-mapeo-contrato.md`](04-mapeo-contrato.md) — contrato (eventos/API) ↔ tablas.
5. [`05-agente-extensiones.md`](05-agente-extensiones.md) — estado de pieza y reparación.
6. [`06-reglas-e-invariantes.md`](06-reglas-e-invariantes.md) — reglas que no se pueden romper.
7. [`07-migraciones-y-dev-local.md`](07-migraciones-y-dev-local.md) — cómo trabajar el esquema.
8. [`08-preguntas-abiertas.md`](08-preguntas-abiertas.md) — decisiones y pendientes.

## Principio rector

Este repositorio define **el contrato de datos interno**. Consumidor, API y agente deben
escribir y leer **únicamente** a través de estas tablas y vistas; cualquier necesidad nueva se
resuelve con una migración aquí, no con lógica ad-hoc en cada servicio.

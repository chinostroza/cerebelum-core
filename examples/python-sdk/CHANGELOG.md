# Changelog - Cerebelum Python SDK

Todos los cambios importantes del SDK serán documentados aquí.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/).

---

## [1.2.0] - 2025-11-20

### 🎉 Añadido

- **Sintaxis Paralela con Listas**: `step >> [a, b, c] >> next`
  - Ejecución paralela explícita y clara
  - Clase `ParallelStepGroup` para representar grupos paralelos
  - Ver `03_parallel_execution.py` para ejemplos

- **Tutorial Completo Paso a Paso**
  - 5 tutoriales progresivos (01-05)
  - De principiante a intermedio en 40 minutos
  - Cada tutorial construye sobre el anterior

- **Ejemplos Avanzados**
  - Carpeta `advanced/` con ejemplos avanzados
  - Comparación LOCAL vs DISTRIBUIDO
  - Patrones avanzados de paralelismo

### ✨ Mejorado

- **Auto-Wrapping de Return Values**
  - `return value` → automáticamente envuelto en `{"ok": value}`
  - Ya no necesitas escribir `{"ok": ...}` manualmente
  - ~40% menos código boilerplate
  - Ver `04_error_handling.py` para ejemplos

- **Auto-Wrapping de Excepciones**
  - `raise ValueError("error")` → automáticamente convertido a `{"error": "error"}`
  - Ya no necesitas `try/catch` manual
  - Código más Pythonic y limpio

- **Validación Temprana de Dependencias**
  - Warnings en tiempo de definición (no runtime)
  - Sugerencias automáticas de typos
  - Mejor experiencia de desarrollo

- **README Tutorial**
  - Guía completa paso a paso
  - Tabla de contenidos con enlaces
  - Tips y troubleshooting
  - Flujo de aprendizaje recomendado

### 📁 Reorganizado

- Tutoriales renombrados: `01_*.py`, `02_*.py`, etc.
- Ejemplos avanzados movidos a `advanced/`
- Documentación técnica movida a `docs/`
- Estructura más clara y ordenada

### 🔧 Técnico

- Wrapper automático en decorador `@step`
- Clase `ParallelStepGroup` en `composition.py`
- Actualizado `WorkflowBuilder.timeline()` para procesar grupos paralelos
- Exportado `ParallelStepGroup` en API pública

**Documentación Detallada:** Ver [`docs/IMPROVEMENTS.md`](./docs/IMPROVEMENTS.md)

---

## [1.1.0] - 2025-11-19

### 🎉 Añadido

- **Fase 6: Error Handling**
  - Jerarquía de excepciones custom (DSLError, StepDefinitionError, etc.)
  - Mejores mensajes de error
  - Tests completos

- **Modo LOCAL de Ejecución**
  - Ejecuta workflows sin necesitar Core
  - Perfecto para desarrollo y testing
  - `DSLLocalExecutor` implementado

### ✨ Mejorado

- Mejor propagación de errores
- Context inmutable (dataclass frozen)
- Validación de workflow más robusta

---

## [1.0.0] - 2025-11-15

### 🎉 Lanzamiento Inicial

- **Fase 1-5 Completas**
  - Decoradores `@step` y `@workflow`
  - Inyección automática de dependencias
  - Composición con operador `>>`
  - Validación de workflows
  - Serialización a protobuf
  - Ejecución local

- **API Declarativa**
  - DSL Pythonic y limpio
  - StepRegistry y WorkflowRegistry
  - Context propagation
  - Dependency analyzer

- **Ejemplos Básicos**
  - Workflow de usuario onboarding
  - Ejemplos de composición
  - Tests de smoke

---

## Tipos de Cambios

- **🎉 Añadido**: Nueva funcionalidad
- **✨ Mejorado**: Cambios en funcionalidad existente
- **🔧 Técnico**: Cambios técnicos internos
- **🐛 Corregido**: Corrección de bugs
- **⚠️ Deprecado**: Funcionalidad que será removida
- **🗑️ Removido**: Funcionalidad removida
- **🔒 Seguridad**: Correcciones de seguridad
- **📁 Reorganizado**: Cambios en estructura de archivos

---

[1.2.0]: https://github.com/cerebelum/python-sdk/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/cerebelum/python-sdk/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/cerebelum/python-sdk/releases/tag/v1.0.0

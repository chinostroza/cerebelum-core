#!/usr/bin/env python3
"""
TUTORIAL 01: Hello World - Tu Primer Workflow

¿Qué aprenderás?
✅ Decorador @step - define pasos del workflow
✅ Decorador @workflow - compone los pasos
✅ Context - información del paso actual
✅ Ejecución básica - await workflow.execute()

Tiempo: 3 minutos
Dificultad: 🟢 Principiante
"""

import asyncio
from cerebelum import step, workflow, Context


# =============================================================================
# PASO 1: Define un Step (paso del workflow)
# =============================================================================

@step
async def greet(context: Context, inputs: dict):
    """
    Un step es una función async decorada con @step.

    Parámetros:
    - context: Información del workflow (execution_id, step_name, etc.)
    - inputs: Los datos de entrada del workflow

    Return:
    - Cualquier valor (será auto-wrapeado en {"ok": valor})
    """
    name = inputs.get("name", "World")
    message = f"Hello, {name}!"

    print(f"[{context.step_name}] {message}")

    return message  # ✅ Auto-wrapping: se convierte en {"ok": "Hello, ..."}


# =============================================================================
# PASO 2: Define un Workflow
# =============================================================================

@workflow
def hello_workflow(wf):
    """
    Un workflow define el orden de ejecución de los steps.

    wf.timeline() acepta:
    - Un solo step: wf.timeline(step1)
    - Composición: wf.timeline(step1 >> step2 >> step3)
    """
    wf.timeline(greet)  # Workflow de un solo paso


# =============================================================================
# PASO 3: Ejecuta el Workflow
# =============================================================================

async def main():
    print("=" * 60)
    print("TUTORIAL 01: Hello World")
    print("=" * 60)
    print()

    # Ejecutar el workflow con datos de entrada
    result = await hello_workflow.execute({
        "name": "Alice"
    })

    print()
    print("=" * 60)
    print("Resultado:")
    print(f"  Output: {result.output}")
    print(f"  Status: {result.status}")
    print(f"  Execution ID: {result.execution_id}")
    print()

    # 🎯 Puntos Clave:
    print("🎯 Puntos Clave:")
    print("  1. @step convierte una función en un paso del workflow")
    print("  2. @workflow define cómo se conectan los pasos")
    print("  3. execute() ejecuta el workflow con los inputs")
    print("  4. No necesitas Core ni Workers (modo LOCAL)")
    print()


if __name__ == "__main__":
    asyncio.run(main())


# =============================================================================
# 🎓 LO QUE APRENDISTE
# =============================================================================
#
# ✅ @step: Decora funciones async para crear steps
# ✅ context: Primer parámetro, info del workflow
# ✅ inputs: Segundo parámetro, datos de entrada
# ✅ @workflow: Define el flujo de ejecución
# ✅ execute(): Ejecuta el workflow
# ✅ Auto-wrapping: No necesitas {"ok": ...} manual
#
# 📚 PRÓXIMO: 02_dependencies.py
#    Aprende cómo un step puede depender de otro
#
# =============================================================================

#!/usr/bin/env python3
"""
TUTORIAL 03: Parallel Execution - Ejecutar Steps en Paralelo

¿Qué aprenderás?
✅ Sintaxis de lista [step_a, step_b] para paralelismo
✅ Cuándo usar ejecución paralela
✅ Combinar resultados de steps paralelos
✅ Visualizar el flujo de ejecución

Tiempo: 7 minutos
Dificultad: 🟡 Intermedio

Requisito: Haber completado 01 y 02
"""

import asyncio
from cerebelum import step, workflow, Context


# =============================================================================
# ESCENARIO: Calcular Estadísticas de un Número
# =============================================================================
#
# Input: Un número
# Output: Varias estadísticas calculadas EN PARALELO
#
# Flujo:
#   1. get_number (obtiene el número)
#   2. [calculate_square, calculate_cube, calculate_factorial] (PARALELO!)
#   3. combine_results (combina los resultados)
#
# =============================================================================


@step
async def get_number(context: Context, inputs: dict):
    """Step 1: Obtiene el número a procesar."""
    number = inputs.get("number", 5)
    print(f"[{context.step_name}] Input number: {number}")
    return {"number": number}


@step
async def calculate_square(context: Context, get_number: dict):
    """
    Step 2a: Calcula el cuadrado.

    🔥 Este step se ejecutará EN PARALELO con
    calculate_cube y calculate_factorial.
    """
    number = get_number["number"]
    result = number ** 2
    print(f"  [{context.step_name}] {number}² = {result} (PARALLEL)")
    return {"square": result}


@step
async def calculate_cube(context: Context, get_number: dict):
    """
    Step 2b: Calcula el cubo.

    🔥 Se ejecuta EN PARALELO con los otros cálculos.
    """
    number = get_number["number"]
    result = number ** 3
    print(f"  [{context.step_name}] {number}³ = {result} (PARALLEL)")
    return {"cube": result}


@step
async def calculate_factorial(context: Context, get_number: dict):
    """
    Step 2c: Calcula el factorial.

    🔥 Se ejecuta EN PARALELO con los otros cálculos.
    """
    number = get_number["number"]

    # Calcular factorial
    factorial = 1
    for i in range(1, number + 1):
        factorial *= i

    print(f"  [{context.step_name}] {number}! = {factorial} (PARALLEL)")
    return {"factorial": factorial}


@step
async def combine_results(
    context: Context,
    calculate_square: dict,
    calculate_cube: dict,
    calculate_factorial: dict
):
    """
    Step 3: Combina los resultados de los steps paralelos.

    ⚠️ NOTA: Este step espera a que TODOS los steps paralelos terminen
    antes de ejecutarse.

    Recibe los resultados de los 3 cálculos como parámetros.
    """
    print(f"[{context.step_name}] Combining results...")

    summary = {
        "square": calculate_square["square"],
        "cube": calculate_cube["cube"],
        "factorial": calculate_factorial["factorial"]
    }

    print(f"  ✓ Combined: {summary}")
    return summary


# =============================================================================
# WORKFLOW: Usando Sintaxis de Lista para Paralelismo
# =============================================================================

@workflow
def parallel_calculation_workflow(wf):
    """
    Workflow con ejecución paralela explícita.

    🔥 SINTAXIS CLAVE: [step_a, step_b, step_c]

    Esto significa: ejecuta step_a, step_b y step_c EN PARALELO.

    Timeline:
    1. get_number (secuencial)
    2. [calculate_square, calculate_cube, calculate_factorial] (PARALELO)
    3. combine_results (secuencial - espera a todos)
    """
    wf.timeline(
        get_number >>
        [calculate_square, calculate_cube, calculate_factorial] >>  # 🔥 PARALELO!
        combine_results
    )


# =============================================================================
# DEMOSTRACIÓN
# =============================================================================

async def demo_sequential():
    """Demuestra ejecución SECUENCIAL (sin listas)."""
    print("=" * 70)
    print("DEMO: Ejecución SECUENCIAL (sin sintaxis de lista)")
    print("=" * 70)
    print()
    print("Si escribiéramos:")
    print("  wf.timeline(get_number >> square >> cube >> factorial >> combine)")
    print()
    print("Los steps se ejecutarían UNO POR UNO:")
    print("  1. get_number")
    print("  2. square (espera a 1)")
    print("  3. cube (espera a 2)")
    print("  4. factorial (espera a 3)")
    print("  5. combine (espera a 4)")
    print()
    print("⏱️  Tiempo total: T1 + T2 + T3 + T4 + T5")
    print()


async def demo_parallel():
    """Demuestra ejecución PARALELA (con listas)."""
    print("=" * 70)
    print("DEMO: Ejecución PARALELA (con sintaxis de lista)")
    print("=" * 70)
    print()
    print("Con la sintaxis actual:")
    print("  wf.timeline(get_number >> [square, cube, factorial] >> combine)")
    print()
    print("Los steps se ejecutan EN PARALELO:")
    print("  1. get_number")
    print("  2. [square, cube, factorial] (todos al mismo tiempo)")
    print("  3. combine (espera a que 2 termine)")
    print()
    print("⏱️  Tiempo total: T1 + max(T2a, T2b, T2c) + T3")
    print("                    ^^^^^^^^^^^^^^^^^^^^")
    print("                    Solo el más lento!")
    print()


async def main():
    await demo_sequential()
    await demo_parallel()

    print("=" * 70)
    print("EJECUTANDO WORKFLOW")
    print("=" * 70)
    print()

    result = await parallel_calculation_workflow.execute({
        "number": 5
    })

    print()
    print("=" * 70)
    print("Resultado:")
    print(f"  Square: {result.output['ok']['square']}")
    print(f"  Cube: {result.output['ok']['cube']}")
    print(f"  Factorial: {result.output['ok']['factorial']}")
    print()


if __name__ == "__main__":
    asyncio.run(main())


# =============================================================================
# 🎓 LO QUE APRENDISTE
# =============================================================================
#
# ✅ Sintaxis de lista: [step_a, step_b, step_c]
#    - Steps dentro de [] se ejecutan EN PARALELO
#    - Útil cuando los steps no dependen entre sí
#
# ✅ Cuándo usar paralelismo:
#    - Múltiples cálculos independientes
#    - Llamadas a APIs externas
#    - Procesar múltiples items
#    - Cualquier cosa que NO dependa de otros steps
#
# ✅ Combinar resultados:
#    - El step siguiente recibe TODOS los resultados
#    - Declara un parámetro por cada step paralelo
#
# ✅ Ventajas:
#    - ⚡ Más rápido (menos tiempo total)
#    - 📊 Mejor uso de recursos
#    - 🔍 Intención explícita (código auto-documentado)
#
# ⚠️ IMPORTANTE:
#    - Steps paralelos NO deben depender entre sí
#    - Todos deben depender del mismo step anterior
#    - El step siguiente espera a que TODOS terminen
#
# 📚 PRÓXIMO: 04_error_handling.py
#    Aprende a manejar errores y excepciones
#
# =============================================================================

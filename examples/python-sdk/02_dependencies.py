#!/usr/bin/env python3
"""
TUTORIAL 02: Dependencies - Steps que Dependen de Otros

¿Qué aprenderás?
✅ Dependencias entre steps
✅ Inyección automática de resultados
✅ Composición con operador >>
✅ Flujo de datos entre steps

Tiempo: 5 minutos
Dificultad: 🟢 Principiante

Requisito: Haber completado 01_hello_world.py
"""

import asyncio
from cerebelum import step, workflow, Context


# =============================================================================
# PASO 1: Define Steps con Dependencias
# =============================================================================

@step
async def fetch_user(context: Context, inputs: dict):
    """
    Step 1: Obtiene datos del usuario.

    Return: Información del usuario
    """
    user_id = inputs.get("user_id")
    print(f"[{context.step_name}] Fetching user {user_id}...")

    # Simular consulta a base de datos
    user = {
        "id": user_id,
        "name": "Alice",
        "age": 30,
        "premium": True
    }

    print(f"  ✓ User found: {user['name']}")
    return user


@step
async def check_eligibility(context: Context, fetch_user: dict):
    """
    Step 2: Verifica elegibilidad del usuario.

    ⚠️ NOTA: El parámetro 'fetch_user' hace que este step
    dependa del step 'fetch_user'.

    El nombre del parámetro DEBE coincidir con el nombre del step.

    Parameters:
    - context: Info del workflow
    - fetch_user: El OUTPUT del step fetch_user (inyectado automáticamente)
    """
    print(f"[{context.step_name}] Checking eligibility...")

    user = fetch_user  # Recibe el resultado del step anterior
    is_eligible = user["age"] >= 18 and user["premium"]

    print(f"  User: {user['name']}")
    print(f"  Age: {user['age']} (>= 18: {user['age'] >= 18})")
    print(f"  Premium: {user['premium']}")
    print(f"  ✓ Eligible: {is_eligible}")

    return {
        "user": user,
        "eligible": is_eligible
    }


@step
async def send_notification(context: Context, check_eligibility: dict):
    """
    Step 3: Envía notificación al usuario.

    Depende de: check_eligibility
    """
    print(f"[{context.step_name}] Sending notification...")

    eligibility = check_eligibility
    user = eligibility["user"]
    is_eligible = eligibility["eligible"]

    if is_eligible:
        message = f"Congratulations {user['name']}! You are eligible."
        print(f"  ✉️  Sent: {message}")
    else:
        message = f"Sorry {user['name']}, you are not eligible."
        print(f"  ✉️  Sent: {message}")

    return {"message": message, "sent": True}


# =============================================================================
# PASO 2: Componer el Workflow
# =============================================================================

@workflow
def user_eligibility_workflow(wf):
    """
    Workflow con 3 steps en secuencia.

    El operador >> conecta steps:
    - fetch_user >> check_eligibility significa:
      "ejecuta fetch_user, luego check_eligibility"

    Las dependencias se resuelven automáticamente por los nombres
    de los parámetros.
    """
    wf.timeline(
        fetch_user >>           # Step 1
        check_eligibility >>    # Step 2 (depende de fetch_user)
        send_notification       # Step 3 (depende de check_eligibility)
    )


# =============================================================================
# PASO 3: Ejecutar
# =============================================================================

async def main():
    print("=" * 70)
    print("TUTORIAL 02: Dependencies - Steps que Dependen de Otros")
    print("=" * 70)
    print()

    print("Flujo del workflow:")
    print("  fetch_user → check_eligibility → send_notification")
    print()
    print("Cómo funcionan las dependencias:")
    print("  1. fetch_user devuelve un dict con user data")
    print("  2. check_eligibility RECIBE ese dict automáticamente")
    print("     (porque tiene parámetro 'fetch_user: dict')")
    print("  3. send_notification recibe el resultado de check_eligibility")
    print()
    print("=" * 70)
    print()

    # Ejecutar
    result = await user_eligibility_workflow.execute({
        "user_id": 123
    })

    print()
    print("=" * 70)
    print("Resultado Final:")
    print(f"  {result.output}")
    print()


if __name__ == "__main__":
    asyncio.run(main())


# =============================================================================
# 🎓 LO QUE APRENDISTE
# =============================================================================
#
# ✅ Dependencias: Declaras dependencias con nombres de parámetros
#    - async def my_step(context, other_step: dict)
#    - 'other_step' debe coincidir con el nombre del step
#
# ✅ Inyección automática: Cerebelum inyecta los resultados
#    - No necesitas pasar datos manualmente
#    - Solo declara el parámetro y listo
#
# ✅ Operador >>: Compone steps en secuencia
#    - step1 >> step2 >> step3
#    - Orden de ejecución de izquierda a derecha
#
# ✅ Flujo de datos: Los datos fluyen automáticamente
#    - Output de step1 → Input de step2
#    - Sin código de pegamento (glue code)
#
# 🔍 OBSERVA: El orden en timeline() puede ser diferente al orden
# de ejecución real. Las dependencias determinan el orden real.
#
# 📚 PRÓXIMO: 03_parallel_execution.py
#    Aprende a ejecutar steps en paralelo
#
# =============================================================================

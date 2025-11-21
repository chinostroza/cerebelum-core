#!/usr/bin/env python3
"""
TUTORIAL 04: Error Handling - Manejo de Errores y Excepciones

¿Qué aprenderás?
✅ Auto-wrapping de excepciones
✅ Usar excepciones nativas de Python (raise)
✅ No necesitas return {"error": ...}
✅ Código más limpio y Pythonic

Tiempo: 8 minutos
Dificultad: 🟡 Intermedio

Requisito: Haber completado 01, 02 y 03
"""

import asyncio
from cerebelum import step, workflow, Context


# =============================================================================
# ❌ ANTES (API Vieja): Manual Error Wrapping
# =============================================================================
#
# @step
# async def validate_age(context, inputs):
#     try:
#         age = inputs["age"]
#         if age < 18:
#             return {"error": "too_young"}  # ❌ Manual error wrapping
#         return {"ok": {"age": age}}  # ❌ Manual success wrapping
#     except Exception as e:
#         return {"error": str(e)}  # ❌ Manual exception handling
#
# Problemas:
# - Mucho boilerplate
# - Fácil olvidar el wrapping
# - No es Pythonic
#
# =============================================================================


# =============================================================================
# ✅ AHORA (DSL v1.2): Auto-Wrapping
# =============================================================================

@step
async def validate_age(context: Context, inputs: dict):
    """
    Valida la edad del usuario.

    ✅ NUEVO: Solo haz raise de excepciones normales de Python.
    El wrapper automático las convertirá en {"error": "mensaje"}.
    """
    age = inputs.get("age")

    if age is None:
        raise ValueError("age is required")  # ✅ Excepción nativa

    if age < 0:
        raise ValueError("age cannot be negative")

    if age < 18:
        raise ValueError("must be 18 or older")  # ✅ Pythonic!

    print(f"[{context.step_name}] Age {age} is valid")
    return {"age": age, "valid": True}  # ✅ Auto-wrapped a {"ok": {...}}


@step
async def fetch_user_data(context: Context, inputs: dict):
    """
    Obtiene datos del usuario.

    Puede fallar si user_id no existe.
    """
    user_id = inputs.get("user_id")

    if not user_id:
        raise ValueError("user_id is required")

    # Simular que algunos IDs no existen
    if user_id == 999:
        raise ValueError(f"user {user_id} not found")  # ✅ Error claro

    print(f"[{context.step_name}] Fetching user {user_id}...")
    return {
        "user_id": user_id,
        "name": "Alice",
        "email": "alice@example.com"
    }


@step
async def send_welcome_email(context: Context, validate_age: dict, fetch_user_data: dict):
    """
    Envía email de bienvenida.

    Solo se ejecuta si validate_age y fetch_user_data tienen éxito.
    """
    age_info = validate_age
    user = fetch_user_data

    print(f"[{context.step_name}] Sending email to {user['email']}...")
    print(f"  User: {user['name']}")
    print(f"  Age: {age_info['age']}")
    print(f"  ✓ Email sent!")

    return {"email_sent": True, "recipient": user["email"]}


# =============================================================================
# WORKFLOWS DE PRUEBA
# =============================================================================

@workflow
def user_onboarding_workflow(wf):
    """Workflow de onboarding que valida edad y crea usuario."""
    wf.timeline(
        [validate_age, fetch_user_data] >>  # Paralelo
        send_welcome_email
    )


# =============================================================================
# DEMOS
# =============================================================================

async def demo_success():
    """Demo: Todo sale bien."""
    print("=" * 70)
    print("DEMO 1: Caso de Éxito")
    print("=" * 70)
    print()

    try:
        result = await user_onboarding_workflow.execute({
            "user_id": 123,
            "age": 25
        })

        print()
        print("✅ Workflow completado")
        print(f"   Output: {result.output}")
        print()

    except Exception as e:
        print(f"❌ Error: {e}")
        print()


async def demo_validation_error():
    """Demo: Error de validación (edad menor a 18)."""
    print("=" * 70)
    print("DEMO 2: Error de Validación (edad < 18)")
    print("=" * 70)
    print()

    try:
        result = await user_onboarding_workflow.execute({
            "user_id": 123,
            "age": 15  # ❌ Menor a 18
        })

        print()
        print(f"Result: {result.output}")
        print()

    except Exception as e:
        print()
        print(f"✅ Excepción capturada (esperado):")
        print(f"   {type(e).__name__}: {e}")
        print()
        print("   ℹ️  La excepción 'must be 18 or older' fue:")
        print("      1. Lanzada por validate_age()")
        print("      2. Auto-wrapeada a {\"error\": \"must be 18 or older\"}")
        print("      3. Propagada como excepción del workflow")
        print()


async def demo_missing_data():
    """Demo: Datos faltantes."""
    print("=" * 70)
    print("DEMO 3: Datos Faltantes (no user_id)")
    print("=" * 70)
    print()

    try:
        result = await user_onboarding_workflow.execute({
            "age": 25
            # ❌ Falta user_id
        })

        print()
        print(f"Result: {result.output}")
        print()

    except Exception as e:
        print()
        print(f"✅ Excepción capturada (esperado):")
        print(f"   {type(e).__name__}: {e}")
        print()


async def demo_user_not_found():
    """Demo: Usuario no existe."""
    print("=" * 70)
    print("DEMO 4: Usuario No Encontrado (ID=999)")
    print("=" * 70)
    print()

    try:
        result = await user_onboarding_workflow.execute({
            "user_id": 999,  # ❌ No existe
            "age": 25
        })

        print()
        print(f"Result: {result.output}")
        print()

    except Exception as e:
        print()
        print(f"✅ Excepción capturada (esperado):")
        print(f"   {type(e).__name__}: {e}")
        print()


async def main():
    print()
    print("=" * 70)
    print("TUTORIAL 04: Error Handling")
    print("=" * 70)
    print()
    print("DSL v1.2 Auto-Wrapping:")
    print("  • return value → {\"ok\": value}")
    print("  • raise Exception → {\"error\": message}")
    print()
    print("Beneficios:")
    print("  ✅ Código más limpio (sin boilerplate)")
    print("  ✅ Excepciones nativas de Python")
    print("  ✅ Pythonic y natural")
    print("  ✅ Menos errores (no olvidas el wrapping)")
    print()

    await demo_success()
    await demo_validation_error()
    await demo_missing_data()
    await demo_user_not_found()

    print("=" * 70)
    print("RESUMEN")
    print("=" * 70)
    print()
    print("✅ Viste 4 casos:")
    print("   1. Éxito - todo funciona")
    print("   2. Validación - edad inválida")
    print("   3. Datos faltantes - user_id requerido")
    print("   4. Usuario no encontrado - ID inexistente")
    print()
    print("🔑 Punto Clave:")
    print("   Solo usa 'raise' para errores.")
    print("   El DSL automáticamente:")
    print("   • Captura la excepción")
    print("   • La convierte en {\"error\": mensaje}")
    print("   • Detiene el workflow")
    print()


if __name__ == "__main__":
    asyncio.run(main())


# =============================================================================
# 🎓 LO QUE APRENDISTE
# =============================================================================
#
# ✅ Auto-wrapping de excepciones:
#    - raise ValueError("error") → {"error": "error"}
#    - No necesitas try/catch manual
#    - No necesitas return {"error": ...}
#
# ✅ Excepciones nativas de Python:
#    - ValueError, TypeError, KeyError, etc.
#    - Pythonic y natural
#    - Mejor experiencia de desarrollo
#
# ✅ Propagación de errores:
#    - Si un step falla, el workflow se detiene
#    - La excepción se propaga al caller
#    - Otros steps no se ejecutan
#
# ✅ Código más limpio:
#    - ~40% menos líneas de código
#    - Enfoque en lógica de negocio
#    - Sin boilerplate de wrapping
#
# 🔍 COMPARACIÓN:
#    ANTES: 10 líneas (con try/catch y wrapping manual)
#    AHORA: 6 líneas (solo lógica y raise)
#
# 📚 PRÓXIMO: 05_complete_example.py
#    Workflow completo de e-commerce con todo lo aprendido
#
# =============================================================================

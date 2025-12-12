#!/usr/bin/env python3
"""
Ejemplo: Onboarding de Atletas - ZEA Sport Platform

Workflow que se ejecuta cuando un atleta se registra.
Valida perfil completo antes de permitir bookings.
"""

import asyncio
from typing import Dict, Any
from cerebelum import (
    WorkflowBuilder,
    DistributedExecutor,
    Worker,
)

# ============================================================================
# STEPS - Usan tus repositorios existentes de FastAPI
# ============================================================================

async def validate_registration(ctx, inputs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Valida que el registro básico esté completo.

    Inputs:
        - user_id: ID del usuario recién registrado
        - email: Email del usuario
    """
    user_id = inputs['user_id']
    email = inputs['email']

    # Aquí usarías tu UserRepository existente
    # from app.repositories.user_repository import UserRepository
    # user_repo = UserRepository()
    # user = await user_repo.get_by_id(user_id)

    print(f"✅ Validando registro de usuario {user_id} ({email})")

    return {
        'user_id': user_id,
        'email': email,
        'registration_valid': True
    }


async def request_profile_completion(ctx, inputs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Solicita al atleta que complete su perfil deportivo.

    En tu app real, esto sería:
    1. Mostrar formulario en UI
    2. Esperar hasta que se complete
    3. O usar approval para que el atleta "apruebe" su perfil
    """
    user_id = inputs['user_id']

    # Opción 1: Approval con timeout (máximo 7 días para completar)
    # Si no completa en 7 días → se auto-rechaza
    approval_result = await ctx.request_approval(
        approval_type="athlete_profile_completion",
        approval_data={
            "user_id": user_id,
            "message": "Complete su perfil deportivo para comenzar a reservar sesiones"
        },
        timeout_ms=7 * 24 * 60 * 60 * 1000  # 7 días
    )

    if approval_result.approved:
        # Atleta completó el perfil
        profile_data = approval_result.data or {}
        return {
            'profile_completed': True,
            'sport': profile_data.get('sport'),
            'position': profile_data.get('position'),
            'objectives': profile_data.get('objectives', []),
            'experience_level': profile_data.get('experience_level'),
            'injury_history': profile_data.get('injury_history'),
            'special_notes': profile_data.get('special_notes'),
        }
    else:
        # Timeout - no completó a tiempo
        return {
            'profile_completed': False,
            'reason': 'timeout'
        }


async def validate_profile_data(ctx, inputs: Dict[str, Any]) -> Dict[str, Any]:
    """Valida que todos los campos obligatorios estén completos."""

    if not inputs['profile_completed']:
        raise Exception("Perfil no completado - atleta no puede hacer bookings")

    # Validar campos obligatorios
    required_fields = ['sport', 'position', 'objectives', 'experience_level']
    missing_fields = [f for f in required_fields if not inputs.get(f)]

    if missing_fields:
        raise Exception(f"Campos obligatorios faltantes: {', '.join(missing_fields)}")

    print(f"✅ Perfil validado correctamente")
    return {
        'validation_passed': True,
        'profile_complete': True
    }


async def enable_booking_capability(ctx, inputs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Habilita al atleta para hacer reservas.

    Actualiza en tu DB: user.can_book = True
    """
    user_id = ctx.execution_id.split('-')[0]  # Ejemplo

    # Aquí usarías tu UserRepository
    # await user_repo.update(user_id, {'can_book': True, 'profile_completed_at': datetime.utcnow()})

    print(f"✅ Atleta {user_id} habilitado para hacer bookings")

    return {
        'can_book': True,
        'enabled_at': 'now'
    }


async def send_welcome_email(ctx, inputs: Dict[str, Any]) -> str:
    """Envía email de bienvenida con próximos pasos."""
    email = inputs.get('email')

    # Aquí usarías tu servicio de email
    # from app.services.email_service import EmailService
    # await EmailService.send_welcome(email, sport=inputs['sport'])

    print(f"📧 Email de bienvenida enviado a {email}")

    return f"Email enviado a {email}"


async def track_onboarding_analytics(ctx, inputs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Guarda métricas para analytics.

    Responde a las preguntas:
    - ¿Cuántos abandonan?
    - ¿En qué paso?
    - ¿Cuánto tiempo tardaron?
    """
    # Aquí guardarías en tu DB de analytics
    # analytics_repo.save({
    #     'event': 'onboarding_completed',
    #     'user_id': inputs['user_id'],
    #     'duration_seconds': ctx.elapsed_seconds,
    #     'completed': inputs['profile_completed']
    # })

    print(f"📊 Analytics guardados - Onboarding completado")

    return {
        'analytics_saved': True
    }


# ============================================================================
# WORKFLOW DEFINITION
# ============================================================================

def build_athlete_onboarding_workflow():
    """
    Workflow de onboarding de atletas.

    Timeline:
    1. Validar registro
    2. Solicitar completar perfil (ESPERA hasta 7 días)
    3. Validar datos del perfil
    4. Habilitar bookings
    5. Enviar email de bienvenida
    6. Guardar analytics
    """
    return (
        WorkflowBuilder("zea_sport.AthleteOnboarding")
        .timeline([
            "validate_registration",
            "request_profile_completion",
            "validate_profile_data",
            "enable_booking_capability",
            "send_welcome_email",
            "track_analytics"
        ])
        .step("validate_registration", validate_registration)
        .step("request_profile_completion", request_profile_completion)
        .step("validate_profile_data", validate_profile_data)
        .step("enable_booking_capability", enable_booking_capability)
        .step("send_welcome_email", send_welcome_email)
        .step("track_analytics", track_onboarding_analytics)
        .build()
    )


# ============================================================================
# EJEMPLO DE USO DESDE FASTAPI
# ============================================================================

async def demo_execution():
    """
    Ejemplo de cómo ejecutar desde tu endpoint FastAPI:

    @app.post("/api/auth/register")
    async def register_user(data: RegisterData):
        # 1. Crear usuario en DB
        user = await user_repo.create(data.email, data.password)

        # 2. Ejecutar workflow de onboarding
        executor = DistributedExecutor(core_url="localhost:9090")
        result = await executor.execute(
            build_athlete_onboarding_workflow(),
            {
                'user_id': user.id,
                'email': user.email
            }
        )

        return {
            'user_id': user.id,
            'onboarding_execution_id': result.execution_id
        }
    """

    # Start worker
    worker = Worker(core_url="localhost:9090", worker_id="zea-sport-worker-1")
    worker_task = asyncio.create_task(worker.run())
    await asyncio.sleep(1)

    # Execute workflow
    executor = DistributedExecutor(core_url="localhost:9090")

    try:
        print("\n" + "="*70)
        print("🏃 EJECUTANDO: Athlete Onboarding Workflow")
        print("="*70 + "\n")

        result = await executor.execute(
            build_athlete_onboarding_workflow(),
            {
                'user_id': 'athlete-123',
                'email': 'juan.perez@email.com'
            }
        )

        print("\n" + "="*70)
        print(f"✅ WORKFLOW COMPLETADO")
        print(f"Execution ID: {result.execution_id}")
        print(f"Output: {result.output}")
        print("="*70 + "\n")

    finally:
        worker_task.cancel()
        try:
            await worker_task
        except asyncio.CancelledError:
            pass


if __name__ == "__main__":
    print("""
    ╔══════════════════════════════════════════════════════════════════╗
    ║         ZEA Sport Platform - Athlete Onboarding Workflow         ║
    ╚══════════════════════════════════════════════════════════════════╝

    Este workflow maneja el onboarding completo de un atleta:

    1. ✅ Valida registro básico
    2. ⏳ Espera hasta 7 días que complete perfil deportivo
    3. ✅ Valida datos obligatorios (deporte, posición, objetivos)
    4. ✅ Habilita capacidad de hacer bookings
    5. 📧 Envía email de bienvenida
    6. 📊 Guarda analytics

    NOTA: En producción, este workflow se ejecutaría desde tu endpoint
    FastAPI POST /api/auth/register

    Para simular la aprobación del perfil:
    - El workflow quedará en estado WAITING_FOR_APPROVAL
    - Usa: cerebelum_cli.py status <execution-id>
    - Usa la API de aprobación para simular que el atleta completó el perfil

    """)

    asyncio.run(demo_execution())

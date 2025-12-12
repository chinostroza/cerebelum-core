#!/usr/bin/env python3
"""
Ejemplo: Finalización de Sesión (Session Completion) - ZEA Sport Platform

Workflow ASÍNCRONO con:
- Registro de tiempo real de trabajo (para pago del coach)
- Evaluación del atleta (timeout 48 horas)
- Evaluación del coach (timeout 7 días)
- Ejecuciones en PARALELO

Este es el ejemplo MÁS AVANZADO que muestra las capacidades de Cerebelum.
"""

import asyncio
from typing import Dict, Any
from datetime import datetime
from cerebelum import (
    WorkflowBuilder,
    DistributedExecutor,
    Worker,
)


# ============================================================================
# STEP 1: Coach registra tiempo real trabajado
# ============================================================================

async def record_actual_session_time(ctx, inputs: Dict[str, Any]) -> Dict[str, Any]:
    """
    El coach registra la hora real de inicio/fin de la sesión.

    Inputs:
        - booking_id: ID del booking
        - actual_start_time: Hora real de inicio (ISO format)
        - actual_end_time: Hora real de fin (ISO format)

    Returns:
        - actual_duration_minutes: Duración en minutos (para cálculo de pago)
    """
    booking_id = inputs['booking_id']
    actual_start = inputs['actual_start_time']
    actual_end = inputs['actual_end_time']

    # Calcular duración real
    # En producción, usarías datetime parsing
    # start_dt = datetime.fromisoformat(actual_start)
    # end_dt = datetime.fromisoformat(actual_end)
    # duration = (end_dt - start_dt).total_seconds() / 60

    # Simulación
    actual_duration_minutes = 90  # 1.5 horas

    # Guardar en DB
    # await booking_repo.update(booking_id, {
    #     'actual_start_time': actual_start,
    #     'actual_end_time': actual_end,
    #     'actual_duration_minutes': actual_duration_minutes,
    #     'status': 'COMPLETED'
    # })

    print(f"✅ Tiempo registrado para booking {booking_id}")
    print(f"   Inicio real: {actual_start}")
    print(f"   Fin real: {actual_end}")
    print(f"   Duración: {actual_duration_minutes} minutos")

    return {
        'booking_id': booking_id,
        'actual_duration_minutes': actual_duration_minutes,
        'time_recorded': True
    }


# ============================================================================
# STEP 2: Solicitar evaluación al atleta (CON TIMEOUT)
# ============================================================================

async def request_athlete_feedback(ctx, inputs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Solicita feedback al atleta con timeout de 48 horas.

    Si el atleta NO responde en 48 horas → auto-completa sin feedback.

    ESTO ES LO IMPORTANTE: Usa approval con timeout!
    """
    booking_id = inputs['booking_id']
    athlete_id = inputs['athlete_id']

    # Enviar email/notificación al atleta
    # await email_service.send_feedback_request(athlete_id, booking_id)
    print(f"📧 Solicitud de evaluación enviada al atleta {athlete_id}")

    # CLAVE: request_approval con timeout de 48 horas
    approval_result = await ctx.request_approval(
        approval_type="athlete_session_feedback",
        approval_data={
            "booking_id": booking_id,
            "athlete_id": athlete_id,
            "questions": {
                "rating": "¿Cómo calificarías esta sesión? (1-5 estrellas)",
                "objectives_met": "¿Se cumplieron tus objetivos?",
                "comments": "Comentarios adicionales"
            }
        },
        timeout_ms=48 * 60 * 60 * 1000  # 48 horas = 172,800,000 ms
    )

    if approval_result.approved:
        # Atleta respondió a tiempo
        feedback = approval_result.data or {}

        # Guardar feedback en DB
        # await feedback_repo.create({
        #     'booking_id': booking_id,
        #     'from_athlete': True,
        #     'rating': feedback.get('rating'),
        #     'objectives_met': feedback.get('objectives_met'),
        #     'comments': feedback.get('comments'),
        #     'submitted_at': datetime.utcnow()
        # })

        print(f"✅ Atleta respondió evaluación")
        print(f"   Rating: {feedback.get('rating')}/5")
        print(f"   Objetivos cumplidos: {feedback.get('objectives_met')}")
        print(f"   Comentarios: {feedback.get('comments')}")

        return {
            'athlete_feedback_received': True,
            'rating': feedback.get('rating'),
            'objectives_met': feedback.get('objectives_met'),
            'comments': feedback.get('comments')
        }
    else:
        # TIMEOUT - Atleta no respondió en 48 horas
        print(f"⏰ Timeout: Atleta no respondió en 48 horas")

        # Guardar en DB que no hubo feedback
        # await feedback_repo.create({
        #     'booking_id': booking_id,
        #     'from_athlete': True,
        #     'status': 'no_response_timeout',
        #     'timeout_at': datetime.utcnow()
        # })

        return {
            'athlete_feedback_received': False,
            'reason': 'timeout_48h'
        }


# ============================================================================
# STEP 3: Solicitar evaluación al coach (CON TIMEOUT)
# ============================================================================

async def request_coach_evaluation(ctx, inputs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Solicita evaluación del atleta al coach con timeout de 7 días.

    Si el coach NO evalúa en 7 días → auto-completa sin evaluación.
    """
    booking_id = inputs['booking_id']
    coach_id = inputs['coach_id']

    # Enviar email/notificación al coach
    # await email_service.send_evaluation_request(coach_id, booking_id)
    print(f"📧 Solicitud de evaluación enviada al coach {coach_id}")

    # CLAVE: request_approval con timeout de 7 días
    approval_result = await ctx.request_approval(
        approval_type="coach_athlete_evaluation",
        approval_data={
            "booking_id": booking_id,
            "coach_id": coach_id,
            "questions": {
                "performance_rating": "¿Cómo fue el desempeño del atleta? (1-5)",
                "areas_worked": "Áreas trabajadas (checkboxes)",
                "areas_to_improve": "Áreas a mejorar",
                "notes_for_next_session": "Notas para próxima sesión"
            }
        },
        timeout_ms=7 * 24 * 60 * 60 * 1000  # 7 días
    )

    if approval_result.approved:
        # Coach evaluó a tiempo
        evaluation = approval_result.data or {}

        # Guardar en DB
        # await evaluation_repo.create({
        #     'booking_id': booking_id,
        #     'from_coach': True,
        #     'performance_rating': evaluation.get('performance_rating'),
        #     'areas_worked': evaluation.get('areas_worked'),
        #     'areas_to_improve': evaluation.get('areas_to_improve'),
        #     'notes_for_next_session': evaluation.get('notes_for_next_session'),
        #     'submitted_at': datetime.utcnow()
        # })

        print(f"✅ Coach completó evaluación")
        print(f"   Performance: {evaluation.get('performance_rating')}/5")
        print(f"   Áreas trabajadas: {evaluation.get('areas_worked')}")
        print(f"   Para mejorar: {evaluation.get('areas_to_improve')}")

        return {
            'coach_evaluation_received': True,
            'performance_rating': evaluation.get('performance_rating'),
            'areas_worked': evaluation.get('areas_worked'),
            'areas_to_improve': evaluation.get('areas_to_improve'),
            'notes_for_next_session': evaluation.get('notes_for_next_session')
        }
    else:
        # TIMEOUT - Coach no evaluó en 7 días
        print(f"⏰ Timeout: Coach no evaluó en 7 días")

        # Guardar en DB
        # await evaluation_repo.create({
        #     'booking_id': booking_id,
        #     'from_coach': True,
        #     'status': 'no_evaluation_timeout',
        #     'timeout_at': datetime.utcnow()
        # })

        return {
            'coach_evaluation_received': False,
            'reason': 'timeout_7d'
        }


# ============================================================================
# STEP 4: Finalizar sesión (después de evaluaciones o timeouts)
# ============================================================================

async def finalize_session(ctx, inputs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Finaliza la sesión después de que:
    - Ambas evaluaciones fueron recibidas, O
    - Timeouts ocurrieron

    Marca la sesión como completamente finalizada.
    El tiempo registrado queda disponible para reportes de pago.
    """
    booking_id = inputs['booking_id']
    actual_duration = inputs['actual_duration_minutes']

    athlete_feedback = inputs.get('athlete_feedback_received', False)
    coach_evaluation = inputs.get('coach_evaluation_received', False)

    # Actualizar DB
    # await booking_repo.update(booking_id, {
    #     'status': 'FINALIZED',
    #     'finalized_at': datetime.utcnow(),
    #     'has_athlete_feedback': athlete_feedback,
    #     'has_coach_evaluation': coach_evaluation
    # })

    print(f"\n" + "="*70)
    print(f"✅ SESIÓN FINALIZADA")
    print(f"   Booking ID: {booking_id}")
    print(f"   Duración registrada: {actual_duration} minutos")
    print(f"   Feedback atleta: {'✅ Recibido' if athlete_feedback else '❌ No recibido'}")
    print(f"   Evaluación coach: {'✅ Recibida' if coach_evaluation else '❌ No recibida'}")
    print("="*70)

    return {
        'session_finalized': True,
        'booking_id': booking_id,
        'billable_minutes': actual_duration,
        'has_complete_feedback': athlete_feedback and coach_evaluation
    }


# ============================================================================
# WORKFLOW DEFINITION
# ============================================================================

def build_session_completion_workflow():
    """
    Workflow de finalización de sesión (ASÍNCRONO).

    Timeline:
    1. Coach registra tiempo real trabajado
    2. PARALELO:
        a) Solicitar feedback a atleta (timeout 48h)
        b) Solicitar evaluación a coach (timeout 7d)
    3. Finalizar sesión (cuando ambos completan o timeout)

    CARACTERÍSTICAS CLAVE:
    - Workflows pueden durar DÍAS (esperando evaluaciones)
    - Evaluaciones en paralelo (no bloquean una a otra)
    - Timeouts automáticos (si no responden, continúa)
    - Sobrevive a reinicios del sistema (gracias a event sourcing)

    VENTAJAS:
    - El tiempo de pago se registra INMEDIATAMENTE
    - Las evaluaciones no bloquean el workflow
    - Si el sistema se reinicia → workflow continúa donde quedó
    - Auditoría completa de quién respondió y cuándo
    """
    return (
        WorkflowBuilder("zea_sport.SessionCompletion")
        .timeline([
            "record_time",
            ["request_athlete_feedback", "request_coach_evaluation"],  # PARALELO
            "finalize_session"
        ])
        .step("record_time", record_actual_session_time)
        .step("request_athlete_feedback", request_athlete_feedback)
        .step("request_coach_evaluation", request_coach_evaluation)
        .step("finalize_session", finalize_session)
        .build()
    )


# ============================================================================
# EJEMPLO DE USO DESDE FASTAPI
# ============================================================================

async def demo_execution():
    """
    Ejemplo de cómo ejecutar desde tu endpoint FastAPI:

    @app.post("/api/bookings/{booking_id}/complete")
    async def complete_session(booking_id: str, data: CompleteSessionData):
        # Este endpoint lo llama el COACH cuando termina la sesión

        executor = DistributedExecutor(core_url="localhost:9090")

        # Ejecutar workflow (NO BLOQUEANTE - retorna inmediatamente)
        result = await executor.execute(
            build_session_completion_workflow(),
            {
                'booking_id': booking_id,
                'athlete_id': data.athlete_id,
                'coach_id': current_user.id,
                'actual_start_time': data.actual_start_time.isoformat(),
                'actual_end_time': data.actual_end_time.isoformat()
            }
        )

        # El workflow quedará ACTIVO esperando las evaluaciones
        # Pueden pasar DÍAS hasta que termine

        return {
            'message': 'Sesión marcada como completa. Evaluaciones enviadas.',
            'execution_id': result.execution_id,
            'billable_minutes': result.output.get('actual_duration_minutes')
        }


    Luego, cuando atleta/coach responden:

    @app.post("/api/feedback/submit")
    async def submit_feedback(data: FeedbackData):
        # Aprobar el workflow correspondiente
        await approve_execution(
            execution_id=data.execution_id,
            approval_type="athlete_session_feedback",
            approval_data={
                'rating': data.rating,
                'objectives_met': data.objectives_met,
                'comments': data.comments
            }
        )

        return {'message': 'Gracias por tu feedback!'}
    """

    # Start worker
    worker = Worker(core_url="localhost:9090", worker_id="zea-sport-worker-1")
    worker_task = asyncio.create_task(worker.run())
    await asyncio.sleep(1)

    # Execute workflow
    executor = DistributedExecutor(core_url="localhost:9090")

    try:
        print("\n" + "="*70)
        print("⭐ EJECUTANDO: Session Completion Workflow (ASÍNCRONO)")
        print("="*70 + "\n")

        result = await executor.execute(
            build_session_completion_workflow(),
            {
                'booking_id': 'booking-123',
                'athlete_id': 'athlete-456',
                'coach_id': 'coach-789',
                'actual_start_time': '2024-12-15T10:05:00',
                'actual_end_time': '2024-12-15T11:35:00'
            }
        )

        print("\n" + "="*70)
        print(f"✅ WORKFLOW INICIADO (esperando evaluaciones)")
        print(f"Execution ID: {result.execution_id}")
        print(f"Estado: WAITING_FOR_APPROVAL (atleta y coach deben evaluar)")
        print(f"\nEste workflow puede durar DÍAS esperando las evaluaciones.")
        print(f"Si no responden en el timeout → auto-completa sin feedback.")
        print("="*70 + "\n")

        print("\n💡 Para simular respuestas:")
        print(f"   1. Usa: cerebelum_cli.py status {result.execution_id}")
        print(f"   2. Usa la API de aprobación para simular feedback")

    finally:
        worker_task.cancel()
        try:
            await worker_task
        except asyncio.CancelledError:
            pass


if __name__ == "__main__":
    print("""
    ╔══════════════════════════════════════════════════════════════════╗
    ║      ZEA Sport Platform - Session Completion Workflow            ║
    ║                      (ASÍNCRONO - AVANZADO)                      ║
    ╚══════════════════════════════════════════════════════════════════╝

    Este es el workflow MÁS COMPLEJO y muestra las capacidades avanzadas
    de Cerebelum:

    FLUJO:
    1. ✅ Coach registra tiempo real trabajado (para su pago)
    2. 🔄 PARALELO (ambos al mismo tiempo):
        a) Solicita feedback a atleta (timeout 48 horas)
        b) Solicita evaluación a coach (timeout 7 días)
    3. ✅ Finaliza sesión (cuando ambos completan o timeout)

    CAPACIDADES DEMOSTRADAS:
    ✅ Workflows que duran DÍAS/SEMANAS
    ✅ Timeouts automáticos (si no responde → continúa)
    ✅ Pasos en PARALELO (evaluaciones simultáneas)
    ✅ Sobrevive a reinicios del sistema
    ✅ Auditoría completa vía event sourcing
    ✅ Estado visible en tiempo real (via CLI)

    VENTAJAS PARA ZEA SPORT:
    - Tiempo de pago registrado INMEDIATAMENTE
    - Evaluaciones no bloquean el cierre
    - Sistema confiable incluso si se reinicia
    - Visibilidad completa de workflows pendientes

    USO EN PRODUCCIÓN:
    - POST /api/bookings/{id}/complete
    - → Ejecuta workflow
    - → Retorna inmediatamente
    - → Workflow queda activo días esperando evaluaciones
    - → Cuando responden → workflow avanza
    - → Si timeout → workflow auto-completa

    """)

    asyncio.run(demo_execution())

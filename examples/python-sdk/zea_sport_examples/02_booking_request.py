#!/usr/bin/env python3
"""
Ejemplo: Solicitud de Reserva (Booking Request) - ZEA Sport Platform

Workflow que maneja el proceso completo de reserva de sesión de entrenamiento.
Incluye validaciones, confirmación y notificaciones.
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
# STEPS
# ============================================================================

async def validate_slot_availability(ctx, inputs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifica que el slot seleccionado siga disponible.

    Inputs:
        - coach_id: ID del entrenador
        - slot_datetime: Fecha/hora del slot (ISO format)
        - athlete_id: ID del atleta
    """
    coach_id = inputs['coach_id']
    slot_datetime = inputs['slot_datetime']

    # En producción, usarías tu SlotRepository
    # from app.repositories.slot_repository import SlotRepository
    # slot_repo = SlotRepository()
    # is_available = await slot_repo.is_available(coach_id, slot_datetime)

    # Simulación
    is_available = True  # En real, query a tu DB

    if not is_available:
        raise Exception(f"Slot {slot_datetime} ya no está disponible")

    print(f"✅ Slot verificado: {slot_datetime} con coach {coach_id}")

    return {
        'slot_available': True,
        'coach_id': coach_id,
        'slot_datetime': slot_datetime
    }


async def check_athlete_balance(ctx, inputs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifica que el atleta tenga créditos/balance suficiente.

    Retorna:
        - has_balance: bool
        - current_balance: int (número de créditos)
    """
    athlete_id = inputs['athlete_id']

    # En producción:
    # athlete = await athlete_repo.get_by_id(athlete_id)
    # has_balance = athlete.credits > 0

    # Simulación
    current_balance = 5  # Atleta tiene 5 créditos
    has_balance = current_balance > 0

    if not has_balance:
        # En vez de fallar, podrías redirigir a compra
        raise Exception("Atleta no tiene créditos. Debe comprar un paquete.")

    print(f"✅ Balance verificado: {current_balance} créditos")

    return {
        'has_balance': True,
        'current_balance': current_balance
    }


async def create_booking_record(ctx, inputs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Crea el registro de la reserva en la base de datos.

    Estado inicial: PENDING (aún no confirmada)
    """
    athlete_id = inputs['athlete_id']
    coach_id = inputs['coach_id']
    slot_datetime = inputs['slot_datetime']
    athlete_notes = inputs.get('athlete_notes', '')

    # En producción:
    # from app.repositories.booking_repository import BookingRepository
    # booking_repo = BookingRepository()
    # booking = await booking_repo.create({
    #     'athlete_id': athlete_id,
    #     'coach_id': coach_id,
    #     'scheduled_at': slot_datetime,
    #     'athlete_notes': athlete_notes,
    #     'status': 'PENDING',
    #     'created_at': datetime.utcnow()
    # })

    # Simulación
    booking_id = f"booking-{athlete_id}-{coach_id}-{datetime.now().timestamp()}"

    print(f"✅ Booking creado: {booking_id}")
    print(f"   Coach: {coach_id}")
    print(f"   Slot: {slot_datetime}")
    print(f"   Notas: {athlete_notes}")

    return {
        'booking_id': booking_id,
        'status': 'PENDING'
    }


async def reserve_slot(ctx, inputs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Marca el slot como reservado (bloquea para otros atletas).

    Esto debe ser ATÓMICO con la creación del booking para evitar
    double-booking.
    """
    coach_id = inputs['coach_id']
    slot_datetime = inputs['slot_datetime']
    booking_id = inputs['booking_id']

    # En producción:
    # await slot_repo.mark_as_reserved(coach_id, slot_datetime, booking_id)

    print(f"✅ Slot reservado exitosamente")

    return {
        'slot_reserved': True
    }


async def deduct_credit(ctx, inputs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Descuenta 1 crédito del balance del atleta.
    """
    athlete_id = inputs['athlete_id']
    current_balance = inputs['current_balance']

    new_balance = current_balance - 1

    # En producción:
    # await athlete_repo.update(athlete_id, {'credits': new_balance})

    print(f"✅ Crédito descontado: {current_balance} → {new_balance}")

    return {
        'credits_deducted': 1,
        'new_balance': new_balance
    }


async def confirm_booking(ctx, inputs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Actualiza el estado del booking a CONFIRMED.
    """
    booking_id = inputs['booking_id']

    # En producción:
    # await booking_repo.update(booking_id, {'status': 'CONFIRMED', 'confirmed_at': datetime.utcnow()})

    print(f"✅ Booking confirmado: {booking_id}")

    return {
        'booking_confirmed': True,
        'status': 'CONFIRMED'
    }


async def notify_coach(ctx, inputs: Dict[str, Any]) -> str:
    """
    Envía notificación al entrenador (email + push).
    """
    coach_id = inputs['coach_id']
    booking_id = inputs['booking_id']
    athlete_notes = inputs.get('athlete_notes', '')

    # En producción:
    # coach = await user_repo.get_by_id(coach_id)
    # await email_service.send_booking_notification(
    #     to=coach.email,
    #     booking_id=booking_id,
    #     athlete_notes=athlete_notes
    # )
    # await push_notification_service.send(coach_id, "Nueva reserva!")

    print(f"📧 Notificación enviada al coach {coach_id}")
    print(f"   Booking: {booking_id}")
    print(f"   Notas del atleta: {athlete_notes}")

    return "Coach notificado"


async def notify_athlete(ctx, inputs: Dict[str, Any]) -> str:
    """
    Envía confirmación al atleta (email + push).
    """
    athlete_id = inputs['athlete_id']
    booking_id = inputs['booking_id']
    slot_datetime = inputs['slot_datetime']

    # En producción:
    # athlete = await user_repo.get_by_id(athlete_id)
    # await email_service.send_booking_confirmation(
    #     to=athlete.email,
    #     booking_id=booking_id,
    #     slot_datetime=slot_datetime
    # )

    print(f"📧 Confirmación enviada al atleta {athlete_id}")
    print(f"   Booking: {booking_id}")
    print(f"   Slot: {slot_datetime}")

    return "Atleta notificado"


# ============================================================================
# WORKFLOW DEFINITION
# ============================================================================

def build_booking_request_workflow():
    """
    Workflow de solicitud de reserva.

    Timeline:
    1. Validar disponibilidad del slot
    2. Verificar balance/créditos del atleta
    3. Crear registro de booking (PENDING)
    4. Reservar slot (bloquear para otros)
    5. Descontar crédito
    6. Confirmar booking (CONFIRMED)
    7. Notificar al coach (paralelo)
    8. Notificar al atleta (paralelo)

    Casos de error:
    - Si slot no disponible → Falla en step 1
    - Si no tiene balance → Falla en step 2
    - Si falla notificación → No importa, booking ya está confirmado
    """
    return (
        WorkflowBuilder("zea_sport.BookingRequest")
        .timeline([
            "validate_slot",
            "check_balance",
            "create_booking",
            "reserve_slot",
            "deduct_credit",
            "confirm_booking",
            ["notify_coach", "notify_athlete"]  # Paralelo
        ])
        .step("validate_slot", validate_slot_availability)
        .step("check_balance", check_athlete_balance)
        .step("create_booking", create_booking_record)
        .step("reserve_slot", reserve_slot)
        .step("deduct_credit", deduct_credit)
        .step("confirm_booking", confirm_booking)
        .step("notify_coach", notify_coach)
        .step("notify_athlete", notify_athlete)
        .build()
    )


# ============================================================================
# EJEMPLO DE USO DESDE FASTAPI
# ============================================================================

async def demo_execution():
    """
    Ejemplo de cómo ejecutar desde tu endpoint FastAPI:

    @app.post("/api/bookings")
    async def create_booking(data: BookingRequest):
        executor = DistributedExecutor(core_url="localhost:9090")

        result = await executor.execute(
            build_booking_request_workflow(),
            {
                'athlete_id': current_user.id,
                'coach_id': data.coach_id,
                'slot_datetime': data.slot_datetime.isoformat(),
                'athlete_notes': data.notes
            }
        )

        # Respuesta inmediata (workflow es rápido, <1 segundo)
        return {
            'booking_id': result.output.get('booking_id'),
            'status': 'CONFIRMED',
            'execution_id': result.execution_id
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
        print("📅 EJECUTANDO: Booking Request Workflow")
        print("="*70 + "\n")

        result = await executor.execute(
            build_booking_request_workflow(),
            {
                'athlete_id': 'athlete-123',
                'coach_id': 'coach-456',
                'slot_datetime': '2024-12-15T10:00:00',
                'athlete_notes': 'Hoy quiero enfocarme en velocidad y técnica de sprint'
            }
        )

        print("\n" + "="*70)
        print(f"✅ BOOKING CONFIRMADO")
        print(f"Execution ID: {result.execution_id}")
        print(f"Booking ID: {result.output.get('booking_id')}")
        print(f"Status: {result.output.get('status')}")
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
    ║         ZEA Sport Platform - Booking Request Workflow            ║
    ╚══════════════════════════════════════════════════════════════════╝

    Este workflow maneja el proceso completo de reserva:

    1. ✅ Valida disponibilidad del slot
    2. ✅ Verifica balance/créditos
    3. 📝 Crea registro de booking (PENDING)
    4. 🔒 Reserva el slot (bloquea para otros)
    5. 💳 Descuenta 1 crédito
    6. ✅ Confirma booking (CONFIRMED)
    7. 📧 Notifica al coach
    8. 📧 Notifica al atleta

    VENTAJAS:
    - Atómico: Si falla algo, nada se guarda
    - Rápido: Workflow completo en <1 segundo
    - Notificaciones no bloquean confirmación
    - Auditoría completa vía event sourcing

    USO EN FASTAPI:
    POST /api/bookings
    → Ejecuta este workflow
    → Retorna booking_id confirmado inmediatamente

    """)

    asyncio.run(demo_execution())

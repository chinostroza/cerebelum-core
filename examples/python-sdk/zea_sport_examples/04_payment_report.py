#!/usr/bin/env python3
"""
Ejemplo: Reporte de Pagos para Entrenadores - ZEA Sport Platform

Workflow que genera reportes mensuales de horas trabajadas por entrenador
para cálculo de nómina.

NOTA: Este workflow usa ExecutionClient para consultar datos históricos.
"""

import asyncio
from typing import Dict, Any, List
from datetime import datetime, timedelta
from cerebelum import (
    WorkflowBuilder,
    DistributedExecutor,
    Worker,
    ExecutionClient,
)


# ============================================================================
# STEPS
# ============================================================================

async def fetch_completed_sessions(ctx, inputs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Consulta todas las sesiones completadas en el período.

    Inputs:
        - coach_id: ID del entrenador (opcional, si None = todos)
        - start_date: Fecha inicio del período (ISO format)
        - end_date: Fecha fin del período (ISO format)

    Returns:
        - sessions: Lista de sesiones con tiempo real trabajado
    """
    coach_id = inputs.get('coach_id')
    start_date = inputs['start_date']
    end_date = inputs['end_date']

    # En producción, consultarías tu BookingRepository:
    # from app.repositories.booking_repository import BookingRepository
    # booking_repo = BookingRepository()
    # sessions = await booking_repo.find_completed_sessions(
    #     coach_id=coach_id,
    #     start_date=start_date,
    #     end_date=end_date
    # )

    # Simulación: datos de ejemplo
    sessions = [
        {
            'booking_id': 'booking-001',
            'coach_id': 'coach-789',
            'athlete_id': 'athlete-123',
            'scheduled_at': '2024-11-05T10:00:00',
            'actual_start_time': '2024-11-05T10:05:00',
            'actual_end_time': '2024-11-05T11:35:00',
            'actual_duration_minutes': 90,
            'status': 'FINALIZED'
        },
        {
            'booking_id': 'booking-002',
            'coach_id': 'coach-789',
            'athlete_id': 'athlete-456',
            'scheduled_at': '2024-11-07T14:00:00',
            'actual_start_time': '2024-11-07T14:00:00',
            'actual_end_time': '2024-11-07T15:45:00',
            'actual_duration_minutes': 105,
            'status': 'FINALIZED'
        },
        {
            'booking_id': 'booking-003',
            'coach_id': 'coach-789',
            'athlete_id': 'athlete-789',
            'scheduled_at': '2024-11-10T09:00:00',
            'actual_start_time': '2024-11-10T09:00:00',
            'actual_end_time': '2024-11-10T10:30:00',
            'actual_duration_minutes': 90,
            'status': 'FINALIZED'
        },
        # ... más sesiones
    ]

    # Filtrar por coach_id si se especifica
    if coach_id:
        sessions = [s for s in sessions if s['coach_id'] == coach_id]

    print(f"✅ Fetched {len(sessions)} completed sessions")
    print(f"   Período: {start_date} → {end_date}")
    if coach_id:
        print(f"   Coach: {coach_id}")

    return {
        'sessions': sessions,
        'total_sessions': len(sessions)
    }


async def calculate_total_hours(ctx, inputs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Calcula el total de horas trabajadas.

    IMPORTANTE: Usa actual_duration_minutes (NO el tiempo programado).
    """
    sessions = inputs['sessions']

    total_minutes = sum(s['actual_duration_minutes'] for s in sessions)
    total_hours = total_minutes / 60.0

    print(f"✅ Calculado total de horas")
    print(f"   Total sesiones: {len(sessions)}")
    print(f"   Total minutos: {total_minutes}")
    print(f"   Total horas: {total_hours:.2f} hrs")

    return {
        'total_sessions': len(sessions),
        'total_minutes': total_minutes,
        'total_hours': round(total_hours, 2)
    }


async def group_by_week(ctx, inputs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Agrupa sesiones por semana para desglose detallado.
    """
    sessions = inputs['sessions']

    # Agrupar por semana
    weeks = {}
    for session in sessions:
        # En producción, parsear fecha real
        # scheduled_dt = datetime.fromisoformat(session['scheduled_at'])
        # week_start = scheduled_dt - timedelta(days=scheduled_dt.weekday())
        # week_key = week_start.strftime('%Y-W%U')

        # Simulación simple
        week_key = "2024-W45"  # Semana 45 de 2024

        if week_key not in weeks:
            weeks[week_key] = {
                'week': week_key,
                'sessions': [],
                'total_minutes': 0,
                'total_hours': 0
            }

        weeks[week_key]['sessions'].append(session)
        weeks[week_key]['total_minutes'] += session['actual_duration_minutes']

    # Calcular horas por semana
    for week_data in weeks.values():
        week_data['total_hours'] = round(week_data['total_minutes'] / 60.0, 2)

    print(f"✅ Agrupado por semana: {len(weeks)} semanas")

    return {
        'weeks': list(weeks.values()),
        'total_weeks': len(weeks)
    }


async def generate_report_data(ctx, inputs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Genera la estructura completa del reporte.
    """
    coach_id = inputs.get('coach_id', 'ALL_COACHES')
    start_date = inputs['start_date']
    end_date = inputs['end_date']
    total_hours = inputs['total_hours']
    total_sessions = inputs['total_sessions']
    weeks = inputs['weeks']
    sessions = inputs['sessions']

    report = {
        'report_id': f"report-{coach_id}-{start_date}-{end_date}",
        'coach_id': coach_id,
        'period': {
            'start_date': start_date,
            'end_date': end_date
        },
        'summary': {
            'total_hours': total_hours,
            'total_sessions': total_sessions,
            'average_session_minutes': round(sum(s['actual_duration_minutes'] for s in sessions) / len(sessions), 2) if sessions else 0
        },
        'weekly_breakdown': weeks,
        'sessions_detail': sessions,
        'generated_at': datetime.now().isoformat()
    }

    print(f"\n{'='*70}")
    print(f"📊 REPORTE DE PAGO GENERADO")
    print(f"{'='*70}")
    print(f"Coach ID: {coach_id}")
    print(f"Período: {start_date} → {end_date}")
    print(f"Total Horas: {total_hours:.2f} hrs")
    print(f"Total Sesiones: {total_sessions}")
    print(f"Promedio por sesión: {report['summary']['average_session_minutes']:.0f} min")
    print(f"{'='*70}\n")

    return report


async def save_report_to_db(ctx, inputs: Dict[str, Any]) -> str:
    """
    Guarda el reporte en la base de datos.
    """
    report_id = inputs['report_id']

    # En producción:
    # from app.repositories.payment_report_repository import PaymentReportRepository
    # report_repo = PaymentReportRepository()
    # await report_repo.create(inputs)  # Guardar todo el reporte

    print(f"✅ Reporte guardado en DB: {report_id}")

    return report_id


async def export_to_csv(ctx, inputs: Dict[str, Any]) -> str:
    """
    Exporta el reporte a CSV para procesamiento de nómina.
    """
    report_id = inputs['report_id']
    sessions = inputs['sessions_detail']

    # En producción:
    # import csv
    # filename = f"/exports/{report_id}.csv"
    # with open(filename, 'w', newline='') as csvfile:
    #     writer = csv.DictWriter(csvfile, fieldnames=['booking_id', 'coach_id', 'date', 'duration_minutes'])
    #     writer.writeheader()
    #     for session in sessions:
    #         writer.writerow({
    #             'booking_id': session['booking_id'],
    #             'coach_id': session['coach_id'],
    #             'date': session['scheduled_at'][:10],
    #             'duration_minutes': session['actual_duration_minutes']
    #         })

    csv_filename = f"{report_id}.csv"
    print(f"✅ Exportado a CSV: {csv_filename}")
    print(f"   {len(sessions)} sesiones exportadas")

    return csv_filename


async def notify_admin(ctx, inputs: Dict[str, Any]) -> str:
    """
    Notifica al administrador que el reporte está listo.
    """
    report_id = inputs['report_id']
    csv_filename = inputs.get('csv_filename')
    total_hours = inputs['summary']['total_hours']

    # En producción:
    # await email_service.send_payment_report_notification(
    #     to='admin@zeasport.com',
    #     report_id=report_id,
    #     csv_attachment=csv_filename,
    #     summary={'total_hours': total_hours}
    # )

    print(f"📧 Notificación enviada al admin")
    print(f"   Reporte: {report_id}")
    print(f"   CSV adjunto: {csv_filename}")

    return "Admin notificado"


# ============================================================================
# WORKFLOW DEFINITION
# ============================================================================

def build_payment_report_workflow():
    """
    Workflow para generar reportes de pago mensuales.

    Timeline:
    1. Fetch sesiones completadas del período
    2. Calcular total de horas
    3. Agrupar por semana
    4. Generar estructura del reporte
    5. Guardar en DB
    6. Exportar a CSV
    7. Notificar admin

    USO:
    - Ejecutar manualmente al final de cada mes
    - O programar automáticamente (cron job)
    - O ejecutar bajo demanda desde UI admin
    """
    return (
        WorkflowBuilder("zea_sport.PaymentReport")
        .timeline([
            "fetch_sessions",
            "calculate_hours",
            "group_by_week",
            "generate_report",
            "save_to_db",
            "export_csv",
            "notify_admin"
        ])
        .step("fetch_sessions", fetch_completed_sessions)
        .step("calculate_hours", calculate_total_hours)
        .step("group_by_week", group_by_week)
        .step("generate_report", generate_report_data)
        .step("save_to_db", save_report_to_db)
        .step("export_csv", export_to_csv)
        .step("notify_admin", notify_admin)
        .build()
    )


# ============================================================================
# EJEMPLO DE USO DESDE FASTAPI
# ============================================================================

async def demo_execution():
    """
    Ejemplo de cómo ejecutar desde tu endpoint FastAPI:

    @app.post("/api/admin/reports/payment")
    async def generate_payment_report(data: PaymentReportRequest):
        # Solo admins pueden ejecutar esto

        executor = DistributedExecutor(core_url="localhost:9090")

        result = await executor.execute(
            build_payment_report_workflow(),
            {
                'coach_id': data.coach_id,  # None = todos los coaches
                'start_date': data.start_date.isoformat(),
                'end_date': data.end_date.isoformat()
            }
        )

        return {
            'report_id': result.output.get('report_id'),
            'total_hours': result.output.get('summary', {}).get('total_hours'),
            'csv_file': result.output.get('csv_filename'),
            'execution_id': result.execution_id
        }


    O ejecutar automáticamente cada mes:

    from apscheduler.schedulers.asyncio import AsyncIOScheduler

    scheduler = AsyncIOScheduler()

    @scheduler.scheduled_job('cron', day=1, hour=2)  # 1ro de cada mes a las 2am
    async def monthly_payment_reports():
        # Generar reportes para todos los coaches
        executor = DistributedExecutor(core_url="localhost:9090")

        last_month_start = datetime.now().replace(day=1) - timedelta(days=1)
        last_month_start = last_month_start.replace(day=1)

        await executor.execute(
            build_payment_report_workflow(),
            {
                'coach_id': None,  # Todos
                'start_date': last_month_start.isoformat(),
                'end_date': (datetime.now().replace(day=1) - timedelta(days=1)).isoformat()
            }
        )
    """

    # Start worker
    worker = Worker(core_url="localhost:9090", worker_id="zea-sport-worker-1")
    worker_task = asyncio.create_task(worker.run())
    await asyncio.sleep(1)

    # Execute workflow
    executor = DistributedExecutor(core_url="localhost:9090")

    try:
        print("\n" + "="*70)
        print("💰 EJECUTANDO: Payment Report Workflow")
        print("="*70 + "\n")

        result = await executor.execute(
            build_payment_report_workflow(),
            {
                'coach_id': 'coach-789',
                'start_date': '2024-11-01',
                'end_date': '2024-11-30'
            }
        )

        print("\n" + "="*70)
        print(f"✅ REPORTE GENERADO")
        print(f"Execution ID: {result.execution_id}")
        print(f"Report ID: {result.output.get('report_id')}")
        print(f"Total Hours: {result.output.get('summary', {}).get('total_hours')} hrs")
        print(f"CSV File: {result.output.get('csv_filename')}")
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
    ║        ZEA Sport Platform - Payment Report Workflow              ║
    ╚══════════════════════════════════════════════════════════════════╝

    Workflow para generar reportes mensuales de pago para entrenadores.

    FLUJO:
    1. 📊 Consulta sesiones completadas en el período
    2. ⏱️  Calcula total de horas (usando tiempo REAL registrado)
    3. 📅 Agrupa por semana para desglose detallado
    4. 📄 Genera estructura completa del reporte
    5. 💾 Guarda en base de datos
    6. 📤 Exporta a CSV para nómina
    7. 📧 Notifica al administrador

    CARACTERÍSTICAS:
    - Usa actual_duration_minutes (NO tiempo programado)
    - Solo cuenta sesiones FINALIZED
    - Filtrable por coach y rango de fechas
    - Desglose semanal y por sesión
    - Exportable a CSV/Excel

    USO EN PRODUCCIÓN:
    - Manual: POST /api/admin/reports/payment
    - Automático: Cron job cada 1ro del mes
    - On-demand: UI de administración

    DATOS DEL REPORTE:
    - Total horas trabajadas
    - Total sesiones
    - Promedio por sesión
    - Desglose semanal
    - Detalles por sesión (con links a booking original)

    """)

    asyncio.run(demo_execution())

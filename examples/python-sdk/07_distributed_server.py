#!/usr/bin/env python3
"""
Tutorial 07: Enterprise Onboarding - DISTRIBUTED SERVER
========================================================

DESCRIPCIÓN:
    Worker server para el workflow de onboarding empresarial.
    Este servidor registra todos los steps y el workflow con Core,
    y procesa las tareas cuando llegan.

CARACTERÍSTICAS:
    - ✅ 12 steps de onboarding empresarial
    - ✅ 3 niveles de paralelismo coordinado
    - ✅ Simulación de integraciones (Slack, GitHub, Email, etc.)
    - ✅ Worker server que procesa tareas de Core

ARQUITECTURA:
    Terminal 1: Core BEAM             (cd ../../ && mix run --no-halt)
    Terminal 2: Worker Server         (python3 07_distributed_server.py) ← ESTE ARCHIVO
    Terminal 3: Execute Workflow      (python3 07_execute_workflow.py)

USO:
    # Terminal 1: Iniciar Core
    cd ../../ && mix run --no-halt

    # Terminal 2: Iniciar Worker Server
    python3 07_distributed_server.py

    # Terminal 3: Ejecutar onboarding
    python3 07_execute_workflow.py "Jane Doe" "jane.doe@company.com" "Engineering" "Developer"

EL SERVIDOR:
    - Nunca retorna (corre hasta Ctrl+C)
    - Muestra logs de cada tarea procesada
    - Auto-registra todos los steps con Core
    - Procesa múltiples ejecuciones en paralelo

NIVEL: 🔴 Avanzado
"""

import asyncio
from datetime import datetime
from cerebelum import step, workflow, Context


# =============================================================================
# STEP 1: AUTHENTICATION
# =============================================================================

@step
async def authenticate(context: Context, inputs: dict):
    """Autenticar al administrador que ejecuta el onboarding."""
    admin_id = inputs.get("admin_id")
    admin_token = inputs.get("admin_token")

    print(f"  🔐 [{context.step_name}] Authenticating admin...")
    print(f"     Admin ID: {admin_id}")

    await asyncio.sleep(0.5)

    if not admin_token or admin_token != "valid-admin-token":
        raise ValueError("Invalid admin credentials")

    print(f"     ✅ Admin authenticated")

    return {
        "admin_id": admin_id,
        "admin_name": "Sarah Johnson",
        "admin_role": "IT Manager"
    }


# =============================================================================
# STEP 2: VALIDATION
# =============================================================================

@step
async def validate_user_data(context: Context, inputs: dict):
    """Validar datos del nuevo usuario."""
    user_data = inputs.get("user_data", {})

    print(f"  ✓ [{context.step_name}] Validating user data...")
    print(f"     Name: {user_data.get('name')}")
    print(f"     Email: {user_data.get('email')}")

    await asyncio.sleep(0.5)

    # Validaciones
    required_fields = ["name", "email", "department", "role"]
    for field in required_fields:
        if not user_data.get(field):
            raise ValueError(f"Missing required field: {field}")

    email = user_data.get("email")
    if "@" not in email or "." not in email:
        raise ValueError(f"Invalid email format: {email}")

    print(f"     ✅ User data validated")

    return {
        "user_id": f"USR-{datetime.now().strftime('%Y%m%d%H%M%S')}",
        "validated_data": user_data
    }


# =============================================================================
# FASE 1: PROVISIONING (PARALELO)
# =============================================================================

@step
async def create_user_account(context: Context, validate_user_data: dict):
    """Crear cuenta de usuario en el sistema de identidad."""
    user_id = validate_user_data["user_id"]
    user_data = validate_user_data["validated_data"]

    print(f"  👤 [{context.step_name}] Creating user account...")
    print(f"     User ID: {user_id}")

    await asyncio.sleep(2.0)

    print(f"     ✅ Account created")

    return {
        "account_id": f"ACC-{user_id}",
        "username": user_data["email"].split("@")[0],
        "initial_password": "TempPass123!",
        "account_status": "active"
    }


@step
async def setup_workspace(context: Context, validate_user_data: dict):
    """Configurar workspace/directorio personal del usuario."""
    user_id = validate_user_data["user_id"]
    user_data = validate_user_data["validated_data"]

    print(f"  📁 [{context.step_name}] Setting up workspace...")
    print(f"     Department: {user_data['department']}")

    await asyncio.sleep(1.5)

    workspace_path = f"/workspaces/{user_data['department']}/{user_id}"

    print(f"     ✅ Workspace created: {workspace_path}")

    return {
        "workspace_path": workspace_path,
        "storage_quota_gb": 100,
        "shared_folders": [
            f"/shared/{user_data['department']}",
            "/shared/company-wide"
        ]
    }


@step
async def provision_tools(context: Context, validate_user_data: dict):
    """Provisionar herramientas: email, calendar, chat."""
    user_id = validate_user_data["user_id"]
    user_data = validate_user_data["validated_data"]

    print(f"  🛠️  [{context.step_name}] Provisioning tools...")
    print(f"     Email: {user_data['email']}")

    await asyncio.sleep(1.8)

    tools = {
        "email": {
            "address": user_data["email"],
            "mailbox_size_gb": 50,
            "status": "active"
        },
        "calendar": {
            "url": f"https://calendar.company.com/{user_id}",
            "status": "active"
        },
        "chat": {
            "username": user_data["email"].split("@")[0],
            "status": "active"
        }
    }

    print(f"     ✅ Tools provisioned: Email, Calendar, Chat")

    return {
        "provisioned_tools": tools,
        "activation_time": datetime.now().isoformat()
    }


# =============================================================================
# FASE 2: CONFIGURATION (PARALELO)
# =============================================================================

@step
async def setup_permissions(
    context: Context,
    validate_user_data: dict,
    create_user_account: dict,
    setup_workspace: dict
):
    """Configurar permisos basados en el rol del usuario."""
    user_data = validate_user_data["validated_data"]
    account_id = create_user_account["account_id"]

    print(f"  🔒 [{context.step_name}] Setting up permissions...")
    print(f"     Role: {user_data['role']}")

    await asyncio.sleep(1.5)

    role_permissions = {
        "Developer": ["code_repository", "deployment_dev", "deployment_staging"],
        "Manager": ["team_management", "reports", "budget"],
        "Designer": ["design_tools", "asset_library", "feedback_system"],
        "Analyst": ["analytics_platform", "database_read", "reporting_tools"]
    }

    permissions = role_permissions.get(user_data["role"], ["basic_access"])

    print(f"     ✅ Permissions configured: {len(permissions)} granted")

    return {
        "granted_permissions": permissions,
        "workspace_access": setup_workspace["workspace_path"],
        "permission_level": user_data["role"]
    }


@step
async def configure_integrations(
    context: Context,
    validate_user_data: dict,
    create_user_account: dict
):
    """Integrar usuario con servicios externos (Slack, GitHub, etc.)."""
    user_data = validate_user_data["validated_data"]
    username = create_user_account["username"]

    print(f"  🔗 [{context.step_name}] Configuring integrations...")
    print(f"     Username: {username}")

    await asyncio.sleep(2.0)

    integrations = {
        "slack": {
            "channel": f"#{user_data['department'].lower()}",
            "username": username,
            "status": "connected"
        },
        "github": {
            "username": username,
            "teams": [user_data["department"]],
            "status": "invited"
        },
        "jira": {
            "username": username,
            "projects": [f"{user_data['department']}-PROJECT"],
            "status": "active"
        }
    }

    print(f"     ✅ Integrations configured: Slack, GitHub, Jira")

    return {
        "configured_integrations": integrations,
        "pending_invitations": ["github"]
    }


@step
async def create_documentation(
    context: Context,
    validate_user_data: dict,
    setup_workspace: dict,
    provision_tools: dict
):
    """Generar documentación personalizada para el usuario."""
    user_data = validate_user_data["validated_data"]
    workspace_path = setup_workspace["workspace_path"]

    print(f"  📚 [{context.step_name}] Creating documentation...")
    print(f"     Role: {user_data['role']}")

    await asyncio.sleep(1.2)

    docs = {
        "welcome_guide": f"{workspace_path}/docs/welcome.pdf",
        "role_specific_guide": f"{workspace_path}/docs/{user_data['role'].lower()}_guide.pdf",
        "tools_quickstart": f"{workspace_path}/docs/tools_quickstart.pdf",
        "company_policies": f"{workspace_path}/docs/policies.pdf"
    }

    print(f"     ✅ Documentation created: {len(docs)} documents")

    return {
        "documentation_files": docs,
        "documentation_portal": f"https://docs.company.com/user/{user_data['email']}"
    }


# =============================================================================
# FASE 3: NOTIFICATIONS (PARALELO)
# =============================================================================

@step
async def send_welcome_email(
    context: Context,
    validate_user_data: dict,
    create_user_account: dict,
    provision_tools: dict,
    create_documentation: dict
):
    """Enviar email de bienvenida con credenciales y recursos."""
    user_data = validate_user_data["validated_data"]

    print(f"  📧 [{context.step_name}] Sending welcome email...")
    print(f"     To: {user_data['email']}")

    await asyncio.sleep(1.0)

    print(f"     ✅ Welcome email sent")

    return {
        "email_sent": True,
        "email_id": f"EMAIL-{datetime.now().strftime('%Y%m%d%H%M%S')}",
        "sent_at": datetime.now().isoformat()
    }


@step
async def notify_team(
    context: Context,
    validate_user_data: dict,
    configure_integrations: dict
):
    """Notificar al equipo sobre el nuevo miembro en Slack."""
    user_data = validate_user_data["validated_data"]
    slack_config = configure_integrations["configured_integrations"]["slack"]

    print(f"  💬 [{context.step_name}] Notifying team on Slack...")
    print(f"     Channel: {slack_config['channel']}")

    await asyncio.sleep(0.8)

    print(f"     ✅ Team notified")

    return {
        "notification_sent": True,
        "channel": slack_config["channel"],
        "timestamp": datetime.now().isoformat()
    }


@step
async def schedule_onboarding_calls(
    context: Context,
    validate_user_data: dict,
    provision_tools: dict
):
    """Agendar reuniones de onboarding (HR, equipo, manager)."""
    user_data = validate_user_data["validated_data"]
    calendar = provision_tools["provisioned_tools"]["calendar"]

    print(f"  📅 [{context.step_name}] Scheduling onboarding calls...")

    await asyncio.sleep(1.0)

    scheduled_calls = [
        {
            "title": "HR Onboarding - Day 1",
            "duration_minutes": 60,
            "attendees": ["hr@company.com", user_data["email"]]
        },
        {
            "title": "Team Introduction",
            "duration_minutes": 30,
            "attendees": [f"{user_data['department'].lower()}@company.com", user_data["email"]]
        },
        {
            "title": "Manager 1-on-1",
            "duration_minutes": 45,
            "attendees": ["manager@company.com", user_data["email"]]
        }
    ]

    print(f"     ✅ Scheduled {len(scheduled_calls)} calls")

    return {
        "scheduled_calls": scheduled_calls,
        "calendar_invites_sent": True
    }


# =============================================================================
# STEP FINAL: FINALIZATION
# =============================================================================

@step
async def finalize_onboarding(
    context: Context,
    authenticate: dict,
    validate_user_data: dict,
    create_user_account: dict,
    setup_workspace: dict,
    provision_tools: dict,
    setup_permissions: dict,
    configure_integrations: dict,
    create_documentation: dict,
    send_welcome_email: dict,
    notify_team: dict,
    schedule_onboarding_calls: dict
):
    """Finalizar onboarding y generar reporte completo."""
    user_data = validate_user_data["validated_data"]
    admin_name = authenticate["admin_name"]

    print(f"  🎉 [{context.step_name}] Finalizing onboarding...")
    print(f"     User: {user_data['name']}")

    await asyncio.sleep(0.5)

    onboarding_report = {
        "user_info": {
            "user_id": validate_user_data["user_id"],
            "name": user_data["name"],
            "email": user_data["email"],
            "department": user_data["department"],
            "role": user_data["role"]
        },
        "account_details": {
            "account_id": create_user_account["account_id"],
            "username": create_user_account["username"],
            "status": create_user_account["account_status"]
        },
        "workspace": {
            "path": setup_workspace["workspace_path"],
            "storage_gb": setup_workspace["storage_quota_gb"]
        },
        "summary": {
            "tools_provisioned": len(provision_tools["provisioned_tools"]),
            "permissions_granted": len(setup_permissions["granted_permissions"]),
            "integrations_configured": len(configure_integrations["configured_integrations"]),
            "documentation_files": len(create_documentation["documentation_files"]),
            "onboarding_calls": len(schedule_onboarding_calls["scheduled_calls"])
        },
        "onboarding_completed_by": admin_name,
        "completed_at": datetime.now().isoformat()
    }

    print(f"\n  " + "=" * 66)
    print(f"  ✅ ONBOARDING COMPLETED!")
    print(f"  " + "=" * 66)
    print(f"     User: {user_data['name']} ({user_data['email']})")
    print(f"     Role: {user_data['role']} | Dept: {user_data['department']}")
    print(f"     Account: {create_user_account['account_id']}")
    print(f"     Execution: {context.execution_id}")
    print(f"  " + "=" * 66)

    return {
        "onboarding_complete": True,
        "report": onboarding_report,
        "success": True
    }


# =============================================================================
# WORKFLOW DEFINITION
# =============================================================================

@workflow
def enterprise_onboarding_workflow(wf):
    """
    Workflow de onboarding empresarial con 3 fases paralelas.

    Estructura:
        authenticate → validate_user_data →
        FASE 1 (paralelo): [create_user_account, setup_workspace, provision_tools] →
        FASE 2 (paralelo): [setup_permissions, configure_integrations, create_documentation] →
        FASE 3 (paralelo): [send_welcome_email, notify_team, schedule_onboarding_calls] →
        finalize_onboarding
    """
    wf.timeline(
        authenticate >>
        validate_user_data >>
        # FASE 1: Provisioning (paralelo)
        [create_user_account, setup_workspace, provision_tools] >>
        # FASE 2: Configuration (paralelo)
        [setup_permissions, configure_integrations, create_documentation] >>
        # FASE 3: Notifications (paralelo)
        [send_welcome_email, notify_team, schedule_onboarding_calls] >>
        # Finalización
        finalize_onboarding
    )


# =============================================================================
# MAIN - DISTRIBUTED SERVER
# =============================================================================

async def main():
    """Ejecutar worker server en modo distribuido."""

    print("\n" + "=" * 70)
    print("🚀 STARTING DISTRIBUTED WORKER SERVER")
    print("=" * 70)
    print("\n📋 Workflow: Enterprise User Onboarding")
    print("📊 Steps: 12 (3 niveles de paralelismo)")
    print("🔧 Mode: DISTRIBUTED")
    print("\n" + "=" * 70)
    print("\n🔌 Connecting to Core at localhost:9090...")
    print("📝 Registering workflow 'enterprise_onboarding_workflow'...")
    print("🏃 Starting worker server...")
    print("\n💡 The server will process tasks and show logs below.")
    print("💡 Use Ctrl+C to stop the server.")
    print("\n🚀 To execute workflows, run in another terminal:")
    print("   python3 07_execute_workflow.py \"Jane Doe\" \"jane@company.com\" \"Engineering\" \"Developer\"")
    print("\n" + "=" * 70)
    print()

    # Ejecutar workflow inicial en modo distribuido
    # distributed=True hace que NUNCA retorne - corre como servidor
    #
    # CONFIGURACIÓN DE RECONEXIÓN (Auto-Reconnection):
    # Por defecto: reintentos infinitos (max_reconnect_attempts=0)
    #
    # Opciones de configuración:
    #
    # 1. DESARROLLO - Infinito (default):
    #    max_reconnect_attempts=0  # Nunca se rinde, siempre intenta reconectar
    #
    # 2. PRODUCCIÓN - Con límite de tiempo:
    #    max_reconnect_attempts=120   # ~2 horas (120 × 60s)
    #    max_reconnect_attempts=1440  # ~24 horas (1440 × 60s)
    #
    # 3. TESTING - Falla rápido:
    #    max_reconnect_attempts=5     # Solo 5 intentos (~31 segundos)
    #
    # Para ambientes productivos con Kubernetes/Docker:
    # - Usa un límite razonable (120-1440 intentos)
    # - Configura restartPolicy=Always en Kubernetes
    # - El orquestador reiniciará el worker si alcanza el límite
    # - Esto previene workers "zombies" que no hacen nada útil

    await enterprise_onboarding_workflow.execute(
        inputs={
            "admin_id": "ADM-001",
            "admin_token": "valid-admin-token",
            "user_data": {
                "name": "Initial User",
                "email": "initial@company.com",
                "department": "Engineering",
                "role": "Developer"
            }
        },
        distributed=True,               # 🔥 Modo servidor distribuido!
        max_reconnect_attempts=0,       # 0 = infinito (default)
        reconnect_max_delay=60.0,       # 60 segundos máximo entre reintentos
    )

    # EJEMPLOS DE USO:
    #
    # Desarrollo (nunca se rinde):
    # await workflow.execute(inputs, distributed=True)
    #
    # Producción (~2 horas máximo):
    # await workflow.execute(
    #     inputs,
    #     distributed=True,
    #     max_reconnect_attempts=120,
    #     reconnect_max_delay=60.0
    # )
    #
    # Testing (falla rápido):
    # await workflow.execute(
    #     inputs,
    #     distributed=True,
    #     max_reconnect_attempts=5,
    #     reconnect_max_delay=10.0
    # )


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print()
        print("=" * 70)
        print("🛑 Server stopped")
        print("=" * 70)

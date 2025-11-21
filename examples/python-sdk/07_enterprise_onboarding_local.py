#!/usr/bin/env python3
"""
Tutorial 07: Enterprise User Onboarding - Complex Workflow
===========================================================

DESCRIPCIÓN:
    Workflow complejo de onboarding de usuario empresarial que demuestra:
    - ✅ 3 niveles de paralelismo
    - ✅ Dependencias complejas entre steps
    - ✅ Simulación de integraciones con servicios externos
    - ✅ Manejo de errores y validaciones
    - ✅ ~12 steps coordinados

FLUJO DEL WORKFLOW:
    1. authenticate                    (Autenticar admin que ejecuta el onboarding)
    2. validate_user_data              (Validar datos del nuevo usuario)
    3. PARALELO - Fase 1: Provisioning
       ├─ create_user_account          (Crear cuenta en sistema de identidad)
       ├─ setup_workspace              (Crear workspace/directorio personal)
       └─ provision_tools              (Provisionar herramientas: email, calendar, etc.)
    4. PARALELO - Fase 2: Configuration
       ├─ setup_permissions            (Configurar permisos basados en rol)
       ├─ configure_integrations       (Integrar con Slack, GitHub, etc.)
       └─ create_documentation         (Generar documentación personalizada)
    5. PARALELO - Fase 3: Notifications
       ├─ send_welcome_email           (Enviar email de bienvenida)
       ├─ notify_team                  (Notificar al equipo en Slack)
       └─ schedule_onboarding_calls    (Agendar reuniones de onboarding)
    6. finalize_onboarding             (Finalizar y crear reporte)

TIEMPO APROXIMADO:
    - Sin paralelismo: ~25 segundos
    - Con paralelismo: ~10 segundos ⚡️

CÓMO EJECUTAR:
    python3 07_enterprise_onboarding.py

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

    print(f"\n🔐 [{context.step_name}] Authenticating admin...")
    print(f"   Admin ID: {admin_id}")

    # Simular verificación de token
    await asyncio.sleep(0.5)

    if not admin_token or admin_token != "valid-admin-token":
        raise ValueError("Invalid admin credentials")

    print(f"   ✅ Admin authenticated successfully")

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

    print(f"\n✓ [{context.step_name}] Validating user data...")
    print(f"   Name: {user_data.get('name')}")
    print(f"   Email: {user_data.get('email')}")
    print(f"   Department: {user_data.get('department')}")
    print(f"   Role: {user_data.get('role')}")

    # Simular validación
    await asyncio.sleep(0.5)

    # Validaciones
    required_fields = ["name", "email", "department", "role"]
    for field in required_fields:
        if not user_data.get(field):
            raise ValueError(f"Missing required field: {field}")

    # Validar formato de email
    email = user_data.get("email")
    if "@" not in email or "." not in email:
        raise ValueError(f"Invalid email format: {email}")

    print(f"   ✅ User data validated")

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

    print(f"\n👤 [{context.step_name}] Creating user account...")
    print(f"   User ID: {user_id}")
    print(f"   Email: {user_data['email']}")

    # Simular creación de cuenta (proceso largo)
    await asyncio.sleep(2.0)

    print(f"   ✅ User account created in identity system")

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

    print(f"\n📁 [{context.step_name}] Setting up workspace...")
    print(f"   User: {user_data['name']}")
    print(f"   Department: {user_data['department']}")

    # Simular creación de workspace
    await asyncio.sleep(1.5)

    workspace_path = f"/workspaces/{user_data['department']}/{user_id}"

    print(f"   ✅ Workspace created at: {workspace_path}")

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

    print(f"\n🛠️  [{context.step_name}] Provisioning tools...")
    print(f"   Email: {user_data['email']}")

    # Simular provisioning de herramientas
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

    print(f"   ✅ Tools provisioned: Email, Calendar, Chat")

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
    workspace_path = setup_workspace["workspace_path"]

    print(f"\n🔒 [{context.step_name}] Setting up permissions...")
    print(f"   Role: {user_data['role']}")
    print(f"   Account: {account_id}")

    # Simular configuración de permisos
    await asyncio.sleep(1.5)

    # Permisos basados en rol
    role_permissions = {
        "Developer": ["code_repository", "deployment_dev", "deployment_staging"],
        "Manager": ["team_management", "reports", "budget"],
        "Designer": ["design_tools", "asset_library", "feedback_system"],
        "Analyst": ["analytics_platform", "database_read", "reporting_tools"]
    }

    permissions = role_permissions.get(user_data["role"], ["basic_access"])

    print(f"   ✅ Permissions configured: {', '.join(permissions)}")

    return {
        "granted_permissions": permissions,
        "workspace_access": workspace_path,
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

    print(f"\n🔗 [{context.step_name}] Configuring integrations...")
    print(f"   Username: {username}")

    # Simular configuración de integraciones
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

    print(f"   ✅ Integrations configured: Slack, GitHub, Jira")

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
    tools = provision_tools["provisioned_tools"]

    print(f"\n📚 [{context.step_name}] Creating documentation...")
    print(f"   Role: {user_data['role']}")

    # Simular generación de documentación
    await asyncio.sleep(1.2)

    docs = {
        "welcome_guide": f"{workspace_path}/docs/welcome.pdf",
        "role_specific_guide": f"{workspace_path}/docs/{user_data['role'].lower()}_guide.pdf",
        "tools_quickstart": f"{workspace_path}/docs/tools_quickstart.pdf",
        "company_policies": f"{workspace_path}/docs/policies.pdf"
    }

    print(f"   ✅ Documentation created: {len(docs)} documents")

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
    account = create_user_account
    docs = create_documentation["documentation_files"]

    print(f"\n📧 [{context.step_name}] Sending welcome email...")
    print(f"   To: {user_data['email']}")

    # Simular envío de email
    await asyncio.sleep(1.0)

    email_content = {
        "subject": f"Welcome to the Company, {user_data['name']}!",
        "to": user_data["email"],
        "attachments": list(docs.values()),
        "includes": [
            "login_credentials",
            "first_steps_guide",
            "team_contacts",
            "onboarding_schedule"
        ]
    }

    print(f"   ✅ Welcome email sent with {len(email_content['includes'])} sections")

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

    print(f"\n💬 [{context.step_name}] Notifying team on Slack...")
    print(f"   Channel: {slack_config['channel']}")
    print(f"   New member: {user_data['name']}")

    # Simular notificación en Slack
    await asyncio.sleep(0.8)

    notification = {
        "channel": slack_config["channel"],
        "message": f"👋 Welcome {user_data['name']} to the {user_data['department']} team!",
        "role": user_data["role"],
        "start_date": datetime.now().strftime("%Y-%m-%d")
    }

    print(f"   ✅ Team notified in {slack_config['channel']}")

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

    print(f"\n📅 [{context.step_name}] Scheduling onboarding calls...")
    print(f"   Calendar: {calendar['url']}")

    # Simular creación de eventos
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

    print(f"   ✅ Scheduled {len(scheduled_calls)} onboarding calls")

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

    print(f"\n🎉 [{context.step_name}] Finalizing onboarding...")
    print(f"   User: {user_data['name']}")

    # Simular generación de reporte
    await asyncio.sleep(0.5)

    # Crear reporte completo
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
        "tools": provision_tools["provisioned_tools"],
        "permissions": setup_permissions["granted_permissions"],
        "integrations": list(configure_integrations["configured_integrations"].keys()),
        "documentation": len(create_documentation["documentation_files"]),
        "notifications": {
            "email_sent": send_welcome_email["email_sent"],
            "team_notified": notify_team["notification_sent"],
            "calls_scheduled": len(schedule_onboarding_calls["scheduled_calls"])
        },
        "onboarding_completed_by": admin_name,
        "completed_at": datetime.now().isoformat()
    }

    print(f"\n" + "=" * 70)
    print(f"✅ ONBOARDING COMPLETED SUCCESSFULLY!")
    print(f"=" * 70)
    print(f"\n📊 SUMMARY:")
    print(f"   User: {user_data['name']} ({user_data['email']})")
    print(f"   Role: {user_data['role']} | Department: {user_data['department']}")
    print(f"   Account ID: {create_user_account['account_id']}")
    print(f"   Username: {create_user_account['username']}")
    print(f"   Workspace: {setup_workspace['workspace_path']}")
    print(f"   Permissions: {len(setup_permissions['granted_permissions'])} granted")
    print(f"   Tools: {len(provision_tools['provisioned_tools'])} provisioned")
    print(f"   Integrations: {len(configure_integrations['configured_integrations'])} configured")
    print(f"   Documentation: {len(create_documentation['documentation_files'])} files created")
    print(f"   Onboarding calls: {len(schedule_onboarding_calls['scheduled_calls'])} scheduled")
    print(f"\n   Completed by: {admin_name}")
    print(f"   Execution ID: {context.execution_id}")
    print(f"=" * 70)

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
# MAIN - DEMO
# =============================================================================

async def main():
    """Ejecutar demo del workflow de onboarding."""

    print("\n" + "=" * 70)
    print("🎓 TUTORIAL 07: ENTERPRISE USER ONBOARDING")
    print("=" * 70)
    print("\nEste workflow demuestra:")
    print("  ✅ Workflow complejo con 12 steps")
    print("  ✅ 3 niveles de paralelismo")
    print("  ✅ Dependencias complejas entre steps")
    print("  ✅ Simulación de integraciones reales")
    print("  ✅ Manejo robusto de datos")
    print("\n" + "=" * 70)

    # Datos de entrada
    inputs = {
        "admin_id": "ADM-001",
        "admin_token": "valid-admin-token",
        "user_data": {
            "name": "Alex Martinez",
            "email": "alex.martinez@company.com",
            "department": "Engineering",
            "role": "Developer"
        }
    }

    print("\n📋 INPUT DATA:")
    print(f"   New User: {inputs['user_data']['name']}")
    print(f"   Email: {inputs['user_data']['email']}")
    print(f"   Department: {inputs['user_data']['department']}")
    print(f"   Role: {inputs['user_data']['role']}")
    print(f"   Initiated by: Admin {inputs['admin_id']}")
    print("\n" + "=" * 70)

    # Registrar tiempo de inicio
    start_time = datetime.now()
    print(f"\n⏱️  Workflow started at: {start_time.strftime('%H:%M:%S')}")

    # Ejecutar workflow
    result = await enterprise_onboarding_workflow.execute(inputs)

    # Calcular tiempo total
    end_time = datetime.now()
    duration = (end_time - start_time).total_seconds()

    print(f"\n⏱️  Workflow completed at: {end_time.strftime('%H:%M:%S')}")
    print(f"⚡️ Total duration: {duration:.2f} seconds")
    print(f"\n💡 Without parallelism this would take ~25 seconds!")
    print(f"💡 Parallelism saved ~{25 - duration:.1f} seconds!")

    print("\n" + "=" * 70)
    print("🎉 Tutorial 07 completed successfully!")
    print("=" * 70)
    print("\n📖 What you learned:")
    print("  • Complex workflow orchestration")
    print("  • Multi-level parallelism")
    print("  • Complex dependencies between steps")
    print("  • Real-world integration simulation")
    print("  • Error handling and validation")
    print("\n🚀 Next: Try modifying the workflow to add more features!")
    print("=" * 70)


if __name__ == "__main__":
    asyncio.run(main())

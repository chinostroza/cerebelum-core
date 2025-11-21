#!/usr/bin/env python3
"""
Tutorial 07: Enterprise Onboarding - EXECUTE WORKFLOW
======================================================

DESCRIPCIÓN:
    Cliente para ejecutar el workflow de onboarding empresarial.
    Envía solicitudes de ejecución a Core con los datos del nuevo usuario.

USO:
    python3 07_execute_workflow.py <name> <email> <department> <role>

EJEMPLOS:
    # Onboarding de un Developer
    python3 07_execute_workflow.py "Jane Doe" "jane.doe@company.com" "Engineering" "Developer"

    # Onboarding de un Manager
    python3 07_execute_workflow.py "John Smith" "john.smith@company.com" "Sales" "Manager"

    # Onboarding de un Designer
    python3 07_execute_workflow.py "Alice Wong" "alice.wong@company.com" "Design" "Designer"

    # Onboarding de un Analyst
    python3 07_execute_workflow.py "Bob Chen" "bob.chen@company.com" "Analytics" "Analyst"

ARQUITECTURA:
    Terminal 1: Core BEAM             (cd ../../ && mix run --no-halt)
    Terminal 2: Worker Server         (python3 07_distributed_server.py)
    Terminal 3: Execute Workflow      (python3 07_execute_workflow.py ...) ← ESTE ARCHIVO

REQUISITOS:
    - Core debe estar corriendo (Terminal 1)
    - Worker server debe estar corriendo (Terminal 2)
    - Workflow 'enterprise_onboarding_workflow' registrado en Core

NIVEL: 🔴 Avanzado
"""

import asyncio
import sys
from datetime import datetime
from cerebelum.distributed import DistributedExecutor


async def execute_onboarding(name: str, email: str, department: str, role: str):
    """
    Ejecutar workflow de onboarding con los datos del usuario.

    Args:
        name: Nombre completo del usuario
        email: Email corporativo
        department: Departamento (Engineering, Sales, Design, Analytics, etc.)
        role: Rol (Developer, Manager, Designer, Analyst, etc.)
    """

    print("\n" + "=" * 70)
    print("🎓 ENTERPRISE USER ONBOARDING - DISTRIBUTED EXECUTION")
    print("=" * 70)
    print()
    print("📤 Submitting onboarding workflow to Core...")
    print()
    print("📋 NEW USER DATA:")
    print(f"   Name: {name}")
    print(f"   Email: {email}")
    print(f"   Department: {department}")
    print(f"   Role: {role}")
    print()
    print("=" * 70)
    print()

    # Crear distributed executor
    executor = DistributedExecutor(
        core_url="localhost:9090",
        worker_id="python-onboarding-executor"
    )

    try:
        # Preparar inputs
        inputs = {
            "admin_id": "ADM-001",
            "admin_token": "valid-admin-token",
            "user_data": {
                "name": name,
                "email": email,
                "department": department,
                "role": role
            }
        }

        # Registrar tiempo de inicio
        start_time = datetime.now()
        print(f"⏱️  Execution started at: {start_time.strftime('%H:%M:%S')}")
        print()

        # Ejecutar workflow remotamente
        result = await executor.execute(
            workflow="enterprise_onboarding_workflow",  # Workflow ID registrado por server
            input_data=inputs
        )

        # Calcular duración
        end_time = datetime.now()
        duration = (end_time - start_time).total_seconds()

        print("=" * 70)
        print("✅ WORKFLOW SUBMITTED SUCCESSFULLY!")
        print("=" * 70)
        print()
        print("📊 EXECUTION INFO:")
        print(f"   Execution ID: {result.execution_id}")
        print(f"   Status: {result.status}")
        print(f"   Started at: {result.started_at}")
        print(f"   Submission time: {duration:.2f} seconds")
        print()
        print("💡 CHECK TERMINAL 2 (worker server) to see execution logs!")
        print("💡 The workflow is being processed by the distributed worker.")
        print()
        print("🎉 Workflow execution details:")
        print(f"   - User: {name}")
        print(f"   - Email: {email}")
        print(f"   - Department: {department}")
        print(f"   - Role: {role}")
        print()
        print("📋 The onboarding process includes:")
        print("   ✅ Authentication & validation")
        print("   ✅ Account & workspace creation")
        print("   ✅ Tool provisioning (Email, Calendar, Chat)")
        print("   ✅ Permissions & integrations setup")
        print("   ✅ Documentation generation")
        print("   ✅ Welcome email & team notifications")
        print("   ✅ Onboarding calls scheduling")
        print()
        print("=" * 70)

    except Exception as e:
        print("=" * 70)
        print(f"❌ ERROR: {type(e).__name__}: {e}")
        print("=" * 70)
        print()
        print("🔍 TROUBLESHOOTING:")
        print()
        print("1. ¿Core está corriendo?")
        print("   Terminal 1: cd ../../ && mix run --no-halt")
        print()
        print("2. ¿Worker server está corriendo?")
        print("   Terminal 2: python3 07_distributed_server.py")
        print()
        print("3. ¿El workflow está registrado?")
        print("   Check Terminal 2 for registration confirmation:")
        print("   ✅ Workflow 'enterprise_onboarding_workflow' blueprint submitted")
        print()
        print("=" * 70)
        raise
    finally:
        executor.close()


def print_usage():
    """Imprimir instrucciones de uso."""
    print()
    print("=" * 70)
    print("❌ ERROR: Invalid arguments")
    print("=" * 70)
    print()
    print("USAGE:")
    print("  python3 07_execute_workflow.py <name> <email> <department> <role>")
    print()
    print("EXAMPLES:")
    print()
    print("  # Developer in Engineering")
    print('  python3 07_execute_workflow.py "Jane Doe" "jane.doe@company.com" "Engineering" "Developer"')
    print()
    print("  # Manager in Sales")
    print('  python3 07_execute_workflow.py "John Smith" "john.smith@company.com" "Sales" "Manager"')
    print()
    print("  # Designer in Design")
    print('  python3 07_execute_workflow.py "Alice Wong" "alice.wong@company.com" "Design" "Designer"')
    print()
    print("  # Analyst in Analytics")
    print('  python3 07_execute_workflow.py "Bob Chen" "bob.chen@company.com" "Analytics" "Analyst"')
    print()
    print("AVAILABLE DEPARTMENTS:")
    print("  • Engineering")
    print("  • Sales")
    print("  • Design")
    print("  • Analytics")
    print("  • Marketing")
    print("  • Operations")
    print()
    print("AVAILABLE ROLES:")
    print("  • Developer    (Engineering)")
    print("  • Manager      (Any department)")
    print("  • Designer     (Design)")
    print("  • Analyst      (Analytics)")
    print()
    print("=" * 70)
    print()


async def main():
    """Main entry point."""

    # Validar argumentos
    if len(sys.argv) != 5:
        print_usage()
        sys.exit(1)

    # Extraer argumentos
    name = sys.argv[1]
    email = sys.argv[2]
    department = sys.argv[3]
    role = sys.argv[4]

    # Validar email básico
    if "@" not in email or "." not in email:
        print()
        print("❌ ERROR: Invalid email format")
        print(f"   Provided: {email}")
        print(f"   Expected: user@company.com")
        print()
        sys.exit(1)

    # Ejecutar onboarding
    await execute_onboarding(name, email, department, role)


if __name__ == "__main__":
    asyncio.run(main())

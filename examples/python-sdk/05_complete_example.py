#!/usr/bin/env python3
"""
TUTORIAL 05: Complete Example - E-commerce Order Processing

¿Qué aprenderás?
✅ Workflow completo real (8 steps)
✅ Aplicar todo lo aprendido (dependencies, parallel, errors)
✅ Ejecución paralela en workflow real
✅ Flujo de datos complejo

Tiempo: 15 minutos
Dificultad: 🟡 Intermedio

Requisito: Haber completado tutorials 01-04

Escenario: Sistema de procesamiento de pedidos e-commerce
- Autenticación de usuario
- Validación de inventario
- Cálculo de impuestos
- Procesamiento de pago
- Notificación y actualización de estado (PARALELO)
- Finalización del pedido
"""

import asyncio
from cerebelum import step, workflow, Context


# =============================================================================
# STEP DEFINITIONS - Clean, Pythonic, No Boilerplate!
# =============================================================================

@step
async def authenticate_user(context: Context, inputs: dict):
    """Authenticate user with API key.

    Args:
        context: Execution context
        inputs: {"api_key": str, "order_id": str}

    Returns:
        {"user_id": int, "authenticated": bool}

    Raises:
        ValueError: If API key is invalid
    """
    print(f"[{context.step_name}] Authenticating user...")

    api_key = inputs.get("api_key")

    # ✅ NEW: Use native exceptions instead of returning {"error": ...}
    if api_key != "valid_api_key_123":
        print(f"  ✗ Authentication failed")
        raise ValueError("invalid_api_key")

    print(f"  ✓ User authenticated")
    # ✅ NEW: No need for {"ok": ...}, just return the data!
    return {"user_id": 42, "authenticated": True}


@step
async def fetch_order(context: Context, authenticate_user: dict, inputs: dict):
    """Fetch order details from database.

    Args:
        context: Execution context
        authenticate_user: Authentication result
        inputs: {"order_id": str}

    Returns:
        Order data dict
    """
    print(f"[{context.step_name}] Fetching order...")

    # Check authentication
    if not authenticate_user.get("authenticated"):
        raise ValueError("not_authenticated")

    order_id = inputs.get("order_id")

    # Simulate database fetch
    order_data = {
        "order_id": order_id,
        "user_id": authenticate_user["user_id"],
        "items": [
            {"sku": "LAPTOP-001", "quantity": 1, "price": 999.99},
            {"sku": "MOUSE-042", "quantity": 2, "price": 29.99},
        ],
        "total": 1059.97,
        "status": "pending",
    }

    print(f"  ✓ Order {order_id} fetched: ${order_data['total']}")
    # ✅ NEW: Auto-wrapped to {"ok": order_data}
    return order_data


@step
async def validate_inventory(context: Context, fetch_order: dict):
    """Validate that all items are in stock.

    Args:
        context: Execution context
        fetch_order: Order data

    Returns:
        {"available": bool, "order": dict}
    """
    print(f"[{context.step_name}] Validating inventory...")

    order = fetch_order

    # Simulate inventory check
    for item in order["items"]:
        print(f"  - Checking {item['sku']}: {item['quantity']} units... ✓")

    # All items available
    print(f"  ✓ All items in stock")
    return {"available": True, "order": order}


@step
async def calculate_tax(context: Context, validate_inventory: dict):
    """Calculate tax for the order.

    Args:
        context: Execution context
        validate_inventory: Validation result

    Returns:
        {"tax": float, "order": dict}
    """
    print(f"[{context.step_name}] Calculating tax...")

    order = validate_inventory["order"]
    subtotal = order["total"]

    # Calculate tax (10%)
    tax = round(subtotal * 0.10, 2)

    print(f"  Subtotal: ${subtotal}")
    print(f"  Tax (10%): ${tax}")
    print(f"  ✓ Total: ${subtotal + tax}")

    return {"tax": tax, "order": order}


@step
async def process_payment(context: Context, calculate_tax: dict):
    """Process payment for the order.

    Args:
        context: Execution context
        calculate_tax: Tax calculation result

    Returns:
        {"payment_id": str, "status": str, "amount": float}
    """
    print(f"[{context.step_name}] Processing payment...")

    order = calculate_tax["order"]
    tax = calculate_tax["tax"]
    total_amount = order["total"] + tax

    # Simulate payment processing
    payment_id = f"PAY-{context.execution_id[:8].upper()}"

    print(f"  Charging ${total_amount}...")
    print(f"  ✓ Payment {payment_id} successful")

    return {
        "payment_id": payment_id,
        "status": "completed",
        "amount": total_amount,
        "order_id": order["order_id"]
    }


# ✅ NEW: These two steps can run in PARALLEL!
# They both depend on process_payment and fetch_order, but not on each other

@step
async def send_confirmation_email(context: Context, process_payment: dict, fetch_order: dict):
    """Send order confirmation email to user (runs in parallel).

    Args:
        context: Execution context
        process_payment: Payment result
        fetch_order: Order data

    Returns:
        {"email_sent": bool, "recipient": str}
    """
    print(f"[{context.step_name}] 📧 Sending confirmation email (PARALLEL)...")

    order = fetch_order
    payment = process_payment

    # Simulate email sending
    recipient = f"user_{order['user_id']}@example.com"
    print(f"  To: {recipient}")
    print(f"  Subject: Order {order['order_id']} Confirmed")
    print(f"  Payment ID: {payment['payment_id']}")
    print(f"  ✓ Email sent")

    return {"email_sent": True, "recipient": recipient}


@step
async def update_order_status(context: Context, process_payment: dict, fetch_order: dict):
    """Update order status in database (runs in parallel).

    Args:
        context: Execution context
        process_payment: Payment result
        fetch_order: Order data

    Returns:
        {"order_id": str, "status": str}
    """
    print(f"[{context.step_name}] 💾 Updating order status (PARALLEL)...")

    order = fetch_order
    order_id = order["order_id"]

    # Simulate database update
    print(f"  Order {order_id}: pending -> confirmed")
    print(f"  ✓ Order status updated")

    return {"order_id": order_id, "status": "confirmed"}


@step
async def finalize_order(
    context: Context,
    send_confirmation_email: dict,
    update_order_status: dict,
    process_payment: dict
):
    """Finalize order after parallel tasks complete.

    Args:
        context: Execution context
        send_confirmation_email: Email result
        update_order_status: Status update result
        process_payment: Payment result

    Returns:
        Final order summary
    """
    print(f"[{context.step_name}] Finalizing order...")

    summary = {
        "order_id": update_order_status["order_id"],
        "status": update_order_status["status"],
        "payment_id": process_payment["payment_id"],
        "amount_charged": process_payment["amount"],
        "email_sent_to": send_confirmation_email["recipient"],
        "completed": True
    }

    print(f"  ✓ Order {summary['order_id']} finalized")

    return summary


# =============================================================================
# WORKFLOW DEFINITION - With Explicit Parallelism!
# =============================================================================

@workflow
def ecommerce_order_workflow(wf):
    """E-commerce order processing workflow.

    ✅ NEW: This workflow demonstrates explicit parallelism!

    Timeline:
    1. authenticate_user (sequential)
    2. fetch_order (sequential)
    3. validate_inventory (sequential)
    4. calculate_tax (sequential)
    5. process_payment (sequential)
    6. [send_confirmation_email, update_order_status] (🔥 PARALLEL!)
    7. finalize_order (sequential - waits for both parallel tasks)
    """
    # ✅ NEW: List syntax makes parallelism explicit and clear!
    wf.timeline(
        authenticate_user >>
        fetch_order >>
        validate_inventory >>
        calculate_tax >>
        process_payment >>
        [send_confirmation_email, update_order_status] >>  # 🔥 PARALLEL!
        finalize_order
    )


# =============================================================================
# MAIN EXECUTION
# =============================================================================

async def main():
    """Execute the complete workflow."""

    print("=" * 70)
    print("CEREBELUM DSL v1.2 - COMPLETE END-TO-END EXAMPLE")
    print("E-commerce Order Processing Workflow")
    print("=" * 70)
    print()

    print("✨ NEW FEATURES DEMONSTRATED:")
    print("  ✅ Auto-wrapping (no manual {'ok': ...})")
    print("  ✅ Native exceptions (no manual {'error': ...})")
    print("  ✅ Parallel syntax [step_a, step_b]")
    print("  ✅ ~40% less boilerplate code")
    print()

    # Input data
    inputs = {
        "api_key": "valid_api_key_123",
        "order_id": "ORD-2024-001",
    }

    print(f"Input:")
    print(f"  - API Key: {inputs['api_key']}")
    print(f"  - Order ID: {inputs['order_id']}")
    print()

    print("=" * 70)
    print("WORKFLOW EXECUTION")
    print("=" * 70)
    print()

    try:
        # Execute workflow (uses DSLLocalExecutor by default)
        result = await ecommerce_order_workflow.execute(inputs)

        print()
        print("=" * 70)
        print("EXECUTION RESULT")
        print("=" * 70)
        print(f"✅ Workflow completed successfully!")
        print(f"  - Execution ID: {result.execution_id}")
        print(f"  - Status: {result.status}")
        print(f"  - Started: {result.started_at}")
        print(f"  - Completed: {result.completed_at}")
        print()
        print(f"📦 Order Summary:")
        output = result.output["ok"]
        print(f"  - Order ID: {output['order_id']}")
        print(f"  - Payment ID: {output['payment_id']}")
        print(f"  - Amount: ${output['amount_charged']}")
        print(f"  - Status: {output['status']}")
        print(f"  - Email sent to: {output['email_sent_to']}")
        print(f"  - Completed: {output['completed']}")
        print()

    except Exception as e:
        print()
        print("=" * 70)
        print("EXECUTION FAILED")
        print("=" * 70)
        print(f"❌ Error: {type(e).__name__}")
        print(f"  {str(e)}")
        print()


if __name__ == "__main__":
    # Run the complete example
    asyncio.run(main())

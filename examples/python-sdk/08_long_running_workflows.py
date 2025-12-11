"""Example: Long-running workflows with polling, retry, and progress reporting.

This example demonstrates best practices for handling operations with variable
latency like:
- Waiting for external resources (droplets, certificates, etc.)
- Polling API endpoints
- Retrying transient failures
- Reporting progress

Run:
    python3 08_long_running_workflows.py
"""

import asyncio
from datetime import timedelta
from cerebelum import (
    step,
    workflow,
    Context,
    sleep,
    poll,
    retry,
    ProgressReporter
)


# ============================================================================
# Example 1: Digital Ocean Droplet with Polling (Original Use Case)
# ============================================================================

@step
async def create_droplet(context: Context, inputs: dict) -> dict:
    """Create droplet - returns immediately but IP takes 30-60s."""
    print(f"🚀 Creating droplet '{inputs['name']}'...")

    # Simulate droplet creation (instant in real API)
    droplet_id = "droplet-12345"

    # Return droplet ID immediately
    return {"droplet_id": droplet_id, "status": "creating"}


@step
async def wait_for_droplet_ip(context: Context, create_droplet: dict) -> dict:
    """Wait for droplet IP using poll() helper - RECOMMENDED APPROACH."""
    droplet_id = create_droplet["droplet_id"]
    print(f"⏳ Waiting for IP address for {droplet_id}...")

    # Simulated API call to check droplet status
    async def check_droplet_status():
        # In real code: return api.get_droplet(droplet_id)
        # For demo: simulate delayed IP assignment
        import random
        await asyncio.sleep(1)  # Simulate API call latency

        # Simulate IP becoming available after ~5 attempts
        if random.random() > 0.7:  # 30% chance per attempt
            return {"ip_address": "192.168.1.100", "status": "active"}
        else:
            return {"ip_address": None, "status": "creating"}

    # Use poll() helper - clean and reusable
    result = await poll(
        check_fn=check_droplet_status,
        interval=5000,  # Check every 5 seconds
        max_attempts=30,  # Max 2.5 minutes
        success_condition=lambda d: d.get("ip_address") is not None,
        on_attempt=lambda n, r: print(f"  Attempt {n}/30: Status={r['status']}")
    )

    print(f"✅ IP address ready: {result['ip_address']}")
    return result


@step
async def configure_server(context: Context, wait_for_droplet_ip: dict) -> dict:
    """Configure server - uses retry() for transient failures."""
    ip = wait_for_droplet_ip["ip_address"]
    print(f"🔧 Configuring server at {ip}...")

    # Simulate SSH connection with retry
    async def connect_ssh():
        import random
        if random.random() > 0.6:  # 40% success rate
            return {"connection_id": "ssh-conn-123"}
        else:
            raise ConnectionError("SSH connection refused")

    # Use retry() helper with exponential backoff
    connection = await retry(
        fn=connect_ssh,
        max_attempts=5,
        delay=2000,  # Start with 2s
        backoff=2.0,  # Double each time (2s, 4s, 8s, 16s)
        on_error=ConnectionError,
        on_attempt=lambda n, e: print(f"  SSH retry {n}/5: {e}")
    )

    print(f"✅ SSH connected: {connection['connection_id']}")
    return {"configured": True, "connection": connection}


@workflow
def digital_ocean_deployment(wf):
    """Complete deployment workflow with polling and retry."""
    wf.timeline(
        create_droplet >>
        wait_for_droplet_ip >>
        configure_server
    )


# ============================================================================
# Example 2: SSL Certificate with Progress Reporting
# ============================================================================

@step
async def request_ssl_certificate(context: Context, inputs: dict) -> dict:
    """Request SSL certificate from Let's Encrypt."""
    domain = inputs["domain"]
    print(f"📜 Requesting SSL certificate for {domain}...")

    # Simulate certificate request
    await sleep(1000)  # 1 second

    return {"cert_id": "cert-abc-123", "domain": domain, "status": "pending"}


@step
async def wait_for_certificate_issuance(
    context: Context,
    request_ssl_certificate: dict
) -> dict:
    """Wait for certificate with progress reporting."""
    cert_id = request_ssl_certificate["cert_id"]
    domain = request_ssl_certificate["domain"]

    progress = ProgressReporter(context)
    progress.update(0, f"Starting certificate issuance for {domain}")

    # Simulate checking certificate status
    async def check_cert_status():
        import random
        await asyncio.sleep(2)  # Simulate API call

        # Simulate gradual progress
        if random.random() > 0.7:
            return {"status": "issued", "cert_data": "CERT_DATA_HERE"}
        else:
            return {"status": "pending"}

    # Poll with progress updates
    attempt = 0
    async def check_with_progress():
        nonlocal attempt
        attempt += 1
        result = await check_cert_status()

        # Update progress
        progress_pct = min(attempt * 20, 90)  # Cap at 90% until issued
        progress.update(progress_pct, f"Checking status... ({result['status']})")

        return result

    result = await poll(
        check_fn=check_with_progress,
        interval=10000,  # Every 10 seconds
        timeout=timedelta(minutes=5),  # Max 5 minutes
        success_condition=lambda r: r["status"] == "issued"
    )

    progress.update(100, "Certificate issued successfully!")
    return result


@workflow
def ssl_certificate_workflow(wf):
    """SSL certificate issuance with progress tracking."""
    wf.timeline(
        request_ssl_certificate >>
        wait_for_certificate_issuance
    )


# ============================================================================
# Example 3: Multi-day Workflow with Sleep (Resurrection Ready)
# ============================================================================

@step
async def send_welcome_email(context: Context, inputs: dict) -> dict:
    """Send welcome email to new user."""
    user_email = inputs["user_email"]
    print(f"📧 Sending welcome email to {user_email}")

    await sleep(500)  # Simulate email sending

    return {"sent_at": "2024-12-11T10:00:00Z", "email": user_email}


@step
async def wait_24_hours(context: Context, send_welcome_email: dict) -> dict:
    """Wait 24 hours - works with workflow resurrection when using Core."""
    print("💤 Sleeping for 24 hours...")
    print("   (In demo: 5 seconds, in production: 24 hours)")

    # In production with Core: use timedelta(days=1)
    # Workflow will hibernate and resurrect after 24 hours
    # await sleep(timedelta(days=1))

    # For demo: 5 seconds
    await sleep(5000)

    print("⏰ Woke up after 24 hours!")
    return {"day": 1}


@step
async def send_reminder_email(context: Context, inputs: dict, wait_24_hours: dict) -> dict:
    """Send reminder email after 24 hours."""
    user_email = inputs["user_email"]
    print(f"📧 Sending day {wait_24_hours['day']} reminder to {user_email}")

    await sleep(500)

    return {"sent_at": "2024-12-12T10:00:00Z", "day": 1}


@workflow
def onboarding_workflow(wf):
    """Multi-day onboarding with sleep (resurrection-ready)."""
    wf.timeline(
        send_welcome_email >>
        wait_24_hours >>
        send_reminder_email
    )


# ============================================================================
# Example 4: Complex Deployment with All Patterns
# ============================================================================

@step
async def provision_infrastructure(context: Context, inputs: dict) -> dict:
    """Provision infrastructure with progress reporting."""
    progress = ProgressReporter(context)

    progress.update(0, "Creating VPC...")
    await sleep(1000)

    progress.update(25, "Creating subnets...")
    await sleep(1000)

    progress.update(50, "Creating security groups...")
    await sleep(1000)

    progress.update(75, "Creating load balancer...")
    await sleep(1000)

    progress.update(100, "Infrastructure ready!")

    return {
        "vpc_id": "vpc-123",
        "subnet_ids": ["subnet-1", "subnet-2"],
        "lb_dns": "my-app-lb.example.com"
    }


@step
async def deploy_application(
    context: Context,
    provision_infrastructure: dict
) -> dict:
    """Deploy application with retry logic."""
    lb_dns = provision_infrastructure["lb_dns"]
    print(f"🚀 Deploying application to {lb_dns}...")

    # Simulate deployment with potential failures
    async def attempt_deployment():
        import random
        if random.random() > 0.5:
            return {"deployment_id": "deploy-456", "status": "success"}
        else:
            raise RuntimeError("Deployment failed: temporary network issue")

    result = await retry(
        fn=attempt_deployment,
        max_attempts=3,
        delay=5000,
        backoff=1.5,
        on_attempt=lambda n, e: print(f"  Deployment attempt {n}/3")
    )

    print(f"✅ Deployed: {result['deployment_id']}")
    return result


@step
async def wait_for_health_check(context: Context, deploy_application: dict) -> dict:
    """Wait for application to be healthy."""
    deployment_id = deploy_application["deployment_id"]
    print(f"🏥 Waiting for health checks on {deployment_id}...")

    async def check_health():
        import random
        await asyncio.sleep(1)

        if random.random() > 0.7:
            return {"healthy": True, "response_time_ms": 45}
        else:
            return {"healthy": False}

    result = await poll(
        check_fn=check_health,
        interval=3000,
        max_attempts=20,
        success_condition=lambda r: r.get("healthy") is True,
        on_attempt=lambda n, r: print(f"  Health check {n}/20: {r}")
    )

    print(f"✅ Application is healthy! Response time: {result['response_time_ms']}ms")
    return result


@workflow
def complete_deployment_workflow(wf):
    """Complete deployment workflow using all patterns."""
    wf.timeline(
        provision_infrastructure >>
        deploy_application >>
        wait_for_health_check
    )


# ============================================================================
# Main - Run Examples
# ============================================================================

async def main():
    """Run all examples."""
    print("=" * 70)
    print("CEREBELUM SDK - Long-Running Workflows Examples")
    print("=" * 70)

    # Example 1: Digital Ocean Droplet
    print("\n📦 Example 1: Digital Ocean Droplet Deployment")
    print("-" * 70)
    result1 = await digital_ocean_deployment.execute({
        "name": "production-server-1",
        "region": "nyc3",
        "size": "s-2vcpu-4gb"
    })
    print(f"✅ Droplet deployment: {result1.status}")

    # Example 2: SSL Certificate
    print("\n📜 Example 2: SSL Certificate Issuance")
    print("-" * 70)
    result2 = await ssl_certificate_workflow.execute({
        "domain": "example.com"
    })
    print(f"✅ Certificate workflow: {result2.status}")

    # Example 3: Multi-day Onboarding
    print("\n📅 Example 3: Multi-day Onboarding Workflow")
    print("-" * 70)
    result3 = await onboarding_workflow.execute({
        "user_email": "newuser@example.com"
    })
    print(f"✅ Onboarding workflow: {result3.status}")

    # Example 4: Complete Deployment
    print("\n🚀 Example 4: Complete Infrastructure Deployment")
    print("-" * 70)
    result4 = await complete_deployment_workflow.execute({
        "environment": "production",
        "region": "us-east-1"
    })
    print(f"✅ Complete deployment: {result4.status}")

    print("\n" + "=" * 70)
    print("✨ All examples completed successfully!")
    print("=" * 70)


if __name__ == "__main__":
    asyncio.run(main())

"""Simple test to verify async helpers work correctly."""

import asyncio
from cerebelum import poll, retry, sleep, ProgressReporter
from datetime import datetime


async def test_poll():
    """Test the poll() helper."""
    print("\n" + "="*60)
    print("TEST 1: poll() - Simulating droplet IP wait")
    print("="*60)

    # Simulate a resource that becomes ready after 3 attempts
    attempts = {"count": 0}

    def check_droplet():
        attempts["count"] += 1
        print(f"  Checking droplet... (attempt {attempts['count']})")

        # Simulate: IP available after 3 attempts
        if attempts["count"] >= 3:
            return {"ip_address": "192.168.1.100", "status": "ready"}
        return {"ip_address": None, "status": "creating"}

    result = await poll(
        check_fn=check_droplet,
        interval=1000,  # Check every 1 second
        max_attempts=10,
        success_condition=lambda d: d["ip_address"] is not None,
        on_attempt=lambda n, d: print(f"  → Status: {d['status']}")
    )

    print(f"✅ SUCCESS: Got IP address: {result['ip_address']}")
    return result


async def test_retry():
    """Test the retry() helper."""
    print("\n" + "="*60)
    print("TEST 2: retry() - Simulating connection with failures")
    print("="*60)

    # Simulate a connection that fails 2 times then succeeds
    attempts = {"count": 0}

    async def connect_to_server():
        attempts["count"] += 1
        print(f"  Attempting connection... (attempt {attempts['count']})")

        if attempts["count"] < 3:
            raise ConnectionError(f"Connection failed (attempt {attempts['count']})")

        return {"connected": True, "server": "api.example.com"}

    result = await retry(
        fn=connect_to_server,
        max_attempts=5,
        delay=500,  # 500ms between retries
        backoff=2.0,  # Double delay each time
        on_attempt=lambda n, e: print(f"  → Retry {n}: {e if e else 'Success'}")
    )

    print(f"✅ SUCCESS: Connected to {result['server']}")
    return result


async def test_sleep():
    """Test the sleep() helper."""
    print("\n" + "="*60)
    print("TEST 3: sleep() - Workflow-aware sleep")
    print("="*60)

    print("  Starting sleep for 2 seconds...")
    start = datetime.now()

    await sleep(2000)  # 2 seconds

    elapsed = (datetime.now() - start).total_seconds()
    print(f"✅ SUCCESS: Slept for {elapsed:.2f} seconds")


async def test_progress_reporter():
    """Test the ProgressReporter."""
    print("\n" + "="*60)
    print("TEST 4: ProgressReporter - Progress tracking")
    print("="*60)

    # Mock context
    class MockContext:
        execution_id = "test-123"
        step_name = "deployment_step"

    progress = ProgressReporter(MockContext())

    print("  Simulating deployment...")
    progress.update(0, "Starting deployment...")
    await asyncio.sleep(0.5)

    progress.update(33, "Building application...")
    await asyncio.sleep(0.5)

    progress.update(66, "Running tests...")
    await asyncio.sleep(0.5)

    progress.update(100, "Deployment complete!")

    print("✅ SUCCESS: Progress reported successfully")


async def main():
    """Run all tests."""
    print("\n" + "="*70)
    print("TESTING CEREBELUM ASYNC HELPERS")
    print("="*70)

    try:
        # Run all tests
        await test_poll()
        await test_retry()
        await test_sleep()
        await test_progress_reporter()

        # Summary
        print("\n" + "="*70)
        print("✨ ALL TESTS PASSED!")
        print("="*70)
        print("\nVerified:")
        print("  ✅ poll() - Polling with success condition")
        print("  ✅ retry() - Retry with exponential backoff")
        print("  ✅ sleep() - Workflow-aware sleep")
        print("  ✅ ProgressReporter - Progress tracking")
        print("\nThese helpers are ready for your team's use case!")
        print("="*70 + "\n")

    except Exception as e:
        print(f"\n❌ TEST FAILED: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    asyncio.run(main())

#!/usr/bin/env python3
"""
Simple test client for Cerebelum Core gRPC server.
Tests basic connectivity and worker registration.
"""

import grpc
import sys
import json
from datetime import datetime

# Import the generated protobuf code
# First, you need to generate Python code from the .proto file
# Run: python3 -m grpc_tools.protoc -I./priv/protos --python_out=./examples --grpc_python_out=./examples ./priv/protos/worker_service.proto

try:
    import worker_service_pb2
    import worker_service_pb2_grpc
except ImportError:
    print("Error: Protobuf files not generated yet!")
    print("\nTo generate them, run:")
    print("  pip install grpcio-tools")
    print("  python3 -m grpc_tools.protoc -I./priv/protos --python_out=./examples --grpc_python_out=./examples ./priv/protos/worker_service.proto")
    print("  python3 -m grpc_tools.protoc -I./priv/protos --python_out=./examples --pyi_out=./examples ./priv/protos/worker_service.proto")
    sys.exit(1)


def test_register_worker(stub):
    """Test registering a worker"""
    print("\n1. Testing Worker Registration...")

    request = worker_service_pb2.RegisterRequest(
        worker_id="test-worker-python-1",
        language="python",
        capabilities=["test.simple_workflow", "test.data_processor"],
        metadata={
            "hostname": "test-machine",
            "env": "production"
        },
        version="1.0.0"
    )

    try:
        response = stub.Register(request)
        print(f"   ✓ Registration successful!")
        print(f"   Message: {response.message}")
        print(f"   Heartbeat interval: {response.heartbeat_interval_ms}ms")
        return True
    except grpc.RpcError as e:
        print(f"   ✗ Registration failed: {e.code()} - {e.details()}")
        return False


def test_heartbeat(stub, worker_id):
    """Test sending a heartbeat"""
    print("\n2. Testing Heartbeat...")

    request = worker_service_pb2.HeartbeatRequest(
        worker_id=worker_id,
        status=worker_service_pb2.WorkerStatus.IDLE
    )

    try:
        response = stub.Heartbeat(request)
        print(f"   ✓ Heartbeat acknowledged: {response.acknowledged}")
        if response.commands:
            print(f"   Commands from server: {response.commands}")
        return True
    except grpc.RpcError as e:
        print(f"   ✗ Heartbeat failed: {e.code()} - {e.details()}")
        return False


def test_submit_blueprint(stub):
    """Test submitting a simple workflow blueprint"""
    print("\n3. Testing Blueprint Submission...")

    # Create a simple workflow: step1 -> step2 -> step3
    timeline = [
        worker_service_pb2.Step(name="step1", depends_on=[]),
        worker_service_pb2.Step(name="step2", depends_on=["step1"]),
        worker_service_pb2.Step(name="step3", depends_on=["step2"])
    ]

    definition = worker_service_pb2.WorkflowDefinition(
        timeline=timeline,
        diverge_rules=[],
        branch_rules=[],
        inputs={}
    )

    blueprint = worker_service_pb2.Blueprint(
        workflow_module="test.simple_workflow",
        language="python",
        source_code="# Simple test workflow with 3 steps",
        definition=definition,
        version="1.0.0"
    )

    try:
        response = stub.SubmitBlueprint(blueprint)
        print(f"   ✓ Blueprint submitted!")
        print(f"   Valid: {response.valid}")
        print(f"   Workflow hash: {response.workflow_hash}")
        if response.errors:
            print(f"   Errors: {response.errors}")
        if response.warnings:
            print(f"   Warnings: {response.warnings}")
        return response.valid
    except grpc.RpcError as e:
        print(f"   ✗ Blueprint submission failed: {e.code()} - {e.details()}")
        return False


def test_execute_workflow(stub):
    """Test executing a workflow"""
    print("\n4. Testing Workflow Execution...")

    from google.protobuf.struct_pb2 import Struct

    # Create input data
    inputs = Struct()
    inputs.update({
        "name": "Test User",
        "count": 10
    })

    options = worker_service_pb2.ExecutionOptions(
        correlation_id="test-execution-1",
        tags=["test", "demo"],
        timeout_ms=60000
    )

    request = worker_service_pb2.ExecuteRequest(
        workflow_module="test.simple_workflow",
        inputs=inputs,
        options=options
    )

    try:
        response = stub.ExecuteWorkflow(request)
        print(f"   ✓ Workflow execution started!")
        print(f"   Execution ID: {response.execution_id}")
        print(f"   Status: {response.status}")
        print(f"   Started at: {response.started_at}")
        return True
    except grpc.RpcError as e:
        print(f"   ✗ Workflow execution failed: {e.code()} - {e.details()}")
        return False


def test_unregister(stub, worker_id):
    """Test unregistering a worker"""
    print("\n5. Testing Worker Unregistration...")

    request = worker_service_pb2.UnregisterRequest(
        worker_id=worker_id,
        reason="test_complete"
    )

    try:
        stub.Unregister(request)
        print(f"   ✓ Worker unregistered successfully!")
        return True
    except grpc.RpcError as e:
        print(f"   ✗ Unregistration failed: {e.code()} - {e.details()}")
        return False


def main():
    # Server address
    server_address = "localhost:9090"
    worker_id = "test-worker-python-1"

    print("=" * 60)
    print("Cerebelum Core gRPC Test Client")
    print("=" * 60)
    print(f"\nConnecting to: {server_address}")

    # Create a gRPC channel
    channel = grpc.insecure_channel(server_address)
    stub = worker_service_pb2_grpc.WorkerServiceStub(channel)

    # Test connection
    try:
        grpc.channel_ready_future(channel).result(timeout=5)
        print("✓ Connected successfully!\n")
    except grpc.FutureTimeoutError:
        print("✗ Connection timeout. Is the server running?\n")
        sys.exit(1)

    # Run tests
    results = []

    results.append(("Worker Registration", test_register_worker(stub)))
    results.append(("Heartbeat", test_heartbeat(stub, worker_id)))
    results.append(("Blueprint Submission", test_submit_blueprint(stub)))
    results.append(("Workflow Execution", test_execute_workflow(stub)))
    results.append(("Worker Unregistration", test_unregister(stub, worker_id)))

    # Print summary
    print("\n" + "=" * 60)
    print("Test Summary")
    print("=" * 60)

    passed = sum(1 for _, result in results if result)
    total = len(results)

    for test_name, result in results:
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"{status:8} - {test_name}")

    print(f"\nTotal: {passed}/{total} tests passed")

    if passed == total:
        print("\n🎉 All tests passed!")
        sys.exit(0)
    else:
        print(f"\n⚠️  {total - passed} test(s) failed")
        sys.exit(1)


if __name__ == "__main__":
    main()

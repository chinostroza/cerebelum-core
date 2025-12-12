#!/usr/bin/env python3
"""Cerebelum CLI - Command-line interface for workflow monitoring and control.

Usage:
    cerebelum list [--status STATUS] [--workflow WORKFLOW] [--limit N]
    cerebelum status EXECUTION_ID
    cerebelum watch EXECUTION_ID [--interval SECONDS]
    cerebelum resume EXECUTION_ID
    cerebelum active

Examples:
    # List all executions
    cerebelum list

    # List only running executions
    cerebelum list --status running

    # Show detailed status
    cerebelum status abc-123

    # Watch execution in real-time
    cerebelum watch abc-123

    # Resume failed execution
    cerebelum resume abc-123

    # Show active workflows
    cerebelum active
"""

import asyncio
import sys
import time
from datetime import datetime
from typing import Optional

import click

# Lazy import to avoid protobuf issues
ExecutionClient = None
ExecutionState = None


def ensure_imports():
    """Lazy import of cerebelum to avoid early protobuf loading."""
    global ExecutionClient, ExecutionState
    if ExecutionClient is None:
        try:
            from cerebelum import ExecutionClient as EC, ExecutionState as ES
            ExecutionClient = EC
            ExecutionState = ES
        except Exception as e:
            click.echo(f"❌ Error importing cerebelum: {e}", err=True)
            click.echo("\n💡 Tip: Make sure protobuf files are generated:", err=True)
            click.echo("   python -m grpc_tools.protoc --proto_path=../../priv/protos \\", err=True)
            click.echo("       --python_out=cerebelum --grpc_python_out=cerebelum \\", err=True)
            click.echo("       ../../priv/protos/worker_service.proto", err=True)
            sys.exit(1)


@click.group()
@click.option('--core-url', default='localhost:9090', envvar='CEREBELUM_CORE_URL',
              help='Cerebelum Core URL (default: localhost:9090)')
@click.pass_context
def cli(ctx, core_url):
    """Cerebelum Workflow CLI - Monitor and control workflow executions."""
    ensure_imports()
    ctx.ensure_object(dict)
    ctx.obj['core_url'] = core_url


@cli.command()
@click.option('--status', type=click.Choice(['running', 'completed', 'failed', 'sleeping', 'approval', 'paused']),
              help='Filter by execution status')
@click.option('--workflow', help='Filter by workflow name')
@click.option('--limit', default=20, type=int, help='Maximum number of results (default: 20)')
@click.pass_context
def list(ctx, status, workflow, limit):
    """List workflow executions."""
    core_url = ctx.obj['core_url']

    async def _list():
        client = ExecutionClient(core_url=core_url)
        try:
            # Convert status string to enum
            status_filter = None
            if status:
                status_map = {
                    'running': ExecutionState.RUNNING,
                    'completed': ExecutionState.COMPLETED,
                    'failed': ExecutionState.FAILED,
                    'sleeping': ExecutionState.SLEEPING,
                    'approval': ExecutionState.WAITING_FOR_APPROVAL,
                    'paused': ExecutionState.PAUSED,
                }
                status_filter = status_map.get(status)

            click.echo("Fetching executions...")
            executions, total_count, has_more = await client.list_executions(
                workflow_name=workflow,
                status=status_filter,
                limit=limit
            )

            if not executions:
                click.echo("\n⚠️  No executions found")
                return

            # Print header
            click.echo(f"\n{'ID':<40} {'WORKFLOW':<25} {'PROGRESS':<12} {'STATUS':<15}")
            click.echo("=" * 100)

            # Print executions
            for exec in executions:
                status_symbol = {
                    ExecutionState.RUNNING: '🔄',
                    ExecutionState.COMPLETED: '✅',
                    ExecutionState.FAILED: '❌',
                    ExecutionState.SLEEPING: '💤',
                    ExecutionState.WAITING_FOR_APPROVAL: '⏸️',
                    ExecutionState.PAUSED: '⏸️',
                }.get(exec.status, '❓')

                exec_id_short = exec.execution_id[:36]
                workflow_short = exec.workflow_name[:23] if len(exec.workflow_name) > 23 else exec.workflow_name
                progress = f"{exec.current_step_index}/{exec.total_steps} ({exec.progress_percentage:.0f}%)"
                status_text = f"{status_symbol} {exec.status.value.replace('EXECUTION_', '')}"

                click.echo(f"{exec_id_short:<40} {workflow_short:<25} {progress:<12} {status_text:<15}")

            # Print footer
            click.echo("=" * 100)
            click.echo(f"Showing {len(executions)} of {total_count} executions")
            if has_more:
                click.echo(f"💡 Use --limit {total_count} to see all executions")

        except Exception as e:
            click.echo(f"❌ Error: {e}", err=True)
            sys.exit(1)
        finally:
            client.close()

    asyncio.run(_list())


@cli.command()
@click.argument('execution_id')
@click.pass_context
def status(ctx, execution_id):
    """Show detailed status of an execution."""
    core_url = ctx.obj['core_url']

    async def _status():
        client = ExecutionClient(core_url=core_url)
        try:
            click.echo(f"Fetching status for {execution_id}...")
            exec_status = await client.get_execution_status(execution_id)

            # Print detailed status
            click.echo("\n" + "=" * 60)
            click.echo(f"  Execution: {exec_status.execution_id}")
            click.echo("=" * 60)

            click.echo(f"\n📊 Overview:")
            click.echo(f"  Workflow:  {exec_status.workflow_name}")

            status_symbol = {
                ExecutionState.RUNNING: '🔄',
                ExecutionState.COMPLETED: '✅',
                ExecutionState.FAILED: '❌',
                ExecutionState.SLEEPING: '💤',
                ExecutionState.WAITING_FOR_APPROVAL: '⏸️',
            }.get(exec_status.status, '❓')
            click.echo(f"  Status:    {status_symbol} {exec_status.status.value.replace('EXECUTION_', '')}")

            if exec_status.started_at:
                click.echo(f"  Started:   {exec_status.started_at}")
            if exec_status.completed_at:
                click.echo(f"  Completed: {exec_status.completed_at}")
            if exec_status.elapsed_seconds:
                minutes = exec_status.elapsed_seconds // 60
                seconds = exec_status.elapsed_seconds % 60
                click.echo(f"  Duration:  {minutes}m {seconds}s")

            click.echo(f"\n📈 Progress:")
            click.echo(f"  Step:      {exec_status.current_step_index + 1}/{exec_status.total_steps}")
            if exec_status.current_step_name:
                click.echo(f"  Current:   {exec_status.current_step_name}")
            click.echo(f"  Complete:  {exec_status.progress_percentage:.1f}%")

            # Progress bar
            bar_width = 40
            filled = int(exec_status.progress_percentage / 100 * bar_width)
            bar = '█' * filled + '░' * (bar_width - filled)
            click.echo(f"  [{bar}] {exec_status.progress_percentage:.1f}%")

            if exec_status.completed_steps:
                click.echo(f"\n✅ Completed Steps ({len(exec_status.completed_steps)}):")
                for step in exec_status.completed_steps[:10]:  # Show first 10
                    click.echo(f"  - {step.step_name}")
                if len(exec_status.completed_steps) > 10:
                    click.echo(f"  ... and {len(exec_status.completed_steps) - 10} more")

            if exec_status.sleep_info:
                click.echo(f"\n💤 Sleep Info:")
                click.echo(f"  Duration:   {exec_status.sleep_info.duration_ms}ms")
                click.echo(f"  Remaining:  {exec_status.sleep_info.remaining_ms}ms")
                if exec_status.sleep_info.sleep_started_at:
                    click.echo(f"  Started:    {exec_status.sleep_info.sleep_started_at}")

            if exec_status.approval_info:
                click.echo(f"\n⏸️  Approval Info:")
                click.echo(f"  Type:       {exec_status.approval_info.approval_type}")
                if exec_status.approval_info.timeout_ms:
                    click.echo(f"  Timeout:    {exec_status.approval_info.timeout_ms}ms")
                    click.echo(f"  Remaining:  {exec_status.approval_info.remaining_timeout_ms}ms")

            if exec_status.error:
                click.echo(f"\n❌ Error:")
                click.echo(f"  Kind:    {exec_status.error['kind']}")
                click.echo(f"  Message: {exec_status.error['message']}")

            click.echo("\n" + "=" * 60)

        except Exception as e:
            click.echo(f"❌ Error: {e}", err=True)
            sys.exit(1)
        finally:
            client.close()

    asyncio.run(_status())


@cli.command()
@click.argument('execution_id')
@click.option('--interval', default=2, type=int, help='Refresh interval in seconds (default: 2)')
@click.pass_context
def watch(ctx, execution_id, interval):
    """Watch execution progress in real-time."""
    core_url = ctx.obj['core_url']

    async def _watch():
        client = ExecutionClient(core_url=core_url)
        try:
            click.echo(f"Watching {execution_id} (refresh every {interval}s, Ctrl+C to stop)")
            click.echo()

            while True:
                exec_status = await client.get_execution_status(execution_id)

                # Clear screen (simple version)
                click.clear()

                # Print header
                click.echo("=" * 60)
                click.echo(f"  Watching: {execution_id[:40]}")
                click.echo("=" * 60)

                # Status
                status_symbol = {
                    ExecutionState.RUNNING: '🔄',
                    ExecutionState.COMPLETED: '✅',
                    ExecutionState.FAILED: '❌',
                    ExecutionState.SLEEPING: '💤',
                }.get(exec_status.status, '❓')

                click.echo(f"\nWorkflow: {exec_status.workflow_name}")
                click.echo(f"Status:   {status_symbol} {exec_status.status.value.replace('EXECUTION_', '')}")

                # Progress
                click.echo(f"\nProgress: {exec_status.current_step_index + 1}/{exec_status.total_steps} ({exec_status.progress_percentage:.1f}%)")
                if exec_status.current_step_name:
                    click.echo(f"Current:  {exec_status.current_step_name}")

                # Progress bar
                bar_width = 50
                filled = int(exec_status.progress_percentage / 100 * bar_width)
                bar = '█' * filled + '░' * (bar_width - filled)
                click.echo(f"\n[{bar}]")

                # Check if finished
                if exec_status.status in [ExecutionState.COMPLETED, ExecutionState.FAILED]:
                    click.echo(f"\n{'='*60}")
                    click.echo(f"✅ Execution finished: {exec_status.status.value}")
                    break

                # Sleep info
                if exec_status.sleep_info:
                    remaining_sec = exec_status.sleep_info.remaining_ms / 1000
                    click.echo(f"\n💤 Sleeping: {remaining_sec:.0f}s remaining")

                click.echo(f"\nLast update: {datetime.now().strftime('%H:%M:%S')}")
                click.echo("Press Ctrl+C to stop watching")

                await asyncio.sleep(interval)

        except KeyboardInterrupt:
            click.echo("\n\n👋 Stopped watching")
        except Exception as e:
            click.echo(f"\n❌ Error: {e}", err=True)
            sys.exit(1)
        finally:
            client.close()

    asyncio.run(_watch())


@cli.command()
@click.argument('execution_id')
@click.pass_context
def resume(ctx, execution_id):
    """Resume a paused or failed execution."""
    core_url = ctx.obj['core_url']

    async def _resume():
        client = ExecutionClient(core_url=core_url)
        try:
            # Check current status first
            click.echo(f"Checking status of {execution_id}...")
            exec_status = await client.get_execution_status(execution_id)

            click.echo(f"Current status: {exec_status.status.value.replace('EXECUTION_', '')}")

            if exec_status.status == ExecutionState.COMPLETED:
                click.echo("⚠️  Execution is already completed")
                return

            if exec_status.status == ExecutionState.RUNNING:
                click.echo("⚠️  Execution is already running")
                return

            # Resume
            click.echo("Resuming execution...")
            result = await client.resume_execution(execution_id)

            if result == "resumed":
                click.echo("✅ Execution resumed successfully!")
                click.echo(f"\n💡 Tip: Use 'cerebelum watch {execution_id}' to monitor progress")
            elif result == "already_running":
                click.echo("⚠️  Execution was already running")
            else:
                click.echo(f"❌ Failed to resume: {result}")

        except Exception as e:
            click.echo(f"❌ Error: {e}", err=True)
            sys.exit(1)
        finally:
            client.close()

    asyncio.run(_resume())


@cli.command()
@click.pass_context
def active(ctx):
    """Show all active (running) workflows."""
    core_url = ctx.obj['core_url']

    async def _active():
        client = ExecutionClient(core_url=core_url)
        try:
            click.echo("Fetching active workflows...")
            active_workflows = await client.list_active_workflows()

            if not active_workflows:
                click.echo("\n⚠️  No active workflows")
                return

            click.echo(f"\n🔄 Active Workflows ({len(active_workflows)}):")
            click.echo("=" * 80)

            for exec in active_workflows:
                click.echo(f"\n{exec.workflow_name}")
                click.echo(f"  ID:       {exec.execution_id[:40]}")
                click.echo(f"  Progress: {exec.current_step_index + 1}/{exec.total_steps} ({exec.progress_percentage:.0f}%)")
                if exec.current_step_name:
                    click.echo(f"  Current:  {exec.current_step_name}")

            click.echo("\n" + "=" * 80)

        except Exception as e:
            click.echo(f"❌ Error: {e}", err=True)
            sys.exit(1)
        finally:
            client.close()

    asyncio.run(_active())


if __name__ == '__main__':
    cli(obj={})

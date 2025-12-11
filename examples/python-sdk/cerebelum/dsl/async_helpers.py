"""Async helpers for long-running operations, polling, and sleep.

These helpers make it easy to handle operations with variable latency
while maintaining workflow determinism and resurrection capabilities.
"""

import asyncio
import time
from typing import Callable, Any, Optional, TypeVar, Union
from datetime import timedelta

from .workflow_markers import SleepMarker

T = TypeVar('T')


async def sleep(duration: Union[int, float, timedelta], data: Optional[dict] = None) -> None:
    """Sleep for a specified duration (workflow-aware).

    In distributed mode with Core: Workflow pauses and can survive restarts
    In local mode: Falls back to asyncio.sleep()

    The workflow can survive system restarts during sleep when connected
    to Cerebelum Core with resurrection enabled.

    Args:
        duration: Sleep duration in:
            - int/float: milliseconds
            - timedelta: time delta object
        data: Optional data to carry through the sleep (for distributed mode)

    Examples:
        >>> from cerebelum import sleep
        >>>
        >>> @step
        >>> async def wait_for_deployment(context: Context, inputs: dict):
        >>>     # Sleep for 30 seconds
        >>>     await sleep(30_000)
        >>>     return {"ok": "deployment_ready"}
        >>>
        >>> @step
        >>> async def wait_one_day(context: Context, inputs: dict):
        >>>     # Sleep for 24 hours (works with resurrection in distributed mode)
        >>>     await sleep(timedelta(days=1))
        >>>     return {"ok": "day_passed"}
        >>>
        >>> @step
        >>> async def wait_with_data(context: Context, inputs: dict):
        >>>     # Sleep and carry data through
        >>>     await sleep(timedelta(hours=1), data={"checkpoint": "before_approval"})
        >>>     return {"ok": "resumed"}

    Notes:
        - Distributed mode: Raises SleepMarker that worker catches
        - Local mode: Worker should catch SleepMarker and use asyncio.sleep()
        - Workflows survive restarts when using Core resurrection
        - Sleep data is preserved across hibernation/resurrection
    """
    # Convert to milliseconds
    if isinstance(duration, timedelta):
        duration_ms = int(duration.total_seconds() * 1000)
    else:
        duration_ms = int(duration)

    # Raise SleepMarker to signal sleep request
    # The executor (local or distributed) will catch this and handle appropriately:
    # - Distributed: sends SLEEP TaskResult to Core (enables resurrection)
    # - Local: catches and calls asyncio.sleep()
    raise SleepMarker(duration_ms, data)


async def poll(
    check_fn: Callable[[], Any],
    *,
    interval: Union[int, float] = 5000,
    max_attempts: int = 30,
    timeout: Optional[Union[int, float, timedelta]] = None,
    success_condition: Optional[Callable[[Any], bool]] = None,
    on_attempt: Optional[Callable[[int, Any], None]] = None,
) -> Any:
    """Poll until a condition is met or timeout occurs.

    Provides a clean, reusable pattern for waiting on external resources
    like API endpoints, database records, file creation, etc.

    Args:
        check_fn: Async or sync function to call repeatedly
        interval: Time between checks in milliseconds (default: 5000ms = 5s)
        max_attempts: Maximum number of attempts (default: 30)
        timeout: Optional total timeout (int/float ms or timedelta)
        success_condition: Optional function to check if result is successful
                          If None, checks for truthy value
        on_attempt: Optional callback for progress reporting
                   Called with (attempt_number, result)

    Returns:
        The successful result from check_fn

    Raises:
        TimeoutError: If max_attempts reached or timeout exceeded
        Exception: If check_fn raises an exception

    Examples:
        >>> from cerebelum import poll
        >>>
        >>> @step
        >>> async def wait_for_droplet_ip(context: Context, create_droplet: dict):
        >>>     droplet_id = create_droplet["droplet_id"]
        >>>
        >>>     # Poll until IP is available
        >>>     result = await poll(
        >>>         check_fn=lambda: get_droplet(droplet_id),
        >>>         interval=5000,  # Check every 5 seconds
        >>>         max_attempts=30,  # Max 2.5 minutes
        >>>         success_condition=lambda d: d.get("ip_address") is not None,
        >>>         on_attempt=lambda n, _: print(f"Waiting for IP... ({n}/30)")
        >>>     )
        >>>
        >>>     return {"ok": {"ip_address": result["ip_address"]}}
        >>>
        >>> @step
        >>> async def wait_for_ssl_cert(context: Context, request_cert: dict):
        >>>     domain = request_cert["domain"]
        >>>
        >>>     # Poll with timeout
        >>>     result = await poll(
        >>>         check_fn=lambda: check_cert_status(domain),
        >>>         interval=10000,  # Every 10 seconds
        >>>         timeout=timedelta(minutes=5),  # Max 5 minutes total
        >>>         success_condition=lambda r: r["status"] == "issued"
        >>>     )
        >>>
        >>>     return {"ok": result}
    """
    # Convert timeout to milliseconds
    timeout_ms = None
    if timeout is not None:
        if isinstance(timeout, timedelta):
            timeout_ms = timeout.total_seconds() * 1000
        else:
            timeout_ms = timeout

    # Default success condition: truthy value
    if success_condition is None:
        success_condition = lambda x: bool(x)

    start_time = time.time()

    for attempt in range(1, max_attempts + 1):
        # Check timeout
        if timeout_ms is not None:
            elapsed_ms = (time.time() - start_time) * 1000
            if elapsed_ms >= timeout_ms:
                raise TimeoutError(
                    f"Polling timed out after {elapsed_ms:.0f}ms "
                    f"(timeout: {timeout_ms}ms)"
                )

        # Execute check function
        if asyncio.iscoroutinefunction(check_fn):
            result = await check_fn()
        else:
            result = check_fn()

        # Call progress callback if provided
        if on_attempt is not None:
            on_attempt(attempt, result)

        # Check success condition
        if success_condition(result):
            return result

        # Not successful yet, sleep before next attempt
        if attempt < max_attempts:
            await sleep(interval)

    # Max attempts reached
    raise TimeoutError(
        f"Polling failed after {max_attempts} attempts "
        f"(interval: {interval}ms)"
    )


async def retry(
    fn: Callable[..., T],
    *args,
    max_attempts: int = 3,
    delay: Union[int, float] = 1000,
    backoff: float = 1.0,
    on_error: Optional[type[Exception]] = None,
    on_attempt: Optional[Callable[[int, Optional[Exception]], None]] = None,
    **kwargs
) -> T:
    """Retry a function with exponential backoff.

    Useful for transient failures like network errors, rate limits, etc.

    Args:
        fn: Function to retry (async or sync)
        *args: Positional arguments for fn
        max_attempts: Maximum number of attempts (default: 3)
        delay: Initial delay between retries in ms (default: 1000ms)
        backoff: Multiplier for delay after each attempt (default: 1.0 = constant)
        on_error: Only retry on this exception type (default: any Exception)
        on_attempt: Callback called with (attempt_number, last_error)
        **kwargs: Keyword arguments for fn

    Returns:
        Result from successful function call

    Raises:
        Exception: The last exception if all attempts fail

    Examples:
        >>> from cerebelum import retry
        >>>
        >>> @step
        >>> async def connect_ssh(context: Context, create_server: dict):
        >>>     ip = create_server["ip_address"]
        >>>
        >>>     # Retry SSH connection with exponential backoff
        >>>     connection = await retry(
        >>>         fn=establish_ssh,
        >>>         ip=ip,
        >>>         max_attempts=5,
        >>>         delay=2000,  # Start with 2s
        >>>         backoff=2.0,  # Double each time (2s, 4s, 8s, 16s)
        >>>         on_error=SSHConnectionError,
        >>>         on_attempt=lambda n, e: print(f"Retry {n}/5: {e}")
        >>>     )
        >>>
        >>>     return {"ok": {"connection_id": connection.id}}
    """
    last_error = None
    current_delay = delay

    for attempt in range(1, max_attempts + 1):
        try:
            # Call progress callback
            if on_attempt is not None:
                on_attempt(attempt, last_error)

            # Execute function
            if asyncio.iscoroutinefunction(fn):
                result = await fn(*args, **kwargs)
            else:
                result = fn(*args, **kwargs)

            return result

        except Exception as e:
            # Check if we should retry this error type
            if on_error is not None and not isinstance(e, on_error):
                raise

            last_error = e

            # Last attempt failed
            if attempt >= max_attempts:
                raise

            # Sleep before retry
            await sleep(current_delay)

            # Apply backoff
            current_delay *= backoff

    # Should never reach here, but satisfy type checker
    raise last_error  # type: ignore


class ProgressReporter:
    """Helper for reporting progress from within steps.

    In local mode: Prints to stdout
    In distributed mode: Reports to Core for UI display

    Examples:
        >>> from cerebelum import ProgressReporter
        >>>
        >>> @step
        >>> async def long_task(context: Context, inputs: dict):
        >>>     progress = ProgressReporter(context)
        >>>
        >>>     progress.update(0, "Starting task...")
        >>>     await do_part_1()
        >>>
        >>>     progress.update(33, "Part 1 complete")
        >>>     await do_part_2()
        >>>
        >>>     progress.update(66, "Part 2 complete")
        >>>     await do_part_3()
        >>>
        >>>     progress.update(100, "Task complete!")
        >>>
        >>>     return {"ok": "done"}
    """

    def __init__(self, context: Any):
        """Initialize progress reporter.

        Args:
            context: Execution context from step
        """
        self.context = context
        self.last_progress = 0

    def update(self, percent: int, message: str = "") -> None:
        """Update progress.

        Args:
            percent: Progress percentage (0-100)
            message: Optional progress message
        """
        self.last_progress = percent

        # In local mode: print to stdout
        # TODO: In distributed mode, emit telemetry event
        progress_bar = self._render_bar(percent)
        print(f"  [{self.context.step_name}] {progress_bar} {percent}% - {message}")

    def _render_bar(self, percent: int, width: int = 20) -> str:
        """Render ASCII progress bar."""
        filled = int(width * percent / 100)
        bar = "█" * filled + "░" * (width - filled)
        return bar

defmodule Cerebelum.Benchmarks.EventStoreBenchmark do
  @moduledoc """
  Performance benchmarks for EventStore.

  Tests:
  - Throughput: Events written per second
  - Latency: Query performance (p50, p95, p99)
  - Batch performance: Different batch sizes
  - Reconstruction performance: State rebuilding from events

  ## Target Performance (from requirements)
  - Write throughput: 640K events/sec
  - Query latency p95: <5ms
  - Batch flush: <100ms

  ## Running Benchmarks

      # Run all benchmarks
      Cerebelum.Benchmarks.EventStoreBenchmark.run_all()

      # Run specific benchmark
      Cerebelum.Benchmarks.EventStoreBenchmark.throughput_benchmark(10_000)
  """

  require Logger
  alias Cerebelum.EventStore
  alias Cerebelum.Events.{ExecutionStartedEvent, StepExecutedEvent}
  alias Cerebelum.Execution.StateReconstructor

  @doc """
  Runs all benchmarks and prints a summary report.
  """
  def run_all do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("EventStore Performance Benchmarks")
    IO.puts(String.duplicate("=", 80) <> "\n")

    # Clean up before benchmarks
    cleanup()

    results = %{
      throughput: throughput_benchmark(100_000),
      batch_performance: batch_performance_benchmark(),
      query_latency: query_latency_benchmark(1000),
      reconstruction: reconstruction_benchmark(1000)
    }

    print_summary(results)
    results
  end

  @doc """
  Benchmarks write throughput (events/sec).

  Measures how many events can be written per second with async batching.
  """
  def throughput_benchmark(num_events \\ 100_000) do
    IO.puts("Running throughput benchmark (#{num_events} events)...")

    # Warm up with different execution
    warmup_id = Ecto.UUID.generate()
    warmup_events = generate_test_events(warmup_id, 100)

    Enum.each(warmup_events, fn {event, version} ->
      EventStore.append(warmup_id, event, version)
    end)

    EventStore.flush()
    Process.sleep(50)

    # Actual benchmark with new execution_id
    execution_id = Ecto.UUID.generate()
    events = generate_test_events(execution_id, num_events)

    {time_micros, :ok} =
      :timer.tc(fn ->
        Enum.each(events, fn {event, version} ->
          EventStore.append(execution_id, event, version)
        end)

        # Wait for all events to be flushed
        EventStore.flush()
        Process.sleep(100)
      end)

    time_seconds = time_micros / 1_000_000
    throughput = num_events / time_seconds

    result = %{
      events: num_events,
      time_seconds: Float.round(time_seconds, 2),
      events_per_second: Float.round(throughput, 0),
      target: 640_000,
      percentage_of_target: Float.round(throughput / 640_000 * 100, 1)
    }

    print_throughput_result(result)
    result
  end

  @doc """
  Benchmarks batch flush performance with different batch sizes.
  """
  def batch_performance_benchmark do
    IO.puts("\nRunning batch performance benchmark...")

    batch_sizes = [10, 50, 100, 500, 1000]

    results =
      Enum.map(batch_sizes, fn size ->
        execution_id = Ecto.UUID.generate()
        events = generate_test_events(execution_id, size)

        {time_micros, :ok} =
          :timer.tc(fn ->
            Enum.each(events, fn {event, version} ->
              EventStore.append(execution_id, event, version)
            end)

            EventStore.flush()
            Process.sleep(10)
          end)

        time_ms = time_micros / 1000

        %{
          batch_size: size,
          time_ms: Float.round(time_ms, 2),
          events_per_ms: Float.round(size / time_ms, 2)
        }
      end)

    print_batch_results(results)
    results
  end

  @doc """
  Benchmarks query latency with percentiles.
  """
  def query_latency_benchmark(num_queries \\ 1000) do
    IO.puts("\nRunning query latency benchmark (#{num_queries} queries)...")

    # Setup: Create execution with events
    execution_id = Ecto.UUID.generate()
    events = generate_test_events(execution_id, 100)

    Enum.each(events, fn {event, version} ->
      EventStore.append(execution_id, event, version)
    end)

    EventStore.flush()
    Process.sleep(100)

    # Run queries and measure latency
    latencies =
      for _ <- 1..num_queries do
        {time_micros, {:ok, _events}} =
          :timer.tc(fn ->
            EventStore.get_events(execution_id)
          end)

        time_micros / 1000  # Convert to milliseconds
      end

    sorted_latencies = Enum.sort(latencies)

    result = %{
      num_queries: num_queries,
      p50_ms: Float.round(percentile(sorted_latencies, 0.5), 2),
      p95_ms: Float.round(percentile(sorted_latencies, 0.95), 2),
      p99_ms: Float.round(percentile(sorted_latencies, 0.99), 2),
      min_ms: Float.round(Enum.min(latencies), 2),
      max_ms: Float.round(Enum.max(latencies), 2),
      avg_ms: Float.round(Enum.sum(latencies) / num_queries, 2),
      target_p95_ms: 5.0
    }

    print_latency_result(result)
    result
  end

  @doc """
  Benchmarks state reconstruction performance.
  """
  def reconstruction_benchmark(num_events \\ 1000) do
    IO.puts("\nRunning state reconstruction benchmark (#{num_events} events)...")

    # Setup: Create execution with events
    execution_id = Ecto.UUID.generate()
    events = generate_test_events(execution_id, num_events)

    Enum.each(events, fn {event, version} ->
      EventStore.append(execution_id, event, version)
    end)

    EventStore.flush()
    Process.sleep(100)

    # Benchmark reconstruction
    {time_micros, {:ok, _state}} =
      :timer.tc(fn ->
        StateReconstructor.reconstruct(execution_id)
      end)

    time_ms = time_micros / 1000

    result = %{
      num_events: num_events,
      time_ms: Float.round(time_ms, 2),
      events_per_ms: Float.round(num_events / time_ms, 2)
    }

    print_reconstruction_result(result)
    result
  end

  # Private Helpers

  defp generate_test_events(execution_id, count) do
    # First event: ExecutionStartedEvent
    start_event = ExecutionStartedEvent.new(
      execution_id,
      TestWorkflow,
      %{},
      0,
      workflow_version: "1.0.0"
    )

    # Rest: StepExecutedEvent
    step_events =
      for i <- 1..(count - 1) do
        StepExecutedEvent.new(
          execution_id,
          String.to_atom("step_#{rem(i, 10)}"),
          i,
          [],
          {:ok, i},
          10,
          i
        )
      end

    [{start_event, 0}] ++ Enum.with_index(step_events, 1)
  end

  defp percentile(sorted_list, p) do
    index = round(length(sorted_list) * p) - 1
    index = max(0, min(index, length(sorted_list) - 1))
    Enum.at(sorted_list, index)
  end

  defp cleanup do
    # Truncate events table
    try do
      Ecto.Adapters.SQL.query!(Cerebelum.Repo, "TRUNCATE TABLE events CASCADE", [])
    rescue
      _ -> :ok
    end
  end

  # Print Functions

  defp print_throughput_result(result) do
    IO.puts("\n  Throughput Results:")
    IO.puts("  ─────────────────────────────────────")
    IO.puts("  Events:             #{format_number(result.events)}")
    IO.puts("  Time:               #{result.time_seconds}s")
    IO.puts("  Throughput:         #{format_number(result.events_per_second)} events/sec")
    IO.puts("  Target:             #{format_number(result.target)} events/sec")
    IO.puts("  Achievement:        #{result.percentage_of_target}% of target")

    if result.events_per_second >= result.target do
      IO.puts("  Status:             ✅ TARGET MET")
    else
      IO.puts("  Status:             ⚠️  Below target")
    end
  end

  defp print_batch_results(results) do
    IO.puts("\n  Batch Performance Results:")
    IO.puts("  ─────────────────────────────────────")
    IO.puts("  Batch Size | Time (ms) | Events/ms")
    IO.puts("  ───────────┼───────────┼──────────")

    Enum.each(results, fn r ->
      IO.puts(
        "  #{String.pad_leading(to_string(r.batch_size), 10)} | " <>
          "#{String.pad_leading(to_string(r.time_ms), 9)} | " <>
          "#{String.pad_leading(to_string(r.events_per_ms), 9)}"
      )
    end)

    # Check if all batches meet <100ms target
    all_under_100ms = Enum.all?(results, &(&1.time_ms < 100))

    if all_under_100ms do
      IO.puts("\n  Status:             ✅ All batches < 100ms")
    else
      IO.puts("\n  Status:             ⚠️  Some batches >= 100ms")
    end
  end

  defp print_latency_result(result) do
    IO.puts("\n  Query Latency Results:")
    IO.puts("  ─────────────────────────────────────")
    IO.puts("  Queries:            #{format_number(result.num_queries)}")
    IO.puts("  Min:                #{result.min_ms}ms")
    IO.puts("  p50 (median):       #{result.p50_ms}ms")
    IO.puts("  Average:            #{result.avg_ms}ms")
    IO.puts("  p95:                #{result.p95_ms}ms")
    IO.puts("  p99:                #{result.p99_ms}ms")
    IO.puts("  Max:                #{result.max_ms}ms")
    IO.puts("  Target p95:         #{result.target_p95_ms}ms")

    if result.p95_ms <= result.target_p95_ms do
      IO.puts("  Status:             ✅ TARGET MET")
    else
      IO.puts("  Status:             ⚠️  p95 above target")
    end
  end

  defp print_reconstruction_result(result) do
    IO.puts("\n  State Reconstruction Results:")
    IO.puts("  ─────────────────────────────────────")
    IO.puts("  Events:             #{format_number(result.num_events)}")
    IO.puts("  Time:               #{result.time_ms}ms")
    IO.puts("  Throughput:         #{result.events_per_ms} events/ms")
  end

  defp print_summary(results) do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("Summary")
    IO.puts(String.duplicate("=", 80))

    throughput_met = results.throughput.events_per_second >= results.throughput.target
    latency_met = results.query_latency.p95_ms <= results.query_latency.target_p95_ms
    batch_met = Enum.all?(results.batch_performance, &(&1.time_ms < 100))

    IO.puts("\n  Performance Targets:")
    IO.puts("  ─────────────────────────────────────")
    IO.puts("  #{if throughput_met, do: "✅", else: "⚠️ "} Write Throughput:  #{format_number(results.throughput.events_per_second)} / #{format_number(results.throughput.target)} events/sec")
    IO.puts("  #{if latency_met, do: "✅", else: "⚠️ "} Query Latency p95:  #{results.query_latency.p95_ms}ms / #{results.query_latency.target_p95_ms}ms")
    IO.puts("  #{if batch_met, do: "✅", else: "⚠️ "} Batch Flush:        All < 100ms")

    if throughput_met && latency_met && batch_met do
      IO.puts("\n  🎉 ALL PERFORMANCE TARGETS MET!")
    else
      IO.puts("\n  ℹ️  Some targets not met (this is expected in development)")
    end

    IO.puts("\n" <> String.duplicate("=", 80) <> "\n")
  end

  defp format_number(num) when is_float(num) do
    num
    |> round()
    |> format_number()
  end

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.reverse()
    |> String.split("", trim: true)
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end
end

defmodule Mix.Tasks.Benchmark do
  @moduledoc """
  Runs EventStore performance benchmarks.

  ## Usage

      # Run all benchmarks
      mix benchmark

      # Run specific benchmark
      mix benchmark throughput
      mix benchmark latency
      mix benchmark batch
      mix benchmark reconstruction

  ## Benchmarks

  - **throughput**: Measures write throughput (events/sec)
  - **latency**: Measures query latency percentiles
  - **batch**: Measures batch flush performance
  - **reconstruction**: Measures state reconstruction performance
  - **all**: Runs all benchmarks (default)
  """

  use Mix.Task

  @shortdoc "Runs EventStore performance benchmarks"

  alias Cerebelum.Benchmarks.EventStoreBenchmark

  @impl Mix.Task
  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    case args do
      [] ->
        EventStoreBenchmark.run_all()

      ["all"] ->
        EventStoreBenchmark.run_all()

      ["throughput"] ->
        IO.puts("\nRunning throughput benchmark...\n")
        EventStoreBenchmark.throughput_benchmark(100_000)

      ["latency"] ->
        IO.puts("\nRunning latency benchmark...\n")
        EventStoreBenchmark.query_latency_benchmark(1000)

      ["batch"] ->
        IO.puts("\nRunning batch performance benchmark...\n")
        EventStoreBenchmark.batch_performance_benchmark()

      ["reconstruction"] ->
        IO.puts("\nRunning reconstruction benchmark...\n")
        EventStoreBenchmark.reconstruction_benchmark(1000)

      [benchmark] ->
        IO.puts("Unknown benchmark: #{benchmark}")
        IO.puts("Available benchmarks: all, throughput, latency, batch, reconstruction")
        exit({:shutdown, 1})

      _ ->
        IO.puts("Usage: mix benchmark [all|throughput|latency|batch|reconstruction]")
        exit({:shutdown, 1})
    end
  end
end

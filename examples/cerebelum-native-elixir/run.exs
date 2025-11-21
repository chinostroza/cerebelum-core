# Script to test the workflow using Cerebelum DSL syntax
# Run with: mix run examples/cerebelum-native-elixir/run.exs

IO.puts("=" <> String.duplicate("=", 69))
IO.puts("🚀 Cerebelum Native Elixir Workflow Test (DSL)")
IO.puts("=" <> String.duplicate("=", 69))
IO.puts("")

# Load the workflow module
Code.require_file("examples/cerebelum-native-elixir/workflow.ex", File.cwd!())

# Test input
input_data = %{user_id: 123}

IO.puts("📥 Input: #{inspect(input_data)}")
IO.puts("")
IO.puts("▶️  Executing workflow...")
IO.puts("-" <> String.duplicate("-", 69))
IO.puts("")

# Execute workflow using Cerebelum API
try do
  # Execute the workflow using Cerebelum.execute_workflow/2
  case Cerebelum.execute_workflow(UserOnboardingWorkflow, input_data) do
    {:ok, execution} ->
      IO.puts("✅ Workflow execution started!")
      IO.puts("   Execution ID: #{execution.id}")
      IO.puts("")

      # Wait for execution to complete
      IO.puts("⏳ Waiting for execution to complete...")
      Process.sleep(2000)

      # Get execution status
      case Cerebelum.get_execution_status(execution.id) do
        {:ok, status} ->
          IO.puts("")
          IO.puts("-" <> String.duplicate("-", 69))
          IO.puts("✅ Workflow completed successfully!")
          IO.puts("")
          IO.puts("State: #{status.state}")
          IO.puts("Results:")
          Enum.each(status.results, fn {step, result} ->
            IO.puts("  #{step}: #{inspect(result)}")
          end)
          IO.puts("")

        {:error, reason} ->
          IO.puts("")
          IO.puts("-" <> String.duplicate("-", 69))
          IO.puts("❌ Failed to get execution status: #{inspect(reason)}")
          IO.puts("")
      end

    {:error, reason} ->
      IO.puts("")
      IO.puts("-" <> String.duplicate("-", 69))
      IO.puts("❌ Workflow execution failed: #{inspect(reason)}")
      IO.puts("")
  end

rescue
  e ->
    IO.puts("")
    IO.puts("-" <> String.duplicate("-", 69))
    IO.puts("❌ Error: #{Exception.message(e)}")
    IO.puts(Exception.format_stacktrace(__STACKTRACE__))
end

#!/usr/bin/env mix run
# Script para ejecutar workflow usando Cerebelum DSL
# Uso: mix run examples/cerebelum-native-elixir/workflow.exs

defmodule UserOnboardingWorkflow do
  @moduledoc """
  Workflow de onboarding de usuarios usando Cerebelum DSL.

  Flujo: fetch_user -> check_eligibility -> send_notification
  """

  use Cerebelum.Workflow

  require Logger

  # Definición del workflow usando DSL
  workflow do
    timeline do
      fetch_user() |> check_eligibility() |> send_notification()
    end
  end

  # Step 1: Obtener datos del usuario
  def fetch_user(context) do
    Logger.info("[Workflow] Executing: fetch_user")
    user_id = Map.get(context.inputs, "user_id") || Map.get(context.inputs, :user_id)
    Logger.info("  → Received user_id: #{inspect(user_id)}")

    user = %{
      id: user_id,
      name: "User#{user_id}",
      email: "user#{user_id}@example.com",
      score: 85
    }

    Logger.info("  → Returning: #{inspect(user)}")
    {:ok, user}
  end

  # Step 2: Verificar elegibilidad
  def check_eligibility(_context, {:ok, user}) do
    Logger.info("[Workflow] Executing: check_eligibility")
    Logger.info("  → Received user: #{inspect(user)}")

    eligible = Map.get(user, :score, 0) >= 80
    result = Map.put(user, :eligible, eligible)

    Logger.info("  → Returning: #{inspect(result)}")
    {:ok, result}
  end

  # Step 3: Enviar notificación
  def send_notification(_context, _fetch_result, {:ok, user}) do
    Logger.info("[Workflow] Executing: send_notification")
    Logger.info("  → Received user: #{inspect(user)}")

    message = if Map.get(user, :eligible, false) do
      "✉️  Notification sent to #{user.email}"
    else
      "⏭️  Skipped notification (not eligible)"
    end

    Logger.info("  → Returning: #{message}")
    {:ok, message}
  end
end

# === Ejecución del Workflow ===

IO.puts("=" <> String.duplicate("=", 69))
IO.puts("🚀 Cerebelum Native Elixir Workflow Test")
IO.puts("=" <> String.duplicate("=", 69))
IO.puts("")

# Input de prueba
input_data = %{user_id: 123}

IO.puts("📥 Input: #{inspect(input_data)}")
IO.puts("")
IO.puts("▶️  Executing workflow...")
IO.puts("-" <> String.duplicate("-", 69))
IO.puts("")

try do
  # Ejecutar el workflow
  case Cerebelum.execute_workflow(UserOnboardingWorkflow, input_data) do
    {:ok, execution} ->
      IO.puts("✅ Workflow execution started!")
      IO.puts("   Execution ID: #{execution.id}")
      IO.puts("")

      # Esperar a que complete
      IO.puts("⏳ Waiting for execution to complete...")
      Process.sleep(2000)

      # Obtener estado final
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

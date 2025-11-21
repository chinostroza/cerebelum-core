defmodule UserOnboardingWorkflow do
  @moduledoc """
  Native Elixir workflow using Cerebelum DSL syntax.

  This workflow uses the same flow as the Python SDK example:
  1. fetch_user - Get user data
  2. check_eligibility - Check if user meets criteria
  3. send_notification - Send notification based on eligibility
  """

  use Cerebelum.Workflow

  require Logger

  # Define the workflow using DSL
  workflow do
    timeline do
      fetch_user() |> check_eligibility() |> send_notification()
    end
  end

  # Step 1: Fetch user data (receives only context)
  def fetch_user(context) do
    Logger.info("[Workflow] Executing: fetch_user")
    user_id = Map.get(context.inputs, "user_id") || Map.get(context.inputs, :user_id)
    Logger.info("  → Received user_id: #{inspect(user_id)}")

    # Simulate database fetch
    user = %{
      id: user_id,
      name: "User#{user_id}",
      email: "user#{user_id}@example.com",
      score: 85
    }

    Logger.info("  → Returning: #{inspect(user)}")
    {:ok, user}
  end

  # Step 2: Check eligibility (receives context + fetch_user result)
  def check_eligibility(context, {:ok, user}) do
    Logger.info("[Workflow] Executing: check_eligibility")
    Logger.info("  → Received user: #{inspect(user)}")

    eligible = Map.get(user, :score, 0) >= 80
    result = Map.put(user, :eligible, eligible)

    Logger.info("  → Returning: #{inspect(result)}")
    {:ok, result}
  end

  # Step 3: Send notification (receives context + fetch_user result + check_eligibility result)
  def send_notification(context, _fetch_result, {:ok, user}) do
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

defmodule Cerebelum.Execution.SupervisorTest do
  use ExUnit.Case, async: false

  alias Cerebelum.Execution.Supervisor
  alias Cerebelum.Examples.CounterWorkflow
  alias Cerebelum.Repo
  alias Cerebelum.EventStore

  setup do
    # Checkout sandbox connection for test isolation
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    # Allow EventStore GenServer to use the sandbox connection
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), Process.whereis(Cerebelum.EventStore))

    # Clean up any running executions
    Supervisor.list_executions()
    |> Enum.each(&Supervisor.terminate_execution/1)

    :timer.sleep(10)
    :ok
  end

  describe "start_execution/3" do
    test "starts a new execution" do
      {:ok, pid} = Supervisor.start_execution(CounterWorkflow, %{})

      assert is_pid(pid)
      assert Process.alive?(pid)

      Supervisor.terminate_execution(pid)
    end

    test "starts execution with inputs" do
      {:ok, pid} = Supervisor.start_execution(CounterWorkflow, %{test: "data"})

      assert Process.alive?(pid)

      Supervisor.terminate_execution(pid)
    end

    test "starts execution with options" do
      {:ok, pid} = Supervisor.start_execution(
        CounterWorkflow,
        %{},
        context_opts: [correlation_id: "test-123"]
      )

      assert Process.alive?(pid)

      Supervisor.terminate_execution(pid)
    end

    test "can start multiple executions concurrently" do
      pids = for _ <- 1..5 do
        {:ok, pid} = Supervisor.start_execution(CounterWorkflow, %{})
        pid
      end

      assert length(pids) == 5
      assert Enum.all?(pids, &Process.alive?/1)

      Enum.each(pids, &Supervisor.terminate_execution/1)
    end
  end

  describe "list_executions/0" do
    test "lists all running executions" do
      {:ok, pid1} = Supervisor.start_execution(CounterWorkflow, %{})
      {:ok, pid2} = Supervisor.start_execution(CounterWorkflow, %{})

      executions = Supervisor.list_executions()

      assert pid1 in executions
      assert pid2 in executions

      Supervisor.terminate_execution(pid1)
      Supervisor.terminate_execution(pid2)
    end

    test "returns empty list when no executions" do
      Supervisor.list_executions()
      |> Enum.each(&Supervisor.terminate_execution/1)

      :timer.sleep(50)

      assert Supervisor.list_executions() == []
    end

    test "updates after terminating executions" do
      {:ok, pid1} = Supervisor.start_execution(CounterWorkflow, %{})
      {:ok, pid2} = Supervisor.start_execution(CounterWorkflow, %{})

      assert length(Supervisor.list_executions()) >= 2

      Supervisor.terminate_execution(pid1)
      :timer.sleep(50)

      executions = Supervisor.list_executions()
      refute pid1 in executions
      assert pid2 in executions

      Supervisor.terminate_execution(pid2)
    end
  end

  describe "count_executions/0" do
    test "counts running executions" do
      initial_count = Supervisor.count_executions()

      {:ok, pid1} = Supervisor.start_execution(CounterWorkflow, %{})
      {:ok, pid2} = Supervisor.start_execution(CounterWorkflow, %{})

      assert Supervisor.count_executions() == initial_count + 2

      Supervisor.terminate_execution(pid1)
      Supervisor.terminate_execution(pid2)
    end

    test "decreases after termination" do
      {:ok, pid} = Supervisor.start_execution(CounterWorkflow, %{})
      count_before = Supervisor.count_executions()

      Supervisor.terminate_execution(pid)
      :timer.sleep(50)

      assert Supervisor.count_executions() == count_before - 1
    end
  end

  describe "terminate_execution/1" do
    test "terminates a running execution" do
      {:ok, pid} = Supervisor.start_execution(CounterWorkflow, %{})

      assert Process.alive?(pid)
      assert :ok = Supervisor.terminate_execution(pid)

      :timer.sleep(50)
      refute Process.alive?(pid)
    end

    test "returns error for non-existent PID" do
      fake_pid = spawn(fn -> :ok end)
      :timer.sleep(10)  # Let it die

      assert {:error, :not_found} = Supervisor.terminate_execution(fake_pid)
    end

    test "can terminate multiple executions" do
      pids = for _ <- 1..3 do
        {:ok, pid} = Supervisor.start_execution(CounterWorkflow, %{})
        pid
      end

      Enum.each(pids, fn pid ->
        assert :ok = Supervisor.terminate_execution(pid)
      end)

      :timer.sleep(100)

      Enum.each(pids, fn pid ->
        refute Process.alive?(pid)
      end)
    end
  end

  describe "supervisor restart strategy" do
    test "supervisor manages child lifecycle" do
      {:ok, pid} = Supervisor.start_execution(CounterWorkflow, %{})

      assert Process.alive?(pid)

      # Supervisor should be alive
      assert Process.whereis(Supervisor) |> Process.alive?()

      Supervisor.terminate_execution(pid)
    end

    test "crashed executions are not restarted (one_for_one)" do
      # This test verifies that executions are :temporary children
      # They should not be restarted if they crash

      defmodule CrashingWorkflow do
        use Cerebelum.Workflow

        workflow do
          timeline do
            crash_step()
          end
        end

        def crash_step(_context) do
          # Cause an exit
          exit(:intentional_crash)
        end
      end

      {:ok, pid} = Supervisor.start_execution(CrashingWorkflow, %{})

      # Wait for it to fail
      :timer.sleep(100)

      # The engine catches exits and transitions to :failed state
      # The process should be alive but in :failed state
      assert Process.alive?(pid)
      status = Cerebelum.Execution.Engine.get_status(pid)
      assert status.state == :failed

      # Verify there's only one child (not restarted)
      children_count = length(Supervisor.list_executions())
      assert children_count == 1

      # Supervisor should still be alive
      assert Process.whereis(Supervisor) |> Process.alive?()
    end
  end
end

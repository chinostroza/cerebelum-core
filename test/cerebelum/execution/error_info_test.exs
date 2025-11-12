defmodule Cerebelum.Execution.ErrorInfoTest do
  use ExUnit.Case, async: true

  alias Cerebelum.Execution.ErrorInfo

  doctest ErrorInfo

  describe "from_exception/4" do
    test "creates error info from exception" do
      exception = %RuntimeError{message: "something went wrong"}
      stacktrace = [{Module, :function, 2, [file: 'file.ex', line: 42]}]

      error = ErrorInfo.from_exception(:my_step, exception, stacktrace, "exec-123")

      assert error.kind == :exception
      assert error.step_name == :my_step
      assert error.reason == exception
      assert error.stacktrace == stacktrace
      assert error.execution_id == "exec-123"
      assert %DateTime{} = error.timestamp
    end

    test "includes timestamp" do
      exception = %RuntimeError{message: "test"}
      before = DateTime.utc_now()

      error = ErrorInfo.from_exception(:step, exception, [], "exec-123")

      after_time = DateTime.utc_now()

      assert DateTime.compare(error.timestamp, before) in [:gt, :eq]
      assert DateTime.compare(error.timestamp, after_time) in [:lt, :eq]
    end
  end

  describe "from_exit/3" do
    test "creates error info from exit" do
      error = ErrorInfo.from_exit(:my_step, :killed, "exec-123")

      assert error.kind == :exit
      assert error.step_name == :my_step
      assert error.reason == :killed
      assert error.stacktrace == nil
      assert error.execution_id == "exec-123"
      assert %DateTime{} = error.timestamp
    end

    test "handles various exit reasons" do
      for reason <- [:normal, :killed, :shutdown, {:shutdown, :app_stopped}] do
        error = ErrorInfo.from_exit(:step, reason, "exec-123")
        assert error.reason == reason
      end
    end
  end

  describe "from_throw/3" do
    test "creates error info from throw" do
      error = ErrorInfo.from_throw(:my_step, {:error, "bad value"}, "exec-123")

      assert error.kind == :throw
      assert error.step_name == :my_step
      assert error.reason == {:error, "bad value"}
      assert error.stacktrace == nil
      assert error.execution_id == "exec-123"
      assert %DateTime{} = error.timestamp
    end

    test "handles various throw values" do
      for value <- [:abort, "error", {:error, :invalid}, %{error: true}] do
        error = ErrorInfo.from_throw(:step, value, "exec-123")
        assert error.reason == value
      end
    end
  end

  describe "from_timeout/2" do
    test "creates error info from timeout" do
      error = ErrorInfo.from_timeout(:slow_step, "exec-123")

      assert error.kind == :timeout
      assert error.step_name == :slow_step
      assert error.reason == :timeout
      assert error.stacktrace == nil
      assert error.execution_id == "exec-123"
      assert %DateTime{} = error.timestamp
    end
  end

  describe "format/1" do
    test "formats exception error" do
      exception = %RuntimeError{message: "boom"}
      error = ErrorInfo.from_exception(:step1, exception, [], "exec-123")

      formatted = ErrorInfo.format(error)

      assert formatted == "Exception in step :step1 - RuntimeError: boom"
    end

    test "formats exit error" do
      error = ErrorInfo.from_exit(:step1, :killed, "exec-123")

      formatted = ErrorInfo.format(error)

      assert formatted == "Exit in step :step1 - reason: :killed"
    end

    test "formats throw error" do
      error = ErrorInfo.from_throw(:step1, {:error, "bad"}, "exec-123")

      formatted = ErrorInfo.format(error)

      assert formatted == "Throw in step :step1 - value: {:error, \"bad\"}"
    end

    test "formats timeout error" do
      error = ErrorInfo.from_timeout(:slow_step, "exec-123")

      formatted = ErrorInfo.format(error)

      assert formatted == "Timeout in step :slow_step - step exceeded maximum execution time"
    end

    test "works with different exception types" do
      exceptions = [
        %ArgumentError{message: "invalid arg"},
        %ArithmeticError{message: "division by zero"},
        %KeyError{key: :foo, term: %{}}
      ]

      for exception <- exceptions do
        error = ErrorInfo.from_exception(:step, exception, [], "exec-123")
        formatted = ErrorInfo.format(error)
        assert String.contains?(formatted, "Exception in step :step")
      end
    end
  end

  describe "to_map/1" do
    test "converts exception error to map" do
      exception = %RuntimeError{message: "boom"}
      stacktrace = [{Module, :func, 2, []}]
      error = ErrorInfo.from_exception(:step1, exception, stacktrace, "exec-123")

      map = ErrorInfo.to_map(error)

      assert map.kind == :exception
      assert map.step_name == :step1
      assert map.reason.type == RuntimeError
      assert map.reason.message == "boom"
      assert map.stacktrace == stacktrace
      assert map.execution_id == "exec-123"
      assert map.timestamp == error.timestamp
      assert is_binary(map.message)
    end

    test "converts exit error to map" do
      error = ErrorInfo.from_exit(:step1, :killed, "exec-123")

      map = ErrorInfo.to_map(error)

      assert map.kind == :exit
      assert map.step_name == :step1
      assert map.reason == :killed
      assert map.stacktrace == nil
      assert is_binary(map.message)
    end

    test "converts throw error to map" do
      error = ErrorInfo.from_throw(:step1, {:error, "oops"}, "exec-123")

      map = ErrorInfo.to_map(error)

      assert map.kind == :throw
      assert map.reason == {:error, "oops"}
      assert is_binary(map.message)
    end

    test "includes formatted message in map" do
      error = ErrorInfo.from_timeout(:step1, "exec-123")

      map = ErrorInfo.to_map(error)

      assert map.message == ErrorInfo.format(error)
    end
  end

  describe "integration with different error scenarios" do
    test "handles complex exception with long stacktrace" do
      exception = %RuntimeError{message: "complex error"}

      stacktrace = [
        {MyModule, :func1, 3, [file: 'lib/my_module.ex', line: 10]},
        {AnotherModule, :func2, 1, [file: 'lib/another.ex', line: 42]},
        {:erlang, :apply, 2, []}
      ]

      error = ErrorInfo.from_exception(:step, exception, stacktrace, "exec-123")

      assert length(error.stacktrace) == 3
      assert error.kind == :exception

      map = ErrorInfo.to_map(error)
      assert length(map.stacktrace) == 3
    end

    test "handles exit with complex reason tuple" do
      reason = {:shutdown, {:failed_to_start_child, SomeWorker, :normal}}
      error = ErrorInfo.from_exit(:step, reason, "exec-123")

      assert error.reason == reason
      formatted = ErrorInfo.format(error)
      assert String.contains?(formatted, "Exit in step")
    end
  end
end

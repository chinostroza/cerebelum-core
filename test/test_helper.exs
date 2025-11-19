# Start the Repo for tests
{:ok, _} = Application.ensure_all_started(:cerebelum_core)

# Configure Ecto Sandbox for concurrent test isolation
Ecto.Adapters.SQL.Sandbox.mode(Cerebelum.Repo, :manual)

# Limit concurrency to avoid Sandbox/Repo overload issues
# With high concurrency (16+), tests fail intermittently due to Ecto.Sandbox connection pool limits.
# max_cases: 2 ensures stable test execution.
ExUnit.start(max_cases: 2)

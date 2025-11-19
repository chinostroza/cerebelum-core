# Getting Started with Cerebelum

Cerebelum is a workflow orchestration framework for Elixir that allows you to define, execute, and monitor complex workflows with ease.

## Installation

Add `cerebelum_core` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:cerebelum_core, "~> 0.1.0"}
  ]
end
```

## Your First Workflow

Here's a simple example of a Cerebelum workflow:

```elixir
defmodule MyApp.Workflows.OrderProcessing do
  use Cerebelum.Workflow

  workflow do
    timeline do
      validate_order() |> charge_payment() |> ship_order() |> send_confirmation()
    end
  end

  def validate_order(context) do
    order = context.inputs.order

    if order.amount > 0 do
      {:ok, %{validated: true}}
    else
      {:error, :invalid_amount}
    end
  end

  def charge_payment(_context, validate_result) do
    # Simulate payment processing
    {:ok, %{transaction_id: "TXN-#{:rand.uniform(1000)}"}}
  end

  def ship_order(_context, _validate, charge_result) do
    # Simulate shipping
    {:ok, %{tracking_number: "TRACK-#{:rand.uniform(1000)}"}}
  end

  def send_confirmation(_context, _validate, _charge, ship_result) do
    # Send confirmation email
    {:ok, %{email_sent: true}}
  end
end
```

## Executing a Workflow

To execute your workflow:

```elixir
# Start the workflow
{:ok, execution} = Cerebelum.execute_workflow(
  MyApp.Workflows.OrderProcessing,
  %{order: %{amount: 100, customer_id: "CUST-123"}}
)

# Wait a moment for it to complete
Process.sleep(100)

# Check the status
{:ok, status} = Cerebelum.get_execution_status(execution.id)

# status will contain:
# %{
#   state: :completed,
#   results: %{
#     validate_order: {:ok, %{validated: true}},
#     charge_payment: {:ok, %{transaction_id: "TXN-..."}},
#     ship_order: {:ok, %{tracking_number: "TRACK-..."}},
#     send_confirmation: {:ok, %{email_sent: true}}
#   },
#   ...
# }
```

## Key Concepts

### Timeline

The `timeline` defines the sequential flow of your workflow. Steps are executed in order:

```elixir
timeline do
  step1() |> step2() |> step3()
end
```

### Context

Each step receives a `context` map containing:
- `inputs` - The initial inputs passed to the workflow
- `execution_id` - Unique ID for this execution
- `workflow_module` - The workflow module name

### Step Results

Previous step results are passed as arguments to subsequent steps:

```elixir
def step2(context, step1_result) do
  # Use step1_result here
end

def step3(context, step1_result, step2_result) do
  # Use both previous results
end
```

## Next Steps

- Learn about [Error Handling with Diverge](diverge.md)
- Explore [Conditional Branching](branch.md)
- See [Example Workflows](../tutorials/01-first-workflow.md)

For full API documentation, see the [Cerebelum module docs](Cerebelum.html).

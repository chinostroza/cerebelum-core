defmodule Cerebelum.Examples.OrderWorkflow do
  @moduledoc """
  Ejemplo de workflow: Procesamiento de Órdenes E-commerce.

  Este workflow demuestra:
  - Timeline con múltiples steps
  - Diverge para manejo de errores y retry
  - Branch para decisiones condicionales
  - Flujo de control complejo

  ## Flujo

  1. `validate_order/1` - Valida que la orden sea correcta
     - Diverge: `:timeout` -> retry, `{:error, _}` -> failed
  2. `check_inventory/2` - Verifica inventario disponible
     - Diverge: `{:error, :out_of_stock}` -> back_to(:notify_customer)
  3. `process_payment/2` - Procesa el pago
     - Branch: amount > 1000 -> high_value_path, else -> standard_path
  4. `ship_order/2` - Envía la orden
  5. `notify_customer/2` - Notifica al cliente

  ## Ejemplo de Orden

      order = %{
        id: "ORD-123",
        items: [%{sku: "ITEM-1", quantity: 2, price: 500}],
        customer: %{email: "customer@example.com"},
        shipping_address: %{...}
      }

      context = Context.new(OrderWorkflow, %{order: order})
  """

  use Cerebelum.Workflow

  workflow do
    timeline do
      validate_order() |>
        check_inventory() |>
        process_payment() |>
        ship_order() |>
        notify_customer()
    end

    # Retry en timeout, fail en otros errores
    diverge from: validate_order() do
      :timeout -> :retry
      {:error, :invalid_order} -> :failed
      {:error, _} -> :failed
    end

    # Retry si no hay stock
    diverge from: check_inventory() do
      {:error, :out_of_stock} -> :failed
      {:error, _} -> :failed
    end

    # Decisión basada en monto
    branch after: process_payment(), on: result do
      result.amount > 1000 -> :high_value_path
      true -> :standard_path
    end
  end

  @doc """
  Valida que la orden contenga todos los campos requeridos.

  ## Validaciones

  - Order ID presente
  - Items no vacíos
  - Customer info presente
  - Shipping address presente

  ## Retorna

  - `{:ok, order}` - Orden válida
  - `{:error, :invalid_order}` - Orden inválida
  - `:timeout` - Timeout en validación externa
  """
  def validate_order(context) do
    order = context.inputs[:order]

    cond do
      is_nil(order) ->
        {:error, :invalid_order}

      is_nil(order[:id]) or order[:items] == [] ->
        {:error, :invalid_order}

      is_nil(order[:customer]) or is_nil(order[:shipping_address]) ->
        {:error, :invalid_order}

      true ->
        {:ok, order}
    end
  end

  @doc """
  Verifica que haya inventario disponible para todos los items.

  ## Retorna

  - `{:ok, inventory}` - Inventario confirmado
  - `{:error, :out_of_stock}` - Items no disponibles
  """
  def check_inventory(_context, validated_order) do
    case validated_order do
      {:ok, order} ->
        # Simular verificación de inventario
        items = order[:items] || []

        if Enum.all?(items, fn item -> item[:quantity] > 0 end) do
          {:ok, %{available: true, items: items}}
        else
          {:error, :out_of_stock}
        end

      error ->
        error
    end
  end

  @doc """
  Procesa el pago de la orden.

  ## Retorna

  - `{:ok, payment_result}` - Pago exitoso con detalles
  - `{:error, :payment_failed}` - Pago rechazado
  """
  def process_payment(_context, validated_order, inventory) do
    case {validated_order, inventory} do
      {{:ok, order}, {:ok, _inv}} ->
        items = order[:items] || []
        amount = Enum.reduce(items, 0, fn item, acc ->
          acc + (item[:price] * item[:quantity])
        end)

        {:ok, %{
          amount: amount,
          currency: "USD",
          payment_method: "credit_card",
          status: :paid
        }}

      _ ->
        {:error, :payment_failed}
    end
  end

  @doc """
  Crea el envío para la orden.

  ## Retorna

  - `{:ok, shipment}` - Envío creado con tracking number
  """
  def ship_order(_context, _validated, _inventory, payment) do
    case payment do
      {:ok, _payment_info} ->
        {:ok, %{
          tracking_number: "TRACK-#{:rand.uniform(999999)}",
          carrier: "FedEx",
          estimated_delivery: Date.add(Date.utc_today(), 3)
        }}

      error ->
        error
    end
  end

  @doc """
  Notifica al cliente sobre el estado de la orden.

  ## Retorna

  - `{:ok, notification}` - Notificación enviada
  """
  def notify_customer(_context, validated_order, _inventory, _payment, shipment) do
    case {validated_order, shipment} do
      {{:ok, order}, {:ok, ship_info}} ->
        {:ok, %{
          customer_email: order[:customer][:email],
          subject: "Order #{order[:id]} Shipped!",
          tracking_number: ship_info[:tracking_number],
          sent: true
        }}

      _ ->
        {:ok, %{sent: false}}
    end
  end
end

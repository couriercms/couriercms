defmodule CourierCMS.Adapters.TargetContractTest do
  use ExUnit.Case, async: true

  alias CourierCMS.Extensions.Gateway

  test "every installed target declares an idempotency strategy" do
    targets = Gateway.target_definitions()
    assert targets != []

    for {_component, definition} <- targets do
      key = definition.key

      assert Gateway.target(key, :idempotency_strategy, []) in [
               :deterministic_id,
               :recovery_lookup
             ]

      assert Gateway.target(key, :capabilities, [%{}])["idempotent_delivery"] == true
    end
  end
end

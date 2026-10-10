defmodule CourierCMSExtension.Fake.Store do
  @moduledoc false

  use Agent

  def start_link(_opts),
    do: Agent.start_link(fn -> %{deliveries: %{}, attempts: %{}} end, name: __MODULE__)

  def fetch(connection_id, destination_id, key) do
    Agent.get(__MODULE__, &get_in(&1, [:deliveries, {connection_id, destination_id, key}]))
  end

  def put_new(connection_id, destination_id, key, record) do
    Agent.get_and_update(__MODULE__, fn state ->
      identity = {connection_id, destination_id, key}

      if Map.has_key?(state.deliveries, identity) do
        {:exists, state}
      else
        {:ok, put_in(state, [:deliveries, identity], record)}
      end
    end)
  end

  def replace(connection_id, destination_id, key, target_reference, record) do
    Agent.get_and_update(__MODULE__, fn state ->
      identity = {connection_id, destination_id, key}

      case Map.get(state.deliveries, identity) do
        %{target_reference: ^target_reference} ->
          {:ok, put_in(state, [:deliveries, identity], record)}

        _missing ->
          {:not_found, state}
      end
    end)
  end

  def increment_attempt(connection_id, destination_id, key) do
    Agent.get_and_update(__MODULE__, fn state ->
      identity = {connection_id, destination_id, key}
      count = Map.get(state.attempts, identity, 0) + 1
      {count, put_in(state, [:attempts, identity], count)}
    end)
  end
end

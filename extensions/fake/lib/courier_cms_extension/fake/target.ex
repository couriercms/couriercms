defmodule CourierCMSExtension.Fake.Target do
  @moduledoc "A deterministic in-memory target Adapter for development and tests."

  @behaviour CourierCMS.ExtensionSDK.TargetAdapter

  alias CourierCMS.ExtensionSDK.{AdapterError, Component, DeliveryEnvelope}
  alias CourierCMSExtension.Fake.Store

  @projection_types ~w(string number boolean datetime)

  @impl true
  def component do
    Component.new!(
      extension_id: "com.couriercms.fake",
      component_id: "fake_target",
      kind: :adapter,
      version: "0.1.0",
      capabilities: [:target, :connection_test, :assets, :canonical_document_storage]
    )
  end

  @impl true
  def definition do
    %{
      key: "fake_target",
      label: "Fake destination",
      description: "Development/test-only in-memory target Adapter",
      connection: %{
        endpoint: %{mode: :input, label: "Endpoint", placeholder: "https://fake-target.example"},
        fields: []
      },
      target: %{
        description: "Stores canonical deliveries in memory for local verification.",
        destination_fields: [
          %{
            key: :namespace,
            label: "Target namespace",
            type: :text,
            default: "couriercms",
            required: true,
            help: "Development-only physical placement example."
          }
        ],
        default_projections: []
      }
    }
  end

  @impl true
  def idempotency_strategy, do: :deterministic_id

  @impl true
  def capabilities(_connection) do
    %{
      "target" => true,
      "connection_test" => true,
      "destination_validation" => true,
      "idempotent_delivery" => true,
      "assets" => "streamed_create_or_update",
      "canonical_document_storage" => true,
      "target_projections" => %{"types" => @projection_types}
    }
  end

  @impl true
  def test_connection(connection) do
    if setting(connection, "simulate_connection_failure", false),
      do: {:error, AdapterError.new(:authorization, "Fake target rejected the connection")},
      else: :ok
  end

  @impl true
  def validate_projections(_connection, projections) when is_list(projections) do
    case Enum.find(projections, &(not valid_projection?(&1))) do
      nil -> :ok
      _invalid -> {:error, AdapterError.new(:mapping_failed, "Invalid projection definition")}
    end
  end

  @impl true
  def validate_destination(_connection, settings) when is_map(settings), do: :ok

  @impl true
  def find_delivery(connection, %{id: destination_id}, couriercms_key) do
    case Store.fetch(connection_id(connection), destination_id, couriercms_key) do
      nil ->
        {:ok, :not_found}

      delivery ->
        {:ok, %{target_reference: delivery.target_reference, ownership: delivery.ownership}}
    end
  end

  @impl true
  def create_delivery(connection, %{envelope: %DeliveryEnvelope{} = envelope} = delivery) do
    with :ok <- maybe_fail_once(connection, envelope) do
      record = record(connection, delivery)

      case Store.put_new(
             connection_id(connection),
             envelope.destination_id,
             envelope.delivery_key,
             record
           ) do
        :ok -> {:ok, result(record)}
        :exists -> recover_create(connection, delivery.destination, envelope)
      end
    end
  end

  @impl true
  def update_delivery(
        connection,
        target_reference,
        %{envelope: %DeliveryEnvelope{} = envelope} = delivery,
        ownership
      ) do
    with :ok <- verify_ownership(envelope, ownership),
         :ok <- maybe_fail_once(connection, envelope),
         record = record(connection, delivery),
         :ok <-
           Store.replace(
             connection_id(connection),
             envelope.destination_id,
             envelope.delivery_key,
             target_reference,
             record
           ) do
      {:ok, result(record)}
    else
      :not_found ->
        {:error, AdapterError.new(:source_not_found, "Fake target delivery was not found")}

      {:error, %AdapterError{} = error} ->
        {:error, error}
    end
  end

  @impl true
  def find_asset(connection, %{id: destination_id}, asset_key) do
    case Store.fetch_asset(connection_id(connection), destination_id, asset_key) do
      nil -> {:ok, :not_found}
      asset -> {:ok, %{target_reference: asset.target_reference, ownership: asset.ownership}}
    end
  end

  @impl true
  def create_asset(connection, asset) do
    record = asset_record(connection, asset)

    case Store.put_new_asset(
           connection_id(connection),
           asset.destination.id,
           asset.asset_key,
           record
         ) do
      :ok -> {:ok, result(record)}
      :exists -> recover_asset_create(connection, asset)
    end
  end

  @impl true
  def update_asset(connection, target_reference, asset, ownership) do
    with :ok <- verify_asset_ownership(asset, ownership),
         record = asset_record(connection, asset),
         :ok <-
           Store.replace_asset(
             connection_id(connection),
             asset.destination.id,
             asset.asset_key,
             target_reference,
             record
           ) do
      {:ok, result(record)}
    else
      :not_found ->
        {:error, AdapterError.new(:source_not_found, "Fake target asset was not found")}

      {:error, %AdapterError{} = error} ->
        {:error, error}
    end
  end

  defp recover_create(connection, destination, envelope) do
    case find_delivery(connection, destination, envelope.delivery_key) do
      {:ok, %{target_reference: id, ownership: ownership}} ->
        with :ok <- verify_ownership(envelope, ownership) do
          {:ok, %{target_reference: id, ownership: ownership}}
        end

      _other ->
        {:error, AdapterError.new(:target_rejected, "Fake target could not create the delivery")}
    end
  end

  defp recover_asset_create(connection, asset) do
    case find_asset(connection, asset.destination, asset.asset_key) do
      {:ok, %{target_reference: id, ownership: ownership}} ->
        with :ok <- verify_asset_ownership(asset, ownership) do
          {:ok, %{target_reference: id, ownership: ownership}}
        end

      _other ->
        {:error, AdapterError.new(:target_rejected, "Fake target could not create the asset")}
    end
  end

  defp asset_record(connection, asset) do
    bytes = asset.content.chunks |> Enum.to_list() |> IO.iodata_to_binary()

    %{
      connection_id: connection_id(connection),
      couriercms_asset_key: asset.asset_key,
      target_reference: "fake-asset:#{asset.destination.id}:#{asset.asset_key}",
      ownership: stringify_keys(asset.ownership),
      descriptor: asset.descriptor,
      bytes: bytes
    }
  end

  defp verify_asset_ownership(asset, ownership) do
    expected = stringify_keys(asset.ownership)

    if ownership == expected do
      :ok
    else
      {:error,
       AdapterError.new(:ownership_violation, "Target asset ownership metadata does not match")}
    end
  end

  defp stringify_keys(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp record(connection, delivery) do
    envelope = delivery.envelope

    %{
      connection_id: connection_id(connection),
      couriercms_key: envelope.delivery_key,
      target_reference: "fake:#{envelope.destination_id}:#{envelope.delivery_key}",
      name: target_name(delivery.name),
      ownership: %{
        "installation_id" => envelope.installation_id,
        "route_id" => envelope.route_id,
        "destination_id" => envelope.destination_id,
        "couriercms_key" => envelope.delivery_key
      },
      envelope: envelope,
      payload: delivery.payload,
      canonical_document: delivery.canonical_document,
      projections: delivery.projections,
      content_hash: envelope.content_hash
    }
  end

  defp result(record),
    do: %{target_reference: record.target_reference, ownership: record.ownership}

  defp verify_ownership(envelope, ownership) do
    if ownership["installation_id"] == envelope.installation_id &&
         ownership["route_id"] == envelope.route_id &&
         ownership["destination_id"] == envelope.destination_id &&
         ownership["couriercms_key"] == envelope.delivery_key do
      :ok
    else
      {:error,
       AdapterError.new(
         :ownership_violation,
         "Target ownership metadata does not match this Route"
       )}
    end
  end

  defp maybe_fail_once(connection, envelope) do
    if envelope.source_identity.item_key in setting(connection, "fail_once_for", []) &&
         Store.increment_attempt(
           connection_id(connection),
           envelope.destination_id,
           envelope.delivery_key
         ) == 1 do
      {:error,
       AdapterError.new(:temporarily_unavailable, "Simulated temporary target outage",
         retryable: true
       )}
    else
      :ok
    end
  end

  defp valid_projection?(projection) when is_map(projection) do
    is_binary(projection["target_field"] || projection[:target_field]) &&
      is_binary(projection["source_path"] || projection[:source_path]) &&
      (projection["type"] || projection[:type]) in @projection_types
  end

  defp valid_projection?(_projection), do: false

  defp connection_id(connection),
    do: Map.get(connection, :id) || Map.get(connection, "id") || "default"

  defp setting(connection, key, default) do
    settings = Map.get(connection, :settings) || Map.get(connection, "settings") || %{}
    Map.get(settings, key, default)
  end

  defp target_name(%{value: value, suffix: suffix}) do
    value = value |> String.downcase() |> String.replace(~r/[^a-z0-9]+/u, "-") |> String.trim("-")
    "#{if(value == "", do: "delivery", else: value)}--#{suffix}"
  end
end

defmodule CourierCMSExtension.Sanity.Target do
  @moduledoc "Sanity Content Lake target Adapter for CourierCMS destination deliveries."

  @behaviour CourierCMS.ExtensionSDK.TargetAdapter

  alias CourierCMSExtension.Sanity.Client
  alias CourierCMS.ExtensionSDK.{AdapterError, Component, DeliveryEnvelope}

  @projection_fields %{
    "projectedTitle" => "string",
    "projectedSlug" => "string",
    "projectedPublishedAt" => "datetime",
    "projectedNumber" => "number",
    "projectedBoolean" => "boolean"
  }

  @impl true
  def component do
    Component.new!(
      extension_id: "com.couriercms.sanity",
      component_id: "sanity",
      kind: :adapter,
      version: "0.1.0",
      capabilities: [
        :target,
        :connection_test,
        :assets,
        :canonical_document_storage,
        :target_projections
      ]
    )
  end

  @impl true
  def definition do
    %{
      key: "sanity",
      label: "Sanity",
      description: "Sanity Content Lake target Adapter",
      connection: %{
        description: "Use a dedicated project robot token with read/write access.",
        endpoint: %{mode: :derived, template: "https://{project_id}.api.sanity.io"},
        fields: [
          %{
            key: :organization_id,
            label: "Organization ID",
            type: :text,
            storage: :setting,
            help: "Optional administrative metadata."
          },
          %{
            key: :project_id,
            label: "Project ID",
            type: :text,
            storage: :setting,
            required: true,
            pattern: ~r/^[a-z0-9]+$/,
            pattern_message: "must contain only lowercase letters and digits"
          },
          %{
            key: :dataset,
            label: "Dataset",
            type: :text,
            storage: :setting,
            required: true,
            default: "production",
            pattern: ~r/^[A-Za-z0-9_-]+$/,
            pattern_message: "must contain only letters, digits, underscores, or hyphens"
          },
          %{
            key: :api_version,
            label: "API version",
            type: :text,
            storage: :setting,
            required: true,
            default: "v2026-09-24",
            hidden: true
          },
          %{
            key: :token,
            label: "Project robot token",
            type: :password,
            storage: :credential,
            required: true,
            min_length: 8,
            autocomplete: "new-password",
            help: "Encrypted before storage and never shown again."
          }
        ]
      },
      target: %{
        description: "Writes canonical documents into the CourierCMS Intake Schema.",
        default_projections: [
          %{
            "target_field" => "projectedTitle",
            "source_path" => "payload.title",
            "type" => "string",
            "required" => false
          },
          %{
            "target_field" => "projectedSlug",
            "source_path" => "payload.slug",
            "type" => "string",
            "required" => false
          },
          %{
            "target_field" => "projectedPublishedAt",
            "source_path" => "payload.published_at",
            "type" => "datetime",
            "required" => false
          }
        ]
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
      "canonical_document_storage" => "json_text",
      "target_projections" => %{"fields" => @projection_fields},
      "assets" => "independent_featured_image"
    }
  end

  @impl true
  def test_connection(connection), do: client(connection).test_connection(connection)

  @impl true
  def validate_projections(_connection, projections) do
    with :ok <- validate_projection_definitions(projections) do
      Enum.reduce_while(projections, :ok, fn projection, :ok ->
        field = projection["target_field"]
        type = projection["type"]

        case @projection_fields[field] do
          ^type ->
            {:cont, :ok}

          nil ->
            {:halt,
             {:error,
              AdapterError.new(
                :mapping_failed,
                "Sanity Intake Schema does not define projection field #{field}"
              )}}

          installed_type ->
            {:halt,
             {:error,
              AdapterError.new(
                :mapping_failed,
                "Sanity projection #{field} is #{installed_type}, not #{type}"
              )}}
        end
      end)
    end
  end

  @impl true
  def validate_destination(_connection, settings) when settings in [%{}, nil], do: :ok

  def validate_destination(_connection, _settings) do
    {:error,
     AdapterError.new(
       :invalid_content,
       "Sanity Destinations are logical and do not accept physical placement settings"
     )}
  end

  @impl true
  def find_delivery(connection, %{id: destination_id}, couriercms_key) do
    case client(connection).find_delivery(connection, destination_id, couriercms_key) do
      {:ok, nil} ->
        {:ok, :not_found}

      {:ok, %{"_id" => id} = document} ->
        {:ok, %{target_reference: id, ownership: ownership_from_document(document)}}

      {:ok, _other} ->
        {:error, AdapterError.new(:invalid_content, "Sanity returned an invalid delivery")}

      error ->
        error
    end
  end

  @impl true
  def create_delivery(
        connection,
        %{
          envelope: envelope,
          payload: payload,
          canonical_document: canonical_document,
          projections: projections,
          destination: destination
        } = delivery
      ) do
    with {:ok, image} <- upload_featured_image(connection, payload) do
      document =
        delivery_document(
          envelope,
          payload,
          canonical_document,
          projections,
          image,
          delivery_name(delivery.name)
        )

      case client(connection).create_document(connection, document) do
        {:ok, document_id} ->
          {:ok, result(document_id, envelope)}

        {:error, %AdapterError{category: :target_rejected}} ->
          recover_create(connection, destination, envelope)

        error ->
          error
      end
    end
  end

  @impl true
  def update_delivery(
        connection,
        document_id,
        %{
          envelope: envelope,
          payload: payload,
          canonical_document: canonical_document,
          projections: projections
        } = delivery,
        ownership
      ) do
    with :ok <- verify_ownership(envelope, ownership),
         {:ok, image} <- upload_featured_image(connection, payload),
         document <-
           delivery_document(
             envelope,
             payload,
             canonical_document,
             projections,
             image,
             delivery_name(delivery.name)
           ),
         fields <- Map.drop(document, ["_id", "_type"]),
         unset <- unset_fields(image, projections),
         {:ok, ^document_id} <-
           client(connection).patch_document(connection, document_id, fields, unset) do
      {:ok, result(document_id, envelope)}
    end
  end

  @impl true
  def find_asset(connection, %{id: destination_id}, asset_key) do
    receipt_id = asset_receipt_id(destination_id, asset_key)

    case client(connection).find_asset_receipt(connection, receipt_id) do
      {:ok, nil} ->
        {:ok, :not_found}

      {:ok, %{"assetId" => asset_id} = receipt}
      when is_binary(asset_id) and asset_id != "" ->
        {:ok, %{target_reference: asset_id, ownership: asset_ownership_from_receipt(receipt)}}

      {:ok, _other} ->
        {:error, AdapterError.new(:invalid_content, "Sanity returned an invalid asset receipt")}

      error ->
        error
    end
  end

  @impl true
  def create_asset(connection, asset) do
    with {:ok, asset_id} <- client(connection).upload_image(connection, asset) do
      receipt = asset_receipt(asset, asset_id)

      case client(connection).create_document(connection, receipt) do
        {:ok, _receipt_id} ->
          {:ok, asset_result(asset_id, asset.ownership)}

        {:error, %AdapterError{category: :target_rejected}} ->
          recover_asset_create(connection, asset)

        error ->
          error
      end
    end
  end

  @impl true
  def update_asset(connection, _target_reference, asset, ownership) do
    with :ok <- verify_asset_ownership(asset, ownership),
         {:ok, asset_id} <- client(connection).upload_image(connection, asset),
         receipt_id <- asset_receipt_id(asset.destination.id, asset.asset_key),
         fields <- asset_receipt(asset, asset_id) |> Map.drop(["_id", "_type"]),
         {:ok, ^receipt_id} <- client(connection).patch_document(connection, receipt_id, fields) do
      {:ok, asset_result(asset_id, asset.ownership)}
    end
  end

  defp upload_featured_image(connection, %{"featured_image" => descriptor})
       when is_map(descriptor) do
    case {descriptor["target_reference"], descriptor["source_url"]} do
      {asset_id, _url} when is_binary(asset_id) and asset_id != "" ->
        {:ok, sanity_image(asset_id, descriptor)}

      {_asset_id, url} when is_binary(url) and url != "" ->
        with {:ok, asset_id} <- client(connection).upload_image_from_url(connection, descriptor) do
          {:ok, sanity_image(asset_id, descriptor)}
        end

      _other ->
        {:ok, nil}
    end
  end

  defp upload_featured_image(_connection, _payload), do: {:ok, nil}

  defp delivery_document(
         %DeliveryEnvelope{} = envelope,
         payload,
         canonical_document,
         projections,
         image,
         delivery_name
       ) do
    identity = envelope.source_identity

    %{
      "_id" => target_document_id(envelope.destination_id, envelope.delivery_key),
      "_type" => "couriercmsDelivery",
      "title" => delivery_name,
      "couriercmsKey" => envelope.delivery_key,
      "installationId" => envelope.installation_id,
      "routeId" => envelope.route_id,
      "destinationId" => envelope.destination_id,
      "routeRevision" => envelope.route_revision,
      "sourceConnectionId" => envelope.source_connection_id,
      "sourceItemId" => identity.item_key,
      "sourceType" => envelope.source_type,
      "locale" => identity.locale_key,
      "sourceRevision" => identity.revision_key,
      "sourceState" => to_string(identity.state),
      "sourceModifiedAt" => iso8601(identity.modified_at),
      "contractVersion" => envelope.contract_version,
      "contentHash" => envelope.content_hash,
      "deliveredAt" => iso8601(envelope.delivered_at),
      "sourceUrl" => payload["canonical_url"],
      "deliveryJson" => Jason.encode!(canonical_document),
      "featuredImage" => image
    }
    |> Map.merge(Map.reject(projections, fn {_field, value} -> is_nil(value) end))
    |> compact()
  end

  defp unset_fields(image, projections) do
    compatibility_fields = ["payloadJson"]
    image_fields = if image, do: [], else: ["featuredImage"]

    missing_projection_fields =
      @projection_fields
      |> Map.keys()
      |> Enum.reject(&(Map.get(projections, &1) != nil))

    compatibility_fields ++ image_fields ++ missing_projection_fields
  end

  defp validate_projection_definitions(projections) do
    case CourierCMS.ExtensionSDK.ProjectionDefinition.validate(projections) do
      :ok -> :ok
      {:error, message} -> {:error, AdapterError.new(:mapping_failed, message)}
    end
  end

  defp verify_ownership(envelope, ownership) do
    if ownership["installation_id"] == envelope.installation_id &&
         ownership["route_id"] == envelope.route_id &&
         ownership["destination_id"] == envelope.destination_id &&
         ownership["couriercms_key"] == envelope.delivery_key do
      :ok
    else
      {:error,
       AdapterError.new(:ownership_violation, "Sanity document is not owned by this Route")}
    end
  end

  defp recover_create(connection, destination, envelope) do
    case find_delivery(connection, destination, envelope.delivery_key) do
      {:ok, %{target_reference: id, ownership: ownership}} ->
        with :ok <- verify_ownership(envelope, ownership) do
          {:ok, result(id, envelope)}
        end

      _other ->
        {:error,
         AdapterError.new(:target_rejected, "Sanity could not create or recover the delivery")}
    end
  end

  defp recover_asset_create(connection, asset) do
    case find_asset(connection, asset.destination, asset.asset_key) do
      {:ok, %{target_reference: asset_id, ownership: ownership}} ->
        with :ok <- verify_asset_ownership(asset, ownership) do
          {:ok, asset_result(asset_id, ownership)}
        end

      _other ->
        {:error,
         AdapterError.new(:target_rejected, "Sanity could not create or recover the asset")}
    end
  end

  defp asset_receipt(asset, asset_id) do
    ownership = stringify_keys(asset.ownership)

    %{
      "_id" => asset_receipt_id(asset.destination.id, asset.asset_key),
      "_type" => "couriercmsAsset",
      "couriercmsAssetKey" => asset.asset_key,
      "installationId" => ownership["installation_id"],
      "routeId" => ownership["route_id"],
      "destinationId" => ownership["destination_id"],
      "asset" => %{"_type" => "reference", "_ref" => asset_id},
      "filename" => asset.descriptor.filename,
      "mediaType" => asset.content.media_type,
      "contentHash" => asset.content.checksum
    }
    |> compact()
  end

  defp asset_ownership_from_receipt(receipt) do
    %{
      "installation_id" => receipt["installationId"],
      "route_id" => receipt["routeId"],
      "destination_id" => receipt["destinationId"],
      "couriercms_asset_key" => receipt["couriercmsAssetKey"]
    }
  end

  defp verify_asset_ownership(asset, ownership) do
    if stringify_keys(ownership) == stringify_keys(asset.ownership) do
      :ok
    else
      {:error, AdapterError.new(:ownership_violation, "Sanity asset is not owned by this Route")}
    end
  end

  defp asset_result(asset_id, ownership),
    do: %{target_reference: asset_id, ownership: stringify_keys(ownership)}

  defp sanity_image(asset_id, descriptor) do
    compact(%{
      "_type" => "image",
      "asset" => %{"_type" => "reference", "_ref" => asset_id},
      "alt" => descriptor["alt"] || get_in(descriptor, ["metadata", "alt"])
    })
  end

  defp ownership_from_document(document) do
    %{
      "installation_id" => document["installationId"],
      "route_id" => document["routeId"],
      "destination_id" => document["destinationId"],
      "couriercms_key" => document["couriercmsKey"]
    }
  end

  defp result(document_id, envelope) do
    %{
      target_reference: document_id,
      ownership: %{
        "installation_id" => envelope.installation_id,
        "route_id" => envelope.route_id,
        "destination_id" => envelope.destination_id,
        "couriercms_key" => envelope.delivery_key
      }
    }
  end

  defp compact(map), do: Map.reject(map, fn {_key, value} -> value in [nil, "", []] end)

  defp target_document_id(destination_id, delivery_key) do
    digest =
      :crypto.hash(:sha256, destination_id <> <<0>> <> delivery_key)
      |> Base.url_encode64(padding: false)

    "couriercms.#{digest}"
  end

  defp asset_receipt_id(destination_id, asset_key) do
    digest =
      :crypto.hash(:sha256, destination_id <> <<0>> <> asset_key)
      |> Base.url_encode64(padding: false)

    "couriercms.asset.#{digest}"
  end

  defp stringify_keys(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp stringify_keys(_value), do: %{}

  defp delivery_name(%{value: value, suffix: suffix}) do
    base =
      value
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")

    "#{if(base == "", do: "delivery", else: base)}--#{suffix}"
  end

  defp iso8601(nil), do: nil
  defp iso8601(datetime), do: DateTime.to_iso8601(datetime)
  defp client(connection), do: setting(connection, :client, Client)

  defp setting(%{settings: settings}, key, default) when is_map(settings),
    do: Map.get(settings, key, Map.get(settings, to_string(key), default))

  defp setting(_connection, _key, default), do: default
end

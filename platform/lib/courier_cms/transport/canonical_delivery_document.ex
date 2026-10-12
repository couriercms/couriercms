defmodule CourierCMS.Transport.CanonicalDeliveryDocument do
  @moduledoc "Builds the complete authoritative document retained by every target delivery."

  alias CourierCMS.ExtensionSDK.DeliveryEnvelope

  @spec build(DeliveryEnvelope.t(), map(), [map()]) :: map()
  def build(%DeliveryEnvelope{} = envelope, payload, assets \\ [])
      when is_map(payload) and is_list(assets) do
    %{
      "couriercms" => envelope_map(envelope),
      "payload" => payload
    }
    |> maybe_put_assets(assets)
  end

  defp maybe_put_assets(document, []), do: document
  defp maybe_put_assets(document, assets), do: Map.put(document, "assets", assets)

  defp envelope_map(envelope) do
    identity = envelope.source_identity

    compact(%{
      "envelopeVersion" => envelope.envelope_version,
      "installationId" => envelope.installation_id,
      "routeId" => envelope.route_id,
      "destinationId" => envelope.destination_id,
      "routeRevision" => envelope.route_revision,
      "deliveryKey" => envelope.delivery_key,
      "sourceConnectionId" => envelope.source_connection_id,
      "sourceItemId" => identity.item_key,
      "sourceType" => envelope.source_type,
      "locale" => identity.locale_key,
      "sourceRevision" => identity.revision_key,
      "sourceState" => to_string(identity.state),
      "sourceModifiedAt" => iso8601(identity.modified_at),
      "contractVersion" => envelope.contract_version,
      "deliveredAt" => iso8601(envelope.delivered_at),
      "contentHash" => envelope.content_hash
    })
  end

  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)
  defp iso8601(nil), do: nil
  defp iso8601(datetime), do: DateTime.to_iso8601(datetime)
end

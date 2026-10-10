defmodule CourierCMS.ExtensionSDK.DeliveryEnvelope do
  @moduledoc "Stable CourierCMS metadata wrapped around a versioned delivery payload."

  alias CourierCMS.ExtensionSDK.SourceIdentity

  @enforce_keys [
    :installation_id,
    :route_id,
    :destination_id,
    :route_revision,
    :delivery_key,
    :source_connection_id,
    :source_identity,
    :source_type,
    :contract_version,
    :content_hash
  ]

  defstruct envelope_version: 1,
            installation_id: nil,
            route_id: nil,
            destination_id: nil,
            route_revision: nil,
            delivery_key: nil,
            source_connection_id: nil,
            source_identity: nil,
            source_type: nil,
            contract_version: nil,
            delivered_at: nil,
            content_hash: nil

  @type t :: %__MODULE__{
          envelope_version: pos_integer(),
          installation_id: String.t(),
          route_id: String.t(),
          destination_id: String.t(),
          route_revision: pos_integer(),
          delivery_key: String.t(),
          source_connection_id: String.t(),
          source_identity: SourceIdentity.t(),
          source_type: String.t(),
          contract_version: pos_integer(),
          delivered_at: DateTime.t() | nil,
          content_hash: String.t()
        }
end

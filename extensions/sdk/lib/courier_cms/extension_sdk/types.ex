defmodule CourierCMS.ExtensionSDK.Types do
  @moduledoc "Transport-neutral boundary types used by Extension behaviours."

  alias CourierCMS.ExtensionSDK.{
    AdapterError,
    AssetContent,
    AssetDescriptor,
    ContentBundle,
    DeliveryEnvelope,
    SourceIdentity
  }

  @type connection :: map()
  @type selection :: map()
  @type cursor :: term()
  @type normalized_identity :: SourceIdentity.t()
  @type normalized_content :: ContentBundle.t()
  @type asset_content :: AssetContent.t()
  @type delivery :: %{
          required(:envelope) => DeliveryEnvelope.t(),
          required(:payload) => map(),
          required(:canonical_document) => map(),
          required(:projections) => map(),
          required(:name) => %{required(:value) => String.t(), required(:suffix) => String.t()},
          required(:destination) => %{
            required(:id) => String.t(),
            required(:scope) => map()
          }
        }
  @type asset_delivery :: %{
          required(:asset_key) => String.t(),
          required(:descriptor) => AssetDescriptor.t(),
          required(:content) => AssetContent.t(),
          required(:destination) => %{
            required(:id) => String.t(),
            required(:scope) => map()
          },
          required(:ownership) => %{
            required(:installation_id) => String.t(),
            required(:route_id) => String.t(),
            required(:destination_id) => String.t(),
            required(:couriercms_asset_key) => String.t()
          }
        }
  @type adapter_error :: AdapterError.t()
end

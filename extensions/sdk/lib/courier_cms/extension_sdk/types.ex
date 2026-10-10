defmodule CourierCMS.ExtensionSDK.Types do
  @moduledoc "Transport-neutral boundary types used by Extension behaviours."

  alias CourierCMS.ExtensionSDK.{AdapterError, ContentNode, DeliveryEnvelope, SourceIdentity}

  @type connection :: map()
  @type selection :: map()
  @type cursor :: term()
  @type normalized_identity :: SourceIdentity.t()
  @type normalized_content :: ContentNode.t()
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
  @type adapter_error :: AdapterError.t()
end

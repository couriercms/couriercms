defmodule CourierCMS.ExtensionSDK.ContentNode do
  @moduledoc "Normalized source content node used to assemble a bounded content graph."

  alias CourierCMS.ExtensionSDK.SourceIdentity

  @enforce_keys [:identity, :source_type]
  defstruct identity: nil,
            source_type: nil,
            name: nil,
            path: nil,
            fields: %{},
            references: [],
            assets: [],
            metadata: %{}

  @type t :: %__MODULE__{
          identity: SourceIdentity.t(),
          source_type: String.t(),
          name: String.t() | nil,
          path: String.t() | nil,
          fields: map(),
          references: list(),
          assets: list(),
          metadata: map()
        }
end

defmodule CourierCMS.ExtensionSDK.ContentNode do
  @moduledoc "One normalized content node contained in a ContentBundle."

  alias CourierCMS.ExtensionSDK.SourceIdentity

  @enforce_keys [:identity, :source_type]
  defstruct identity: nil,
            source_type: nil,
            name: nil,
            path: nil,
            fields: %{},
            metadata: %{}

  @type t :: %__MODULE__{
          identity: SourceIdentity.t(),
          source_type: String.t(),
          name: String.t() | nil,
          path: String.t() | nil,
          fields: map(),
          metadata: map()
        }
end

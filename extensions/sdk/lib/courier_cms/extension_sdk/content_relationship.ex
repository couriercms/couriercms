defmodule CourierCMS.ExtensionSDK.ContentRelationship do
  @moduledoc "A normalized relationship between two nodes in a ContentBundle."

  alias CourierCMS.ExtensionSDK.SourceIdentity

  @enforce_keys [:name, :from, :to]
  defstruct name: nil,
            from: nil,
            to: nil,
            position: nil,
            required: true,
            metadata: %{}

  @type t :: %__MODULE__{
          name: String.t(),
          from: SourceIdentity.t(),
          to: SourceIdentity.t(),
          position: non_neg_integer() | nil,
          required: boolean(),
          metadata: map()
        }

  @spec identity(t()) :: {String.t(), String.t(), String.t(), non_neg_integer() | nil}
  def identity(%__MODULE__{} = relationship) do
    {
      SourceIdentity.logical_key(relationship.from),
      relationship.name,
      SourceIdentity.logical_key(relationship.to),
      relationship.position
    }
  end
end

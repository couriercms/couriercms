defmodule CourierCMS.ExtensionSDK.AssetDescriptor do
  @moduledoc """
  Ephemeral description of one source media or file dependency.

  The descriptor is part of a ContentBundle. It is not a persisted Delivery
  Asset or a transport for binary data. The source Adapter remains responsible
  for interpreting the bounded retrieval metadata.
  """

  @enforce_keys [:source_key]
  defstruct source_key: nil,
            variant_key: "original",
            field_path: nil,
            filename: nil,
            media_type: nil,
            size: nil,
            checksum: nil,
            required: true,
            retrieval: %{},
            metadata: %{}

  @type t :: %__MODULE__{
          source_key: String.t(),
          variant_key: String.t(),
          field_path: String.t() | nil,
          filename: String.t() | nil,
          media_type: String.t() | nil,
          size: non_neg_integer() | nil,
          checksum: String.t() | nil,
          required: boolean(),
          retrieval: map(),
          metadata: map()
        }

  @spec identity(t()) :: {String.t(), String.t()}
  def identity(%__MODULE__{} = descriptor),
    do: {descriptor.source_key, descriptor.variant_key}
end

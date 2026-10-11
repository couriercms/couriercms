defmodule CourierCMS.ExtensionSDK.AssetContent do
  @moduledoc """
  A bounded, replayable stream returned by a source Adapter for one asset.

  `chunks` must be an enumerable of binaries and must be safe to enumerate once.
  The platform consumes it inside the current asset attempt; it is never stored
  in a database or Oban job argument.
  """

  @enforce_keys [:chunks]
  defstruct chunks: [], byte_size: nil, checksum: nil, media_type: nil

  @type t :: %__MODULE__{
          chunks: term(),
          byte_size: non_neg_integer() | nil,
          checksum: String.t() | nil,
          media_type: String.t() | nil
        }
end

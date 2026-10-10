defmodule CourierCMS.Extensions.Diagnostic do
  @moduledoc "A safe operator-facing result from discovering or loading an Extension package."

  @enforce_keys [:package, :status, :message]
  defstruct [:package, :extension_id, :version, :checksum, :status, :message]

  @type status :: :loaded | :rejected
  @type t :: %__MODULE__{
          package: String.t(),
          extension_id: String.t() | nil,
          version: String.t() | nil,
          checksum: String.t() | nil,
          status: status(),
          message: String.t()
        }
end

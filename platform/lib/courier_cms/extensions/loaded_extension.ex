defmodule CourierCMS.Extensions.LoadedExtension do
  @moduledoc false

  @enforce_keys [
    :manifest,
    :package_path,
    :package_checksum,
    :cache_path,
    :otp_application,
    :code_path,
    :component_entries
  ]
  defstruct @enforce_keys
end

defmodule CourierCMS.EncryptedMap do
  @moduledoc "Encrypted-at-rest map type for credentials and other secret values."

  use Cloak.Ecto.Map, vault: CourierCMS.Vault
end

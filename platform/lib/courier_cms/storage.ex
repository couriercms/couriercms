defmodule CourierCMS.Storage do
  @moduledoc "Database-specific primitives kept below CourierCMS domain logic."

  import Ecto.Query, only: [lock: 2]

  alias CourierCMS.ReleaseProfile

  @doc "Uses PostgreSQL row locking; SQLite Local transactions serialize writers."
  def lock_for_update(query) do
    if ReleaseProfile.server?(), do: lock(query, "FOR UPDATE"), else: query
  end

  @doc "Encodes UUID parameters for raw SQL using the selected adapter's storage form."
  def uuid_parameter(uuid) when is_binary(uuid) do
    if ReleaseProfile.local?(), do: uuid, else: Ecto.UUID.dump!(uuid)
  end
end

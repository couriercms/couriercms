defmodule CourierCMS.Execution.DeliveryLock do
  @moduledoc """
  A database-backed lease that serializes delivery for one logical item.

  Leases avoid holding a database connection while an adapter performs remote
  calls. Expiry makes locks recoverable after an abrupt worker termination.
  """

  use Ecto.Schema
  import Ecto.Query

  alias CourierCMS.Repo

  @primary_key {:delivery_key, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "delivery_locks" do
    field :owner_token, Ecto.UUID
    field :expires_at, :utc_datetime_usec

    timestamps()
  end

  @spec acquire(String.t(), Ecto.UUID.t(), non_neg_integer()) :: :ok | :busy
  def acquire(delivery_key, owner_token, ttl_ms) do
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, ttl_ms, :millisecond)

    query = """
    INSERT INTO delivery_locks
      (delivery_key, owner_token, expires_at, inserted_at, updated_at)
    VALUES ($1, $2, $3, $4, $4)
    ON CONFLICT (delivery_key) DO UPDATE
    SET owner_token = EXCLUDED.owner_token,
        expires_at = EXCLUDED.expires_at,
        updated_at = EXCLUDED.updated_at
    WHERE delivery_locks.expires_at <= EXCLUDED.inserted_at
       OR delivery_locks.owner_token = EXCLUDED.owner_token
    RETURNING delivery_key
    """

    dumped_owner_token = Ecto.UUID.dump!(owner_token)

    case Ecto.Adapters.SQL.query!(Repo, query, [delivery_key, dumped_owner_token, expires_at, now]) do
      %{num_rows: 1} -> :ok
      %{num_rows: 0} -> :busy
    end
  end

  @spec release(String.t(), Ecto.UUID.t()) :: :ok
  def release(delivery_key, owner_token) do
    from(lock in __MODULE__,
      where: lock.delivery_key == ^delivery_key and lock.owner_token == ^owner_token
    )
    |> Repo.delete_all()

    :ok
  end
end

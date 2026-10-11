defmodule CourierCMS.Execution.ConnectionLimiter do
  @moduledoc """
  Cluster-wide concurrency leases for configured CMS Connections.

  Each Connection owns a bounded set of database-coordinated slots. Leases are
  acquired in stable Connection-ID order and expire after an abrupt worker exit.
  """

  alias CourierCMS.Repo
  alias CourierCMS.Storage

  @type lease :: {Ecto.UUID.t(), pos_integer()}

  @spec with_leases([map()], Ecto.UUID.t(), non_neg_integer(), (-> result)) ::
          result | {:snooze, pos_integer()}
        when result: term()
  def with_leases(connections, owner_token, ttl_ms, function) do
    case acquire_all(connections, owner_token, ttl_ms) do
      {:ok, leases} ->
        try do
          function.()
        after
          release_all(leases, owner_token)
        end

      :busy ->
        :telemetry.execute([:couriercms, :connection, :saturated], %{count: 1}, %{})
        {:snooze, 1}
    end
  end

  @spec acquire(map(), Ecto.UUID.t(), non_neg_integer()) :: {:ok, lease()} | :busy
  def acquire(connection, owner_token, ttl_ms) do
    limit = concurrency_limit(connection)

    Enum.find_value(1..limit, :busy, fn slot_number ->
      if acquire_slot(connection.id, slot_number, owner_token, ttl_ms) do
        {:ok, {connection.id, slot_number}}
      end
    end)
  end

  @spec release(lease(), Ecto.UUID.t()) :: :ok
  def release({connection_id, slot_number}, owner_token) do
    Ecto.Adapters.SQL.query!(
      Repo,
      """
      DELETE FROM connection_leases
      WHERE connection_id = $1 AND slot_number = $2 AND owner_token = $3
      """,
      [Storage.uuid_parameter(connection_id), slot_number, Storage.uuid_parameter(owner_token)]
    )

    :ok
  end

  defp acquire_all(connections, owner_token, ttl_ms) do
    connections
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce_while({:ok, []}, fn connection, {:ok, leases} ->
      case acquire(connection, owner_token, ttl_ms) do
        {:ok, lease} ->
          {:cont, {:ok, [lease | leases]}}

        :busy ->
          release_all(leases, owner_token)
          {:halt, :busy}
      end
    end)
  end

  defp release_all(leases, owner_token) do
    Enum.each(leases, &release(&1, owner_token))
    :ok
  end

  defp acquire_slot(connection_id, slot_number, owner_token, ttl_ms) do
    now = DateTime.utc_now()
    expires_at = DateTime.add(now, ttl_ms, :millisecond)

    query = """
    INSERT INTO connection_leases
      (connection_id, slot_number, owner_token, expires_at, inserted_at, updated_at)
    VALUES ($1, $2, $3, $4, $5, $5)
    ON CONFLICT (connection_id, slot_number) DO UPDATE
    SET owner_token = EXCLUDED.owner_token,
        expires_at = EXCLUDED.expires_at,
        updated_at = EXCLUDED.updated_at
    WHERE connection_leases.expires_at <= EXCLUDED.inserted_at
       OR connection_leases.owner_token = EXCLUDED.owner_token
    RETURNING slot_number
    """

    params = [
      Storage.uuid_parameter(connection_id),
      slot_number,
      Storage.uuid_parameter(owner_token),
      expires_at,
      now
    ]

    Ecto.Adapters.SQL.query!(Repo, query, params).num_rows == 1
  end

  defp concurrency_limit(connection) do
    configured =
      Map.get(connection.settings || %{}, "max_concurrency") ||
        Map.get(connection.settings || %{}, :max_concurrency)

    case configured do
      value when is_integer(value) and value > 0 and value <= 100 -> value
      _other -> Application.fetch_env!(:couriercms, :default_connection_concurrency)
    end
  end
end

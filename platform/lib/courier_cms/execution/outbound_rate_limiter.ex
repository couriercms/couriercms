defmodule CourierCMS.Execution.OutboundRateLimiter do
  @moduledoc "Cluster-wide fixed-window request limiting for CMS Connections."

  alias CourierCMS.ExtensionSDK.AdapterError
  alias CourierCMS.Repo
  alias CourierCMS.Storage

  def check(connection) do
    if Application.get_env(:couriercms, :outbound_rate_limiting, true) do
      do_check(connection)
    else
      :ok
    end
  end

  defp do_check(connection) do
    limit = request_limit(connection)
    bucket = System.system_time(:second)
    now = DateTime.utc_now()

    result =
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        INSERT INTO connection_rate_buckets
          (connection_id, bucket, request_count, inserted_at, updated_at)
        VALUES ($1, $2, 1, $3, $3)
        ON CONFLICT (connection_id, bucket) DO UPDATE
        SET request_count = connection_rate_buckets.request_count + 1,
            updated_at = EXCLUDED.updated_at
        WHERE connection_rate_buckets.request_count < $4
        RETURNING request_count
        """,
        [Storage.uuid_parameter(connection.id), bucket, now, limit]
      )

    if result.num_rows == 1 do
      :ok
    else
      retry_after_ms = 1_000 - rem(System.system_time(:millisecond), 1_000)

      :telemetry.execute(
        [:couriercms, :connection, :rate_limited],
        %{count: 1},
        %{adapter: connection.adapter_key}
      )

      {:error,
       AdapterError.new(:rate_limited, "Connection request-rate limit reached",
         retryable: true,
         retry_after_ms: retry_after_ms
       )}
    end
  end

  defp request_limit(connection) do
    configured =
      Map.get(connection.settings || %{}, "requests_per_second") ||
        Map.get(connection.settings || %{}, :requests_per_second)

    case configured do
      value when is_integer(value) and value in 1..10_000 -> value
      _other -> Application.fetch_env!(:couriercms, :default_connection_requests_per_second)
    end
  end
end

defmodule CourierCMSWeb.HealthController do
  use CourierCMSWeb, :controller

  alias CourierCMS.Repo
  alias CourierCMS.Observability

  def live(conn, _params), do: json(conn, %{status: "ok"})

  def ready(conn, _params) do
    case readiness() do
      :ok ->
        json(conn, %{status: "ready"})

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "not_ready", reason: reason})
    end
  end

  defp readiness do
    with {:ok, _result} <- Ecto.Adapters.SQL.query(Repo, "SELECT 1", []),
         false <- pending_migrations?(),
         :ok <- worker_readiness(),
         :ok <- extension_readiness() do
      :ok
    else
      true -> {:error, "pending_migrations"}
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, _reason} -> {:error, "database_unavailable"}
    end
  rescue
    _exception -> {:error, "readiness_check_failed"}
  end

  defp worker_readiness do
    if Application.get_env(:couriercms, :require_worker_readiness, false) and
         not Observability.worker_ready?(),
       do: {:error, "workers_unavailable"},
       else: :ok
  end

  defp extension_readiness do
    if Application.get_env(:couriercms, :require_extension_consistency, false) and
         not Observability.extension_cluster_ready?(),
       do: {:error, "extension_set_mismatch"},
       else: :ok
  end

  defp pending_migrations? do
    Enum.any?(Ecto.Migrator.migrations(Repo), fn {status, _version, _name} -> status == :down end)
  end
end

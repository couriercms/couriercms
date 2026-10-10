defmodule CourierCMSWeb.CacheBodyReader do
  @moduledoc false

  def read_body(conn, opts) do
    connector? = String.starts_with?(conn.request_path, "/api/connectors/")

    max_bytes =
      if connector?, do: Application.fetch_env!(:couriercms, :max_webhook_bytes), else: nil

    opts = if connector?, do: Keyword.put(opts, :length, min(max_bytes, 64_000)), else: opts

    read_body(conn, opts, "", max_bytes)
  end

  defp read_body(conn, opts, acc, max_bytes) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        body = acc <> body

        if within_limit?(body, max_bytes),
          do: {:ok, body, Plug.Conn.put_private(conn, :raw_body, body)},
          else: {:error, :too_large}

      {:more, body, conn} ->
        body = acc <> body

        if within_limit?(body, max_bytes),
          do: read_body(conn, opts, body, max_bytes),
          else: {:error, :too_large}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp within_limit?(_body, nil), do: true
  defp within_limit?(body, max_bytes), do: byte_size(body) <= max_bytes
end

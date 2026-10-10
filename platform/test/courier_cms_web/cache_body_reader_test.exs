defmodule CourierCMSWeb.CacheBodyReaderTest do
  use ExUnit.Case, async: true

  alias CourierCMSWeb.CacheBodyReader

  test "rejects Connector request bodies above the configured hard limit" do
    conn =
      Plug.Test.conn(
        :post,
        "/api/connectors/connection/events",
        String.duplicate("x", Application.fetch_env!(:couriercms, :max_webhook_bytes) + 1)
      )

    assert {:error, :too_large} = CacheBodyReader.read_body(conn, [])
  end
end

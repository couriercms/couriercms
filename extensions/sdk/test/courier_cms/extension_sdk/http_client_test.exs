defmodule CourierCMS.ExtensionSDK.HTTPClientTest do
  use ExUnit.Case, async: false

  alias CourierCMS.ExtensionSDK.HTTPClient

  defmodule Provider do
    @behaviour HTTPClient

    @impl true
    def request(connection, method, options),
      do: {:ok, {connection, method, options}}
  end

  setup do
    previous = Application.get_env(:couriercms_extension_sdk, :http_client)
    Application.put_env(:couriercms_extension_sdk, :http_client, Provider)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:couriercms_extension_sdk, :http_client, previous),
        else: Application.delete_env(:couriercms_extension_sdk, :http_client)
    end)
  end

  test "delegates outbound requests without exposing platform internals" do
    connection = %{id: "connection-1"}
    options = [url: "https://cms.example/items"]

    assert {:ok, {^connection, :get, ^options}} =
             HTTPClient.request(connection, :get, options)
  end
end

defmodule CourierCMS.ExtensionSDK.HTTPClient do
  @moduledoc """
  Platform-supplied outbound HTTP boundary for native Extensions.

  Extensions describe a request; CourierCMS retains responsibility for network
  policy, connection rate limits, timeouts, and response-size limits.
  """

  @type method :: :get | :post | :put | :patch | :delete | :head
  @type options :: keyword()

  @callback request(map(), method(), options()) :: {:ok, term()} | {:error, term()}

  def request(connection, method, options) when is_map(connection) and is_list(options) do
    provider = Application.fetch_env!(:couriercms_extension_sdk, :http_client)
    provider.request(connection, method, options)
  end
end

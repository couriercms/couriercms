defmodule CourierCMSExtension.WordPress.TestHTTPClient do
  @behaviour CourierCMS.ExtensionSDK.HTTPClient

  @impl true
  def request(_connection, method, options) do
    options
    |> Keyword.delete(:couriercms_timeout)
    |> Keyword.put(:method, method)
    |> Req.request()
  end
end

Application.put_env(
  :couriercms_extension_sdk,
  :http_client,
  CourierCMSExtension.WordPress.TestHTTPClient
)

ExUnit.start()

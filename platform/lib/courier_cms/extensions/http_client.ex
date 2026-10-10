defmodule CourierCMS.Extensions.HTTPClient do
  @moduledoc "Platform-owned outbound HTTP controls used by native Extensions."

  @behaviour CourierCMS.ExtensionSDK.HTTPClient

  alias CourierCMS.Adapters.ResponseLimit
  alias CourierCMS.Execution.OutboundRateLimiter
  alias CourierCMS.ExtensionSDK.AdapterError
  alias CourierCMS.Security.URLPolicy

  @methods [:get, :post, :put, :patch, :delete, :head]

  @impl true
  def request(connection, method, options) when method in @methods do
    with {:ok, url} <- fetch_url(options),
         :ok <- validate_url(url),
         :ok <- OutboundRateLimiter.check(connection) do
      options
      |> put_defaults()
      |> Keyword.put(:method, method)
      |> Req.request()
      |> ResponseLimit.validate()
    end
  end

  def request(_connection, _method, _options),
    do: {:error, AdapterError.new(:invalid_content, "Extension HTTP method is not allowed")}

  defp fetch_url(options) do
    case Keyword.get(options, :url) do
      url when is_binary(url) and url != "" -> {:ok, url}
      _other -> {:error, AdapterError.new(:invalid_content, "Extension HTTP URL is required")}
    end
  end

  defp validate_url(url) do
    case URLPolicy.validate(url) do
      :ok ->
        :ok

      {:error, _reason} ->
        {:error, AdapterError.new(:authorization, "CMS endpoint is blocked by network policy")}
    end
  end

  defp put_defaults(options) do
    receive_timeout =
      case Keyword.get(options, :couriercms_timeout, :standard) do
        :asset -> Application.fetch_env!(:couriercms, :asset_receive_timeout_ms)
        _other -> Application.fetch_env!(:couriercms, :adapter_receive_timeout_ms)
      end

    connect_options =
      options
      |> Keyword.get(:connect_options, [])
      |> Keyword.put(:timeout, Application.fetch_env!(:couriercms, :adapter_connect_timeout_ms))

    options
    |> Keyword.delete(:couriercms_timeout)
    |> Keyword.put(:retry, false)
    |> Keyword.put(:max_redirects, 0)
    |> Keyword.put(:receive_timeout, receive_timeout)
    |> Keyword.put(:connect_options, connect_options)
  end
end

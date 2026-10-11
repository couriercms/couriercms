defmodule CourierCMS.Adapters.ResponseLimit do
  @moduledoc false

  alias CourierCMS.ExtensionSDK.AdapterError

  def validate({:ok, %Req.Response{body: %Req.Response.Async{}}} = result), do: result

  def validate({:ok, %Req.Response{body: body}} = result) do
    limit = Application.fetch_env!(:couriercms, :max_adapter_response_bytes)

    if encoded_size(body) <= limit do
      result
    else
      {:error,
       AdapterError.new(:invalid_content, "CMS response exceeded the configured size limit")}
    end
  end

  def validate(result), do: result

  defp encoded_size(body) when is_binary(body), do: byte_size(body)
  defp encoded_size(body), do: :erlang.external_size(body)
end

defmodule CourierCMSExtension.Sanity.Client do
  @moduledoc false

  alias CourierCMS.ExtensionSDK.{AdapterError, HTTPClient}

  @api_version "v2026-09-24"
  @user_agent "CourierCMS/0.1 SanityAdapter"

  def test_connection(connection) do
    with {:ok, _count} <- query(connection, "count(*)", %{}),
         {:ok, _response} <-
           mutate(
             connection,
             %{
               "create" => %{
                 "_type" => "couriercmsDelivery",
                 "couriercmsKey" => "connection-test"
               }
             },
             dry_run: true
           ) do
      :ok
    end
  end

  def find_delivery(connection, destination_id, couriercms_key) do
    query =
      ~S|*[_type == "couriercmsDelivery" && destinationId == $destinationId && couriercmsKey == $couriercmsKey][0]{_id, installationId, routeId, destinationId, couriercmsKey}|

    query(connection, query, %{
      "destinationId" => destination_id,
      "couriercmsKey" => couriercms_key
    })
  end

  def find_asset_receipt(connection, receipt_id) do
    query =
      ~S|*[_type == "couriercmsAsset" && _id == $receiptId][0]{_id, installationId, routeId, destinationId, couriercmsAssetKey, "assetId": asset._ref}|

    query(connection, query, %{"receiptId" => receipt_id})
  end

  def create_document(connection, document) do
    with {:ok, response} <- mutate(connection, %{"create" => document}),
         {:ok, document_id} <- mutation_document_id(response) do
      {:ok, document_id}
    end
  end

  def patch_document(connection, document_id, fields, unset \\ []) do
    patch =
      %{"id" => document_id, "set" => fields}
      |> then(fn patch -> if unset == [], do: patch, else: Map.put(patch, "unset", unset) end)

    with {:ok, response} <- mutate(connection, %{"patch" => patch}),
         {:ok, ^document_id} <- mutation_document_id(response) do
      {:ok, document_id}
    end
  end

  def upload_image(connection, asset) do
    options =
      request_options(connection,
        url: api_base(connection) <> "/assets/images/#{dataset(connection)}",
        params: [
          tag: "couriercms.delivery_asset",
          filename: asset.descriptor.filename,
          label: asset.descriptor.metadata["alt"]
        ],
        headers: [{"content-type", asset.content.media_type || "application/octet-stream"}],
        body: asset.content.chunks,
        couriercms_timeout: :asset
      )

    HTTPClient.request(connection, :post, options)
    |> case do
      {:ok, %Req.Response{status: status, body: %{"document" => %{"_id" => id}}}}
      when status in 200..299 ->
        {:ok, id}

      result ->
        normalize_response(result)
    end
  end

  defp query(connection, query, params) do
    query_params =
      [{:query, query}, {:perspective, "raw"}] ++
        Enum.map(params, fn {key, value} -> {"$#{key}", Jason.encode!(value)} end)

    options =
      request_options(connection,
        url: api_base(connection) <> "/data/query/#{dataset(connection)}",
        params: query_params
      )

    HTTPClient.request(connection, :get, options)
    |> case do
      {:ok, %Req.Response{status: status, body: %{"result" => result}}}
      when status in 200..299 ->
        {:ok, result}

      result ->
        normalize_response(result)
    end
  end

  defp mutate(connection, mutation, opts \\ []) do
    options =
      request_options(connection,
        url: api_base(connection) <> "/data/mutate/#{dataset(connection)}",
        params: [
          dryRun: Keyword.get(opts, :dry_run, false),
          returnIds: true,
          tag: "couriercms.delivery"
        ],
        json: %{"mutations" => [mutation]}
      )

    HTTPClient.request(connection, :post, options)
    |> case do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        {:ok, response.body}

      result ->
        normalize_response(result)
    end
  end

  defp mutation_document_id(%{"results" => [result | _]}) do
    case result["documentId"] || result["id"] do
      id when is_binary(id) and id != "" -> {:ok, id}
      _other -> {:error, AdapterError.new(:invalid_content, "Sanity omitted the document ID")}
    end
  end

  defp mutation_document_id(_response),
    do: {:error, AdapterError.new(:invalid_content, "Sanity returned an invalid mutation result")}

  defp request_options(connection, options) do
    base_headers = [
      {"accept", "application/json"},
      {"authorization", "Bearer #{token(connection)}"},
      {"user-agent", @user_agent}
    ]

    custom_headers = Keyword.get(options, :headers, [])

    base = [
      headers: base_headers ++ custom_headers,
      retry: false,
      max_redirects: 0
    ]

    options = Keyword.merge(base, Keyword.delete(options, :headers))

    case setting(connection, :req_options) do
      req_options when is_list(req_options) -> Keyword.merge(options, req_options)
      _other -> options
    end
  end

  defp normalize_response({:ok, %Req.Response{} = response}),
    do: {:error, response_error(response)}

  defp normalize_response({:error, %Req.TransportError{reason: :timeout}}),
    do: {:error, AdapterError.new(:timeout, "Sanity request timed out", retryable: true)}

  defp normalize_response({:error, %AdapterError{} = error}), do: {:error, error}

  defp normalize_response({:error, _reason}),
    do:
      {:error,
       AdapterError.new(:temporarily_unavailable, "Sanity could not be reached", retryable: true)}

  defp response_error(%Req.Response{status: 401}),
    do: AdapterError.new(:authentication, "Sanity authentication failed")

  defp response_error(%Req.Response{status: 403}),
    do: AdapterError.new(:authorization, "Sanity denied access")

  defp response_error(%Req.Response{status: 404}),
    do: AdapterError.new(:source_not_found, "Sanity project or dataset was not found")

  defp response_error(%Req.Response{status: 429} = response) do
    AdapterError.new(:rate_limited, "Sanity rate limit reached",
      retryable: true,
      retry_after_ms: retry_after_ms(response)
    )
  end

  defp response_error(%Req.Response{status: status}) when status in 500..599,
    do:
      AdapterError.new(:temporarily_unavailable, "Sanity is temporarily unavailable",
        retryable: true,
        external_code: Integer.to_string(status)
      )

  defp response_error(%Req.Response{status: status}),
    do:
      AdapterError.new(:target_rejected, "Sanity rejected the request",
        external_code: Integer.to_string(status)
      )

  defp retry_after_ms(response) do
    case Req.Response.get_header(response, "retry-after") do
      [value | _] ->
        case Integer.parse(value) do
          {seconds, ""} -> seconds * 1_000
          _other -> nil
        end

      _other ->
        nil
    end
  end

  defp api_base(connection) do
    endpoint = String.trim_trailing(connection.endpoint, "/")
    endpoint <> "/#{setting(connection, "api_version", @api_version)}"
  end

  defp dataset(connection), do: setting(connection, "dataset", "production")

  defp token(%{credentials: %{"token" => token}}) when is_binary(token), do: token
  defp token(_connection), do: ""

  defp setting(connection, key, default \\ nil)

  defp setting(%{settings: settings}, key, default) when is_map(settings),
    do: Map.get(settings, key, Map.get(settings, to_string(key), default))

  defp setting(_connection, _key, default), do: default
end

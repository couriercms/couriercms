defmodule CourierCMSExtension.WordPress.Client do
  @moduledoc false

  alias CourierCMS.ExtensionSDK.{AdapterError, AssetContent, HTTPClient}

  @user_agent "CourierCMS/0.1 WordPressAdapter"

  def test_connection(connection) do
    with {:ok, response} <-
           get(connection, "/posts",
             context: context(connection),
             status: "publish",
             per_page: 1,
             _fields: "id"
           ) do
      if is_list(response.body),
        do: :ok,
        else:
          {:error,
           AdapterError.new(:invalid_content, "WordPress returned an unexpected response")}
    end
  end

  def list_posts(connection, params) do
    with {:ok, response} <- get(connection, "/posts", params) do
      {:ok,
       %{
         posts: response.body,
         total_pages: integer_header(response, "x-wp-totalpages", 1)
       }}
    end
  end

  def get_post(connection, id) do
    get(connection, "/posts/#{URI.encode(to_string(id))}",
      context: context(connection),
      _embed: "author,wp:term,wp:featuredmedia"
    )
    |> case do
      {:ok, response} -> {:ok, response.body}
      error -> error
    end
  end

  def read_asset(connection, url) when is_binary(url) and url != "" do
    options = [
      url: url,
      headers: [{"accept", "*/*"}, {"user-agent", @user_agent}],
      into: :self,
      decode_body: false,
      retry: false,
      max_redirects: 0,
      couriercms_timeout: :asset,
      couriercms_stream: :asset
    ]

    options =
      case asset_authentication(connection, url) do
        nil -> options
        auth -> Keyword.put(options, :auth, auth)
      end

    options =
      case setting(connection, :req_options) do
        nil -> options
        req_options when is_list(req_options) -> Keyword.merge(options, req_options)
      end

    case HTTPClient.request(connection, :get, options) do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        {:ok,
         %AssetContent{
           chunks: response.body,
           byte_size: content_length(response),
           media_type: media_type(response)
         }}

      {:ok, %Req.Response{} = response} ->
        {:error, response_error(response)}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, transport_error(reason)}

      {:error, %AdapterError{} = error} ->
        {:error, error}

      {:error, _exception} ->
        {:error,
         AdapterError.new(:temporarily_unavailable, "WordPress asset request failed",
           retryable: true
         )}
    end
  end

  def read_asset(_connection, _url),
    do: {:error, AdapterError.new(:invalid_content, "WordPress asset URL is invalid")}

  defp asset_authentication(connection, url) do
    if same_origin?(connection.endpoint, url), do: authentication(connection)
  end

  defp same_origin?(left, right) do
    left = URI.parse(left)
    right = URI.parse(right)

    left.scheme in ["http", "https"] and left.scheme == right.scheme and
      String.downcase(left.host || "") == String.downcase(right.host || "") and
      effective_port(left) == effective_port(right)
  end

  defp effective_port(%URI{port: port}) when is_integer(port), do: port
  defp effective_port(%URI{scheme: "https"}), do: 443
  defp effective_port(%URI{scheme: "http"}), do: 80
  defp effective_port(_uri), do: nil

  def resolve_term_ids(connection, resource, slugs) when resource in ["categories", "tags"] do
    slugs
    |> Enum.map(&slugify/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce_while({:ok, []}, fn slug, {:ok, ids} ->
      case get(connection, "/#{resource}", slug: slug, per_page: 100, _fields: "id,slug") do
        {:ok, %{body: [%{"id" => id} | _]}} -> {:cont, {:ok, [id | ids]}}
        {:ok, %{body: []}} -> {:halt, {:ok, :not_found}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, ids} when is_list(ids) -> {:ok, Enum.reverse(ids)}
      result -> result
    end
  end

  defp get(connection, path, params) do
    url = api_base(connection.endpoint) <> path

    options = [
      url: url,
      params: params,
      headers: [{"accept", "application/json"}, {"user-agent", @user_agent}],
      retry: false,
      max_redirects: 0
    ]

    options =
      case authentication(connection) do
        nil -> options
        auth -> Keyword.put(options, :auth, auth)
      end

    options =
      case setting(connection, :req_options) do
        nil -> options
        req_options when is_list(req_options) -> Keyword.merge(options, req_options)
      end

    case HTTPClient.request(connection, :get, options) do
      {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, %Req.Response{} = response} ->
        {:error, response_error(response)}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, transport_error(reason)}

      {:error, %AdapterError{} = error} ->
        {:error, error}

      {:error, _exception} ->
        {:error,
         AdapterError.new(:temporarily_unavailable, "WordPress request failed", retryable: true)}
    end
  end

  defp api_base(endpoint) do
    endpoint = String.trim_trailing(endpoint, "/")

    cond do
      String.ends_with?(endpoint, "/wp-json/wp/v2") -> endpoint
      String.ends_with?(endpoint, "/wp-json") -> endpoint <> "/wp/v2"
      true -> endpoint <> "/wp-json/wp/v2"
    end
  end

  defp context(connection) do
    if authentication(connection), do: "edit", else: "view"
  end

  defp authentication(%{
         credentials: %{"username" => username, "application_password" => password}
       })
       when is_binary(username) and username != "" and is_binary(password) and password != "" do
    {:basic, "#{username}:#{password}"}
  end

  defp authentication(_connection), do: nil

  defp response_error(%Req.Response{status: 400}),
    do: AdapterError.new(:invalid_selection, "WordPress rejected the request")

  defp response_error(%Req.Response{status: 401}),
    do: AdapterError.new(:authentication, "WordPress authentication failed")

  defp response_error(%Req.Response{status: 403}),
    do: AdapterError.new(:authorization, "WordPress denied access")

  defp response_error(%Req.Response{status: 404}),
    do: AdapterError.new(:source_not_found, "WordPress content was not found")

  defp response_error(%Req.Response{status: 429} = response) do
    AdapterError.new(:rate_limited, "WordPress rate limit reached",
      retryable: true,
      retry_after_ms: retry_after_ms(response)
    )
  end

  defp response_error(%Req.Response{status: status}) when status in 500..599,
    do:
      AdapterError.new(:temporarily_unavailable, "WordPress is temporarily unavailable",
        retryable: true,
        external_code: Integer.to_string(status)
      )

  defp response_error(%Req.Response{status: status}),
    do:
      AdapterError.new(:invalid_content, "WordPress returned an unexpected status",
        external_code: Integer.to_string(status)
      )

  defp transport_error(:timeout),
    do: AdapterError.new(:timeout, "WordPress request timed out", retryable: true)

  defp transport_error(_reason),
    do:
      AdapterError.new(:temporarily_unavailable, "WordPress could not be reached",
        retryable: true
      )

  defp integer_header(response, name, default) do
    case Req.Response.get_header(response, name) do
      [value | _] ->
        case Integer.parse(value) do
          {integer, ""} -> integer
          _other -> default
        end

      _other ->
        default
    end
  end

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

  defp content_length(response) do
    case first_header(response, "content-length") do
      nil ->
        nil

      value ->
        case Integer.parse(value) do
          {size, ""} when size >= 0 -> size
          _other -> nil
        end
    end
  end

  defp media_type(response) do
    case first_header(response, "content-type") do
      nil -> nil
      value -> value |> String.split(";", parts: 2) |> List.first() |> String.trim()
    end
  end

  defp first_header(response, name) do
    case Req.Response.get_header(response, name) do
      [value | _] -> value
      _other -> nil
    end
  end

  defp setting(%{settings: settings}, key) when is_map(settings) do
    Map.get(settings, key, Map.get(settings, Atom.to_string(key)))
  end

  defp setting(_connection, _key), do: nil

  defp slugify(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, "-")
    |> String.trim("-")
  end
end

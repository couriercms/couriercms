defmodule CourierCMS.Security.URLPolicy do
  @moduledoc "Network policy for outbound CMS adapter endpoints."

  @type reason ::
          :invalid_url
          | :insecure_scheme
          | :unresolvable_host
          | :private_network_blocked
          | :local_network_blocked

  @spec validate(String.t()) :: :ok | {:error, reason()}
  def validate(url) when is_binary(url) do
    with %URI{scheme: scheme, host: host} when is_binary(host) <- URI.parse(url),
         :ok <- validate_scheme(scheme),
         {:ok, addresses} <- resolve(host),
         :ok <- validate_addresses(addresses) do
      :ok
    else
      %URI{} -> {:error, :invalid_url}
      {:error, reason} -> {:error, reason}
    end
  end

  def validate(_url), do: {:error, :invalid_url}

  defp validate_scheme("https"), do: :ok

  defp validate_scheme("http") do
    if Application.get_env(:couriercms, :allow_http_cms_endpoints, false),
      do: :ok,
      else: {:error, :insecure_scheme}
  end

  defp validate_scheme(_scheme), do: {:error, :invalid_url}

  defp resolve(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} ->
        {:ok, [address]}

      {:error, :einval} ->
        addresses =
          [:inet, :inet6]
          |> Enum.flat_map(fn family ->
            case :inet.getaddrs(String.to_charlist(host), family) do
              {:ok, values} -> values
              {:error, _reason} -> []
            end
          end)
          |> Enum.uniq()

        cond do
          addresses != [] -> {:ok, addresses}
          Application.get_env(:couriercms, :allow_unresolved_cms_hosts, false) -> {:ok, []}
          true -> {:error, :unresolvable_host}
        end
    end
  end

  defp validate_addresses(addresses) do
    cond do
      Enum.any?(addresses, &local_or_metadata?/1) &&
          !Application.get_env(:couriercms, :allow_unsafe_local_cms_endpoints, false) ->
        {:error, :local_network_blocked}

      Enum.any?(addresses, &private?/1) &&
          !Application.get_env(:couriercms, :allow_private_cms_networks, false) ->
        {:error, :private_network_blocked}

      true ->
        :ok
    end
  end

  defp local_or_metadata?({127, _, _, _}), do: true
  defp local_or_metadata?({169, 254, _, _}), do: true
  defp local_or_metadata?({0, _, _, _}), do: true
  defp local_or_metadata?({a, _, _, _}) when a >= 224, do: true
  defp local_or_metadata?({0, 0, 0, 0, 0, 0, 0, 0}), do: true
  defp local_or_metadata?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp local_or_metadata?({first, _, _, _, _, _, _, _}) when first in 0xFE80..0xFEBF, do: true
  defp local_or_metadata?(_address), do: false

  defp private?({10, _, _, _}), do: true
  defp private?({172, second, _, _}) when second in 16..31, do: true
  defp private?({192, 168, _, _}), do: true
  defp private?({first, _, _, _, _, _, _, _}) when first in 0xFC00..0xFDFF, do: true
  defp private?(_address), do: false
end

defmodule CourierCMS.Transport.DeliveryName do
  @moduledoc "Resolves a readable Delivery Item name without using it as identity."

  @spec resolve(map(), String.t(), String.t(), String.t()) :: map()
  def resolve(canonical_document, path, source_item_key, delivery_key) do
    value = value_at(canonical_document, path) || source_item_key

    %{
      value: to_string(value),
      suffix: String.slice(delivery_key, 0, 8)
    }
  end

  defp value_at(document, path) when is_binary(path) do
    path
    |> String.split(".", trim: true)
    |> Enum.reduce_while(document, fn segment, value ->
      case value do
        map when is_map(map) ->
          case Map.fetch(map, segment) do
            {:ok, next} -> {:cont, next}
            :error -> {:halt, nil}
          end

        _other ->
          {:halt, nil}
      end
    end)
    |> case do
      value when is_binary(value) and value != "" -> value
      value when is_integer(value) or is_float(value) -> value
      _other -> nil
    end
  end

  defp value_at(_document, _path), do: nil
end

defmodule CourierCMSExtension.WordPress.InlineImages do
  @moduledoc false

  @img_start ~r/<img(?=[\s\/>])/i
  @attribute ~r/([^\s=\/>]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/u

  def extract(html) when is_binary(html), do: scan(html, [])
  def extract(_html), do: []

  defp scan(html, images) do
    case Regex.run(@img_start, html, return: :index) do
      [{start, length}] ->
        rest = binary_part(html, start + length, byte_size(html) - start - length)

        case take_tag(rest, nil, []) do
          {:ok, attributes, remaining} ->
            image = parse_attributes(attributes)
            scan(remaining, [image | images])

          :error ->
            Enum.reverse(images)
        end

      nil ->
        Enum.reverse(images)
    end
  end

  defp take_tag(<<>>, _quote, _bytes), do: :error

  defp take_tag(<<quote, rest::binary>>, quote, bytes) when quote in [?", ?'],
    do: take_tag(rest, nil, [quote | bytes])

  defp take_tag(<<quote, rest::binary>>, nil, bytes) when quote in [?", ?'],
    do: take_tag(rest, quote, [quote | bytes])

  defp take_tag(<<?>, rest::binary>>, nil, bytes),
    do: {:ok, bytes |> Enum.reverse() |> :erlang.list_to_binary(), rest}

  defp take_tag(<<byte, rest::binary>>, quote, bytes),
    do: take_tag(rest, quote, [byte | bytes])

  defp parse_attributes(attributes) do
    @attribute
    |> Regex.scan(attributes, capture: :all_but_first)
    |> Map.new(fn [name | values] ->
      value = Enum.find(values, &(&1 != "")) || ""
      {String.downcase(name), decode_entities(value)}
    end)
  end

  defp decode_entities(value) do
    value
    |> String.replace("&amp;", "&")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#039;", "'")
    |> String.replace("&apos;", "'")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
  end
end

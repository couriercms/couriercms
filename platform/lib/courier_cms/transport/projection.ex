defmodule CourierCMS.Transport.Projection do
  @moduledoc "Validates target projections and derives them from a Canonical Delivery Document."

  alias CourierCMS.ExtensionSDK.AdapterError

  @spec validate_definitions(term()) :: :ok | {:error, String.t()}
  def validate_definitions(definitions),
    do: CourierCMS.ExtensionSDK.ProjectionDefinition.validate(definitions)

  @spec parse(String.t() | nil) :: {:ok, [map()]} | {:error, String.t()}
  def parse(text) do
    text
    |> to_string()
    |> String.split("\n", trim: true)
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, definitions} ->
      case parse_line(String.trim(line)) do
        {:ok, definition} -> {:cont, {:ok, [definition | definitions]}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
    |> case do
      {:ok, definitions} ->
        definitions = Enum.reverse(definitions)

        case validate_definitions(definitions) do
          :ok -> {:ok, definitions}
          error -> error
        end

      error ->
        error
    end
  end

  @spec format([map()]) :: String.t()
  def format(definitions) do
    Enum.map_join(definitions, "\n", fn definition ->
      suffix = if definition["required"] == true, do: ":required", else: ""

      "#{definition["target_field"]}=#{definition["source_path"]}:#{definition["type"]}#{suffix}"
    end)
  end

  @spec project(map(), [map()]) :: {:ok, map()} | {:error, AdapterError.t()}
  def project(document, definitions) when is_map(document) and is_list(definitions) do
    case validate_definitions(definitions) do
      :ok ->
        Enum.reduce_while(definitions, {:ok, %{}}, fn definition, {:ok, projected} ->
          field = definition["target_field"]
          path = definition["source_path"]
          type = definition["type"]
          required? = definition["required"] == true
          value = get_path(document, path)

          cond do
            is_nil(value) and required? ->
              {:halt, error("Required projection #{field} has no value at #{path}")}

            is_nil(value) ->
              {:cont, {:ok, Map.put(projected, field, nil)}}

            valid_type?(value, type) ->
              {:cont, {:ok, Map.put(projected, field, value)}}

            true ->
              {:halt, error("Projection #{field} is not a valid #{type} value")}
          end
        end)

      {:error, message} ->
        error("Invalid projection definition: #{message}")
    end
  end

  defp parse_line(line) do
    with [field, expression] <- String.split(line, "=", parts: 2),
         parts when length(parts) in [2, 3] <- String.split(expression, ":"),
         [path, type | rest] <- parts,
         true <- rest in [[], ["required"]] do
      {:ok,
       %{
         "target_field" => String.trim(field),
         "source_path" => String.trim(path),
         "type" => String.trim(type),
         "required" => rest == ["required"]
       }}
    else
      _other ->
        {:error,
         "Projection line #{inspect(line)} must use targetField=payload.path:type[:required]"}
    end
  end

  defp get_path(document, path) do
    path
    |> String.split(".", trim: true)
    |> Enum.reduce_while(document, fn segment, current ->
      if is_map(current) and Map.has_key?(current, segment),
        do: {:cont, Map.get(current, segment)},
        else: {:halt, nil}
    end)
  end

  defp valid_type?(value, "string"), do: is_binary(value)
  defp valid_type?(value, "number"), do: is_number(value)
  defp valid_type?(value, "boolean"), do: is_boolean(value)

  defp valid_type?(value, "datetime") when is_binary(value) do
    match?({:ok, _datetime, _offset}, DateTime.from_iso8601(value))
  end

  defp valid_type?(_value, _type), do: false

  defp error(message),
    do: {:error, AdapterError.new(:mapping_failed, message, retryable: false)}
end

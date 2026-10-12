defmodule CourierCMS.Processors.Definition do
  @moduledoc "Interprets generic configuration metadata declared by Processor Extensions."

  alias CourierCMS.ExtensionSDK.AdapterError

  @field_types [:text, :integer, :checkbox, :json_object]

  def validate!(definition) do
    case validate(definition) do
      :ok -> definition
      {:error, message} -> raise ArgumentError, "Invalid Processor definition: #{message}"
    end
  end

  def validate(%{label: label, description: description} = definition)
      when is_binary(label) and label != "" and is_binary(description) do
    fields = Map.get(definition, :config_fields, [])

    if is_list(fields),
      do: validate_fields(fields),
      else: {:error, "config_fields must be a list"}
  end

  def validate(_definition), do: {:error, "label and description strings are required"}

  defp validate_fields(fields) do
    keys = Enum.map(fields, &field_value(&1, :key))

    cond do
      Enum.any?(fields, &(field_value(&1, :type) not in @field_types)) ->
        {:error, "configuration field type is unsupported"}

      Enum.any?(fields, &(not valid_field?(&1))) ->
        {:error, "configuration fields require a key and label"}

      length(Enum.uniq(keys)) != length(keys) ->
        {:error, "configuration field keys must be unique"}

      true ->
        :ok
    end
  end

  def fields(definition), do: Map.get(definition, :config_fields, [])

  def defaults(definition), do: form_values(definition, %{})

  def form_values(definition, config) when is_map(config) do
    Map.new(fields(definition), fn field ->
      default = Map.get(field, :default, empty_value(field.type))
      {to_string(field.key), format(field, value(config, to_string(field.key), default))}
    end)
  end

  def cast_config(definition, params) when is_map(params) do
    fields(definition)
    |> Enum.reduce_while({:ok, %{}}, fn field, {:ok, config} ->
      raw = value(params, to_string(field.key), Map.get(field, :default, empty_value(field.type)))

      case cast(field, raw) do
        {:ok, cast_value} ->
          {:cont, {:ok, Map.put(config, to_string(field.key), cast_value)}}

        {:error, message} ->
          {:halt,
           {:error,
            AdapterError.new(:invalid_content, "#{Map.get(field, :label, field.key)} #{message}")}}
      end
    end)
  end

  def cast_config(_definition, _params),
    do: {:error, AdapterError.new(:invalid_content, "Processor configuration is invalid")}

  defp valid_field?(%{key: key, label: label})
       when (is_atom(key) or is_binary(key)) and is_binary(label) and label != "",
       do: to_string(key) != ""

  defp valid_field?(_field), do: false

  defp field_value(field, key) when is_map(field), do: Map.get(field, key)
  defp field_value(_field, _key), do: nil

  defp cast(%{type: :checkbox}, raw), do: {:ok, raw in [true, "true", "1", 1, "on"]}
  defp cast(%{type: :integer}, raw) when is_integer(raw), do: {:ok, raw}

  defp cast(%{type: :integer}, raw) do
    case Integer.parse(to_string(raw)) do
      {integer, ""} -> {:ok, integer}
      _other -> {:error, "must be an integer"}
    end
  end

  defp cast(%{type: :json_object}, raw) when is_map(raw), do: {:ok, raw}

  defp cast(%{type: :json_object}, raw) do
    case Jason.decode(to_string(raw)) do
      {:ok, value} when is_map(value) -> {:ok, value}
      _other -> {:error, "must be a JSON object"}
    end
  end

  defp cast(%{type: :text} = field, raw) do
    value = to_string(raw)

    if value == "" and Map.get(field, :required, false),
      do: {:error, "is required"},
      else: {:ok, value}
  end

  defp format(%{type: :json_object}, value) when is_map(value),
    do: Jason.encode!(value, pretty: true)

  defp format(%{type: :checkbox}, value), do: to_string(value == true)
  defp format(_field, value), do: to_string(value)

  defp empty_value(:checkbox), do: false
  defp empty_value(:integer), do: 0
  defp empty_value(:json_object), do: %{}
  defp empty_value(:text), do: ""

  defp value(map, key, default),
    do: Map.get(map, key, Map.get(map, safe_existing_atom(key), default))

  defp safe_existing_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> :__missing__
  end
end

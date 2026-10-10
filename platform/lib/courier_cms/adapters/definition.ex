defmodule CourierCMS.Adapters.Definition do
  @moduledoc """
  Interprets declarative UI and validation metadata owned by each built-in Adapter.

  The core understands generic field types and storage locations only. CMS names,
  configuration keys, selection predicates, defaults, and help text remain at
  the Adapter edge.
  """

  alias CourierCMS.ExtensionSDK.AdapterError
  alias CourierCMS.Extensions.Gateway

  @field_types [:text, :url, :password, :select, :list, :integer, :checkbox]

  def validate!(definition) do
    case validate(definition) do
      :ok -> definition
      {:error, message} -> raise ArgumentError, "Invalid Adapter definition: #{message}"
    end
  end

  def validate(%{key: key, label: label, connection: connection} = definition)
      when is_binary(key) and key != "" and is_binary(label) and label != "" and
             is_map(connection) do
    with :ok <- validate_endpoint_definition(connection[:endpoint]),
         :ok <- validate_fields(Map.get(connection, :fields, []), true),
         :ok <- validate_source_definition(Map.get(definition, :source)),
         :ok <- validate_target_definition(Map.get(definition, :target)),
         :ok <- validate_connector_definition(Map.get(definition, :connector)) do
      :ok
    end
  end

  def validate(_definition), do: {:error, "key, label, and connection metadata are required"}

  def connection_fields(adapter_key) do
    with {:ok, definition} <- Gateway.fetch_definition(adapter_key) do
      definition |> Map.get(:connection, %{}) |> Map.get(:fields, [])
    else
      :error -> []
    end
  end

  def endpoint_definition(adapter_key) do
    with {:ok, definition} <- Gateway.fetch_definition(adapter_key) do
      definition |> Map.get(:connection, %{}) |> Map.get(:endpoint, %{mode: :input})
    else
      :error -> %{mode: :input}
    end
  end

  def source_definition(adapter_key) do
    with {:ok, definition} <- Gateway.fetch_definition(adapter_key),
         %{} = source <- Map.get(definition, :source) do
      {:ok, source}
    else
      _other -> {:error, AdapterError.new(:unsupported, "Source Adapter is not registered")}
    end
  end

  def target_definition(adapter_key) do
    with {:ok, definition} <- Gateway.fetch_definition(adapter_key),
         %{} = target <- Map.get(definition, :target) do
      {:ok, target}
    else
      _other -> {:error, AdapterError.new(:unsupported, "Target Adapter is not registered")}
    end
  end

  def default_connection_values(adapter_key) do
    fields = connection_fields(adapter_key)

    %{
      "configuration" => defaults(fields, :setting),
      "credential_values" => defaults(fields, :credential),
      "endpoint" => endpoint_default(endpoint_definition(adapter_key))
    }
  end

  def prepare_connection_attrs(attrs) when is_map(attrs) do
    adapter_key = value(attrs, "adapter_key")

    with {:ok, definition} <- fetch_definition(adapter_key),
         fields <- definition |> Map.get(:connection, %{}) |> Map.get(:fields, []),
         {:ok, values} <- cast_connection_fields(fields, attrs),
         {:ok, endpoint} <- derive_endpoint(definition, attrs, values.settings) do
      {:ok,
       attrs
       |> stringify_keys()
       |> Map.put("settings", values.settings)
       |> Map.put("credentials", values.credentials)
       |> Map.put("endpoint", endpoint)}
    end
  end

  def prepare_connection_attrs(_attrs),
    do: {:error, AdapterError.new(:invalid_content, "Connection configuration is invalid")}

  def cast_selection(adapter_key, params) when is_map(params) do
    with {:ok, source} <- source_definition(adapter_key),
         {:ok, selection} <- cast_fields(source.selection_fields, params, :invalid_selection) do
      {:ok, selection}
    end
  end

  def cast_selection(_adapter_key, _params),
    do: {:error, AdapterError.new(:invalid_selection, "Source selection is invalid")}

  def cast_credentials(adapter_key, params) when is_map(params) do
    fields =
      adapter_key
      |> connection_fields()
      |> Enum.filter(&(&1.storage == :credential))

    Enum.reduce_while(fields, {:ok, %{}}, fn field, {:ok, credentials} ->
      raw = value(params, to_string(field.key), "")

      if blank?(raw) do
        {:cont, {:ok, credentials}}
      else
        optional_field = Map.put(field, :required, false)

        case cast_field(optional_field, raw) do
          {:ok, cast_value} ->
            target_key = to_string(Map.get(field, :target_key, field.key))
            {:cont, {:ok, Map.put(credentials, target_key, cast_value)}}

          {:error, message} ->
            {:halt, {:error, AdapterError.new(:invalid_content, "#{field.label} #{message}")}}
        end
      end
    end)
    |> case do
      {:ok, credentials} when map_size(credentials) > 0 ->
        {:ok, credentials}

      {:ok, _credentials} ->
        {:error, AdapterError.new(:invalid_content, "Enter a replacement credential")}

      error ->
        error
    end
  end

  def default_selection(adapter_key) do
    with {:ok, source} <- source_definition(adapter_key) do
      defaults(source.selection_fields)
    else
      _error -> %{}
    end
  end

  def default_mapping(adapter_key) do
    with {:ok, source} <- source_definition(adapter_key),
         do: source.default_mapping,
         else: (_ -> %{})
  end

  def default_aggregation_rules(adapter_key) do
    with {:ok, source} <- source_definition(adapter_key),
         do: Map.get(source, :default_aggregation_rules, %{}),
         else: (_ -> %{})
  end

  def default_delivery_contract(adapter_key) do
    with {:ok, source} <- source_definition(adapter_key),
         do: Map.get(source, :delivery_contract, %{"name" => "delivery", "version" => 1}),
         else: (_ -> %{"name" => "delivery", "version" => 1})
  end

  def default_projections(adapter_key) do
    with {:ok, target} <- target_definition(adapter_key),
         do: Map.get(target, :default_projections, []),
         else: (_ -> [])
  end

  def destination_fields(adapter_key) do
    with {:ok, target} <- target_definition(adapter_key),
         do: Map.get(target, :destination_fields, []),
         else: (_ -> [])
  end

  def default_destination_settings(adapter_key) do
    adapter_key
    |> destination_fields()
    |> defaults()
  end

  def cast_destination_settings(adapter_key, params) when is_map(params) do
    with {:ok, _target} <- target_definition(adapter_key),
         {:ok, settings} <-
           cast_fields(destination_fields(adapter_key), params, :invalid_content) do
      {:ok, settings}
    end
  end

  def cast_destination_settings(_adapter_key, _params),
    do: {:error, AdapterError.new(:invalid_content, "Destination configuration is invalid")}

  def connector(adapter_key) do
    with {:ok, definition} <- Gateway.fetch_definition(adapter_key),
         %{} = connector <- Map.get(definition, :connector) do
      {:ok, connector}
    else
      _other -> :error
    end
  end

  def connector_path(connector, connection_id) do
    connector.path_template
    |> String.replace("{connection_id}", connection_id)
  end

  def field_value(params, field) do
    params
    |> value(to_string(field.key), Map.get(field, :default, ""))
    |> format_field_value(field.type)
  end

  defp fetch_definition(adapter_key) when is_binary(adapter_key) and adapter_key != "" do
    case Gateway.fetch_definition(adapter_key) do
      {:ok, definition} -> {:ok, definition}
      :error -> {:error, AdapterError.new(:unsupported, "Adapter is not registered")}
    end
  end

  defp fetch_definition(_adapter_key),
    do: {:error, AdapterError.new(:unsupported, "Choose a registered Adapter")}

  defp validate_endpoint_definition(%{mode: :input}), do: :ok

  defp validate_endpoint_definition(%{mode: :derived, template: template})
       when is_binary(template) and template != "",
       do: :ok

  defp validate_endpoint_definition(_endpoint),
    do: {:error, "connection endpoint must be input or derived"}

  defp validate_fields(fields, connection?) when is_list(fields) do
    keys = Enum.map(fields, &Map.get(&1, :key))

    cond do
      Enum.any?(fields, &(Map.get(&1, :type) not in @field_types)) ->
        {:error, "field type is unsupported"}

      connection? and
          Enum.any?(fields, &(Map.get(&1, :storage) not in [:setting, :credential])) ->
        {:error, "connection fields require setting or credential storage"}

      Enum.any?(keys, &is_nil/1) or length(Enum.uniq(keys)) != length(keys) ->
        {:error, "field keys must be present and unique"}

      true ->
        :ok
    end
  end

  defp validate_fields(_fields, _connection?), do: {:error, "fields must be a list"}

  defp validate_source_definition(nil), do: :ok

  defp validate_source_definition(%{
         content_label: label,
         selection_fields: fields,
         default_mapping: mapping
       })
       when is_binary(label) do
    with :ok <- validate_fields(fields, false), do: CourierCMS.Mapping.validate(mapping)
  end

  defp validate_source_definition(_source),
    do: {:error, "source metadata is incomplete"}

  defp validate_target_definition(nil), do: :ok

  defp validate_target_definition(%{} = target) do
    with :ok <- validate_fields(Map.get(target, :destination_fields, []), false) do
      CourierCMS.Transport.Projection.validate_definitions(
        Map.get(target, :default_projections, [])
      )
    end
  end

  defp validate_target_definition(_target), do: {:error, "target metadata is invalid"}

  defp validate_connector_definition(nil), do: :ok

  defp validate_connector_definition(%{path_template: path}) when is_binary(path) do
    if String.contains?(path, "{connection_id}"),
      do: :ok,
      else: {:error, "Connector path must include {connection_id}"}
  end

  defp validate_connector_definition(_connector), do: {:error, "Connector metadata is invalid"}

  defp cast_connection_fields(fields, attrs) do
    configuration = value(attrs, "configuration", %{}) || %{}
    credential_values = value(attrs, "credential_values", %{}) || %{}

    Enum.reduce_while(fields, {:ok, %{settings: %{}, credentials: %{}}}, fn field,
                                                                            {:ok, result} ->
      source = if field.storage == :credential, do: credential_values, else: configuration
      raw = value(source, to_string(field.key), Map.get(field, :default, ""))

      case cast_field(field, raw) do
        {:ok, cast_value} ->
          bucket = if field.storage == :credential, do: :credentials, else: :settings
          target_key = to_string(Map.get(field, :target_key, field.key))
          updated = Map.update!(result, bucket, &maybe_put(&1, target_key, cast_value))
          {:cont, {:ok, updated}}

        {:error, message} ->
          {:halt, {:error, AdapterError.new(:invalid_content, "#{field.label} #{message}")}}
      end
    end)
  end

  defp cast_fields(fields, params, error_category) do
    Enum.reduce_while(fields, {:ok, %{}}, fn field, {:ok, result} ->
      raw = value(params, to_string(field.key), Map.get(field, :default, ""))

      case cast_field(field, raw) do
        {:ok, cast_value} ->
          {:cont, {:ok, Map.put(result, to_string(field.key), cast_value)}}

        {:error, message} ->
          {:halt, {:error, AdapterError.new(error_category, "#{field.label} #{message}")}}
      end
    end)
  end

  defp cast_field(%{type: type}, _raw) when type not in @field_types,
    do: {:error, "uses an unsupported field type"}

  defp cast_field(field, raw) do
    raw = if is_binary(raw), do: String.trim(raw), else: raw

    cond do
      blank?(raw) and Map.get(field, :required, false) ->
        {:error, "is required"}

      blank?(raw) ->
        {:ok, empty_value(field.type)}

      field.type == :list ->
        {:ok, normalize_list(raw)}

      field.type == :integer ->
        cast_integer(raw)

      field.type == :checkbox ->
        {:ok, raw in [true, "true", "1", 1, "on"]}

      field.type == :select ->
        validate_option(field, to_string(raw))

      is_integer(Map.get(field, :min_length)) and
          String.length(to_string(raw)) < field.min_length ->
        {:error, "must be at least #{field.min_length} characters"}

      is_struct(Map.get(field, :pattern), Regex) and
          not Regex.match?(field.pattern, to_string(raw)) ->
        {:error, Map.get(field, :pattern_message, "has an invalid format")}

      true ->
        {:ok, to_string(raw)}
    end
  end

  defp validate_option(field, value) do
    allowed = Enum.map(field.options, fn {_label, option} -> to_string(option) end)
    if value in allowed, do: {:ok, value}, else: {:error, "is not supported"}
  end

  defp cast_integer(value) when is_integer(value), do: {:ok, value}

  defp cast_integer(value) do
    case Integer.parse(to_string(value)) do
      {integer, ""} -> {:ok, integer}
      _other -> {:error, "must be an integer"}
    end
  end

  defp derive_endpoint(definition, attrs, settings) do
    endpoint = definition |> Map.get(:connection, %{}) |> Map.get(:endpoint, %{mode: :input})

    case endpoint.mode do
      :input ->
        case value(attrs, "endpoint") do
          value when is_binary(value) and value != "" -> {:ok, String.trim(value)}
          _other -> {:error, AdapterError.new(:invalid_content, "Endpoint is required")}
        end

      :derived ->
        rendered =
          Regex.replace(~r/\{([a-zA-Z0-9_]+)\}/, endpoint.template, fn _match, key ->
            to_string(Map.get(settings, key, ""))
          end)

        if String.contains?(rendered, "{}") or String.contains?(rendered, "//."),
          do:
            {:error, AdapterError.new(:invalid_content, "Endpoint configuration is incomplete")},
          else: {:ok, rendered}
    end
  end

  defp defaults(fields, storage \\ nil) do
    fields
    |> Enum.filter(&(is_nil(storage) or Map.get(&1, :storage) == storage))
    |> Map.new(fn field ->
      {to_string(field.key), Map.get(field, :default, empty_value(field.type))}
    end)
  end

  defp endpoint_default(%{mode: :input} = endpoint), do: Map.get(endpoint, :default, "")
  defp endpoint_default(_endpoint), do: ""

  defp empty_value(:list), do: []
  defp empty_value(:checkbox), do: false
  defp empty_value(_type), do: ""

  defp normalize_list(values) when is_list(values),
    do: values |> Enum.map(&to_string/1) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp normalize_list(value), do: value |> String.split(",", trim: true) |> normalize_list()

  defp format_field_value(value, :list) when is_list(value), do: Enum.join(value, ", ")
  defp format_field_value(value, :checkbox), do: to_string(value == true or value == "true")
  defp format_field_value(value, _type), do: value

  defp maybe_put(map, _key, value) when value in [nil, "", []], do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp blank?(value), do: value in [nil, "", []]

  defp stringify_keys(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp value(map, key, default \\ nil)

  defp value(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, safe_existing_atom(key), default))

  defp value(_map, _key, default), do: default

  defp safe_existing_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> :__missing__
  end
end

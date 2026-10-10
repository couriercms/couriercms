defmodule CourierCMS.ExtensionSDK.Component do
  @moduledoc "Stable identity and capability metadata for one Extension component."

  @kinds [:adapter, :processor]

  @enforce_keys [:extension_id, :component_id, :kind, :version]
  defstruct [:extension_id, :component_id, :kind, :version, capabilities: []]

  @type kind :: :adapter | :processor
  @type t :: %__MODULE__{
          extension_id: String.t(),
          component_id: String.t(),
          kind: kind(),
          version: String.t(),
          capabilities: [atom()]
        }

  @id_pattern ~r/^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)+$/
  @component_pattern ~r/^[a-z][a-z0-9]*(?:[_-][a-z0-9]+)*$/

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) do
    attrs = Map.new(attrs)

    component = %__MODULE__{
      extension_id: value(attrs, :extension_id),
      component_id: value(attrs, :component_id),
      kind: value(attrs, :kind),
      version: value(attrs, :version),
      capabilities: value(attrs, :capabilities, [])
    }

    case validate(component) do
      :ok -> {:ok, component}
      {:error, _reason} = error -> error
    end
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, component} -> component
      {:error, reason} -> raise ArgumentError, "invalid Extension component: #{reason}"
    end
  end

  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{} = component) do
    cond do
      not valid_string?(component.extension_id, @id_pattern) ->
        {:error, "extension_id must be a stable namespaced identifier"}

      not valid_string?(component.component_id, @component_pattern) ->
        {:error, "component_id must be a stable lowercase identifier"}

      component.kind not in @kinds ->
        {:error, "kind must be adapter or processor"}

      not valid_version?(component.version) ->
        {:error, "version must use semantic versioning"}

      not is_list(component.capabilities) or
          Enum.any?(component.capabilities, &(not is_atom(&1))) ->
        {:error, "capabilities must be a list of atoms"}

      length(Enum.uniq(component.capabilities)) != length(component.capabilities) ->
        {:error, "capabilities must be unique"}

      true ->
        :ok
    end
  end

  @spec key(t()) :: {String.t(), String.t()}
  def key(%__MODULE__{} = component),
    do: {component.extension_id, component.component_id}

  defp valid_string?(value, pattern),
    do: is_binary(value) and byte_size(value) <= 255 and Regex.match?(pattern, value)

  defp valid_version?(value) when is_binary(value),
    do: match?({:ok, _version}, Version.parse(value))

  defp valid_version?(_value), do: false

  defp value(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end

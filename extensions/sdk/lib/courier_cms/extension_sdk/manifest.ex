defmodule CourierCMS.ExtensionSDK.Manifest do
  @moduledoc "Validated declarative metadata for one native OTP Extension package."

  alias CourierCMS.ExtensionSDK.Component

  @manifest_version 1
  @required_fields ~w(
    manifestVersion
    extensionId
    name
    version
    otpApplication
    sdkRequirement
    couriercmsRequirement
    elixirRequirement
    otpRequirement
    components
  )
  @max_components 100
  @max_capabilities 100

  @enforce_keys [
    :manifest_version,
    :extension_id,
    :name,
    :version,
    :otp_application,
    :sdk_requirement,
    :couriercms_requirement,
    :elixir_requirement,
    :otp_requirement,
    :components
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          manifest_version: pos_integer(),
          extension_id: String.t(),
          name: String.t(),
          version: String.t(),
          otp_application: String.t(),
          sdk_requirement: String.t(),
          couriercms_requirement: String.t(),
          elixir_requirement: String.t(),
          otp_requirement: String.t(),
          components: [component_declaration()]
        }

  @type component_declaration :: %{
          id: String.t(),
          kind: Component.kind(),
          module: String.t(),
          capabilities: [String.t()]
        }

  @spec parse(map()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(manifest) when is_map(manifest) do
    errors =
      []
      |> require_fields(manifest)
      |> validate_manifest_version(manifest)
      |> validate_strings(manifest)
      |> validate_requirements(manifest)
      |> validate_application(manifest)
      |> validate_components(manifest)

    if errors == [] do
      {:ok, build(manifest)}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  def parse(_manifest), do: {:error, ["manifest must be an object"]}

  defp build(manifest) do
    %__MODULE__{
      manifest_version: manifest["manifestVersion"],
      extension_id: manifest["extensionId"],
      name: manifest["name"],
      version: manifest["version"],
      otp_application: manifest["otpApplication"],
      sdk_requirement: manifest["sdkRequirement"],
      couriercms_requirement: manifest["couriercmsRequirement"],
      elixir_requirement: manifest["elixirRequirement"],
      otp_requirement: manifest["otpRequirement"],
      components: Enum.map(manifest["components"], &build_component/1)
    }
  end

  defp build_component(component) do
    %{
      id: component["id"],
      kind: parse_kind(component["kind"]),
      module: component["module"],
      capabilities: component["capabilities"] || []
    }
  end

  defp require_fields(errors, manifest) do
    Enum.reduce(@required_fields, errors, fn field, result ->
      if Map.has_key?(manifest, field), do: result, else: ["#{field} is required" | result]
    end)
  end

  defp validate_manifest_version(errors, %{"manifestVersion" => @manifest_version}), do: errors

  defp validate_manifest_version(errors, %{"manifestVersion" => _version}),
    do: ["manifestVersion is unsupported" | errors]

  defp validate_manifest_version(errors, _manifest), do: errors

  defp validate_strings(errors, manifest) do
    string_fields = [
      {"extensionId", 255},
      {"name", 255},
      {"version", 64},
      {"sdkRequirement", 255},
      {"couriercmsRequirement", 255},
      {"elixirRequirement", 255},
      {"otpRequirement", 255}
    ]

    Enum.reduce(string_fields, errors, fn {field, maximum}, result ->
      case manifest[field] do
        value when is_binary(value) and value != "" and byte_size(value) <= maximum -> result
        nil -> result
        _other -> ["#{field} must be a non-empty string of at most #{maximum} bytes" | result]
      end
    end)
  end

  defp validate_requirements(errors, manifest) do
    requirement_fields =
      ~w(sdkRequirement couriercmsRequirement elixirRequirement otpRequirement)

    Enum.reduce(requirement_fields, errors, fn field, result ->
      case manifest[field] do
        value when is_binary(value) ->
          case Version.parse_requirement(value) do
            {:ok, _requirement} -> result
            :error -> ["#{field} must be a valid version requirement" | result]
          end

        _other ->
          result
      end
    end)
  end

  defp validate_application(errors, %{"otpApplication" => application})
       when is_binary(application) and application != "" and byte_size(application) <= 64 do
    if Regex.match?(~r/^[a-z][a-z0-9_]*$/, application),
      do: errors,
      else: ["otpApplication must be a lowercase OTP application name" | errors]
  end

  defp validate_application(errors, %{"otpApplication" => _application}),
    do: ["otpApplication must be a non-empty string" | errors]

  defp validate_application(errors, _manifest), do: errors

  defp validate_components(errors, %{
         "extensionId" => extension_id,
         "version" => version,
         "components" => components
       })
       when is_list(components) and components != [] and length(components) <= @max_components do
    component_errors =
      components
      |> Enum.with_index()
      |> Enum.flat_map(fn {component, index} ->
        validate_component(extension_id, version, component, index)
      end)

    ids = Enum.map(components, & &1["id"])

    duplicate_errors =
      if length(ids) == length(Enum.uniq(ids)),
        do: [],
        else: ["component IDs must be unique"]

    Enum.reverse(component_errors ++ duplicate_errors) ++ errors
  end

  defp validate_components(errors, %{"components" => _components}),
    do: ["components must be a non-empty list with at most #{@max_components} entries" | errors]

  defp validate_components(errors, _manifest), do: errors

  defp validate_component(extension_id, version, component, index) when is_map(component) do
    kind = parse_kind(component["kind"])
    capabilities = component["capabilities"] || []

    attrs = %{
      extension_id: extension_id,
      component_id: component["id"],
      kind: kind,
      version: version,
      capabilities: []
    }

    result =
      case Component.new(attrs) do
        {:ok, _component} -> []
        {:error, reason} -> ["components[#{index}] #{reason}"]
      end

    result
    |> validate_component_module(component, index)
    |> validate_component_capabilities(capabilities, index)
  end

  defp validate_component(_extension_id, _version, _component, index),
    do: ["components[#{index}] must be an object"]

  defp validate_component_module(errors, %{"module" => module}, _index)
       when is_binary(module) and module != "" and byte_size(module) <= 255,
       do:
         if(Regex.match?(~r/^[A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)+$/, module),
           do: errors,
           else: ["component module must be a fully qualified Elixir module" | errors]
         )

  defp validate_component_module(errors, _component, index),
    do: ["components[#{index}] module must be a non-empty string" | errors]

  defp validate_component_capabilities(errors, capabilities, _index)
       when is_list(capabilities) and length(capabilities) <= @max_capabilities do
    cond do
      not Enum.all?(capabilities, &(is_binary(&1) and Regex.match?(~r/^[a-z][a-z0-9_]*$/, &1))) ->
        ["component capabilities must be lowercase identifiers" | errors]

      length(capabilities) != length(Enum.uniq(capabilities)) ->
        ["component capabilities must be unique" | errors]

      true ->
        errors
    end
  end

  defp validate_component_capabilities(errors, _capabilities, index),
    do: [
      "components[#{index}] capabilities must be a list with at most #{@max_capabilities} entries"
      | errors
    ]

  defp parse_kind("adapter"), do: :adapter
  defp parse_kind("processor"), do: :processor
  defp parse_kind(_kind), do: :invalid
end

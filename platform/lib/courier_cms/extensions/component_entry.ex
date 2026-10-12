defmodule CourierCMS.Extensions.ComponentEntry do
  @moduledoc false

  alias CourierCMS.Adapters.Definition
  alias CourierCMS.ExtensionSDK.{Component, Processor, SourceAdapter, TargetAdapter}
  alias CourierCMS.Extensions.Artifact
  alias CourierCMS.Processors.Definition, as: ProcessorDefinition

  def build!(adapter_key, source_module, target_module, expected_component \\ nil, opts \\ []) do
    modules = [source_module, target_module] |> Enum.reject(&is_nil/1) |> Enum.uniq()
    components = modules |> Enum.map(&component!/1) |> Enum.uniq()

    component =
      case components do
        [component] ->
          component

        _other ->
          raise ArgumentError, "Adapter #{inspect(adapter_key)} has conflicting components"
      end

    if expected_component && component != expected_component do
      raise ArgumentError, "loaded component identity does not match its manifest"
    end

    if component.component_id != adapter_key do
      raise ArgumentError,
            "Adapter #{inspect(adapter_key)} must match component ID #{inspect(component.component_id)}"
    end

    validate_capability!(source_module, component, :source, SourceAdapter)
    validate_capability!(target_module, component, :target, TargetAdapter)

    definition = modules |> Enum.map(& &1.definition()) |> merge_definitions()
    Definition.validate!(definition)

    if definition.key != adapter_key do
      raise ArgumentError, "Adapter definition key does not match component ID"
    end

    artifact = Keyword.get(opts, :artifact) || Artifact.bundled(component, modules)

    %{
      adapter_key: adapter_key,
      component: component,
      artifact: artifact,
      definition: definition,
      source_module: source_module,
      target_module: target_module,
      processor_module: nil
    }
  end

  def build_processor!(module, expected_component \\ nil, opts \\ []) do
    component = component!(module)

    if expected_component && component != expected_component do
      raise ArgumentError, "loaded component identity does not match its manifest"
    end

    unless component.kind == :processor and :processor in component.capabilities do
      raise ArgumentError, "Processor component must declare processor kind and capability"
    end

    validate_behaviour!(module, Processor)
    definition = module.definition()

    ProcessorDefinition.validate!(definition)

    artifact = Keyword.get(opts, :artifact) || Artifact.bundled(component, [module])

    %{
      adapter_key: component.component_id,
      component: component,
      artifact: artifact,
      definition: definition,
      source_module: nil,
      target_module: nil,
      processor_module: module
    }
  end

  defp component!(module) do
    unless Code.ensure_loaded?(module) and function_exported?(module, :component, 0) do
      raise ArgumentError, "#{inspect(module)} does not declare Extension component identity"
    end

    component = module.component()

    case Component.validate(component) do
      :ok -> component
      {:error, reason} -> raise ArgumentError, "#{inspect(module)}: #{reason}"
    end
  end

  defp validate_capability!(nil, _component, _capability, _behaviour), do: :ok

  defp validate_capability!(module, component, capability, behaviour) do
    unless capability in component.capabilities do
      raise ArgumentError, "#{inspect(module)} does not declare #{capability} capability"
    end

    validate_behaviour!(module, behaviour)
  end

  defp validate_behaviour!(module, behaviour) do
    optional = behaviour.behaviour_info(:optional_callbacks)

    behaviour.behaviour_info(:callbacks)
    |> Enum.reject(&(&1 in optional))
    |> Enum.each(fn {name, arity} ->
      unless function_exported?(module, name, arity) do
        raise ArgumentError,
              "#{inspect(module)} does not implement required callback #{name}/#{arity}"
      end
    end)
  end

  defp merge_definitions(definitions) do
    Enum.reduce(definitions, %{}, fn definition, merged ->
      Map.merge(merged, definition, fn
        :connection, left, right -> merge_connection_definitions(left, right)
        _key, _left, right -> right
      end)
    end)
  end

  defp merge_connection_definitions(left, right) do
    Map.merge(left, right, fn
      :fields, left_fields, right_fields ->
        (left_fields ++ right_fields) |> Enum.uniq_by(& &1.key)

      _key, left_value, right_value ->
        if left_value == right_value,
          do: left_value,
          else: raise(ArgumentError, "Source and target connection definitions conflict")
    end)
  end
end

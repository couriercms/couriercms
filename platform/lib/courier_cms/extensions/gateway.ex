defmodule CourierCMS.Extensions.Gateway do
  @moduledoc "The only platform boundary for resolving and invoking Extension components."

  alias CourierCMS.ExtensionSDK.AdapterError
  alias CourierCMS.Extensions.{Artifact, ComponentRegistry}

  @source_operations %{
    capabilities: 1,
    test_connection: 1,
    enumerate: 3,
    changes_since: 4,
    read_root: 3,
    read_asset: 2
  }
  @target_operations %{
    capabilities: 1,
    idempotency_strategy: 0,
    test_connection: 1,
    validate_destination: 2,
    validate_projections: 2,
    find_delivery: 3,
    create_delivery: 2,
    update_delivery: 4,
    find_asset: 3,
    create_asset: 2,
    update_asset: 4
  }
  @processor_operations %{validate_config: 1, process: 2}

  def fetch_component(adapter_key) do
    with {:ok, entry} <- ComponentRegistry.fetch_by_alias(adapter_key),
         do: {:ok, entry.component}
  end

  def fetch_component(extension_id, component_id) do
    with {:ok, entry} <- ComponentRegistry.fetch(extension_id, component_id),
         do: {:ok, entry.component}
  end

  def identity_attributes(adapter_key) do
    with {:ok, component} <- fetch_component(adapter_key) do
      {:ok,
       %{
         extension_id: component.extension_id,
         component_id: component.component_id
       }}
    end
  end

  def artifact(reference) do
    with {:ok, entry} <- component(reference), do: {:ok, Artifact.from_entry(entry)}
  end

  def validate_artifact(artifact, capability) when capability in [:source, :target, :processor] do
    with :ok <- Artifact.validate(artifact),
         {:ok, entry} <- component(Artifact.reference(artifact)),
         true <- Artifact.matches?(artifact, entry.artifact),
         true <- capability_available?(entry, capability) do
      {:ok, Artifact.reference(artifact)}
    else
      _other ->
        {:error,
         AdapterError.new(
           :unsupported,
           "The Run requires an Extension artifact that is not installed on this node"
         )}
    end
  end

  def components, do: Enum.map(ComponentRegistry.list(), & &1.component)

  def fetch_definition(adapter_key) do
    with {:ok, entry} <- ComponentRegistry.fetch_by_alias(adapter_key),
         do: {:ok, entry.definition}
  end

  def fetch_definition!(adapter_key) do
    case fetch_definition(adapter_key) do
      {:ok, definition} -> definition
      :error -> raise ArgumentError, "Adapter #{inspect(adapter_key)} is not registered"
    end
  end

  def definitions do
    ComponentRegistry.list()
    |> Enum.filter(&(&1.source_module || &1.target_module))
    |> Enum.map(& &1.definition)
    |> Enum.sort_by(& &1.label)
  end

  def source_definitions do
    ComponentRegistry.list()
    |> Enum.filter(& &1.source_module)
    |> Enum.map(& &1.definition)
    |> Enum.sort_by(& &1.label)
  end

  def target_definitions do
    ComponentRegistry.list()
    |> Enum.filter(& &1.target_module)
    |> Enum.map(& &1.definition)
    |> Enum.sort_by(& &1.label)
  end

  def processor_definitions do
    ComponentRegistry.list()
    |> Enum.filter(& &1.processor_module)
    |> Enum.map(fn entry ->
      Map.merge(entry.definition, %{
        extension_id: entry.component.extension_id,
        component_id: entry.component.component_id,
        version: entry.component.version
      })
    end)
    |> Enum.sort_by(& &1.label)
  end

  def source_available?(reference) do
    match?({:ok, %{source_module: module}} when not is_nil(module), component(reference))
  end

  def source_supports?(reference, operation) do
    with {:ok, expected_arity} <- Map.fetch(@source_operations, operation),
         {:ok, %{source_module: module}} when not is_nil(module) <- component(reference) do
      function_exported?(module, operation, expected_arity)
    else
      _other -> false
    end
  end

  def target_available?(reference) do
    match?({:ok, %{target_module: module}} when not is_nil(module), component(reference))
  end

  def target_supports?(reference, operation) do
    with {:ok, expected_arity} <- Map.fetch(@target_operations, operation),
         {:ok, %{target_module: module}} when not is_nil(module) <- component(reference) do
      function_exported?(module, operation, expected_arity)
    else
      _other -> false
    end
  end

  def source(reference, operation, args) when is_list(args) do
    invoke(reference, :source_module, @source_operations, operation, args)
  end

  def target(reference, operation, args) when is_list(args) do
    invoke(reference, :target_module, @target_operations, operation, args)
  end

  def processor_available?(reference) do
    match?({:ok, %{processor_module: module}} when not is_nil(module), component(reference))
  end

  def processor(reference, operation, args) when is_list(args) do
    invoke(reference, :processor_module, @processor_operations, operation, args)
  end

  def processor_definition(reference) do
    with {:ok, %{processor_module: module} = entry} when not is_nil(module) <-
           component(reference) do
      {:ok,
       Map.merge(entry.definition, %{
         extension_id: entry.component.extension_id,
         component_id: entry.component.component_id,
         version: entry.component.version
       })}
    else
      _other -> :error
    end
  end

  def test_connection(reference, connection) do
    case component(reference) do
      {:ok, %{source_module: source}} when not is_nil(source) ->
        invoke_module(source, @source_operations, :test_connection, [connection])

      {:ok, %{target_module: target}} when not is_nil(target) ->
        invoke_module(target, @target_operations, :test_connection, [connection])

      _other ->
        :error
    end
  end

  def capabilities(reference, connection) do
    case component(reference) do
      {:ok, %{source_module: source}} when not is_nil(source) ->
        invoke_module(source, @source_operations, :capabilities, [connection])

      {:ok, %{target_module: target}} when not is_nil(target) ->
        invoke_module(target, @target_operations, :capabilities, [connection])

      _other ->
        :error
    end
  end

  defp invoke(reference, module_field, operations, operation, args) do
    with {:ok, entry} <- component(reference),
         module when not is_nil(module) <- Map.fetch!(entry, module_field) do
      invoke_module(module, operations, operation, args)
    else
      _other -> :error
    end
  end

  defp invoke_module(module, operations, operation, args) do
    with {:ok, expected_arity} <- Map.fetch(operations, operation),
         true <- expected_arity == length(args),
         true <- function_exported?(module, operation, expected_arity) do
      apply(module, operation, args)
    else
      _other -> :error
    end
  end

  defp capability_available?(entry, :source), do: not is_nil(entry.source_module)
  defp capability_available?(entry, :target), do: not is_nil(entry.target_module)
  defp capability_available?(entry, :processor), do: not is_nil(entry.processor_module)

  defp component(adapter_key) when is_binary(adapter_key),
    do: ComponentRegistry.fetch_by_alias(adapter_key)

  defp component({extension_id, component_id}),
    do: ComponentRegistry.fetch(extension_id, component_id)

  defp component(reference) when is_map(reference) do
    extension_id = Map.get(reference, :extension_id, Map.get(reference, "extension_id"))
    component_id = Map.get(reference, :component_id, Map.get(reference, "component_id"))

    if is_binary(extension_id) and is_binary(component_id),
      do: ComponentRegistry.fetch(extension_id, component_id),
      else: :error
  end

  defp component(_reference), do: :error
end

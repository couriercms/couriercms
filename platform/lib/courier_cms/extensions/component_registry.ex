defmodule CourierCMS.Extensions.ComponentRegistry do
  @moduledoc """
  Supervised node-local registry of validated Extension components.

  PostgreSQL stores durable component references. This ETS table contains only
  rebuildable runtime dispatch metadata loaded during node startup.
  """

  use GenServer

  alias CourierCMS.ExtensionSDK.Component
  alias CourierCMS.Extensions.{ComponentEntry, PackageLoader}

  @table __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec fetch_by_alias(String.t()) :: {:ok, map()} | :error
  def fetch_by_alias(adapter_key) when is_binary(adapter_key) do
    with [{_alias_key, component_key}] <- lookup({:alias, adapter_key}),
         [{_component_key, entry}] <- lookup({:component, component_key}) do
      {:ok, entry}
    else
      _other -> :error
    end
  end

  @spec fetch(String.t(), String.t()) :: {:ok, map()} | :error
  def fetch(extension_id, component_id) do
    case lookup({:component, {extension_id, component_id}}) do
      [{_key, entry}] -> {:ok, entry}
      _other -> :error
    end
  end

  @spec list() :: [map()]
  def list do
    if table_available?() do
      @table
      |> :ets.tab2list()
      |> Enum.flat_map(fn
        {{:component, _key}, entry} -> [entry]
        _alias -> []
      end)
      |> Enum.sort_by(&Component.key(&1.component))
    else
      []
    end
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :protected, read_concurrency: true])

    entries = build_entries!()

    Enum.each(entries, fn entry ->
      component_key = Component.key(entry.component)
      true = :ets.insert_new(@table, {{:component, component_key}, entry})
      true = :ets.insert_new(@table, {{:alias, entry.adapter_key}, component_key})
    end)

    {:ok, %{component_count: length(entries)}}
  end

  defp build_entries! do
    sources = Application.get_env(:couriercms, :source_adapters, %{})
    targets = Application.get_env(:couriercms, :target_adapters, %{})

    bundled =
      sources
      |> Map.keys()
      |> Kernel.++(Map.keys(targets))
      |> Enum.uniq()
      |> Enum.map(&ComponentEntry.build!(&1, Map.get(sources, &1), Map.get(targets, &1)))

    packaged = PackageLoader.component_entries()
    ensure_unique!(bundled ++ packaged)
  end

  defp ensure_unique!(entries) do
    Enum.reduce(entries, {MapSet.new(), MapSet.new(), []}, fn entry,
                                                              {component_keys, aliases, result} ->
      component_key = Component.key(entry.component)

      if MapSet.member?(component_keys, component_key) or
           MapSet.member?(aliases, entry.adapter_key) do
        raise ArgumentError,
              "Extension component collision for #{inspect(component_key)} / #{inspect(entry.adapter_key)}"
      end

      {
        MapSet.put(component_keys, component_key),
        MapSet.put(aliases, entry.adapter_key),
        [entry | result]
      }
    end)
    |> elem(2)
    |> Enum.reverse()
  end

  defp lookup(key) do
    if table_available?(), do: :ets.lookup(@table, key), else: []
  end

  defp table_available?, do: :ets.whereis(@table) != :undefined
end

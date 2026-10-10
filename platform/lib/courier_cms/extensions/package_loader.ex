defmodule CourierCMS.Extensions.PackageLoader do
  @moduledoc "Discovers and loads trusted precompiled Extension packages during node startup."

  use GenServer

  require Logger

  alias CourierCMS.Extensions.{Diagnostic, Package}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def component_entries(server \\ __MODULE__), do: GenServer.call(server, :component_entries)
  def loaded_extensions(server \\ __MODULE__), do: GenServer.call(server, :loaded_extensions)
  def diagnostics(server \\ __MODULE__), do: GenServer.call(server, :diagnostics)

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    {loaded, diagnostics} =
      case persisted_state(name) do
        nil ->
          state = discover(options(opts))
          persist_state(name, state)
          state

        state ->
          state
      end

    Enum.each(diagnostics, fn diagnostic ->
      log_level = if diagnostic.status == :loaded, do: :info, else: :error
      Logger.log(log_level, "Extension package #{diagnostic.package}: #{diagnostic.message}")
    end)

    {:ok, %{loaded: loaded, diagnostics: diagnostics}}
  end

  @impl true
  def handle_call(:component_entries, _from, state) do
    entries = Enum.flat_map(state.loaded, & &1.component_entries)
    {:reply, entries, state}
  end

  def handle_call(:loaded_extensions, _from, state), do: {:reply, state.loaded, state}
  def handle_call(:diagnostics, _from, state), do: {:reply, state.diagnostics, state}

  defp discover(opts) do
    paths = package_paths(opts.extensions_dir)
    {selected, excess} = Enum.split(paths, opts.max_packages)

    excess_diagnostics =
      Enum.map(excess, fn path ->
        %Diagnostic{
          package: Path.basename(path),
          status: :rejected,
          message: "installed package count exceeds the configured limit"
        }
      end)

    selected
    |> Enum.map(&inspect_safely(&1, opts))
    |> reject_conflicting_candidates()
    |> Enum.reduce({[], excess_diagnostics}, fn
      {:error, diagnostic}, {loaded, diagnostics} ->
        {loaded, [diagnostic | diagnostics]}

      {:ok, candidate}, {loaded, diagnostics} ->
        case activate_safely(candidate, opts) do
          {:ok, extension} ->
            diagnostic = diagnostic(candidate, :loaded, "loaded")
            {[extension | loaded], [diagnostic | diagnostics]}

          {:error, message} ->
            {loaded, [diagnostic(candidate, :rejected, message) | diagnostics]}
        end
    end)
    |> then(fn {loaded, diagnostics} ->
      {Enum.reverse(loaded), Enum.reverse(diagnostics)}
    end)
  end

  defp package_paths(directory) do
    case File.ls(directory) do
      {:ok, names} ->
        names
        |> Enum.filter(&String.ends_with?(&1, ".couriercms"))
        |> Enum.map(&Path.join(directory, &1))
        |> Enum.sort()

      {:error, :enoent} ->
        []

      {:error, reason} ->
        Logger.error("Cannot inspect Extension directory #{directory}: #{inspect(reason)}")
        []
    end
  end

  defp inspect_safely(path, opts) do
    case Package.inspect(path, opts) do
      {:ok, candidate} ->
        {:ok, candidate}

      {:error, message} ->
        {:error,
         %Diagnostic{
           package: Path.basename(path),
           status: :rejected,
           message: message
         }}
    end
  rescue
    error ->
      {:error,
       %Diagnostic{
         package: Path.basename(path),
         status: :rejected,
         message: Exception.message(error)
       }}
  end

  defp reject_conflicting_candidates(results) do
    candidates = for {:ok, candidate} <- results, do: candidate

    duplicate_ids =
      candidates
      |> Enum.group_by(& &1.manifest.extension_id)
      |> Enum.filter(fn {_id, matches} -> length(matches) > 1 end)
      |> MapSet.new(fn {id, _matches} -> id end)

    duplicate_aliases =
      candidates
      |> Enum.flat_map(fn candidate ->
        Enum.map(candidate.manifest.components, &{&1.id, candidate.path})
      end)
      |> Enum.group_by(&elem(&1, 0))
      |> Enum.filter(fn {_alias, matches} -> length(matches) > 1 end)
      |> MapSet.new(fn {adapter_alias, _matches} -> adapter_alias end)

    {reserved_ids, reserved_aliases} = bundled_identities()

    Enum.map(results, fn
      {:ok, candidate} ->
        extension_id = candidate.manifest.extension_id
        aliases = Enum.map(candidate.manifest.components, & &1.id)

        cond do
          MapSet.member?(duplicate_ids, extension_id) ->
            {:error,
             diagnostic(candidate, :rejected, "multiple installed versions use this Extension ID")}

          MapSet.member?(reserved_ids, extension_id) ->
            {:error,
             diagnostic(candidate, :rejected, "Extension ID collides with a bundled component")}

          Enum.any?(aliases, &MapSet.member?(duplicate_aliases, &1)) ->
            {:error,
             diagnostic(
               candidate,
               :rejected,
               "component ID is also declared by another installed Extension"
             )}

          Enum.any?(aliases, &MapSet.member?(reserved_aliases, &1)) ->
            {:error,
             diagnostic(candidate, :rejected, "component ID collides with a bundled component")}

          true ->
            {:ok, candidate}
        end

      error ->
        error
    end)
  end

  defp bundled_identities do
    sources = Application.get_env(:couriercms, :source_adapters, %{})
    targets = Application.get_env(:couriercms, :target_adapters, %{})
    aliases = Map.keys(sources) ++ Map.keys(targets)

    ids =
      (Map.values(sources) ++ Map.values(targets))
      |> Enum.uniq()
      |> Enum.flat_map(fn module ->
        if Code.ensure_loaded?(module) and function_exported?(module, :component, 0),
          do: [module.component().extension_id],
          else: []
      end)

    {MapSet.new(ids), MapSet.new(aliases)}
  end

  defp activate_safely(candidate, opts) do
    Package.activate(candidate, opts)
  rescue
    error -> {:error, Exception.message(error)}
  catch
    kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
  end

  defp diagnostic(%Package.Candidate{} = candidate, status, message) do
    %Diagnostic{
      package: Path.basename(candidate.path),
      extension_id: candidate.manifest.extension_id,
      version: candidate.manifest.version,
      checksum: candidate.checksum,
      status: status,
      message: message
    }
  end

  defp options(overrides) do
    %{
      extensions_dir:
        Keyword.get(
          overrides,
          :extensions_dir,
          Application.fetch_env!(:couriercms, :extensions_dir)
        ),
      cache_dir:
        Keyword.get(
          overrides,
          :cache_dir,
          Application.fetch_env!(:couriercms, :extension_cache_dir)
        ),
      signature_policy:
        Keyword.get(
          overrides,
          :signature_policy,
          Application.fetch_env!(:couriercms, :extension_signature_policy)
        ),
      trusted_keys:
        Keyword.get(
          overrides,
          :trusted_keys,
          Application.fetch_env!(:couriercms, :extension_trusted_keys)
        ),
      max_package_bytes:
        Keyword.get(
          overrides,
          :max_package_bytes,
          Application.fetch_env!(:couriercms, :extension_max_package_bytes)
        ),
      max_uncompressed_bytes:
        Keyword.get(
          overrides,
          :max_uncompressed_bytes,
          Application.fetch_env!(:couriercms, :extension_max_uncompressed_bytes)
        ),
      max_entries:
        Keyword.get(
          overrides,
          :max_entries,
          Application.fetch_env!(:couriercms, :extension_max_entries)
        ),
      max_packages:
        Keyword.get(
          overrides,
          :max_packages,
          Application.fetch_env!(:couriercms, :extension_max_packages)
        )
    }
  end

  defp persisted_state(__MODULE__) do
    :persistent_term.get({__MODULE__, :startup_state}, nil)
  end

  defp persisted_state(_name), do: nil

  defp persist_state(__MODULE__, state) do
    :persistent_term.put({__MODULE__, :startup_state}, state)
  end

  defp persist_state(_name, _state), do: :ok
end

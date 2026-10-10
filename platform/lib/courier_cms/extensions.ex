defmodule CourierCMS.Extensions do
  @moduledoc """
  Operator-facing inventory and durable reference checks for native Extensions.

  Package installation remains a filesystem and restart operation. This context
  deliberately provides diagnostics and guards, not runtime package mutation.
  """

  import Ecto.Query

  alias CourierCMS.Accounts
  alias CourierCMS.Accounts.Scope
  alias CourierCMS.Connections.Connection
  alias CourierCMS.Execution.Run
  alias CourierCMS.Extensions.{ComponentRegistry, Gateway, PackageLoader}
  alias CourierCMS.Repo
  alias CourierCMS.Routes.{Route, RouteRevision}

  @unfinished_run_statuses [:queued, :planning, :running]

  @doc "Returns a deterministic, content-free description of this node's runtime components."
  def runtime_snapshot do
    artifacts =
      ComponentRegistry.list()
      |> Enum.map(fn entry ->
        %{
          "extension_id" => entry.component.extension_id,
          "component_id" => entry.component.component_id,
          "version" => entry.artifact["version"],
          "checksum" => entry.artifact["checksum"],
          "sdk_version" => entry.artifact["sdk_version"],
          "runtime" => entry.artifact["runtime"]
        }
      end)
      |> Enum.sort_by(&{&1["extension_id"], &1["component_id"]})

    fingerprint =
      artifacts
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    status =
      if Enum.any?(PackageLoader.diagnostics(), &(&1.status == :rejected)),
        do: "degraded",
        else: "ok"

    %{fingerprint: fingerprint, artifacts: artifacts, status: status}
  end

  @doc "Compares fresh web and worker heartbeat Extension sets with this node."
  def cluster_status(max_age_seconds \\ 90) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_seconds, :second)
    local = runtime_snapshot()

    nodes =
      CourierCMS.Execution.WorkerHeartbeat
      |> where(
        [heartbeat],
        heartbeat.role in ["all", "web", "worker"] and heartbeat.last_seen_at >= ^cutoff
      )
      |> order_by([heartbeat], asc: heartbeat.node_id)
      |> Repo.all()
      |> Enum.map(fn heartbeat ->
        %{
          node_id: heartbeat.node_id,
          role: heartbeat.role,
          version: heartbeat.version,
          fingerprint: heartbeat.extension_fingerprint,
          extension_set: heartbeat.extension_set,
          status: heartbeat.extension_status,
          last_seen_at: heartbeat.last_seen_at,
          matches_local: heartbeat.extension_fingerprint == local.fingerprint
        }
      end)

    mismatched_nodes =
      Enum.reject(nodes, fn node ->
        is_binary(node.fingerprint) and node.matches_local
      end)

    %{
      local_fingerprint: local.fingerprint,
      consistent?: mismatched_nodes == [],
      fresh_nodes: nodes,
      mismatched_nodes: mismatched_nodes
    }
  end

  @doc "Returns this node's Extension inventory for an authorized operator."
  def operator_inventory(%Scope{} = scope) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin]) do
      {:ok, build_inventory(scope.workspace.id)}
    end
  end

  @doc "Returns durable references that must be cleared before package removal."
  def references(extension_id, workspace_id \\ nil) when is_binary(extension_id) do
    %{
      connections: count_connections(extension_id, workspace_id, false),
      enabled_connections: count_connections(extension_id, workspace_id, true),
      routes: count_routes(extension_id, workspace_id, false),
      active_routes: count_routes(extension_id, workspace_id, true),
      unfinished_runs: count_unfinished_runs(extension_id, workspace_id)
    }
  end

  @doc "Raises when an Extension still has active or unfinished references."
  def assert_removable!(extension_id) when is_binary(extension_id) do
    refs = references(extension_id)

    blockers =
      [
        {refs.enabled_connections, "enabled Connection(s)"},
        {refs.active_routes, "active Route(s)"},
        {refs.unfinished_runs, "unfinished Run(s)"}
      ]
      |> Enum.reject(fn {count, _label} -> count == 0 end)
      |> Enum.map_join(", ", fn {count, label} -> "#{count} #{label}" end)

    if blockers == "" do
      :ok
    else
      raise ArgumentError,
            "Extension #{inspect(extension_id)} cannot be removed: #{blockers}"
    end
  end

  @doc "Raises when this node has rejected packages or unresolved active references."
  def verify_runtime! do
    rejected = Enum.filter(PackageLoader.diagnostics(), &(&1.status == :rejected))
    cluster = cluster_status()

    unresolved =
      Connection
      |> where([connection], connection.enabled)
      |> select([connection], {connection.extension_id, connection.component_id})
      |> Repo.all()
      |> Kernel.++(active_route_components())
      |> Enum.uniq()
      |> Enum.reject(fn {extension_id, component_id} ->
        match?({:ok, _entry}, ComponentRegistry.fetch(extension_id, component_id))
      end)

    artifact_errors = unfinished_artifact_errors()

    errors =
      Enum.map(rejected, &"#{&1.package}: #{&1.message}") ++
        Enum.map(unresolved, fn {extension_id, component_id} ->
          "missing component #{extension_id}/#{component_id}"
        end) ++
        artifact_errors ++
        Enum.map(cluster.mismatched_nodes, fn node ->
          "fresh node #{node.node_id} has a different Extension artifact set"
        end)

    if errors == [] do
      :ok
    else
      raise "Extension runtime verification failed: #{Enum.join(errors, "; ")}"
    end
  end

  defp build_inventory(workspace_id) do
    entries = ComponentRegistry.list()
    loaded = PackageLoader.loaded_extensions()
    diagnostics = PackageLoader.diagnostics()

    loaded_by_id = Map.new(loaded, &{&1.manifest.extension_id, &1})
    referenced_identities = referenced_identities(workspace_id)

    registered =
      entries
      |> Enum.group_by(& &1.component.extension_id)
      |> Enum.map(fn {extension_id, component_entries} ->
        loaded_extension = Map.get(loaded_by_id, extension_id)
        first = hd(component_entries)
        registered_component_ids = MapSet.new(component_entries, & &1.component.component_id)

        missing_component_ids =
          referenced_identities
          |> Enum.filter(&(elem(&1, 0) == extension_id))
          |> Enum.map(&elem(&1, 1))
          |> Enum.reject(&MapSet.member?(registered_component_ids, &1))
          |> Enum.uniq()

        component_summaries =
          Enum.map(component_entries, &component_summary/1) ++
            Enum.map(missing_component_ids, fn component_id ->
              %{id: component_id, kind: nil, capabilities: [], available: false}
            end)

        %{
          extension_id: extension_id,
          name: loaded_extension && loaded_extension.manifest.name,
          version: first.component.version,
          checksum: first.artifact["checksum"],
          sdk_compatibility:
            if(loaded_extension,
              do: loaded_extension.manifest.sdk_requirement,
              else: CourierCMS.ExtensionSDK.version()
            ),
          application:
            if(loaded_extension,
              do: Atom.to_string(loaded_extension.otp_application),
              else: "couriercms"
            ),
          provenance: first.artifact["provenance"],
          package: loaded_extension && Path.basename(loaded_extension.package_path),
          status: if(missing_component_ids == [], do: :loaded, else: :incomplete),
          message:
            if(missing_component_ids == [],
              do: "Loaded on this node",
              else: "Loaded, but referenced components are missing on this node"
            ),
          node: to_string(node()),
          components: component_summaries,
          references: references(extension_id, workspace_id)
        }
      end)

    registered_ids = MapSet.new(registered, & &1.extension_id)

    missing =
      referenced_identities
      |> Enum.reject(fn {extension_id, _component_id} ->
        MapSet.member?(registered_ids, extension_id)
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn {extension_id, component_ids} ->
        %{
          extension_id: extension_id,
          name: nil,
          version: nil,
          checksum: nil,
          sdk_compatibility: nil,
          application: nil,
          provenance: nil,
          package: nil,
          status: :missing,
          message: "Referenced configuration is not installed on this node",
          node: to_string(node()),
          components:
            Enum.map(Enum.uniq(component_ids), fn component_id ->
              %{id: component_id, kind: nil, capabilities: [], available: false}
            end),
          references: references(extension_id, workspace_id)
        }
      end)

    %{
      node: to_string(node()),
      extensions: Enum.sort_by(registered ++ missing, & &1.extension_id),
      rejected_packages: Enum.filter(diagnostics, &(&1.status == :rejected)),
      cluster: cluster_status()
    }
  end

  defp component_summary(entry) do
    %{
      id: entry.component.component_id,
      kind: entry.component.kind,
      capabilities: entry.component.capabilities,
      available: true
    }
  end

  defp referenced_identities(workspace_id) do
    connection_refs =
      Connection
      |> where([connection], connection.workspace_id == ^workspace_id)
      |> select([connection], {connection.extension_id, connection.component_id})
      |> Repo.all()

    route_refs =
      Route
      |> join(:inner, [route], revision in RouteRevision,
        on: revision.id == route.current_revision_id
      )
      |> where([route], route.workspace_id == ^workspace_id)
      |> select([_route, revision], {
        revision.source_extension_id,
        revision.source_component_id,
        revision.target_extension_id,
        revision.target_component_id
      })
      |> Repo.all()
      |> Enum.flat_map(fn {source_extension, source_component, target_extension, target_component} ->
        [{source_extension, source_component}, {target_extension, target_component}]
      end)

    (connection_refs ++ route_refs)
    |> Enum.reject(fn {extension_id, component_id} ->
      not is_binary(extension_id) or not is_binary(component_id)
    end)
    |> Enum.uniq()
  end

  defp active_route_components do
    Route
    |> join(:inner, [route], revision in RouteRevision,
      on: revision.id == route.current_revision_id
    )
    |> where([route], route.enabled)
    |> select([_route, revision], {
      revision.source_extension_id,
      revision.source_component_id,
      revision.target_extension_id,
      revision.target_component_id
    })
    |> Repo.all()
    |> Enum.flat_map(fn {source_extension, source_component, target_extension, target_component} ->
      [{source_extension, source_component}, {target_extension, target_component}]
    end)
  end

  defp unfinished_artifact_errors do
    Run
    |> where([run], run.status in ^@unfinished_run_statuses)
    |> select([run], {run.id, run.source_artifact, run.target_artifact})
    |> Repo.all()
    |> Enum.flat_map(fn {run_id, source_artifact, target_artifact} ->
      [{:source, source_artifact}, {:target, target_artifact}]
      |> Enum.flat_map(fn {capability, artifact} ->
        case Gateway.validate_artifact(artifact, capability) do
          {:ok, _reference} -> []
          {:error, _error} -> ["Run #{run_id} requires an unavailable #{capability} artifact"]
        end
      end)
    end)
  end

  defp count_connections(extension_id, workspace_id, enabled_only) do
    Connection
    |> maybe_workspace(:connection, workspace_id)
    |> where([connection], connection.extension_id == ^extension_id)
    |> maybe_enabled(:connection, enabled_only)
    |> Repo.aggregate(:count, :id)
  end

  defp count_routes(extension_id, workspace_id, enabled_only) do
    Route
    |> join(:inner, [route], revision in RouteRevision,
      on: revision.id == route.current_revision_id
    )
    |> maybe_workspace(:route, workspace_id)
    |> where(
      [_route, revision],
      revision.source_extension_id == ^extension_id or
        revision.target_extension_id == ^extension_id
    )
    |> maybe_enabled(:route, enabled_only)
    |> Repo.aggregate(:count, :id)
  end

  defp count_unfinished_runs(extension_id, workspace_id) do
    Run
    |> join(:inner, [run], route in Route, on: route.id == run.route_id)
    |> maybe_workspace(:run, workspace_id)
    |> where([run], run.status in ^@unfinished_run_statuses)
    |> where(
      [run],
      fragment("?->>'extension_id' = ?", run.source_artifact, ^extension_id) or
        fragment("?->>'extension_id' = ?", run.target_artifact, ^extension_id) or
        fragment(
          "EXISTS (SELECT 1 FROM unnest(?) AS artifact WHERE artifact->>'extension_id' = ?)",
          run.processor_artifacts,
          ^extension_id
        )
    )
    |> Repo.aggregate(:count, :id)
  end

  defp maybe_workspace(query, _binding, nil), do: query

  defp maybe_workspace(query, :connection, workspace_id),
    do: where(query, [connection], connection.workspace_id == ^workspace_id)

  defp maybe_workspace(query, :route, workspace_id),
    do: where(query, [route, _revision], route.workspace_id == ^workspace_id)

  defp maybe_workspace(query, :run, workspace_id),
    do: where(query, [_run, route], route.workspace_id == ^workspace_id)

  defp maybe_enabled(query, _binding, false), do: query
  defp maybe_enabled(query, :connection, true), do: where(query, [connection], connection.enabled)
  defp maybe_enabled(query, :route, true), do: where(query, [route, _revision], route.enabled)
end

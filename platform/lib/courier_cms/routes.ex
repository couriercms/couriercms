defmodule CourierCMS.Routes do
  @moduledoc "The boundary for one-way Routes and immutable executable revisions."

  import Ecto.Query

  alias CourierCMS.Accounts
  alias CourierCMS.Accounts.Scope
  alias CourierCMS.Adapters.Definition
  alias CourierCMS.ExtensionSDK.AdapterError
  alias CourierCMS.Execution.{Checkpoint, Run}
  alias CourierCMS.Extensions.Gateway
  alias CourierCMS.Connections.Connection
  alias CourierCMS.Destinations.Destination
  alias CourierCMS.Mapping
  alias CourierCMS.Repo
  alias CourierCMS.Routes.{Route, RouteRevision}

  @polling_modes ["incremental", "full"]
  @reconciliation_intervals [1_440, 10_080, 43_200]

  def default_mapping(adapter_key), do: Definition.default_mapping(adapter_key)
  def default_projections(adapter_key), do: Definition.default_projections(adapter_key)

  def list_routes(%Scope{} = scope) do
    Route
    |> where([route], route.workspace_id == ^scope.workspace.id)
    |> order_by([route], asc: route.name)
    |> preload([:source_connection, :target_connection, :current_destination, :current_revision])
    |> Repo.all()
  end

  def get_route!(%Scope{} = scope, id) do
    Route
    |> Repo.get_by!(id: id, workspace_id: scope.workspace.id)
    |> Repo.preload([
      :source_connection,
      :target_connection,
      :current_destination,
      :current_revision
    ])
  end

  def change_route(%Scope{}, %Route{} = route, attrs \\ %{}), do: Route.changeset(route, attrs)

  def create_route(%Scope{} = scope, attrs, revision_attrs) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin]) do
      do_create_route(scope.workspace.id, attrs, revision_attrs)
    end
  end

  def update_route(%Scope{} = scope, %Route{} = route, attrs) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin]),
         true <- route.workspace_id == scope.workspace.id do
      route
      |> Route.changeset(Map.take(attrs, [:name, :enabled, "name", "enabled"]))
      |> Repo.update()
      |> case do
        {:ok, updated} ->
          {:ok,
           Repo.preload(
             updated,
             [:source_connection, :target_connection, :current_destination, :current_revision],
             force: true
           )}

        error ->
          error
      end
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  def update_selection(%Scope{} = scope, %Route{} = route, selection) when is_map(selection) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin]),
         true <- route.workspace_id == scope.workspace.id do
      route = Repo.preload(route, [:source_connection, :current_revision])
      current = route.current_revision

      with {:ok, selection} <-
             Definition.cast_selection(route.source_connection.adapter_key, selection) do
        values = revision_values(route, current, selection: selection)
        insert_revision(route, values)
      end
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  def update_mapping(%Scope{} = scope, %Route{} = route, mapping) when is_map(mapping) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin]),
         true <- route.workspace_id == scope.workspace.id,
         :ok <- Mapping.validate(mapping) do
      route = Repo.preload(route, :current_revision)
      current = route.current_revision

      values =
        revision_values(route, current,
          mapping: mapping,
          contract_version: current.contract_version + 1
        )

      insert_revision(route, values)
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  def update_mapping(%Scope{}, %Route{}, _mapping),
    do: {:error, "Mapping configuration is invalid."}

  def update_schedule(%Scope{} = scope, %Route{} = route, enabled, interval_minutes)
      when is_boolean(enabled) and interval_minutes in [5, 15, 30, 60, 360, 1_440] do
    update_schedule(scope, route, enabled, interval_minutes, "incremental", 1_440)
  end

  def update_schedule(%Scope{}, %Route{}, _enabled, _interval_minutes),
    do: {:error, :invalid_schedule}

  def update_schedule(
        %Scope{} = scope,
        %Route{} = route,
        enabled,
        interval_minutes,
        polling_mode,
        reconciliation_interval_minutes
      )
      when is_boolean(enabled) and interval_minutes in [5, 15, 30, 60, 360, 1_440] and
             polling_mode in @polling_modes and
             reconciliation_interval_minutes in @reconciliation_intervals do
    with :ok <- Accounts.authorize(scope, [:owner, :admin]),
         true <- route.workspace_id == scope.workspace.id do
      route = Repo.preload(route, :current_revision)
      current = route.current_revision

      trigger_settings =
        Map.put(current.trigger_settings, "schedule", %{
          "enabled" => enabled,
          "interval_minutes" => interval_minutes,
          "polling_mode" => polling_mode,
          "reconciliation_interval_minutes" => reconciliation_interval_minutes
        })

      values = %{
        route_id: route.id,
        revision_number: current.revision_number + 1,
        source_extension_id: current.source_extension_id,
        source_component_id: current.source_component_id,
        target_extension_id: current.target_extension_id,
        target_component_id: current.target_component_id,
        selection: current.selection,
        aggregation_rules: current.aggregation_rules,
        mapping: current.mapping,
        projections: current.projections,
        delivery_name_path: current.delivery_name_path,
        delivery_contract: current.delivery_contract,
        contract_version: current.contract_version,
        transformations: current.transformations,
        trigger_settings: trigger_settings
      }

      attrs = Map.put(values, :checksum, checksum(values))

      Repo.transaction(fn ->
        with {:ok, revision} <-
               %RouteRevision{} |> RouteRevision.changeset(attrs) |> Repo.insert(),
             {:ok, route} <-
               route
               |> Ecto.Changeset.change(current_revision_id: revision.id)
               |> Repo.update() do
          Repo.preload(route, [:source_connection, :target_connection, :current_revision],
            force: true
          )
        else
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  def update_schedule(%Scope{}, %Route{}, _enabled, _interval, _mode, _reconciliation),
    do: {:error, :invalid_schedule}

  def update_projections(%Scope{} = scope, %Route{} = route, projections)
      when is_list(projections) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin]),
         true <- route.workspace_id == scope.workspace.id do
      route = Repo.preload(route, [:target_connection, :current_revision])
      current = route.current_revision

      with :ok <- validate_target_projections(route.target_connection, projections) do
        values = %{
          route_id: route.id,
          revision_number: current.revision_number + 1,
          source_extension_id: current.source_extension_id,
          source_component_id: current.source_component_id,
          target_extension_id: current.target_extension_id,
          target_component_id: current.target_component_id,
          selection: current.selection,
          aggregation_rules: current.aggregation_rules,
          mapping: current.mapping,
          projections: projections,
          delivery_name_path: current.delivery_name_path,
          delivery_contract: current.delivery_contract,
          contract_version: current.contract_version + 1,
          transformations: current.transformations,
          trigger_settings: current.trigger_settings
        }

        attrs = Map.put(values, :checksum, checksum(values))

        Repo.transaction(fn ->
          with {:ok, revision} <-
                 %RouteRevision{} |> RouteRevision.changeset(attrs) |> Repo.insert(),
               {:ok, route} <-
                 route
                 |> Ecto.Changeset.change(current_revision_id: revision.id)
                 |> Repo.update() do
            Repo.preload(route, [:source_connection, :target_connection, :current_revision],
              force: true
            )
          else
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)
      end
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  def update_projections(%Scope{}, %Route{}, _projections),
    do: {:error, AdapterError.new(:mapping_failed, "Projection configuration is invalid")}

  @doc false
  def create_seed_route(workspace_id, attrs, revision_attrs) do
    do_create_route(workspace_id, attrs, revision_attrs)
  end

  defp do_create_route(workspace_id, attrs, revision_attrs) do
    attrs = put_workspace(attrs, workspace_id)

    projections =
      Map.get(revision_attrs, :projections, Map.get(revision_attrs, "projections", []))

    target_connection_id =
      Map.get(attrs, :target_connection_id, Map.get(attrs, "target_connection_id"))

    source_connection_id =
      Map.get(attrs, :source_connection_id, Map.get(attrs, "source_connection_id"))

    destination_id =
      Map.get(attrs, :current_destination_id, Map.get(attrs, "current_destination_id"))

    selection = Map.get(revision_attrs, :selection, Map.get(revision_attrs, "selection", %{}))
    mapping = Map.get(revision_attrs, :mapping, Map.get(revision_attrs, "mapping"))

    with {:ok, source_connection_id} <- cast_binary_id(source_connection_id),
         {:ok, target_connection_id} <- cast_binary_id(target_connection_id),
         {:ok, destination_id} <- cast_binary_id(destination_id),
         %Connection{} = source <-
           Repo.get_by(Connection, id: source_connection_id, workspace_id: workspace_id),
         %Connection{} = target <-
           Repo.get_by(Connection, id: target_connection_id, workspace_id: workspace_id),
         %Destination{} = destination <-
           Repo.get_by(Destination, id: destination_id, workspace_id: workspace_id),
         true <- destination.target_connection_id == target.id,
         {:ok, _source_adapter} <- fetch_source(component_reference(source)),
         {:ok, _target_adapter} <- fetch_target(component_reference(target)),
         {:ok, selection} <- Definition.cast_selection(source.adapter_key, selection),
         mapping <- mapping || Definition.default_mapping(source.adapter_key),
         :ok <- Mapping.validate(mapping),
         :ok <- validate_target_projections(target, projections) do
      Repo.transaction(fn ->
        destination =
          Destination
          |> where([current], current.id == ^destination.id)
          |> lock("FOR UPDATE")
          |> Repo.one!()

        unless destination.lifecycle_status == :available and
                 destination.validation_status == :valid and
                 is_nil(destination.owner_route_id) do
          Repo.rollback(:destination_unavailable)
        end

        with {:ok, route} <- %Route{} |> Route.changeset(attrs) |> Repo.insert(),
             {:ok, _destination} <-
               destination
               |> Destination.changeset(%{
                 lifecycle_status: :reserved,
                 owner_route_id: route.id
               })
               |> Repo.update(),
             revision_attrs <-
               revision_attributes(
                 route,
                 revision_attrs,
                 source,
                 target,
                 selection,
                 mapping
               ),
             {:ok, revision} <-
               %RouteRevision{} |> RouteRevision.changeset(revision_attrs) |> Repo.insert(),
             {:ok, route} <-
               route |> Ecto.Changeset.change(current_revision_id: revision.id) |> Repo.update() do
          Repo.preload(
            route,
            [:source_connection, :target_connection, :current_destination, :current_revision],
            force: true
          )
        else
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    else
      nil ->
        {:error, AdapterError.new(:unsupported, "A Connection or Destination was not found")}

      false ->
        {:error, :destination_connection_mismatch}

      :error ->
        {:error, AdapterError.new(:unsupported, "Adapter is not registered")}

      {:error, :invalid_binary_id} ->
        {:error, AdapterError.new(:invalid_content, "Choose valid Connections and a Destination")}

      error ->
        error
    end
  end

  defp revision_attributes(
         route,
         attrs,
         source,
         target,
         selection,
         mapping
       ) do
    values = %{
      route_id: route.id,
      revision_number: 1,
      source_extension_id: source.extension_id,
      source_component_id: source.component_id,
      target_extension_id: target.extension_id,
      target_component_id: target.component_id,
      selection: selection,
      aggregation_rules:
        Map.get(
          attrs,
          :aggregation_rules,
          Definition.default_aggregation_rules(source.adapter_key)
        ),
      mapping: mapping,
      projections: Map.get(attrs, :projections, Map.get(attrs, "projections", [])),
      delivery_name_path:
        Map.get(attrs, :delivery_name_path, Map.get(attrs, "delivery_name_path", "payload.title")),
      delivery_contract:
        Map.get(
          attrs,
          :delivery_contract,
          Definition.default_delivery_contract(source.adapter_key)
        ),
      contract_version: 1,
      transformations: [],
      trigger_settings: %{"manual" => true}
    }

    Map.put(values, :checksum, checksum(values))
  end

  defp revision_values(route, current, overrides) do
    %{
      route_id: route.id,
      revision_number: current.revision_number + 1,
      source_extension_id: current.source_extension_id,
      source_component_id: current.source_component_id,
      target_extension_id: current.target_extension_id,
      target_component_id: current.target_component_id,
      selection: Keyword.get(overrides, :selection, current.selection),
      aggregation_rules: Keyword.get(overrides, :aggregation_rules, current.aggregation_rules),
      mapping: Keyword.get(overrides, :mapping, current.mapping),
      projections: Keyword.get(overrides, :projections, current.projections),
      delivery_name_path: Keyword.get(overrides, :delivery_name_path, current.delivery_name_path),
      delivery_contract: Keyword.get(overrides, :delivery_contract, current.delivery_contract),
      contract_version: Keyword.get(overrides, :contract_version, current.contract_version),
      transformations: Keyword.get(overrides, :transformations, current.transformations),
      trigger_settings: Keyword.get(overrides, :trigger_settings, current.trigger_settings)
    }
  end

  defp insert_revision(route, values) do
    attrs = Map.put(values, :checksum, checksum(values))

    Repo.transaction(fn ->
      with {:ok, revision} <-
             %RouteRevision{} |> RouteRevision.changeset(attrs) |> Repo.insert(),
           {:ok, route} <-
             route
             |> Ecto.Changeset.change(current_revision_id: revision.id)
             |> Repo.update() do
        Repo.preload(
          route,
          [:source_connection, :target_connection, :current_destination, :current_revision],
          force: true
        )
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp validate_target_projections(connection, projections) do
    case Gateway.target(component_reference(connection), :validate_projections, [
           connection,
           projections
         ]) do
      :error -> {:error, AdapterError.new(:unsupported, "Target Adapter is not registered")}
      result -> result
    end
  end

  def update_delivery_name_path(%Scope{} = scope, %Route{} = route, path)
      when is_binary(path) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin]),
         true <- route.workspace_id == scope.workspace.id,
         true <- String.trim(path) != "" do
      route = Repo.preload(route, :current_revision)

      route
      |> revision_values(route.current_revision, delivery_name_path: String.trim(path))
      |> then(&insert_revision(route, &1))
    else
      false -> {:error, :invalid_delivery_name_path}
      error -> error
    end
  end

  def move_destination(%Scope{} = scope, %Route{} = route, destination_id) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin]),
         true <- route.workspace_id == scope.workspace.id,
         {:ok, destination_id} <- cast_binary_id(destination_id) do
      result =
        Repo.transaction(fn ->
          route =
            Route
            |> where([current], current.id == ^route.id)
            |> lock("FOR UPDATE")
            |> Repo.one!()
            |> Repo.preload(:current_destination)

          if route.current_destination_id == destination_id do
            route
          else
            active_run? =
              Repo.exists?(
                from run in Run,
                  where:
                    run.route_id == ^route.id and
                      run.status in [:queued, :planning, :running]
              )

            if active_run?, do: Repo.rollback(:route_has_active_run)

            destination =
              Destination
              |> where([current], current.id == ^destination_id)
              |> lock("FOR UPDATE")
              |> Repo.one()

            unless destination && destination.workspace_id == route.workspace_id &&
                     destination.target_connection_id == route.target_connection_id &&
                     destination.lifecycle_status == :available &&
                     destination.validation_status == :valid &&
                     is_nil(destination.owner_route_id) do
              Repo.rollback(:destination_unavailable)
            end

            old = route.current_destination

            old_attrs =
              if old.lifecycle_status == :active or old.first_delivered_at do
                %{
                  lifecycle_status: :retired,
                  retired_at: DateTime.utc_now()
                }
              else
                %{
                  lifecycle_status: :available,
                  owner_route_id: nil
                }
              end

            old |> Destination.changeset(old_attrs) |> Repo.update!()

            destination
            |> Destination.changeset(%{
              lifecycle_status: :reserved,
              owner_route_id: route.id
            })
            |> Repo.update!()

            updated =
              route
              |> Route.changeset(%{current_destination_id: destination.id})
              |> Repo.update!()

            Repo.delete_all(
              from checkpoint in Checkpoint, where: checkpoint.route_id == ^route.id
            )

            updated
          end
        end)

      case result do
        {:ok, updated} ->
          {:ok,
           Repo.preload(
             updated,
             [
               :source_connection,
               :target_connection,
               :current_destination,
               :current_revision
             ],
             force: true
           )}

        error ->
          error
      end
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  def archive_route(%Scope{} = scope, %Route{} = route) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin]),
         true <- route.workspace_id == scope.workspace.id do
      result =
        Repo.transaction(fn ->
          route =
            Route
            |> where([current], current.id == ^route.id)
            |> lock("FOR UPDATE")
            |> Repo.one!()
            |> Repo.preload(:current_destination)

          active_run? =
            Repo.exists?(
              from run in Run,
                where:
                  run.route_id == ^route.id and
                    run.status in [:queued, :planning, :running]
            )

          if active_run?, do: Repo.rollback(:route_has_active_run)

          now = DateTime.utc_now()
          destination = route.current_destination

          destination_attrs =
            if destination.lifecycle_status == :active or destination.first_delivered_at do
              %{lifecycle_status: :retired, retired_at: now}
            else
              %{lifecycle_status: :available, owner_route_id: nil}
            end

          destination |> Destination.changeset(destination_attrs) |> Repo.update!()

          route
          |> Route.changeset(%{enabled: false, archived_at: now})
          |> Repo.update!()
        end)

      case result do
        {:ok, archived} ->
          {:ok,
           Repo.preload(
             archived,
             [:source_connection, :target_connection, :current_destination, :current_revision],
             force: true
           )}

        error ->
          error
      end
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  defp fetch_source(adapter_key) do
    if Gateway.source_available?(adapter_key), do: {:ok, adapter_key}, else: :error
  end

  defp fetch_target(adapter_key) do
    if Gateway.target_available?(adapter_key), do: {:ok, adapter_key}, else: :error
  end

  defp component_reference(connection) do
    %{extension_id: connection.extension_id, component_id: connection.component_id}
  end

  defp checksum(values) do
    values
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp put_workspace(attrs, workspace_id) do
    if Enum.all?(Map.keys(attrs), &is_atom/1),
      do: Map.put(attrs, :workspace_id, workspace_id),
      else: Map.put(attrs, "workspace_id", workspace_id)
  end

  defp cast_binary_id(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :invalid_binary_id}
    end
  end
end

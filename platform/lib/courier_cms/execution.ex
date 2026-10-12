defmodule CourierCMS.Execution do
  @moduledoc "Plans and executes durable, observable Route Runs."

  import Ecto.Query

  alias CourierCMS.Accounts
  alias CourierCMS.Accounts.Scope
  alias CourierCMS.Assets
  alias CourierCMS.Assets.{DeliveryAsset, DeliveryAssetBinding, RunAsset, Transfer}

  alias CourierCMS.ExtensionSDK.{
    AdapterError,
    AssetContent,
    AssetDescriptor,
    ContentBundle,
    DeliveryEnvelope,
    SourceIdentity
  }

  alias CourierCMS.Extensions.Gateway

  alias CourierCMS.Execution.{
    Checkpoint,
    ConnectionLimiter,
    DeliveryLock,
    DeliveryWorker,
    AssetWorker,
    JobArgs,
    PlanRunWorker,
    ProcessorExecution,
    Retry,
    Run,
    RunItem
  }

  alias CourierCMS.Installation
  alias CourierCMS.Mapping
  alias CourierCMS.Processors
  alias CourierCMS.Transformations
  alias CourierCMS.Destinations.Destination
  alias CourierCMS.Ownership.{DeliveryBinding, RouteItem}
  alias CourierCMS.Repo
  alias CourierCMS.Storage
  alias CourierCMS.Routes.Route
  alias CourierCMS.Transport.{CanonicalDeliveryDocument, DeliveryName, Projection}
  alias CourierCMS.Workspaces

  @checkpoint_overlap_seconds 120
  @run_item_page_size 50
  @processor_execution_page_limit 500
  @run_item_statuses [:pending, :processing, :succeeded, :retrying, :failed, :skipped, :cancelled]
  @run_asset_page_size 50
  @run_asset_statuses [
    :pending,
    :processing,
    :succeeded,
    :retrying,
    :failed,
    :skipped,
    :cancelled
  ]
  @resolved_asset_references_key "couriercms_resolved_asset_references"

  def list_runs(%Scope{} = scope, limit \\ 50) do
    Run
    |> join(:inner, [run], route in assoc(run, :route))
    |> where([_run, route], route.workspace_id == ^scope.workspace.id)
    |> order_by([run], desc: run.inserted_at)
    |> limit(^limit)
    |> preload(:route)
    |> Repo.all()
  end

  @doc "Returns the most recently delivered target bindings for the current workspace."
  def list_delivery_items(%Scope{} = scope, limit \\ 100) do
    DeliveryBinding
    |> join(:inner, [binding], item in assoc(binding, :route_item))
    |> join(:inner, [_binding, item], route in assoc(item, :route))
    |> where([_binding, _item, route], route.workspace_id == ^scope.workspace.id)
    |> order_by([binding], desc: binding.last_delivered_at, desc: binding.updated_at)
    |> limit(^min(max(limit, 1), 100))
    |> preload([binding, item, route], route_item: {item, route: route}, destination: [])
    |> Repo.all()
  end

  def list_route_runs(%Scope{} = scope, route_id, opts \\ []) do
    page = opts |> Keyword.get(:page, 1) |> max(1)
    page_size = opts |> Keyword.get(:page_size, 20) |> min(100) |> max(1)

    query =
      Run
      |> join(:inner, [run], route in assoc(run, :route))
      |> where(
        [run, route],
        run.route_id == ^route_id and route.workspace_id == ^scope.workspace.id
      )

    total_count = Repo.aggregate(query, :count, :id)
    total_pages = max(Integer.ceil_div(total_count, page_size), 1)
    page = min(page, total_pages)

    items =
      query
      |> order_by([run], desc: run.inserted_at)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> preload(:route)
      |> Repo.all()

    %{
      items: items,
      page: page,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  def get_run!(%Scope{} = scope, id) do
    Run
    |> join(:inner, [run], route in assoc(run, :route))
    |> where([run, route], run.id == ^id and route.workspace_id == ^scope.workspace.id)
    |> select([run, _route], run)
    |> Repo.one!()
    |> Repo.preload([
      :route_revision,
      :destination,
      route: [:source_connection, :target_connection]
    ])
  end

  @doc """
  Returns one bounded page of Run Items for an operator who explicitly opens
  the item list. Run summary queries never preload this collection.
  """
  def list_run_items(%Scope{} = scope, run_id, opts \\ []) do
    page = opts |> Keyword.get(:page, 1) |> max(1)
    page_size = opts |> Keyword.get(:page_size, @run_item_page_size) |> min(100) |> max(1)
    status = Keyword.get(opts, :status)
    source_query = opts |> Keyword.get(:source_query, "") |> String.trim()

    query =
      RunItem
      |> join(:inner, [item], run in assoc(item, :run))
      |> join(:inner, [_item, run], route in assoc(run, :route))
      |> where(
        [item, _run, route],
        item.run_id == ^run_id and route.workspace_id == ^scope.workspace.id
      )
      |> maybe_filter_run_item_status(status)
      |> maybe_filter_run_item_source(source_query)

    total_count = Repo.aggregate(query, :count, :id)
    total_pages = max(Integer.ceil_div(total_count, page_size), 1)
    page = min(page, total_pages)

    items =
      query
      |> order_by([item], asc: item.inserted_at, asc: item.id)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> Repo.all()
      |> load_processor_executions()

    %{
      items: items,
      page: page,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  defp maybe_filter_run_item_status(query, status) when status in @run_item_statuses,
    do: where(query, [item], item.status == ^status)

  defp maybe_filter_run_item_status(query, _status), do: query

  defp maybe_filter_run_item_source(query, ""), do: query

  defp maybe_filter_run_item_source(query, source_query) do
    pattern = "%#{source_query}%"

    if CourierCMS.ReleaseProfile.local?() do
      where(query, [item], fragment("lower(?) LIKE lower(?)", item.source_item_key, ^pattern))
    else
      where(query, [item], ilike(item.source_item_key, ^pattern))
    end
  end

  defp load_processor_executions([]), do: []

  defp load_processor_executions(items) do
    item_ids = Enum.map(items, & &1.id)

    executions_by_item =
      ProcessorExecution
      |> where([execution], execution.run_item_id in ^item_ids)
      |> order_by([execution],
        desc: execution.attempt,
        desc: execution.position,
        desc: execution.inserted_at
      )
      |> limit(^@processor_execution_page_limit)
      |> Repo.all()
      |> Enum.group_by(& &1.run_item_id)

    Enum.map(items, fn item ->
      executions =
        executions_by_item
        |> Map.get(item.id, [])
        |> Enum.sort_by(&{&1.attempt, &1.position, &1.inserted_at}, :asc)

      %{item | processor_executions: executions}
    end)
  end

  @doc "Returns one bounded, workspace-scoped page of Delivery Assets for a Run."
  def list_run_assets(%Scope{} = scope, run_id, opts \\ []) do
    page = opts |> Keyword.get(:page, 1) |> max(1)
    page_size = opts |> Keyword.get(:page_size, @run_asset_page_size) |> min(100) |> max(1)
    status = Keyword.get(opts, :status)
    source_query = opts |> Keyword.get(:source_query, "") |> String.trim()

    query =
      RunAsset
      |> join(:inner, [asset], run in assoc(asset, :run))
      |> join(:inner, [_asset, run], route in assoc(run, :route))
      |> join(:inner, [asset, _run, _route], delivery_asset in assoc(asset, :delivery_asset))
      |> join(:left, [asset, run, _route, delivery_asset], binding in DeliveryAssetBinding,
        on:
          binding.delivery_asset_id == delivery_asset.id and
            binding.destination_id == run.destination_id
      )
      |> where(
        [asset, _run, route, _delivery_asset, _binding],
        asset.run_id == ^run_id and route.workspace_id == ^scope.workspace.id
      )
      |> maybe_filter_run_asset_status(status)
      |> maybe_filter_run_asset_source(source_query)

    total_count = Repo.aggregate(query, :count, :id)
    total_pages = max(Integer.ceil_div(total_count, page_size), 1)
    page = min(page, total_pages)

    items =
      query
      |> order_by([asset], asc: asset.inserted_at, asc: asset.id)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> select([asset, _run, _route, delivery_asset, binding], %{
        run_asset: asset,
        delivery_asset: delivery_asset,
        binding: binding
      })
      |> Repo.all()

    %{
      items: items,
      page: page,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  defp maybe_filter_run_asset_status(query, status) when status in @run_asset_statuses,
    do: where(query, [asset], asset.status == ^status)

  defp maybe_filter_run_asset_status(query, _status), do: query

  defp maybe_filter_run_asset_source(query, ""), do: query

  defp maybe_filter_run_asset_source(query, source_query) do
    pattern = "%#{source_query}%"

    if CourierCMS.ReleaseProfile.local?() do
      where(
        query,
        [_asset, _run, _route, delivery_asset],
        fragment("lower(?) LIKE lower(?)", delivery_asset.source_asset_key, ^pattern) or
          fragment("lower(?) LIKE lower(?)", delivery_asset.filename, ^pattern)
      )
    else
      where(
        query,
        [_asset, _run, _route, delivery_asset],
        ilike(delivery_asset.source_asset_key, ^pattern) or
          ilike(delivery_asset.filename, ^pattern)
      )
    end
  end

  def preview_route(%Scope{} = scope, route_id, opts \\ []) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin]),
         %Route{} = route <-
           Route
           |> Repo.get_by(id: route_id, workspace_id: scope.workspace.id)
           |> Repo.preload([
             :current_revision,
             :current_destination,
             :source_connection,
             :target_connection
           ]),
         source_reference <- revision_source_reference(route.current_revision),
         target_reference <- revision_target_reference(route.current_revision),
         {:ok, source} <- fetch_source(source_reference),
         {:ok, target} <- fetch_target(target_reference),
         :ok <-
           Gateway.target(target, :validate_projections, [
             route.target_connection,
             route.current_revision.projections
           ]),
         {:ok, %{items: [identity | _items]}} <-
           Gateway.source(source, :enumerate, [
             route.source_connection,
             Keyword.get(opts, :selection, route.current_revision.selection),
             nil
           ]),
         {:ok, bundle} <-
           Gateway.source(source, :read_root, [
             route.source_connection,
             identity,
             route.current_revision.aggregation_rules
           ]),
         :ok <- CourierCMS.Transport.ContentBundleValidator.validate(bundle),
         {:ok, payload} <-
           Mapping.apply(bundle, Keyword.get(opts, :mapping, route.current_revision.mapping)),
         {:ok, payload} <-
           Transformations.apply(
             payload,
             Keyword.get(opts, :transformations, route.current_revision.transformations)
           ),
         {:ok, payload} <-
           Processors.apply(
             payload,
             Keyword.get(opts, :processors, route.current_revision.processors)
           ) do
      asset_references = asset_references(bundle, route.id)

      hash =
        content_hash(
          bundle.root.identity,
          route.current_revision.contract_version,
          payload,
          asset_references
        )

      envelope = %DeliveryEnvelope{
        installation_id: Installation.id(),
        route_id: route.id,
        destination_id: route.current_destination_id,
        route_revision: route.current_revision.revision_number,
        delivery_key: "preview",
        source_connection_id: route.source_connection_id,
        source_identity: bundle.root.identity,
        source_type: bundle.root.source_type,
        contract_version: route.current_revision.contract_version,
        delivered_at: DateTime.utc_now(),
        content_hash: hash
      }

      canonical_document = CanonicalDeliveryDocument.build(envelope, payload, asset_references)

      delivery_name =
        DeliveryName.resolve(
          canonical_document,
          route.current_revision.delivery_name_path,
          bundle.root.identity.item_key,
          envelope.delivery_key
        )

      with {:ok, projections} <-
             Projection.project(canonical_document, route.current_revision.projections) do
        {:ok,
         %{
           canonical_document: canonical_document,
           delivery_name: delivery_name,
           projections: projections
         }}
      end
    else
      nil -> {:error, :not_found}
      {:ok, %{items: []}} -> {:error, :no_matching_content}
      error -> error
    end
  end

  def start_manual_run(%Scope{} = scope, route_id, opts \\ []) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin, :operator]) do
      route =
        Route
        |> Repo.get_by!(id: route_id, workspace_id: scope.workspace.id)
        |> Repo.preload([
          :current_revision,
          :current_destination,
          :source_connection,
          :target_connection
        ])

      delivery_mode = if Keyword.get(opts, :force_redelivery, false), do: "force", else: "normal"

      with true <- route_deliverable?(route),
           {:ok, artifacts} <- run_artifact_attributes(route.current_revision) do
        Ecto.Multi.new()
        |> Ecto.Multi.insert(
          :run,
          Run.changeset(
            %Run{},
            Map.merge(artifacts, %{
              route_id: route.id,
              route_revision_id: route.current_revision_id,
              destination_id: route.current_destination_id,
              trigger_kind: :manual,
              trigger_metadata: %{
                "initiated_by" => scope.user.id,
                "delivery_mode" => delivery_mode
              },
              initiated_by_user_id: scope.user.id,
              status: :queued
            })
          )
        )
        |> Oban.insert(:job, fn %{run: run} ->
          PlanRunWorker.new(JobArgs.put(%{"run_id" => run.id}),
            max_attempts: Application.fetch_env!(:couriercms, :planning_max_attempts)
          )
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{run: run}} ->
            Workspaces.audit(scope, "run.started", "run", run.id, %{
              "route_id" => route.id,
              "delivery_mode" => delivery_mode
            })

            broadcast(run.id)
            {:ok, run}

          {:error, _step, reason, _changes} ->
            {:error, reason}
        end
      else
        false -> {:error, :route_not_active}
        error -> error
      end
    end
  end

  def start_scheduled_run(%Route{} = route, now \\ DateTime.utc_now()) do
    route = Repo.preload(route, :current_destination)

    if route_deliverable?(route) do
      Repo.transaction(fn ->
        locked_route =
          Route
          |> where([current], current.id == ^route.id)
          |> Storage.lock_for_update()
          |> Repo.one!()
          |> Repo.preload([
            :current_revision,
            :current_destination,
            :source_connection,
            :target_connection
          ])

        last_run = latest_scheduled_run(locked_route.id)
        active_run = active_scheduled_run(locked_route.id)

        cond do
          active_run ->
            :telemetry.execute(
              [:couriercms, :schedule, :overlap_skipped],
              %{count: 1},
              %{route_id: locked_route.id}
            )

            active_run

          route_deliverable?(locked_route) &&
              schedule_due?(locked_route, now, last_run) ->
            schedule_key =
              "#{locked_route.current_revision_id}:after:#{(last_run && last_run.id) || "initial"}"

            case insert_triggered_run(
                   locked_route,
                   :schedule,
                   schedule_metadata(locked_route, now, schedule_key)
                 ) do
              {:ok, run} -> run
              {:error, reason} -> Repo.rollback(reason)
            end

          true ->
            last_run || Repo.rollback(:route_not_due)
        end
      end)
      |> case do
        {:ok, run} -> {:ok, run}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :route_not_active}
    end
  end

  def start_connector_runs(%CourierCMS.Connectors.ConnectorEvent{} = event) do
    routes =
      Route
      |> where(
        [route],
        route.source_connection_id == ^event.connection_id and route.enabled == true and
          not is_nil(route.current_revision_id)
      )
      |> preload([
        :current_revision,
        :current_destination,
        :source_connection,
        :target_connection
      ])
      |> Repo.all()
      |> Enum.filter(&route_deliverable?/1)

    base_metadata = %{
      "connector_event_id" => event.id,
      "connector_contract_version" => event.contract_version,
      "event_kind" => event.event_kind,
      "external_event_id" => event.external_event_id,
      "source_item_key" => event.source_item_key,
      "source_modified_at" =>
        event.source_modified_at && DateTime.to_iso8601(event.source_modified_at)
    }

    Enum.reduce_while(routes, {:ok, []}, fn route, {:ok, runs} ->
      metadata =
        if destination_baseline_required?(route) do
          base_metadata
          |> Map.put("source_item_key", nil)
          |> Map.put("retrieval_mode", "full")
          |> Map.put("retrieval_reason", "destination_changed")
        else
          base_metadata
        end

      case insert_triggered_run(route, :publish, metadata) do
        {:ok, run} -> {:cont, {:ok, [run | runs]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, runs} -> {:ok, Enum.reverse(runs)}
      error -> error
    end
  end

  def enqueue_due_schedules(now \\ DateTime.utc_now()) do
    due_routes =
      Route
      |> where([route], route.enabled == true and not is_nil(route.current_revision_id))
      |> preload([:current_revision, :current_destination, :source_connection])
      |> Repo.all()
      |> Enum.filter(&(route_deliverable?(&1) && schedule_due?(&1, now)))

    Enum.each(due_routes, &start_scheduled_run(&1, now))

    :telemetry.execute(
      [:couriercms, :schedule, :dispatch],
      %{routes_due: length(due_routes)},
      %{}
    )

    :ok
  end

  def next_scheduled_at(%Route{} = route, now \\ DateTime.utc_now()) do
    with interval when is_integer(interval) <- schedule_interval(route),
         %Run{} = last <- latest_scheduled_run(route.id) do
      DateTime.add(scheduled_at(last), interval * 60, :second)
    else
      nil -> if schedule_interval(route), do: now
      _other -> nil
    end
  end

  def plan_run(run_id, attempt \\ 1, max_attempts \\ 1) do
    run = load_execution_run!(run_id)

    if run.status == :cancelled,
      do: :ok,
      else: do_plan_run(run, attempt, max_attempts)
  end

  defp do_plan_run(run, attempt, max_attempts) do
    with {:ok, run} <- ensure_run_artifacts(run),
         {:ok, source, _target, _processors} <- execution_references(run) do
      run =
        update_run(run, %{
          status: :planning,
          started_at: run.started_at || DateTime.utc_now(),
          completed_at: nil,
          error_category: nil,
          error_summary: nil
        })

      broadcast(run.id)

      do_plan_with_source(run, source, attempt, max_attempts)
    else
      {:error, %AdapterError{} = error} ->
        fail_planning(run, error)
    end
  rescue
    exception ->
      error = AdapterError.new(:internal, Exception.message(exception), retryable: true)

      if attempt < max_attempts,
        do: retry_planning(run, error),
        else: fail_planning(run, error)
  end

  defp do_plan_with_source(run, source, attempt, max_attempts) do
    with {:ok, run} <- plan_discovery(source, run),
         {:ok, _run} <- finalize_planning(run) do
      reconcile_run(run.id)

      broadcast(run.id)
      :ok
    else
      {:error, :cancelled} ->
        :ok

      {:error, %AdapterError{retryable: true} = error} when attempt < max_attempts ->
        retry_planning(run, error)

      {:error, %AdapterError{} = error} ->
        fail_planning(run, error)

      {:error, reason} ->
        fail_planning(run, AdapterError.new(:internal, safe_reason(reason)))
    end
  end

  def process_run_item(run_item_id, attempt, max_attempts) do
    run_item = load_run_item!(run_item_id)

    if terminal_item?(run_item) do
      :ok
    else
      with {:ok, _run} <- ensure_run_artifacts(run_item.run),
           run_item <- load_run_item!(run_item_id),
           {:ok, source, target, processors} <- execution_references(run_item.run) do
        process_run_item_with_lock(run_item, source, target, processors, attempt, max_attempts)
      else
        {:error, %AdapterError{} = error} ->
          record_item_error(run_item, :failed, error)
          {:discard, error.message}
      end
    end
  end

  def process_run_asset(run_asset_id, attempt, max_attempts) do
    run_asset = load_run_asset!(run_asset_id)

    if terminal_asset?(run_asset) do
      :ok
    else
      with {:ok, _run} <- ensure_run_artifacts(run_asset.run),
           run_asset <- load_run_asset!(run_asset_id),
           {:ok, source, target, _processors} <- execution_references(run_asset.run) do
        process_run_asset_with_lock(run_asset, source, target, attempt, max_attempts)
      else
        {:error, %AdapterError{} = error} ->
          record_asset_error(run_asset, :failed, error)
          {:discard, error.message}
      end
    end
  end

  defp process_run_asset_with_lock(run_asset, source, target, attempt, max_attempts) do
    owner_token = Ecto.UUID.generate()
    ttl_ms = Application.fetch_env!(:couriercms, :delivery_lock_ttl_ms)
    lock_key = "asset:#{run_asset.run.destination_id}:#{run_asset.asset_key}"

    case DeliveryLock.acquire(lock_key, owner_token, ttl_ms) do
      :ok ->
        try do
          run_asset = load_run_asset!(run_asset.id)

          ConnectionLimiter.with_leases(
            [run_asset.run.route.source_connection, run_asset.run.route.target_connection],
            owner_token,
            ttl_ms,
            fn -> do_process_run_asset(run_asset, source, target, attempt, max_attempts) end
          )
        after
          DeliveryLock.release(lock_key, owner_token)
        end

      :busy ->
        :telemetry.execute([:couriercms, :asset_delivery, :lock_contention], %{count: 1}, %{})
        {:snooze, Retry.short_snooze()}
    end
  end

  defp do_process_run_asset(run_asset, source, target, attempt, max_attempts) do
    if terminal_asset?(run_asset) do
      :ok
    else
      run_asset =
        transition_run_asset(run_asset, %{
          status: :processing,
          attempt_count: attempt,
          started_at: run_asset.started_at || DateTime.utc_now(),
          error_category: nil,
          error_summary: nil
        })

      started_at = System.monotonic_time()
      result = deliver_asset(run_asset, source, target)
      emit_asset_delivery_duration(run_asset, result, started_at)

      case result do
        {:ok, operation, content_hash} ->
          complete_asset(run_asset, operation, content_hash, :succeeded)

        {:skip, content_hash} ->
          complete_asset(run_asset, "skip", content_hash, :skipped)

        {:error, %AdapterError{retryable: true, retry_after_ms: retry_after_ms} = error}
        when attempt < max_attempts and is_integer(retry_after_ms) ->
          record_asset_error(run_asset, :retrying, error)
          {:snooze, Retry.after_ms(retry_after_ms)}

        {:error, %AdapterError{retryable: true} = error} when attempt < max_attempts ->
          record_asset_error(run_asset, :retrying, error)
          {:error, error.message}

        {:error, %AdapterError{} = error} ->
          record_asset_error(run_asset, :failed, error)
          {:discard, error.message}
      end
    end
  rescue
    _exception ->
      error = AdapterError.new(:internal, "Delivery Asset processing failed")
      record_asset_error(run_asset, :failed, error)
      {:discard, error.message}
  end

  defp terminal_asset?(run_asset),
    do: run_asset.status in [:succeeded, :skipped, :failed, :cancelled]

  defp process_run_item_with_lock(run_item, source, target, processors, attempt, max_attempts) do
    owner_token = Ecto.UUID.generate()
    ttl_ms = Application.fetch_env!(:couriercms, :delivery_lock_ttl_ms)

    case DeliveryLock.acquire(run_item.delivery_key, owner_token, ttl_ms) do
      :ok ->
        try do
          run_item = load_run_item!(run_item.id)

          ConnectionLimiter.with_leases(
            [run_item.run.route.source_connection, run_item.run.route.target_connection],
            owner_token,
            ttl_ms,
            fn ->
              do_process_run_item(run_item, source, target, processors, attempt, max_attempts)
            end
          )
        after
          DeliveryLock.release(run_item.delivery_key, owner_token)
        end

      :busy ->
        :telemetry.execute([:couriercms, :delivery, :lock_contention], %{count: 1}, %{})
        {:snooze, Retry.short_snooze()}
    end
  end

  defp do_process_run_item(run_item, source, target, processors, attempt, max_attempts) do
    if terminal_item?(run_item) do
      :ok
    else
      delivery_attempt = max(run_item.attempt_count + 1, attempt)

      run_item =
        transition_run_item(run_item, %{
          status: :processing,
          attempt_count: delivery_attempt,
          started_at: run_item.started_at || DateTime.utc_now(),
          error_category: nil,
          error_summary: nil
        })

      broadcast(run_item.run_id)

      started_at = System.monotonic_time()
      result = deliver(run_item, source, target, processors, delivery_attempt)
      emit_delivery_duration(run_item, result, started_at)

      case result do
        {:ok, operation, route_item, content_hash} ->
          complete_item(run_item, route_item, operation, content_hash)

        {:skip, route_item, content_hash} ->
          complete_item(run_item, route_item, "skip", content_hash, :skipped)

        {:waiting_for_assets, delay} ->
          transition_run_item(run_item, %{status: :pending})
          broadcast(run_item.run_id)
          {:snooze, delay}

        {:error, %AdapterError{retryable: true, retry_after_ms: retry_after_ms} = error}
        when attempt < max_attempts and is_integer(retry_after_ms) ->
          record_item_error(run_item, :retrying, error)
          {:snooze, Retry.after_ms(retry_after_ms)}

        {:error, %AdapterError{retryable: true} = error} when attempt < max_attempts ->
          record_item_error(run_item, :retrying, error)
          {:error, error.message}

        {:error, %AdapterError{} = error} ->
          record_item_error(run_item, :failed, error)
          {:discard, error.message}
      end
    end
  rescue
    exception ->
      error = AdapterError.new(:internal, Exception.message(exception))
      record_item_error(run_item, :failed, error)
      {:discard, error.message}
  end

  defp emit_delivery_duration(run_item, result, started_at) do
    status =
      case result do
        {:ok, _operation, _route_item, _hash} -> :succeeded
        {:skip, _route_item, _hash} -> :skipped
        {:waiting_for_assets, _delay} -> :waiting_for_assets
        {:error, %AdapterError{retryable: true}} -> :retrying
        {:error, %AdapterError{}} -> :failed
      end

    :telemetry.execute(
      [:couriercms, :delivery, :duration],
      %{duration: System.monotonic_time() - started_at},
      %{adapter: run_item.run.route.target_connection.adapter_key, status: status}
    )
  end

  defp terminal_item?(run_item),
    do: run_item.status in [:succeeded, :skipped, :failed, :cancelled]

  def retry_run_item(%Scope{} = scope, run_item_id) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin, :operator]),
         %RunItem{} = run_item <- scoped_run_item(scope, run_item_id) do
      do_retry_run_item(scope, run_item)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def retry_run_asset(%Scope{} = scope, run_asset_id) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin, :operator]),
         %RunAsset{} = run_asset <- scoped_run_asset(scope, run_asset_id) do
      do_retry_run_asset(scope, run_asset)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def cancel_run(%Scope{} = scope, run_id) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin, :operator]),
         %Run{} = run <- scoped_run(scope, run_id) do
      do_cancel_run(scope, run)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp do_cancel_run(scope, run) do
    if run.status in [:queued, :planning, :running] do
      now = DateTime.utc_now()

      result =
        Repo.transaction(fn ->
          current_run =
            Run
            |> where([current], current.id == ^run.id)
            |> Storage.lock_for_update()
            |> Repo.one!()

          if current_run.status not in [:queued, :planning, :running] do
            Repo.rollback(:not_cancellable)
          end

          RunItem
          |> where(
            [item],
            item.run_id == ^run.id and item.status in [:pending, :retrying]
          )
          |> Repo.update_all(set: [status: :cancelled, completed_at: now, updated_at: now])

          RunAsset
          |> where(
            [asset],
            asset.run_id == ^run.id and asset.status in [:pending, :processing, :retrying]
          )
          |> Repo.update_all(set: [status: :cancelled, completed_at: now, updated_at: now])

          current_run
          |> Run.changeset(%{status: :cancelled, cancelled_at: now, completed_at: now})
          |> Repo.update!()
        end)

      case result do
        {:ok, cancelled_run} ->
          Workspaces.audit(scope, "run.cancelled", "run", run.id)
          broadcast(run.id)
          {:ok, cancelled_run}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :not_cancellable}
    end
  end

  defp do_retry_run_item(scope, run_item) do
    if run_item.status in [:failed, :retrying] do
      Repo.transaction(fn ->
        current =
          RunItem
          |> where([item], item.id == ^run_item.id)
          |> Storage.lock_for_update()
          |> Repo.one!()

        if current.status not in [:failed, :retrying], do: Repo.rollback(:not_retryable)

        reset_required_assets_for_item(current.id)

        current
        |> RunItem.changeset(%{
          status: :pending,
          error_category: nil,
          error_summary: nil,
          completed_at: nil
        })
        |> Repo.update!()

        insert_delivery_job!(current.id)
      end)
      |> case do
        {:ok, job} ->
          Workspaces.audit(scope, "run_item.retried", "run_item", run_item.id)
          reconcile_run(run_item.run_id)
          broadcast(run_item.run_id)
          {:ok, job}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    else
      {:error, :not_retryable}
    end
  end

  defp do_retry_run_asset(scope, run_asset) do
    if run_asset.status in [:failed, :retrying] do
      Repo.transaction(fn ->
        current =
          RunAsset
          |> where([asset], asset.id == ^run_asset.id)
          |> Storage.lock_for_update()
          |> Repo.one!()

        if current.status not in [:failed, :retrying], do: Repo.rollback(:not_retryable)

        current
        |> RunAsset.changeset(%{
          status: :pending,
          attempt_count: 0,
          error_category: nil,
          error_summary: nil,
          completed_at: nil
        })
        |> Repo.update!()

        asset_job = insert_asset_job!(current.id)
        item_jobs = reset_required_items_for_asset(current.id)
        %{asset_job: asset_job, item_jobs: item_jobs}
      end)
      |> case do
        {:ok, jobs} ->
          Workspaces.audit(scope, "run_asset.retried", "run_asset", run_asset.id)
          reconcile_run(run_asset.run_id)
          broadcast(run_asset.run_id)
          {:ok, jobs}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :not_retryable}
    end
  end

  defp reset_required_assets_for_item(run_item_id) do
    RunAsset
    |> join(:inner, [asset], dependency in CourierCMS.Assets.RunItemAsset,
      on: dependency.run_asset_id == asset.id
    )
    |> where(
      [asset, dependency],
      dependency.run_item_id == ^run_item_id and dependency.required == true and
        asset.status == :failed
    )
    |> order_by([asset], asc: asset.id)
    |> Storage.lock_for_update()
    |> Repo.all()
    |> Enum.map(fn asset ->
      asset
      |> RunAsset.changeset(%{
        status: :pending,
        attempt_count: 0,
        error_category: nil,
        error_summary: nil,
        completed_at: nil
      })
      |> Repo.update!()

      insert_asset_job!(asset.id)
    end)
  end

  defp reset_required_items_for_asset(run_asset_id) do
    RunItem
    |> join(:inner, [item], dependency in CourierCMS.Assets.RunItemAsset,
      on: dependency.run_item_id == item.id
    )
    |> where(
      [item, dependency],
      dependency.run_asset_id == ^run_asset_id and dependency.required == true and
        item.status == :failed
    )
    |> order_by([item], asc: item.id)
    |> Storage.lock_for_update()
    |> Repo.all()
    |> Enum.map(fn item ->
      item
      |> RunItem.changeset(%{
        status: :pending,
        error_category: nil,
        error_summary: nil,
        completed_at: nil
      })
      |> Repo.update!()

      insert_delivery_job!(item.id)
    end)
  end

  defp insert_asset_job!(run_asset_id) do
    AssetWorker.new(JobArgs.put(%{"run_asset_id" => run_asset_id}),
      max_attempts: Application.fetch_env!(:couriercms, :asset_delivery_max_attempts)
    )
    |> insert_oban_job!()
  end

  defp insert_delivery_job!(run_item_id) do
    DeliveryWorker.new(JobArgs.put(%{"run_item_id" => run_item_id}),
      max_attempts: Application.fetch_env!(:couriercms, :delivery_max_attempts)
    )
    |> insert_oban_job!()
  end

  defp insert_oban_job!(changeset) do
    case Oban.insert(changeset) do
      {:ok, job} -> job
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp scoped_run_item(scope, id) do
    RunItem
    |> join(:inner, [item], run in assoc(item, :run))
    |> join(:inner, [_item, run], route in assoc(run, :route))
    |> where([item, _run, route], item.id == ^id and route.workspace_id == ^scope.workspace.id)
    |> select([item, _run, _route], item)
    |> Repo.one()
  end

  defp scoped_run_asset(scope, id) do
    RunAsset
    |> join(:inner, [asset], run in assoc(asset, :run))
    |> join(:inner, [_asset, run], route in assoc(run, :route))
    |> where([asset, _run, route], asset.id == ^id and route.workspace_id == ^scope.workspace.id)
    |> select([asset, _run, _route], asset)
    |> Repo.one()
  end

  defp scoped_run(scope, id) do
    Run
    |> join(:inner, [run], route in assoc(run, :route))
    |> where([run, route], run.id == ^id and route.workspace_id == ^scope.workspace.id)
    |> select([run, _route], run)
    |> Repo.one()
  end

  defp deliver(run_item, source, target, processors, delivery_attempt) do
    run = run_item.run
    route_item = Repo.get!(RouteItem, run_item.route_item_id)

    binding =
      Repo.get_by(DeliveryBinding,
        route_item_id: route_item.id,
        destination_id: run.destination_id
      )

    with {:ok, identity} <- identity_from_item(run_item) do
      if source_read_skippable?(source, run, route_item, binding, identity) do
        {:skip, route_item, binding.last_content_hash}
      else
        read_and_deliver(
          run_item,
          source,
          target,
          processors,
          delivery_attempt,
          identity,
          route_item,
          binding
        )
      end
    end
  end

  defp read_and_deliver(
         run_item,
         source,
         target,
         processors,
         delivery_attempt,
         identity,
         route_item,
         binding
       ) do
    run = run_item.run
    route = run.route
    revision = run.route_revision

    with {:ok, bundle} <-
           Gateway.source(source, :read_root, [
             route.source_connection,
             identity,
             revision.aggregation_rules
           ]),
         :ok <- CourierCMS.Transport.ContentBundleValidator.validate(bundle),
         {:ok, bundle} <- prepare_bundle_assets(run_item, source, target, bundle),
         {:ok, payload} <- Mapping.apply(bundle, revision.mapping),
         {:ok, payload} <- Transformations.apply(payload, revision.transformations),
         {:ok, payload} <-
           Processors.apply(payload, revision.processors, processors,
             observer: processor_observer(run_item, delivery_attempt)
           ) do
      asset_references = asset_references(bundle, route.id)

      content_hash =
        content_hash(
          bundle.root.identity,
          revision.contract_version,
          payload,
          asset_references
        )

      envelope = envelope(run_item, bundle.root.source_type, bundle.root.identity, content_hash)
      canonical_document = CanonicalDeliveryDocument.build(envelope, payload, asset_references)

      delivery_name =
        DeliveryName.resolve(
          canonical_document,
          revision.delivery_name_path,
          identity.item_key,
          envelope.delivery_key
        )

      with :ok <- validate_delivery_size(canonical_document),
           {:ok, projections} <- Projection.project(canonical_document, revision.projections) do
        cond do
          stale_delivery?(route_item, bundle.root.identity) ->
            {:skip, route_item, (binding && binding.last_content_hash) || content_hash}

          unchanged?(binding, content_hash) && !force_redelivery?(run) ->
            {:skip, route_item, content_hash}

          true ->
            deliver_to_target(
              target,
              route.target_connection,
              route_item,
              binding,
              envelope,
              payload,
              canonical_document,
              projections,
              delivery_name,
              content_hash,
              revision.id,
              %{
                id: run.destination.id,
                scope: run.destination.scope
              }
            )
        end
      end
    end
  end

  defp processor_observer(run_item, attempt) do
    fn
      :started, evidence -> start_processor_execution(run_item.id, attempt, evidence)
      :finished, evidence -> finish_processor_execution(run_item.id, attempt, evidence)
    end
  end

  defp start_processor_execution(run_item_id, attempt, evidence) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      ProcessorExecution
      |> where(
        [execution],
        execution.run_item_id == ^run_item_id and execution.status == :processing and
          execution.attempt < ^attempt
      )
      |> Repo.update_all(
        set: [
          status: :failed,
          error_category: "interrupted",
          error_summary: "Processor execution was interrupted before completion",
          retryable: true,
          completed_at: now,
          updated_at: now
        ]
      )

      %ProcessorExecution{}
      |> ProcessorExecution.changeset(
        evidence
        |> Map.put(:run_item_id, run_item_id)
        |> Map.put(:attempt, attempt)
      )
      |> Repo.insert!()
    end)

    :ok
  rescue
    _exception -> processor_evidence_error()
  end

  defp finish_processor_execution(run_item_id, attempt, evidence) do
    execution =
      Repo.get_by!(ProcessorExecution,
        run_item_id: run_item_id,
        attempt: attempt,
        position: evidence.position
      )

    execution
    |> ProcessorExecution.changeset(%{
      status: evidence.status,
      output_hash: evidence.output_hash,
      output_bytes: evidence.output_bytes,
      duration_us: evidence.duration_us,
      error_category: evidence.error_category,
      error_summary: bounded_error_summary(evidence.error_summary),
      retryable: evidence.retryable,
      completed_at: evidence.completed_at
    })
    |> Repo.update!()

    :ok
  rescue
    _exception -> processor_evidence_error()
  end

  defp processor_evidence_error do
    {:error,
     AdapterError.new(
       :internal,
       "Processor execution evidence could not be recorded",
       retryable: true
     )}
  end

  defp bounded_error_summary(nil), do: nil
  defp bounded_error_summary(summary), do: summary |> to_string() |> String.slice(0, 500)

  defp prepare_bundle_assets(_run_item, _source, _target, %ContentBundle{assets: []} = bundle),
    do: {:ok, bundle}

  defp prepare_bundle_assets(run_item, source, target, %ContentBundle{} = bundle) do
    if asset_pipeline_supported?(source, target) do
      with {:ok, _run_assets} <- Assets.plan_dependencies(run_item, bundle.assets) do
        reconcile_run(run_item.run_id)
        resolve_bundle_assets(run_item, bundle)
      end
    else
      with {:ok, _run_assets} <-
             Assets.plan_dependencies(run_item, bundle.assets, schedule_jobs: false) do
        {:ok, bundle}
      end
    end
  end

  defp asset_pipeline_supported?(source, target) do
    Gateway.source_supports?(source, :read_asset) and
      Enum.all?([:find_asset, :create_asset, :update_asset], fn operation ->
        Gateway.target_supports?(target, operation)
      end)
  end

  defp resolve_bundle_assets(run_item, bundle) do
    dependencies = Assets.dependencies(run_item.id)

    cond do
      Enum.any?(dependencies, &(&1.required and &1.run_asset.status == :failed)) ->
        {:error,
         AdapterError.new(:target_rejected, "A required Delivery Asset could not be delivered")}

      Enum.any?(dependencies, &(&1.run_asset.status in [:pending, :processing, :retrying])) ->
        {:waiting_for_assets, Retry.short_snooze()}

      Enum.any?(dependencies, fn dependency ->
        dependency.required and
            not usable_asset_binding?(dependency.run_asset, run_item.run.destination_id)
      end) ->
        {:error,
         AdapterError.new(
           :internal,
           "A required Delivery Asset has no verified target binding"
         )}

      true ->
        {:ok,
         inject_asset_references(
           bundle,
           dependencies,
           run_item.run.destination_id,
           run_item.run.route_id
         )}
    end
  end

  defp usable_asset_binding?(%{status: status, delivery_asset: asset}, destination_id)
       when status in [:succeeded, :skipped] do
    Enum.any?(asset.bindings, fn binding ->
      binding.destination_id == destination_id and is_binary(binding.target_reference) and
        binding.target_reference != "" and binding.state == :delivered
    end)
  end

  defp usable_asset_binding?(_run_asset, _destination_id), do: false

  defp inject_asset_references(bundle, dependencies, destination_id, route_id) do
    by_key = Map.new(dependencies, &{&1.run_asset.asset_key, &1})

    Enum.reduce(bundle.assets, bundle, fn descriptor, current_bundle ->
      asset_key =
        DeliveryAsset.key(route_id, descriptor.source_key, descriptor.variant_key)

      case Map.get(by_key, asset_key) do
        %{run_asset: %{status: status, delivery_asset: asset}}
        when status in [:succeeded, :skipped] ->
          case Enum.find(asset.bindings, &(&1.destination_id == destination_id)) do
            %DeliveryAssetBinding{target_reference: target_reference} = binding
            when is_binary(target_reference) ->
              put_asset_reference(current_bundle, descriptor, asset_key, binding)

            _missing ->
              current_bundle
          end

        _other ->
          current_bundle
      end
    end)
  end

  defp put_asset_reference(bundle, descriptor, asset_key, binding) do
    path = descriptor.field_path || "$assets"

    manifest_reference = asset_reference(descriptor, asset_key, binding)

    resolved =
      bundle.metadata
      |> Map.get(@resolved_asset_references_key, %{})
      |> Map.put(asset_reference_key(descriptor), manifest_reference)

    bundle = %{
      bundle
      | metadata: Map.put(bundle.metadata, @resolved_asset_references_key, resolved)
    }

    if String.starts_with?(path, "fields.") do
      segments = path |> String.replace_prefix("fields.", "") |> String.split(".")

      reference = %{
        "couriercms_asset_key" => asset_key,
        "target_reference" => binding.target_reference,
        "source_key" => descriptor.source_key,
        "variant_key" => descriptor.variant_key,
        "filename" => descriptor.filename,
        "media_type" => descriptor.media_type,
        "checksum" => binding.last_content_hash,
        "metadata" => descriptor.metadata
      }

      root = %{bundle.root | fields: put_asset_path(bundle.root.fields, segments, reference)}
      %{bundle | root: root}
    else
      bundle
    end
  end

  defp asset_references(%ContentBundle{} = bundle, route_id) do
    resolved = Map.get(bundle.metadata, @resolved_asset_references_key, %{})

    bundle.assets
    |> Enum.map(fn descriptor ->
      Map.get_lazy(resolved, asset_reference_key(descriptor), fn ->
        asset_reference(
          descriptor,
          DeliveryAsset.key(route_id, descriptor.source_key, descriptor.variant_key),
          nil
        )
      end)
    end)
    |> Enum.sort_by(&{&1["sourceKey"], &1["variantKey"]})
  end

  defp asset_reference(descriptor, asset_key, binding) do
    %{
      "couriercmsAssetKey" => asset_key,
      "sourceKey" => descriptor.source_key,
      "variantKey" => descriptor.variant_key,
      "filename" => descriptor.filename,
      "mediaType" => descriptor.media_type,
      "checksum" => (binding && binding.last_content_hash) || descriptor.checksum,
      "targetReference" => binding && binding.target_reference,
      "required" => descriptor.required,
      "sourceUrl" => descriptor.metadata["source_url"],
      "metadata" => descriptor.metadata
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp asset_reference_key(descriptor),
    do: {descriptor.source_key, descriptor.variant_key}

  defp put_asset_path(fields, [key], reference) do
    existing = Map.get(fields, key)
    value = if is_map(existing), do: Map.merge(existing, reference), else: reference
    Map.put(fields, key, value)
  end

  defp put_asset_path(fields, [key | rest], reference) do
    nested = Map.get(fields, key)
    nested = if is_map(nested), do: nested, else: %{}
    Map.put(fields, key, put_asset_path(nested, rest, reference))
  end

  defp deliver_asset(run_asset, source, target) do
    with {:ok, descriptor} <- asset_descriptor(run_asset, source),
         {:ok, %AssetContent{} = content} <-
           Gateway.source(source, :read_asset, [
             run_asset.run.route.source_connection,
             descriptor
           ]) do
      Transfer.with_materialized(content, descriptor, fn materialized ->
        deliver_materialized_asset(run_asset, target, descriptor, materialized)
      end)
    end
  end

  defp asset_descriptor(run_asset, source) do
    dependency =
      run_asset.run_item_assets
      |> Enum.sort_by(& &1.id)
      |> List.first()

    with %{run_item: run_item} <- dependency,
         {:ok, identity} <- identity_from_item(run_item),
         {:ok, bundle} <-
           Gateway.source(source, :read_root, [
             run_asset.run.route.source_connection,
             identity,
             run_asset.run.route_revision.aggregation_rules
           ]),
         :ok <- CourierCMS.Transport.ContentBundleValidator.validate(bundle),
         %AssetDescriptor{} = descriptor <-
           Enum.find(bundle.assets, fn descriptor ->
             AssetDescriptor.identity(descriptor) ==
               {run_asset.delivery_asset.source_asset_key, run_asset.delivery_asset.variant_key}
           end) do
      {:ok, descriptor}
    else
      nil ->
        {:error,
         AdapterError.new(:invalid_content, "Delivery Asset dependency is no longer available")}

      _other ->
        {:error,
         AdapterError.new(:invalid_content, "Delivery Asset descriptor could not be resolved")}
    end
  end

  defp deliver_materialized_asset(run_asset, target, descriptor, content) do
    run = run_asset.run
    connection = run.route.target_connection
    destination = %{id: run.destination.id, scope: run.destination.scope}
    binding = Assets.binding(run_asset.delivery_asset, run.destination_id)
    ownership = asset_ownership(run_asset)

    delivery = %{
      asset_key: run_asset.asset_key,
      descriptor: descriptor,
      content: content,
      destination: destination,
      ownership: ownership
    }

    with {:ok, found} <-
           Gateway.target(target, :find_asset, [connection, destination, run_asset.asset_key]),
         {:ok, operation, result} <-
           write_asset(target, connection, binding, found, delivery, content.checksum),
         :ok <- verify_asset_result(result, ownership),
         {:ok, _binding} <-
           bind_asset(run_asset, result, content, descriptor) do
      if operation == "skip",
        do: {:skip, content.checksum},
        else: {:ok, operation, content.checksum}
    end
  end

  defp write_asset(_target, _connection, binding, found, _delivery, content_hash)
       when not is_nil(binding) and binding.last_content_hash == content_hash and
              found != :not_found do
    cond do
      binding.target_reference != found.target_reference ->
        {:error,
         AdapterError.new(
           :ownership_violation,
           "Target asset identity does not match the stored binding"
         )}

      true ->
        {:ok, "skip", found}
    end
  end

  defp write_asset(target, connection, _binding, :not_found, delivery, _content_hash) do
    case Gateway.target(target, :create_asset, [connection, delivery]) do
      {:ok, result} -> {:ok, "create", result}
      error -> error
    end
  end

  defp write_asset(target, connection, binding, found, delivery, _content_hash) do
    if binding && binding.target_reference && binding.target_reference != found.target_reference do
      {:error,
       AdapterError.new(:ownership_violation, "Target asset identity conflicts with its binding")}
    else
      case Gateway.target(target, :update_asset, [
             connection,
             found.target_reference,
             delivery,
             found.ownership
           ]) do
        {:ok, result} -> {:ok, "update", result}
        error -> error
      end
    end
  end

  defp asset_ownership(run_asset) do
    %{
      installation_id: Installation.id(),
      route_id: run_asset.run.route_id,
      destination_id: run_asset.run.destination_id,
      couriercms_asset_key: run_asset.asset_key
    }
  end

  defp verify_asset_result(result, expected) do
    ownership = stringify_keys(result.ownership)

    if ownership == stringify_keys(expected) and is_binary(result.target_reference) and
         result.target_reference != "" do
      :ok
    else
      {:error,
       AdapterError.new(:ownership_violation, "Target returned conflicting asset ownership")}
    end
  end

  defp stringify_keys(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp stringify_keys(_value), do: %{}

  defp bind_asset(run_asset, result, content, descriptor) do
    Repo.transaction(fn ->
      binding =
        Assets.binding(run_asset.delivery_asset, run_asset.run.destination_id) ||
          %DeliveryAssetBinding{}

      binding =
        binding
        |> DeliveryAssetBinding.changeset(%{
          delivery_asset_id: run_asset.delivery_asset_id,
          destination_id: run_asset.run.destination_id,
          target_reference: result.target_reference,
          ownership_evidence: stringify_keys(result.ownership),
          last_content_hash: content.checksum,
          last_delivered_at: DateTime.utc_now(),
          last_successful_run_id: run_asset.run_id,
          last_route_revision_id: run_asset.run.route_revision_id,
          state: :delivered
        })
        |> Repo.insert_or_update!()

      run_asset.delivery_asset
      |> DeliveryAsset.changeset(%{
        filename: descriptor.filename,
        media_type: descriptor.media_type,
        byte_size: content.byte_size,
        source_checksum: content.checksum,
        metadata: descriptor.metadata,
        state: :delivered
      })
      |> Repo.update!()

      binding
    end)
  end

  defp source_read_skippable?(source, run, route_item, binding, identity) do
    capabilities = Gateway.source(source, :capabilities, [run.route.source_connection])

    is_map(capabilities) && capabilities["authoritative_change_token"] == true &&
      is_binary(identity.change_token) && identity.change_token != "" &&
      !force_redelivery?(run) && binding && is_binary(binding.target_reference) &&
      binding.ownership_evidence != %{} && is_binary(binding.last_content_hash) &&
      route_item.last_source_change_token == identity.change_token &&
      binding.last_route_revision_id == run.route_revision_id
  end

  defp deliver_to_target(
         target,
         connection,
         route_item,
         binding,
         envelope,
         payload,
         canonical_document,
         projections,
         delivery_name,
         content_hash,
         route_revision_id,
         destination
       ) do
    delivery = %{
      envelope: envelope,
      payload: payload,
      canonical_document: canonical_document,
      projections: projections,
      name: delivery_name,
      destination: destination
    }

    with {:ok, found} <-
           Gateway.target(target, :find_delivery, [
             connection,
             destination,
             envelope.delivery_key
           ]),
         {:ok, operation, result} <-
           write_delivery(target, connection, binding, found, delivery),
         {:ok, route_item} <-
           bind_delivery(
             route_item,
             binding,
             result,
             envelope,
             content_hash,
             route_revision_id
           ) do
      {:ok, operation, route_item, content_hash}
    end
  end

  defp write_delivery(target, connection, _binding, :not_found, delivery) do
    case Gateway.target(target, :create_delivery, [connection, delivery]) do
      {:ok, result} -> {:ok, "create", result}
      error -> error
    end
  end

  defp write_delivery(target, connection, binding, found, delivery) do
    cond do
      binding && binding.target_reference && binding.target_reference != found.target_reference ->
        {:error,
         AdapterError.new(
           :ownership_violation,
           "Target identity does not match the stored Route Item binding"
         )}

      true ->
        case Gateway.target(target, :update_delivery, [
               connection,
               found.target_reference,
               delivery,
               found.ownership
             ]) do
          {:ok, result} -> {:ok, "update", result}
          error -> error
        end
    end
  end

  defp bind_delivery(route_item, binding, result, envelope, content_hash, route_revision_id) do
    ownership = result.ownership

    if ownership["installation_id"] == envelope.installation_id &&
         ownership["route_id"] == envelope.route_id &&
         ownership["destination_id"] == envelope.destination_id &&
         ownership["couriercms_key"] == envelope.delivery_key do
      Repo.transaction(fn ->
        binding = binding || %DeliveryBinding{}

        binding
        |> DeliveryBinding.changeset(%{
          route_item_id: route_item.id,
          destination_id: envelope.destination_id,
          target_reference: result.target_reference,
          ownership_evidence: ownership,
          last_route_revision_id: route_revision_id,
          last_content_hash: content_hash,
          last_delivered_at: envelope.delivered_at,
          state: :delivered
        })
        |> Repo.insert_or_update!()

        route_item =
          route_item
          |> RouteItem.changeset(%{
            source_revision_key: envelope.source_identity.revision_key,
            last_source_modified_at: envelope.source_identity.modified_at,
            last_source_change_token: envelope.source_identity.change_token,
            state: :delivered
          })
          |> Repo.update!()

        destination = Repo.get!(Destination, envelope.destination_id)

        destination
        |> Destination.changeset(%{
          lifecycle_status: :active,
          first_delivered_at: destination.first_delivered_at || envelope.delivered_at
        })
        |> Repo.update!()

        route_item
      end)
    else
      {:error,
       AdapterError.new(:ownership_violation, "Target returned conflicting ownership metadata")}
    end
  end

  defp unchanged?(%DeliveryBinding{} = binding, content_hash) do
    binding.target_reference && binding.ownership_evidence != %{} &&
      binding.last_content_hash == content_hash
  end

  defp unchanged?(nil, _content_hash), do: false

  defp stale_delivery?(
         %RouteItem{last_source_modified_at: %DateTime{} = delivered_at},
         %{modified_at: %DateTime{} = source_modified_at}
       ),
       do: DateTime.before?(source_modified_at, delivered_at)

  defp stale_delivery?(_route_item, _identity), do: false

  defp validate_delivery_size(canonical_document) do
    max_bytes = Application.fetch_env!(:couriercms, :max_delivery_bytes)

    case Jason.encode(canonical_document) do
      {:ok, json} when byte_size(json) <= max_bytes ->
        :ok

      {:ok, _json} ->
        {:error,
         AdapterError.new(
           :contract_validation_failed,
           "Canonical Delivery Document exceeds the configured size limit"
         )}

      {:error, _reason} ->
        {:error,
         AdapterError.new(
           :contract_validation_failed,
           "Canonical Delivery Document is not valid JSON"
         )}
    end
  end

  defp force_redelivery?(%Run{trigger_kind: :manual, trigger_metadata: metadata}),
    do: metadata["delivery_mode"] == "force"

  defp force_redelivery?(_run), do: false

  defp complete_item(run_item, route_item, operation, content_hash, status \\ :succeeded) do
    now = DateTime.utc_now()

    transition_run_item(run_item, %{
      route_item_id: route_item.id,
      planned_operation: operation,
      status: status,
      content_hash: content_hash,
      completed_at: now
    })

    if status == :succeeded do
      DeliveryBinding
      |> Repo.get_by!(
        route_item_id: route_item.id,
        destination_id: run_item.run.destination_id
      )
      |> DeliveryBinding.changeset(%{last_successful_run_id: run_item.run_id})
      |> Repo.update!()
    end

    :telemetry.execute(
      [:couriercms, :delivery, :completed],
      %{count: 1},
      %{adapter: run_item.run.route.target_connection.adapter_key, status: status}
    )

    maybe_finalize_run(run_item.run_id)
    broadcast(run_item.run_id)
    :ok
  end

  defp record_item_error(run_item, status, error) do
    transition_run_item(run_item, %{
      status: status,
      error_category: to_string(error.category),
      error_summary: error.message,
      completed_at: if(status == :failed, do: DateTime.utc_now(), else: nil)
    })

    :telemetry.execute(
      [:couriercms, :delivery, :failed],
      %{count: 1},
      %{
        adapter: run_item.run.route.target_connection.adapter_key,
        category: error.category,
        terminal: status == :failed
      }
    )

    if status == :failed, do: CourierCMS.Alerts.enqueue_terminal_failure(run_item)

    maybe_finalize_run(run_item.run_id)
    broadcast(run_item.run_id)
  end

  defp complete_asset(run_asset, operation, content_hash, status) do
    transition_run_asset(run_asset, %{
      planned_operation: operation,
      status: status,
      content_hash: content_hash,
      completed_at: DateTime.utc_now(),
      error_category: nil,
      error_summary: nil
    })

    reconcile_run(run_asset.run_id)
    broadcast(run_asset.run_id)
    :ok
  end

  defp record_asset_error(run_asset, status, error) do
    transition_run_asset(run_asset, %{
      status: status,
      error_category: to_string(error.category),
      error_summary: error.message,
      completed_at: if(status == :failed, do: DateTime.utc_now(), else: nil)
    })

    if status == :failed do
      run_asset.delivery_asset
      |> DeliveryAsset.changeset(%{state: :failed})
      |> Repo.update!()
    end

    reconcile_run(run_asset.run_id)
    broadcast(run_asset.run_id)
  end

  defp transition_run_asset(run_asset, attrs) do
    Repo.transaction(fn ->
      current =
        RunAsset
        |> where([asset], asset.id == ^run_asset.id)
        |> Storage.lock_for_update()
        |> Repo.one!()

      current
      |> RunAsset.changeset(attrs)
      |> Repo.update!()
    end)
    |> case do
      {:ok, updated} ->
        updated
        |> Map.put(:run, run_asset.run)
        |> Map.put(:delivery_asset, run_asset.delivery_asset)
        |> Map.put(:run_item_assets, run_asset.run_item_assets)

      {:error, reason} ->
        raise "Run Asset transition failed: #{inspect(reason)}"
    end
  end

  defp emit_asset_delivery_duration(run_asset, result, started_at) do
    status =
      case result do
        {:ok, _operation, _hash} -> :succeeded
        {:skip, _hash} -> :skipped
        {:error, %AdapterError{retryable: true}} -> :retrying
        {:error, %AdapterError{}} -> :failed
      end

    :telemetry.execute(
      [:couriercms, :asset_delivery, :duration],
      %{duration: System.monotonic_time() - started_at},
      %{adapter: run_asset.run.route.target_connection.adapter_key, status: status}
    )
  end

  def reconcile_run(run_id) do
    {:ok, run} =
      Repo.transaction(fn ->
        run = Run |> where([run], run.id == ^run_id) |> Storage.lock_for_update() |> Repo.one!()

        counts =
          Repo.all(
            from item in RunItem,
              where: item.run_id == ^run_id,
              group_by: item.status,
              select: {item.status, count(item.id)}
          )
          |> Map.new()

        asset_counts =
          Repo.all(
            from asset in RunAsset,
              where: asset.run_id == ^run_id,
              group_by: asset.status,
              select: {asset.status, count(asset.id)}
          )
          |> Map.new()

        pending =
          Enum.sum(
            for status <- [:pending, :processing, :retrying], do: Map.get(counts, status, 0)
          )

        succeeded = Map.get(counts, :succeeded, 0)
        skipped = Map.get(counts, :skipped, 0)
        failed = Map.get(counts, :failed, 0)
        planning? = run.status in [:queued, :planning]

        status =
          cond do
            run.status == :cancelled -> :cancelled
            run.status == :failed && run.error_category -> :failed
            planning? -> :planning
            pending > 0 -> :running
            failed == 0 -> :succeeded
            succeeded + skipped > 0 -> :partially_succeeded
            true -> :failed
          end

        update_run(run, %{
          status: status,
          items_succeeded: succeeded,
          items_failed: failed,
          items_retrying: Map.get(counts, :retrying, 0),
          items_skipped: skipped,
          assets_discovered: asset_counts |> Map.values() |> Enum.sum(),
          assets_succeeded: Map.get(asset_counts, :succeeded, 0),
          assets_failed: Map.get(asset_counts, :failed, 0),
          assets_retrying: Map.get(asset_counts, :retrying, 0),
          assets_skipped: Map.get(asset_counts, :skipped, 0),
          completed_at:
            cond do
              planning? or pending > 0 -> nil
              status == :cancelled -> run.completed_at
              true -> run.completed_at || DateTime.utc_now()
            end
        })
      end)

    run
  end

  defp transition_run_item(run_item, attrs) do
    Repo.transaction(fn ->
      current =
        RunItem
        |> where([item], item.id == ^run_item.id)
        |> Storage.lock_for_update()
        |> Repo.one!()

      next_status = Map.fetch!(attrs, :status)

      updated =
        current
        |> RunItem.changeset(attrs)
        |> Repo.update!()

      deltas = status_counter_deltas(current.status, next_status)

      if deltas != [] do
        Repo.update_all(from(run in Run, where: run.id == ^current.run_id), inc: deltas)
      end

      updated
    end)
    |> case do
      {:ok, updated} ->
        updated
        |> Map.put(:run, run_item.run)
        |> Map.put(:route_item, run_item.route_item)

      {:error, reason} ->
        raise "Run Item transition failed: #{inspect(reason)}"
    end
  end

  defp status_counter_deltas(previous, next) when previous == next, do: []

  defp status_counter_deltas(previous, next) do
    [counter_delta(previous, -1), counter_delta(next, 1)]
    |> Enum.reject(&is_nil/1)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {field, values} -> {field, Enum.sum(values)} end)
    |> Enum.reject(&(elem(&1, 1) == 0))
  end

  defp counter_delta(:succeeded, amount), do: {:items_succeeded, amount}
  defp counter_delta(:failed, amount), do: {:items_failed, amount}
  defp counter_delta(:retrying, amount), do: {:items_retrying, amount}
  defp counter_delta(:skipped, amount), do: {:items_skipped, amount}
  defp counter_delta(_status, _amount), do: nil

  defp maybe_finalize_run(run_id) do
    run = Repo.get!(Run, run_id)
    terminal = run.items_succeeded + run.items_failed + run.items_skipped

    if run.planning_complete && run.status not in [:cancelled, :failed] &&
         terminal == run.items_discovered do
      reconcile_run(run_id)
    else
      {:ok, run}
    end
  end

  def subscribe(run_id), do: Phoenix.PubSub.subscribe(CourierCMS.PubSub, "run:#{run_id}")

  def subscribe_route(route_id),
    do: Phoenix.PubSub.subscribe(CourierCMS.PubSub, "route:#{route_id}:runs")

  defp broadcast(run_id) do
    Phoenix.PubSub.broadcast(CourierCMS.PubSub, "run:#{run_id}", {:run_updated, run_id})

    route_id = Repo.one(from run in Run, where: run.id == ^run_id, select: run.route_id)

    if route_id do
      Phoenix.PubSub.broadcast(
        CourierCMS.PubSub,
        "route:#{route_id}:runs",
        {:route_runs_updated, route_id}
      )
    end
  end

  defp persist_planned_page(run, identities, next_cursor, page_number, seen_cursors) do
    case Repo.transaction(fn ->
           identities = Enum.uniq_by(identities, &{&1.item_key, &1.locale_key})
           now = DateTime.utc_now()

           route_item_rows =
             Enum.map(identities, fn identity ->
               %{
                 id: Ecto.UUID.generate(),
                 route_id: run.route_id,
                 source_item_key: identity.item_key,
                 locale_key: identity.locale_key,
                 source_revision_key: identity.revision_key,
                 state: :pending,
                 inserted_at: now,
                 updated_at: now
               }
             end)

           Repo.insert_all(RouteItem, route_item_rows,
             on_conflict: :nothing,
             conflict_target: [:route_id, :source_item_key, :locale_key]
           )

           route_items = route_items_for_page(run.route_id, identities)

           route_items_by_identity =
             Map.new(route_items, &{{&1.source_item_key, &1.locale_key}, &1})

           run_item_rows =
             Enum.map(identities, fn identity ->
               route_item =
                 Map.fetch!(route_items_by_identity, {identity.item_key, identity.locale_key})

               delivery_key = SourceIdentity.delivery_key(identity, run.route_id)

               %{
                 id: Ecto.UUID.generate(),
                 run_id: run.id,
                 route_item_id: route_item.id,
                 delivery_key: delivery_key,
                 source_item_key: identity.item_key,
                 locale_key: identity.locale_key,
                 source_revision_key: identity.revision_key,
                 source_modified_at: utc_datetime_usec(identity.modified_at),
                 source_change_token: identity.change_token,
                 source_state: identity.state,
                 status: :pending,
                 attempt_count: 0,
                 inserted_at: now,
                 updated_at: now
               }
             end)

           {_count, inserted_items} =
             Repo.insert_all(RunItem, run_item_rows,
               on_conflict: :nothing,
               conflict_target: [:run_id, :delivery_key],
               returning: [:id]
             )

           inserted_items
           |> Enum.map(fn item ->
             DeliveryWorker.new(JobArgs.put(%{"run_item_id" => Map.fetch!(item, :id)}),
               max_attempts: Application.fetch_env!(:couriercms, :delivery_max_attempts)
             )
           end)
           |> case do
             [] -> []
             jobs -> Oban.insert_all(jobs)
           end

           discovered =
             Repo.aggregate(from(item in RunItem, where: item.run_id == ^run.id), :count)

           cursor_state =
             if is_nil(next_cursor) do
               nil
             else
               %{
                 "value" => next_cursor,
                 "seen" => seen_cursors |> MapSet.to_list() |> Enum.reject(&is_nil/1)
               }
             end

           run
           |> Run.changeset(%{
             items_discovered: discovered,
             planning_page: page_number,
             planning_complete: is_nil(next_cursor)
           })
           |> Ecto.Changeset.force_change(:planning_cursor, cursor_state)
           |> Repo.update!()
         end) do
      {:ok, _run} ->
        :telemetry.execute(
          [:couriercms, :planning, :page],
          %{items: length(identities)},
          %{adapter: run.route.source_connection.adapter_key}
        )

        broadcast(run.id)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp route_items_for_page(route_id, identities) do
    source_item_keys = identities |> Enum.map(& &1.item_key) |> Enum.uniq()

    RouteItem
    |> where(
      [item],
      item.route_id == ^route_id and item.source_item_key in ^source_item_keys
    )
    |> Repo.all()
  end

  defp destination_baseline_required?(route) do
    Repo.exists?(
      from item in RouteItem,
        left_join: binding in DeliveryBinding,
        on:
          binding.route_item_id == item.id and
            binding.destination_id == ^route.current_destination_id,
        where: item.route_id == ^route.id and is_nil(binding.id)
    )
  end

  defp utc_datetime_usec(nil), do: nil

  defp utc_datetime_usec(%DateTime{microsecond: {value, _precision}} = datetime),
    do: %{datetime | microsecond: {value, 6}}

  defp insert_triggered_run(route, trigger_kind, metadata) do
    connector_event_id = metadata["connector_event_id"]

    existing =
      if connector_event_id,
        do: Repo.get_by(Run, route_id: route.id, connector_event_id: connector_event_id)

    if existing do
      {:ok, existing}
    else
      do_insert_triggered_run(route, trigger_kind, metadata, connector_event_id)
    end
  end

  defp do_insert_triggered_run(route, trigger_kind, metadata, connector_event_id) do
    route =
      Repo.preload(route, [
        :current_revision,
        :current_destination,
        :source_connection,
        :target_connection
      ])

    with true <- route_deliverable?(route),
         {:ok, artifacts} <- run_artifact_attributes(route.current_revision) do
      Ecto.Multi.new()
      |> Ecto.Multi.insert(
        :run,
        Run.changeset(
          %Run{},
          Map.merge(artifacts, %{
            route_id: route.id,
            route_revision_id: route.current_revision_id,
            destination_id: route.current_destination_id,
            trigger_kind: trigger_kind,
            trigger_metadata: metadata,
            schedule_key: metadata["schedule_key"],
            connector_event_id: connector_event_id,
            status: :queued
          })
        )
      )
      |> Oban.insert(:job, fn %{run: run} ->
        PlanRunWorker.new(JobArgs.put(%{"run_id" => run.id}),
          max_attempts: Application.fetch_env!(:couriercms, :planning_max_attempts)
        )
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{run: run}} ->
          broadcast(run.id)
          {:ok, run}

        {:error, _step, reason, _changes} ->
          existing_schedule =
            if schedule_key = metadata["schedule_key"] do
              Repo.get_by(Run, route_id: route.id, schedule_key: schedule_key)
            end

          if existing_schedule, do: {:ok, existing_schedule}, else: {:error, reason}
      end
    else
      false -> {:error, :route_not_active}
      error -> error
    end
  end

  defp route_deliverable?(%Route{} = route) do
    destination = route.current_destination

    route.enabled && is_nil(route.archived_at) && not is_nil(route.current_revision_id) &&
      match?(%Destination{}, destination) &&
      destination.validation_status == :valid &&
      destination.lifecycle_status in [:reserved, :active] &&
      destination.owner_route_id == route.id
  end

  defp schedule_due?(route, now) do
    schedule_due?(route, now, latest_scheduled_run(route.id))
  end

  defp schedule_due?(route, now, last_run) do
    case {schedule_interval(route), last_run} do
      {nil, _last} ->
        false

      {_interval, nil} ->
        true

      {interval, last} ->
        DateTime.compare(now, DateTime.add(scheduled_at(last), interval * 60)) != :lt
    end
  end

  defp schedule_interval(%Route{current_revision: revision}) when not is_nil(revision) do
    case get_in(revision.trigger_settings, ["schedule"]) do
      %{"enabled" => true, "interval_minutes" => interval}
      when is_integer(interval) and interval > 0 ->
        interval

      _other ->
        nil
    end
  end

  defp schedule_interval(_route), do: nil

  defp latest_scheduled_run(route_id) do
    Run
    |> where([run], run.route_id == ^route_id and run.trigger_kind == :schedule)
    |> order_by([run], desc: run.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp active_scheduled_run(route_id) do
    Run
    |> where(
      [run],
      run.route_id == ^route_id and run.trigger_kind == :schedule and
        run.status in [:queued, :planning, :running]
    )
    |> order_by([run], desc: run.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp schedule_metadata(route, now, schedule_key) do
    schedule = get_in(route.current_revision.trigger_settings, ["schedule"]) || %{}
    requested_mode = schedule["polling_mode"] || "incremental"
    reconciliation_interval = schedule["reconciliation_interval_minutes"] || 1_440
    checkpoint = Repo.get_by(Checkpoint, route_id: route.id)

    {mode, reason} =
      cond do
        requested_mode == "full" ->
          {"full", "configured_full"}

        is_nil(checkpoint) ->
          {"full", "initial"}

        !checkpoint_matches_revision?(checkpoint, route.current_revision_id) ->
          {"full", "configuration_changed"}

        reconciliation_due?(checkpoint, now, reconciliation_interval) ->
          {"full", "reconciliation"}

        incremental_supported?(route.source_connection) ->
          {"incremental", "checkpoint"}

        true ->
          {"full", "adapter_fallback"}
      end

    %{
      "schedule_key" => schedule_key,
      "scheduled_at" => DateTime.to_iso8601(now),
      "checkpoint_cutoff" => DateTime.to_iso8601(now),
      "requested_retrieval_mode" => requested_mode,
      "retrieval_mode" => mode,
      "retrieval_reason" => reason,
      "incremental_window" => incremental_window(checkpoint, now)
    }
  end

  defp scheduled_at(%Run{trigger_metadata: %{"scheduled_at" => value}} = run) do
    case parse_datetime(value) do
      {:ok, datetime} -> datetime
      :error -> run.inserted_at
    end
  end

  defp scheduled_at(%Run{} = run), do: run.inserted_at

  defp reconciliation_due?(%Checkpoint{last_full_scan_at: nil}, _now, _interval), do: true

  defp reconciliation_due?(checkpoint, now, interval_minutes) do
    DateTime.diff(now, checkpoint.last_full_scan_at, :minute) >= interval_minutes
  end

  defp checkpoint_matches_revision?(checkpoint, revision_id),
    do: checkpoint.value["route_revision_id"] == revision_id

  defp incremental_supported?(connection) do
    case fetch_source(connection_reference(connection)) do
      {:ok, source} ->
        capabilities = Gateway.source(source, :capabilities, [connection])
        capabilities["incremental_changes"] == true

      _other ->
        false
    end
  end

  defp incremental_window(nil, _now), do: nil

  defp incremental_window(%Checkpoint{value: %{"watermark" => watermark}}, now) do
    case parse_datetime(watermark) do
      {:ok, datetime} ->
        %{
          "after" =>
            datetime
            |> DateTime.add(-@checkpoint_overlap_seconds, :second)
            |> DateTime.to_iso8601(),
          "before" => DateTime.to_iso8601(now)
        }

      :error ->
        nil
    end
  end

  defp incremental_window(_checkpoint, _now), do: nil

  defp plan_discovery(source, %Run{trigger_kind: :schedule} = run) do
    if run.trigger_metadata["retrieval_mode"] == "incremental" do
      plan_incrementally(source, run)
    else
      with :ok <- plan_pages(source, run, :full) do
        {:ok, run}
      end
    end
  end

  defp plan_discovery(source, run) do
    with :ok <- plan_pages(source, run, :full) do
      {:ok, run}
    end
  end

  defp plan_incrementally(source, run) do
    window = run.trigger_metadata["incremental_window"]

    result =
      if is_map(window) && Gateway.source_supports?(source, :changes_since) do
        plan_pages(source, run, {:incremental, window})
      else
        {:error, AdapterError.new(:unsupported, "Incremental discovery is unavailable")}
      end

    case result do
      :ok ->
        {:ok, run}

      {:error, %AdapterError{category: category}}
      when category in [:unsupported, :invalid_selection] ->
        metadata =
          run.trigger_metadata
          |> Map.put("retrieval_mode", "full")
          |> Map.put("retrieval_reason", "incremental_fallback")

        run = update_run(run, %{trigger_metadata: metadata})

        with :ok <- plan_pages(source, run, :full) do
          {:ok, run}
        end

      error ->
        error
    end
  end

  defp advance_checkpoint!(%Run{trigger_kind: :schedule} = run) do
    {:ok, cutoff} = parse_datetime(run.trigger_metadata["checkpoint_cutoff"])
    checkpoint = Repo.get_by(Checkpoint, route_id: run.route_id) || %Checkpoint{}

    attrs = %{
      route_id: run.route_id,
      source_connection_id: run.route.source_connection_id,
      last_run_id: run.id,
      adapter_key: run.route.source_connection.adapter_key,
      value: %{
        "version" => 1,
        "watermark" => DateTime.to_iso8601(cutoff),
        "route_revision_id" => run.route_revision_id
      },
      last_advanced_at: DateTime.utc_now(),
      last_full_scan_at:
        if(run.trigger_metadata["retrieval_mode"] == "full",
          do: cutoff,
          else: checkpoint.last_full_scan_at
        )
    }

    checkpoint
    |> Checkpoint.changeset(attrs)
    |> Repo.insert_or_update!()

    :telemetry.execute(
      [:couriercms, :checkpoint, :advanced],
      %{count: 1},
      %{
        adapter: run.route.source_connection.adapter_key,
        retrieval_mode: run.trigger_metadata["retrieval_mode"]
      }
    )

    :ok
  end

  defp advance_checkpoint!(_run), do: :ok

  defp selection_for_run(%Run{trigger_kind: trigger_kind, trigger_metadata: metadata} = run)
       when trigger_kind in [:publish, :save] do
    case metadata["source_item_key"] do
      key when is_binary(key) and key != "" ->
        Map.put(run.route_revision.selection, "source_item_ids", [key])

      _other ->
        run.route_revision.selection
    end
  end

  defp selection_for_run(run), do: run.route_revision.selection

  defp plan_pages(_source, %Run{planning_complete: true}, _mode), do: :ok

  defp plan_pages(source, run, mode) do
    cursor_state = run.planning_cursor || %{}
    cursor = cursor_state["value"]
    seen_cursors = MapSet.new(cursor_state["seen"] || [])
    plan_pages(source, run, mode, cursor, run.planning_page, seen_cursors)
  end

  defp plan_pages(source, run, mode, cursor, page_count, seen_cursors) do
    if page_count >= Application.fetch_env!(:couriercms, :max_planning_pages) do
      {:error, AdapterError.new(:invalid_selection, "Source enumeration exceeded the page limit")}
    else
      do_plan_page(source, run, mode, cursor, page_count, seen_cursors)
    end
  end

  defp do_plan_page(source, run, mode, cursor, page_count, seen_cursors) do
    connection = run.route.source_connection
    selection = selection_for_run(run)

    result =
      if run_cancelled?(run.id) do
        {:error, :cancelled}
      else
        case mode do
          :full ->
            Gateway.source(source, :enumerate, [connection, selection, cursor])

          {:incremental, window} ->
            Gateway.source(source, :changes_since, [connection, selection, window, cursor])
        end
      end

    case result do
      {:ok, %{items: items, cursor: next_cursor}} when is_list(items) ->
        with :ok <- validate_page_size(items),
             :ok <- ensure_run_capacity(run, items),
             :ok <- validate_next_cursor(next_cursor, seen_cursors),
             next_seen =
               if(next_cursor, do: MapSet.put(seen_cursors, next_cursor), else: seen_cursors),
             :ok <- persist_planned_page(run, items, next_cursor, page_count + 1, next_seen) do
          case next_cursor do
            nil ->
              :ok

            next_cursor ->
              plan_pages(
                source,
                run,
                mode,
                next_cursor,
                page_count + 1,
                next_seen
              )
          end
        end

      {:ok, _invalid_page} ->
        {:error, AdapterError.new(:invalid_content, "Source returned an invalid page")}

      error ->
        error
    end
  end

  defp validate_next_cursor(nil, _seen_cursors), do: :ok

  defp validate_next_cursor(cursor, seen_cursors) do
    if MapSet.member?(seen_cursors, cursor) do
      {:error, AdapterError.new(:invalid_content, "Source repeated an enumeration cursor")}
    else
      :ok
    end
  end

  defp validate_page_size(items) do
    if length(items) <= Application.fetch_env!(:couriercms, :max_source_page_items) do
      :ok
    else
      {:error,
       AdapterError.new(:invalid_content, "Source page exceeds the configured item limit")}
    end
  end

  defp ensure_run_capacity(run, identities) do
    existing_count = Repo.aggregate(from(item in RunItem, where: item.run_id == ^run.id), :count)

    page_identities = identities |> Enum.map(&{&1.item_key, &1.locale_key}) |> MapSet.new()

    source_item_keys = Enum.map(page_identities, &elem(&1, 0))

    existing_identities =
      RunItem
      |> where([item], item.run_id == ^run.id)
      |> where([item], item.source_item_key in ^source_item_keys)
      |> select([item], {item.source_item_key, item.locale_key})
      |> Repo.all()
      |> MapSet.new()

    existing_in_page =
      page_identities
      |> MapSet.intersection(existing_identities)
      |> MapSet.size()

    new_count = MapSet.size(page_identities) - existing_in_page

    if existing_count + new_count <= Application.fetch_env!(:couriercms, :max_run_items) do
      :ok
    else
      {:error, AdapterError.new(:invalid_selection, "Run exceeds the configured item limit")}
    end
  end

  defp finalize_planning(run) do
    case Repo.transaction(fn ->
           current_run =
             Run
             |> where([current], current.id == ^run.id)
             |> Storage.lock_for_update()
             |> Repo.one!()

           if current_run.status == :cancelled do
             Repo.rollback(:cancelled)
           end

           discovered =
             Repo.aggregate(from(item in RunItem, where: item.run_id == ^run.id), :count)

           advance_checkpoint!(run)

           current_run
           |> Run.changeset(%{status: :running, items_discovered: discovered})
           |> Repo.update!()
         end) do
      {:ok, finalized_run} -> {:ok, finalized_run}
      {:error, :cancelled} -> {:error, :cancelled}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_cancelled?(run_id), do: Repo.get!(Run, run_id).status == :cancelled

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _other -> :error
    end
  end

  defp parse_datetime(_value), do: :error

  defp identity_from_item(item) do
    SourceIdentity.new(%{
      item_key: item.source_item_key,
      locale_key: item.locale_key,
      revision_key: item.source_revision_key,
      state: item.source_state,
      modified_at: item.source_modified_at,
      change_token: item.source_change_token
    })
  end

  defp envelope(run_item, source_type, identity, content_hash) do
    run = run_item.run

    %DeliveryEnvelope{
      installation_id: Installation.id(),
      route_id: run.route_id,
      destination_id: run.destination_id,
      route_revision: run.route_revision.revision_number,
      delivery_key: run_item.delivery_key,
      source_connection_id: run.route.source_connection_id,
      source_identity: identity,
      source_type: source_type,
      contract_version: run.route_revision.contract_version,
      delivered_at: DateTime.utc_now(),
      content_hash: content_hash
    }
  end

  defp content_hash(identity, contract_version, payload, assets) do
    %{identity: identity, contract_version: contract_version, payload: payload, assets: assets}
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> then(&("sha256:" <> &1))
  end

  defp load_execution_run!(run_id) do
    Run
    |> Repo.get!(run_id)
    |> Repo.preload([
      :route_revision,
      :destination,
      route: [:source_connection, :target_connection]
    ])
  end

  defp load_run_item!(id) do
    RunItem
    |> Repo.get!(id)
    |> Repo.preload([
      :route_item,
      run: [:route_revision, :destination, route: [:source_connection, :target_connection]]
    ])
  end

  defp load_run_asset!(id) do
    RunAsset
    |> Repo.get!(id)
    |> Repo.preload([
      :delivery_asset,
      run_item_assets: :run_item,
      run: [:route_revision, :destination, route: [:source_connection, :target_connection]]
    ])
  end

  defp run_artifact_attributes(revision) do
    with {:ok, source_artifact} <- Gateway.artifact(revision_source_reference(revision)),
         {:ok, target_artifact} <- Gateway.artifact(revision_target_reference(revision)),
         {:ok, processor_artifacts} <- processor_artifacts(revision.processors) do
      {:ok,
       %{
         source_artifact: source_artifact,
         target_artifact: target_artifact,
         processor_artifacts: processor_artifacts
       }}
    else
      :error ->
        {:error,
         AdapterError.new(
           :unsupported,
           "A Route Extension component is not installed on this node"
         )}
    end
  end

  # Runs created before artifact evidence was introduced are pinned once, under
  # a database lock, before they perform any more work. Completed historical
  # Runs remain truthful: they do not claim evidence that was never recorded.
  defp ensure_run_artifacts(%Run{source_artifact: source, target_artifact: target} = run)
       when is_map(source) and is_map(target) do
    if length(run.processor_artifacts || []) == length(run.route_revision.processors || []),
      do: {:ok, run},
      else: pin_run_artifacts(run)
  end

  defp ensure_run_artifacts(%Run{} = run), do: pin_run_artifacts(run)

  defp pin_run_artifacts(%Run{} = run) do
    result =
      Repo.transaction(fn ->
        locked_run =
          Run
          |> where([current], current.id == ^run.id)
          |> Storage.lock_for_update()
          |> Repo.one!()
          |> Repo.preload(:route_revision)

        if is_map(locked_run.source_artifact) and is_map(locked_run.target_artifact) and
             length(locked_run.processor_artifacts || []) ==
               length(locked_run.route_revision.processors || []) do
          locked_run
        else
          case run_artifact_attributes(locked_run.route_revision) do
            {:ok, artifacts} ->
              locked_run
              |> Run.changeset(artifacts)
              |> Repo.update!()

            {:error, error} ->
              Repo.rollback(error)
          end
        end
      end)

    case result do
      {:ok, _run} -> {:ok, load_execution_run!(run.id)}
      {:error, %AdapterError{} = error} -> {:error, error}
    end
  end

  defp execution_references(%Run{} = run) do
    with {:ok, source} <- Gateway.validate_artifact(run.source_artifact, :source),
         {:ok, target} <- Gateway.validate_artifact(run.target_artifact, :target),
         :ok <- validate_processor_artifacts(run.processor_artifacts) do
      {:ok, source, target, run.processor_artifacts}
    end
  end

  defp processor_artifacts(processors) do
    Enum.reduce_while(processors, {:ok, []}, fn processor, {:ok, artifacts} ->
      reference = %{
        extension_id: processor["extension_id"],
        component_id: processor["component_id"]
      }

      case Gateway.artifact(reference) do
        {:ok, artifact} ->
          if artifact["version"] == processor["component_version"],
            do: {:cont, {:ok, [artifact | artifacts]}},
            else: {:halt, :error}

        _other ->
          {:halt, :error}
      end
    end)
    |> case do
      {:ok, artifacts} -> {:ok, Enum.reverse(artifacts)}
      :error -> :error
    end
  end

  defp validate_processor_artifacts(artifacts) when is_list(artifacts) do
    if Enum.all?(artifacts, &match?({:ok, _}, Gateway.validate_artifact(&1, :processor))),
      do: :ok,
      else:
        {:error,
         AdapterError.new(
           :unsupported,
           "The Run requires a Processor artifact that is not installed on this node"
         )}
  end

  defp validate_processor_artifacts(_artifacts) do
    {:error,
     AdapterError.new(
       :unsupported,
       "The Run requires a Processor artifact that is not installed on this node"
     )}
  end

  defp revision_source_reference(revision) do
    %{
      extension_id: revision.source_extension_id,
      component_id: revision.source_component_id
    }
  end

  defp revision_target_reference(revision) do
    %{
      extension_id: revision.target_extension_id,
      component_id: revision.target_component_id
    }
  end

  defp connection_reference(connection) do
    %{extension_id: connection.extension_id, component_id: connection.component_id}
  end

  defp fetch_source(key) do
    if Gateway.source_available?(key),
      do: {:ok, key},
      else: {:error, AdapterError.new(:unsupported, "Source Adapter is not registered")}
  end

  defp fetch_target(key) do
    if Gateway.target_available?(key),
      do: {:ok, key},
      else: {:error, AdapterError.new(:unsupported, "Target Adapter is not registered")}
  end

  defp fail_planning(run, error) do
    update_run(run, %{
      status: :failed,
      error_category: to_string(error.category),
      error_summary: error.message,
      completed_at: DateTime.utc_now()
    })

    broadcast(run.id)
    {:discard, error.message}
  end

  defp retry_planning(run, error) do
    update_run(run, %{
      status: :queued,
      error_category: to_string(error.category),
      error_summary: error.message,
      completed_at: nil
    })

    broadcast(run.id)
    {:error, error.message}
  end

  defp update_run(run, attrs), do: run |> Run.changeset(attrs) |> Repo.update!()
  defp safe_reason(reason) when is_binary(reason), do: reason
  defp safe_reason(_reason), do: "The Run could not be planned"
end

defmodule CourierCMS.Execution.AutomaticDeliveryTest do
  use CourierCMS.DataCase

  alias CourierCMS.Connectors
  alias CourierCMS.Connectors.{ConnectorEvent, ConnectorEventWorker}
  alias CourierCMS.Connections.Connection
  alias CourierCMS.Assets.RunAsset
  alias CourierCMS.Execution
  alias CourierCMS.Execution.{Checkpoint, Run, RunItem}
  alias CourierCMS.Repo
  alias CourierCMS.Routes

  test "a due periodic route starts once and records a scheduled Run" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    assert {:ok, route} = Routes.update_schedule(scope, route, true, 15)
    now = ~U[2026-09-24 20:00:00Z]
    assert Execution.next_scheduled_at(route, now) == now

    assert :ok = Execution.enqueue_due_schedules(now)
    assert Repo.aggregate(from(run in Run, where: run.trigger_kind == :schedule), :count) == 1

    assert :ok = Execution.enqueue_due_schedules(now)
    assert Repo.aggregate(from(run in Run, where: run.trigger_kind == :schedule), :count) == 1
  end

  test "a scheduled interval has a durable identity under duplicate dispatch" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)
    assert {:ok, route} = Routes.update_schedule(scope, route, true, 15)
    now = ~U[2026-09-24 20:00:00Z]

    assert {:ok, first} = Execution.start_scheduled_run(route, now)
    assert {:ok, duplicate} = Execution.start_scheduled_run(route, now)

    assert duplicate.id == first.id
    assert Repo.aggregate(from(run in Run, where: run.route_id == ^route.id), :count) == 1
  end

  test "a due schedule does not overlap an active scheduled Run" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)
    assert {:ok, route} = Routes.update_schedule(scope, route, true, 5)

    assert {:ok, active} =
             Execution.start_scheduled_run(route, ~U[2026-09-24 20:00:00Z])

    assert :ok = Execution.plan_run(active.id)

    assert {:ok, same_run} =
             Execution.start_scheduled_run(route, ~U[2026-09-24 20:20:00Z])

    assert same_run.id == active.id
    assert Repo.aggregate(from(run in Run, where: run.route_id == ^route.id), :count) == 1
  end

  test "scheduled polling establishes a full checkpoint then discovers only modified content" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    assert {:ok, route} =
             Routes.update_schedule(scope, route, true, 5, "incremental", 1_440)

    baseline_at = ~U[2026-09-24 20:00:00Z]
    assert {:ok, baseline} = Execution.start_scheduled_run(route, baseline_at)
    assert baseline.trigger_metadata["retrieval_mode"] == "full"
    assert baseline.trigger_metadata["retrieval_reason"] == "initial"
    assert :ok = Execution.plan_run(baseline.id)
    complete_run(baseline.id)

    assert Repo.aggregate(from(item in RunItem, where: item.run_id == ^baseline.id), :count) == 3

    checkpoint = Repo.get_by!(Checkpoint, route_id: route.id)
    assert checkpoint.value["watermark"] == "2026-09-24T20:00:00Z"
    assert checkpoint.value["route_revision_id"] == route.current_revision_id
    assert DateTime.compare(checkpoint.last_full_scan_at, baseline_at) == :eq

    changed_at = ~U[2026-09-24 20:04:00Z]

    route.source_connection
    |> Ecto.Changeset.change(
      settings: %{
        "revision_overrides" => %{"101" => "8"},
        "modified_at_overrides" => %{"101" => changed_at}
      }
    )
    |> Repo.update!()

    route = Routes.get_route!(scope, route.id)
    incremental_at = ~U[2026-09-24 20:05:00Z]
    assert {:ok, incremental} = Execution.start_scheduled_run(route, incremental_at)
    assert incremental.trigger_metadata["retrieval_mode"] == "incremental"
    assert incremental.trigger_metadata["retrieval_reason"] == "checkpoint"
    assert :ok = Execution.plan_run(incremental.id)

    assert [%RunItem{source_item_key: "101", source_revision_key: "8"}] =
             Repo.all(from(item in RunItem, where: item.run_id == ^incremental.id))

    checkpoint = Repo.get_by!(Checkpoint, route_id: route.id)
    assert checkpoint.value["watermark"] == "2026-09-24T20:05:00Z"
    assert DateTime.compare(checkpoint.last_full_scan_at, baseline_at) == :eq
  end

  test "a planning failure does not advance its checkpoint and can resume safely" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    assert {:ok, route} = Routes.update_schedule(scope, route, true, 5, "incremental", 1_440)

    route.source_connection
    |> Ecto.Changeset.change(settings: %{"fail_enumeration_at_cursor" => 2})
    |> Repo.update!()

    route = Routes.get_route!(scope, route.id)
    assert {:ok, run} = Execution.start_scheduled_run(route, ~U[2026-09-24 20:00:00Z])

    assert {:error, "Fake source enumeration failed"} = Execution.plan_run(run.id, 1, 3)
    refute Repo.get_by(Checkpoint, route_id: route.id)

    assert Repo.aggregate(from(item in RunItem, where: item.run_id == ^run.id), :count) == 2

    assert Repo.aggregate(
             from(job in Oban.Job,
               where: job.worker == "CourierCMS.Execution.DeliveryWorker"
             ),
             :count
           ) == 2

    route.source_connection
    |> Ecto.Changeset.change(settings: %{})
    |> Repo.update!()

    assert :ok = Execution.plan_run(run.id, 2, 3)
    assert Repo.get_by!(Checkpoint, route_id: route.id).last_run_id == run.id
    assert Repo.aggregate(from(item in RunItem, where: item.run_id == ^run.id), :count) == 3
  end

  test "incremental polling performs the configured full reconciliation" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    assert {:ok, route} =
             Routes.update_schedule(scope, route, true, 5, "incremental", 1_440)

    baseline_at = ~U[2026-09-23 20:00:00Z]
    assert {:ok, baseline} = Execution.start_scheduled_run(route, baseline_at)
    assert :ok = Execution.plan_run(baseline.id)
    complete_run(baseline.id)

    route = Routes.get_route!(scope, route.id)
    reconciliation_at = ~U[2026-09-24 20:00:00Z]
    assert {:ok, reconciliation} = Execution.start_scheduled_run(route, reconciliation_at)
    assert reconciliation.trigger_metadata["retrieval_mode"] == "full"
    assert reconciliation.trigger_metadata["retrieval_reason"] == "reconciliation"
  end

  test "an unsupported incremental query falls back to a full scan" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    assert {:ok, route} =
             Routes.update_schedule(scope, route, true, 5, "incremental", 1_440)

    baseline_at = ~U[2026-09-24 20:00:00Z]
    assert {:ok, baseline} = Execution.start_scheduled_run(route, baseline_at)
    assert :ok = Execution.plan_run(baseline.id)
    complete_run(baseline.id)

    route.source_connection
    |> Ecto.Changeset.change(settings: %{"reject_incremental" => true})
    |> Repo.update!()

    route = Routes.get_route!(scope, route.id)
    assert {:ok, fallback} = Execution.start_scheduled_run(route, ~U[2026-09-24 20:05:00Z])
    assert fallback.trigger_metadata["retrieval_mode"] == "incremental"
    assert :ok = Execution.plan_run(fallback.id)

    fallback = Repo.get!(Run, fallback.id)
    assert fallback.trigger_metadata["retrieval_mode"] == "full"
    assert fallback.trigger_metadata["retrieval_reason"] == "incremental_fallback"
    assert fallback.items_discovered == 3
  end

  test "a Route revision change establishes a new full baseline" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    assert {:ok, route} =
             Routes.update_schedule(scope, route, true, 5, "incremental", 1_440)

    assert {:ok, baseline} =
             Execution.start_scheduled_run(route, ~U[2026-09-24 20:00:00Z])

    assert :ok = Execution.plan_run(baseline.id)
    complete_run(baseline.id)

    assert {:ok, route} =
             Routes.update_selection(scope, route, %{
               "content_type" => "post",
               "state" => "published",
               "category" => "Engineering",
               "tags" => ["architecture"],
               "published_year" => ""
             })

    assert {:ok, changed} =
             Execution.start_scheduled_run(route, ~U[2026-09-24 20:05:00Z])

    assert changed.trigger_metadata["retrieval_mode"] == "full"
    assert changed.trigger_metadata["retrieval_reason"] == "configuration_changed"
  end

  test "Route subscribers are notified when a Run is created and changes" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)
    assert :ok = Execution.subscribe_route(route.id)

    assert {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert_receive {:route_runs_updated, route_id}
    assert route_id == route.id

    assert :ok = Execution.plan_run(run.id)
    assert_receive {:route_runs_updated, route_id}
    assert route_id == route.id
  end

  test "a publish event plans only the affected item through matching Routes" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    event =
      %ConnectorEvent{}
      |> ConnectorEvent.changeset(%{
        contract_version: 1,
        connection_id: route.source_connection_id,
        external_event_id: Ecto.UUID.generate(),
        event_kind: "content.updated",
        source_item_key: "101",
        status: :accepted,
        received_at: DateTime.utc_now()
      })
      |> Repo.insert!()

    assert {:ok, [run]} = Execution.start_connector_runs(event)
    assert run.trigger_kind == :publish
    assert run.trigger_metadata["event_kind"] == "content.updated"
    assert run.trigger_metadata["connector_contract_version"] == 1
    assert :ok = Execution.plan_run(run.id)

    assert [%RunItem{source_item_key: "101"}] =
             Repo.all(from(item in RunItem, where: item.run_id == ^run.id))
  end

  test "reprocessing a durable Connector event does not create another Run" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    event =
      %ConnectorEvent{}
      |> ConnectorEvent.changeset(%{
        contract_version: 1,
        connection_id: route.source_connection_id,
        external_event_id: Ecto.UUID.generate(),
        event_kind: "content.updated",
        source_item_key: "101",
        status: :accepted,
        received_at: DateTime.utc_now()
      })
      |> Repo.insert!()

    assert :ok = Connectors.process_event(event.id)
    assert :ok = Connectors.process_event(event.id)

    assert Repo.aggregate(
             from(run in Run, where: run.connector_event_id == ^event.id),
             :count
           ) == 1

    assert Repo.get!(ConnectorEvent, event.id).status == :processed
  end

  test "reconciliation requeues a stranded Connector Event without an active job" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)
    stale_at = DateTime.add(DateTime.utc_now(), -2, :hour)

    event =
      %ConnectorEvent{}
      |> ConnectorEvent.changeset(%{
        contract_version: 1,
        connection_id: route.source_connection_id,
        external_event_id: Ecto.UUID.generate(),
        event_kind: "content.updated",
        source_item_key: "101",
        status: :processing,
        received_at: stale_at
      })
      |> Repo.insert!()

    previous = Application.get_env(:couriercms, :stranded_after_ms)
    Application.put_env(:couriercms, :stranded_after_ms, 60_000)
    on_exit(fn -> Application.put_env(:couriercms, :stranded_after_ms, previous) end)

    assert :ok =
             CourierCMS.Execution.ReconcileWorker.perform(%Oban.Job{args: %{"v" => 1}})

    assert Repo.get!(ConnectorEvent, event.id).status == :accepted

    worker = ConnectorEventWorker |> Module.split() |> Enum.join(".")

    assert Repo.exists?(
             from(job in Oban.Job,
               where:
                 job.worker == ^worker and job.args["event_id"] == ^event.id and
                   job.state in ["available", "scheduled", "executing", "retryable"]
             )
           )
  end

  test "reconciliation requeues stranded delivery items after a process crash" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)
    assert {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(run.id)

    Repo.delete_all(
      from(job in Oban.Job, where: job.worker == "CourierCMS.Execution.DeliveryWorker")
    )

    stale_at = DateTime.add(DateTime.utc_now(), -2, :hour)

    Repo.update_all(
      from(item in RunItem, where: item.run_id == ^run.id),
      set: [status: :processing, updated_at: stale_at]
    )

    previous = Application.get_env(:couriercms, :stranded_after_ms)
    Application.put_env(:couriercms, :stranded_after_ms, 60_000)
    on_exit(fn -> Application.put_env(:couriercms, :stranded_after_ms, previous) end)

    assert :ok =
             CourierCMS.Execution.ReconcileWorker.perform(%Oban.Job{args: %{"v" => 1}})

    assert Repo.aggregate(
             from(job in Oban.Job,
               where: job.worker == "CourierCMS.Execution.DeliveryWorker"
             ),
             :count
           ) == 3

    assert Repo.aggregate(
             from(item in RunItem,
               where: item.run_id == ^run.id and item.status == :pending
             ),
             :count
           ) == 3
  end

  test "reconciliation requeues stranded Delivery Assets after a process crash" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)
    assert {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(run.id)

    item = Repo.get_by!(RunItem, run_id: run.id, source_item_key: "101")
    assert {:snooze, _seconds} = Execution.process_run_item(item.id, 1, 3)
    asset = Repo.get_by!(RunAsset, run_id: run.id)

    Repo.delete_all(
      from(job in Oban.Job, where: job.worker == "CourierCMS.Execution.AssetWorker")
    )

    stale_at = DateTime.add(DateTime.utc_now(), -2, :hour)

    Repo.update_all(from(current in RunAsset, where: current.id == ^asset.id),
      set: [status: :processing, updated_at: stale_at]
    )

    previous = Application.get_env(:couriercms, :stranded_after_ms)
    Application.put_env(:couriercms, :stranded_after_ms, 60_000)
    on_exit(fn -> Application.put_env(:couriercms, :stranded_after_ms, previous) end)

    assert :ok =
             CourierCMS.Execution.ReconcileWorker.perform(%Oban.Job{args: %{"v" => 1}})

    assert Repo.get!(RunAsset, asset.id).status == :pending

    assert Repo.exists?(
             from(job in Oban.Job,
               where:
                 job.worker == "CourierCMS.Execution.AssetWorker" and
                   job.args["run_asset_id"] == ^asset.id and
                   job.state in ["available", "scheduled", "executing", "retryable"]
             )
           )
  end

  test "an operator can immediately reconcile a Run with a missing asset job" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)
    assert {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(run.id)

    item = Repo.get_by!(RunItem, run_id: run.id, source_item_key: "101")
    assert {:snooze, _seconds} = Execution.process_run_item(item.id, 1, 3)
    asset = Repo.get_by!(RunAsset, run_id: run.id)

    Repo.delete_all(
      from(job in Oban.Job,
        where:
          job.worker == "CourierCMS.Execution.AssetWorker" and
            job.args["run_asset_id"] == ^asset.id
      )
    )

    assert {:ok, %{assets: 1, items: 0, planners: 0}} =
             Execution.reconcile_stranded_run(scope, run.id)

    assert Repo.get!(RunAsset, asset.id).status == :pending

    assert Repo.exists?(
             from(job in Oban.Job,
               where:
                 job.worker == "CourierCMS.Execution.AssetWorker" and
                   job.args["run_asset_id"] == ^asset.id and
                   job.state in ["available", "scheduled", "executing", "retryable"]
             )
           )
  end

  test "retention removes old completed Runs and their Run Items in a bounded batch" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)
    assert {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(run.id)

    Repo.delete_all(from(job in Oban.Job, where: job.args["run_id"] == ^run.id))

    Repo.delete_all(
      from(job in Oban.Job, where: job.worker == "CourierCMS.Execution.DeliveryWorker")
    )

    old = DateTime.add(DateTime.utc_now(), -2, :day)

    Repo.update_all(from(saved in Run, where: saved.id == ^run.id),
      set: [status: :succeeded, completed_at: old]
    )

    previous_enabled = Application.get_env(:couriercms, :retention_enabled)
    previous_days = Application.get_env(:couriercms, :run_retention_days)
    Application.put_env(:couriercms, :retention_enabled, true)
    Application.put_env(:couriercms, :run_retention_days, 1)

    on_exit(fn ->
      Application.put_env(:couriercms, :retention_enabled, previous_enabled)
      Application.put_env(:couriercms, :run_retention_days, previous_days)
    end)

    assert :ok = CourierCMS.Execution.RetentionWorker.perform(%Oban.Job{args: %{"v" => 1}})
    refute Repo.get(Run, run.id)
    assert Repo.aggregate(from(item in RunItem, where: item.run_id == ^run.id), :count) == 0
  end

  defp route_fixture(scope) do
    source = connection_fixture(scope, "Source", "fake_source")
    target = connection_fixture(scope, "Target", "fake_target")
    destination = destination_fixture(scope, target)

    {:ok, route} =
      Routes.create_route(
        scope,
        %{
          name: "Automatic route #{System.unique_integer()}",
          source_connection_id: source.id,
          target_connection_id: target.id,
          current_destination_id: destination.id,
          enabled: true
        },
        %{
          selection: %{
            "content_type" => "post",
            "state" => "published",
            "category" => "Engineering",
            "tags" => [],
            "published_year" => ""
          },
          mapping: Routes.default_mapping("fake_source")
        }
      )

    route
  end

  defp connection_fixture(scope, name, adapter_key) do
    %Connection{}
    |> Connection.changeset(%{
      name: "#{name} #{System.unique_integer()}",
      adapter_key: adapter_key,
      extension_id: "com.couriercms.fake",
      component_id: adapter_key,
      endpoint: "https://#{adapter_key}.example",
      workspace_id: scope.workspace.id
    })
    |> Repo.insert!()
  end

  defp complete_run(run_id) do
    RunItem
    |> where([item], item.run_id == ^run_id)
    |> Repo.all()
    |> Enum.each(&process_item/1)
  end

  defp process_item(item) do
    case Execution.process_run_item(item.id, 1, 3) do
      :ok ->
        :ok

      {:snooze, _seconds} ->
        RunAsset
        |> where([asset], asset.run_id == ^item.run_id and asset.status == :pending)
        |> Repo.all()
        |> Enum.each(&assert(:ok = Execution.process_run_asset(&1.id, 1, 3)))

        assert :ok = Execution.process_run_item(item.id, 1, 3)
    end
  end
end

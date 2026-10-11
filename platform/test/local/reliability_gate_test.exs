defmodule CourierCMS.Local.ReliabilityGateTest do
  use CourierCMS.DataCase
  use Oban.Testing, repo: CourierCMS.Repo

  if CourierCMS.ReleaseProfile.server?() do
    @moduletag skip: "Local SQLite decision-gate coverage"
  end

  alias CourierCMS.Connections.Connection
  alias CourierCMS.Assets.RunAsset
  alias CourierCMS.Execution
  alias CourierCMS.Execution.{Checkpoint, RunItem}
  alias CourierCMS.LocalRecovery
  alias CourierCMS.Ownership.DeliveryBinding
  alias CourierCMS.Repo
  alias CourierCMS.Routes

  test "startup recovery immediately returns interrupted Oban jobs to the Local queue" do
    assert {:ok, job} =
             %{run_id: Ecto.UUID.generate()}
             |> CourierCMS.Execution.PlanRunWorker.new(max_attempts: 1)
             |> Oban.insert()

    now = DateTime.utc_now()

    Repo.update_all(
      from(saved in Oban.Job, where: saved.id == ^job.id),
      set: [state: "executing", attempt: 1, attempted_at: now, attempted_by: ["terminated"]]
    )

    assert {:ok, 1} = LocalRecovery.recover_orphaned_jobs()

    recovered = Repo.get!(Oban.Job, job.id)
    assert recovered.state == "available"
    assert recovered.attempt == 1
    assert recovered.max_attempts == 2
    assert recovered.attempted_by == []
  end

  test "a partially persisted plan resumes without duplicate items and advances its checkpoint once" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    assert {:ok, route} = Routes.update_schedule(scope, route, true, 5, "incremental", 1_440)

    route.source_connection
    |> Ecto.Changeset.change(settings: %{"fail_enumeration_at_cursor" => 2})
    |> Repo.update!()

    route = Routes.get_route!(scope, route.id)
    assert {:ok, run} = Execution.start_scheduled_run(route, ~U[2026-10-11 12:00:00Z])
    assert {:error, "Fake source enumeration failed"} = Execution.plan_run(run.id, 1, 3)

    assert Repo.aggregate(from(item in RunItem, where: item.run_id == ^run.id), :count) == 2
    refute Repo.get_by(Checkpoint, route_id: route.id)

    route.source_connection
    |> Ecto.Changeset.change(settings: %{})
    |> Repo.update!()

    assert :ok = Execution.plan_run(run.id, 2, 3)

    assert Repo.aggregate(from(item in RunItem, where: item.run_id == ^run.id), :count) == 3
    assert Repo.get_by!(Checkpoint, route_id: route.id).last_run_id == run.id
  end

  test "a stranded processing item is reconciled and duplicate execution stays idempotent" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)
    assert {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(run.id)

    [stranded | _remaining] =
      Repo.all(from(item in RunItem, where: item.run_id == ^run.id, order_by: item.id))

    Repo.delete_all(
      from(job in Oban.Job,
        where:
          job.worker == "CourierCMS.Execution.DeliveryWorker" and
            job.args["run_item_id"] == ^stranded.id
      )
    )

    stale_at = DateTime.add(DateTime.utc_now(), -2, :hour)

    stranded
    |> RunItem.changeset(%{status: :processing})
    |> Ecto.Changeset.force_change(:updated_at, stale_at)
    |> Repo.update!()

    previous = Application.get_env(:couriercms, :stranded_after_ms)
    Application.put_env(:couriercms, :stranded_after_ms, 60_000)
    on_exit(fn -> Application.put_env(:couriercms, :stranded_after_ms, previous) end)

    assert :ok = CourierCMS.Execution.ReconcileWorker.perform(%Oban.Job{args: %{"v" => 1}})
    assert Repo.get!(RunItem, stranded.id).status == :pending

    run.id
    |> run_items()
    |> Enum.each(&process_item/1)

    assert Execution.get_run!(scope, run.id).status == :succeeded
    assert :ok = Execution.process_run_item(stranded.id, 1, 3)
    assert Repo.aggregate(DeliveryBinding, :count) == 3
  end

  defp run_items(run_id) do
    Repo.all(from(item in RunItem, where: item.run_id == ^run_id, order_by: item.id))
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

  defp route_fixture(scope) do
    source = connection_fixture(scope, "Local source", "fake_source")
    target = connection_fixture(scope, "Local target", "fake_target")
    destination = destination_fixture(scope, target)

    {:ok, route} =
      Routes.create_route(
        scope,
        %{
          name: "Local reliability #{System.unique_integer([:positive])}",
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
      name: "#{name} #{System.unique_integer([:positive])}",
      adapter_key: adapter_key,
      extension_id: "com.couriercms.fake",
      component_id: adapter_key,
      endpoint: "https://#{adapter_key}.example",
      workspace_id: scope.workspace.id
    })
    |> Repo.insert!()
  end
end

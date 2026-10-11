defmodule CourierCMS.Execution.ServerBaselineTest do
  use CourierCMSWeb.ConnCase
  use Oban.Testing, repo: CourierCMS.Repo

  import Ecto.Query

  @moduletag :benchmark
  @moduletag timeout: 300_000
  @moduletag ownership_timeout: 300_000

  alias CourierCMS.Connections.Connection
  alias CourierCMS.Execution
  alias CourierCMS.Execution.{RunItem, Run}
  alias CourierCMS.Ownership.DeliveryBinding
  alias CourierCMS.Repo

  setup :register_and_log_in_user

  test "records a reproducible execution and operator-page baseline", %{
    conn: conn,
    scope: scope
  } do
    requested = System.get_env("COURIERCMS_BASELINE_ITEM_COUNT", "500") |> String.to_integer()
    item_count = min(max(requested, 100), 10_000)
    route = route_fixture(scope, item_count)

    assert {:ok, run} = Execution.start_manual_run(scope, route.id)

    {:ok, planning_ms, planning_queries} =
      measure(fn -> assert :ok = Execution.plan_run(run.id) end)

    items = Repo.all(from(item in RunItem, where: item.run_id == ^run.id))
    assert length(items) == item_count

    {:ok, delivery_ms, delivery_queries} =
      measure(fn ->
        Enum.each(items, fn item ->
          assert :ok = Execution.process_run_item(item.id, 1, 3)
        end)
      end)

    {%Run{status: :succeeded}, reconciliation_ms, reconciliation_queries} =
      measure(fn -> assert %Run{status: :succeeded} = Execution.reconcile_run(run.id) end)

    {{:ok, view, _html}, operator_page_ms, operator_page_queries} =
      measure(fn -> live(conn, ~p"/runs/#{run.id}") end)

    GenServer.stop(view.pid)

    destination_id = route.current_destination_id

    assert Repo.aggregate(
             from(binding in DeliveryBinding,
               where: binding.destination_id == ^destination_id
             ),
             :count
           ) == item_count

    metrics = %{
      profile: CourierCMS.ReleaseProfile.current(),
      items: item_count,
      planning_ms: planning_ms,
      planning_queries: planning_queries,
      delivery_ms: delivery_ms,
      delivery_queries: delivery_queries,
      delivery_items_per_second: Float.round(item_count * 1_000 / max(delivery_ms, 1), 2),
      reconciliation_ms: reconciliation_ms,
      reconciliation_queries: reconciliation_queries,
      operator_page_ms: operator_page_ms,
      operator_page_queries: operator_page_queries
    }

    IO.puts("COURIERCMS_BASELINE " <> Jason.encode!(metrics))

    if System.get_env("COURIERCMS_ENFORCE_BASELINE") == "true" do
      assert planning_queries <= threshold("COURIERCMS_MAX_PLANNING_QUERIES", 40)
      assert delivery_queries <= threshold("COURIERCMS_MAX_DELIVERY_QUERIES", 27_000)
      assert reconciliation_queries <= threshold("COURIERCMS_MAX_RECONCILIATION_QUERIES", 6)
      assert operator_page_queries <= threshold("COURIERCMS_MAX_OPERATOR_PAGE_QUERIES", 30)
      assert planning_ms <= threshold("COURIERCMS_MAX_PLANNING_MS", 2_000)
      assert delivery_ms <= threshold("COURIERCMS_MAX_DELIVERY_MS", 90_000)
      assert reconciliation_ms <= threshold("COURIERCMS_MAX_RECONCILIATION_MS", 1_000)
      assert operator_page_ms <= threshold("COURIERCMS_MAX_OPERATOR_PAGE_MS", 2_000)
    end
  end

  defp threshold(name, default) do
    name
    |> System.get_env(Integer.to_string(default))
    |> String.to_integer()
  end

  defp measure(fun) do
    owner = self()
    handler_id = "couriercms-baseline-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:courier_cms, :repo, :query],
        fn _event, _measurements, _metadata, pid -> send(pid, :baseline_query) end,
        owner
      )

    started_at = System.monotonic_time()

    try do
      result = fun.()
      elapsed = System.monotonic_time() - started_at
      {result, System.convert_time_unit(elapsed, :native, :millisecond), drain_queries(0)}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_queries(count) do
    receive do
      :baseline_query -> drain_queries(count + 1)
    after
      10 -> count
    end
  end

  defp route_fixture(scope, item_count) do
    source =
      connection_fixture(scope, "Baseline source", "fake_source", %{
        "synthetic_item_count" => item_count,
        "synthetic_page_size" => min(item_count, 1_000)
      })

    target = connection_fixture(scope, "Baseline target", "fake_target", %{})
    destination = destination_fixture(scope, target)

    {:ok, route} =
      CourierCMS.Routes.create_route(
        scope,
        %{
          name: "Baseline Route #{System.unique_integer([:positive])}",
          source_connection_id: source.id,
          target_connection_id: target.id,
          current_destination_id: destination.id,
          enabled: true
        },
        %{
          selection: CourierCMS.Adapters.Definition.default_selection("fake_source"),
          mapping: %{"title" => "fields.title", "body" => "fields.body"}
        }
      )

    route
  end

  defp connection_fixture(scope, name, adapter_key, settings) do
    %Connection{}
    |> Connection.changeset(%{
      name: "#{name} #{System.unique_integer([:positive])}",
      adapter_key: adapter_key,
      extension_id: "com.couriercms.fake",
      component_id: adapter_key,
      endpoint: "https://#{adapter_key}.example",
      settings: settings,
      workspace_id: scope.workspace.id
    })
    |> Repo.insert!()
  end
end

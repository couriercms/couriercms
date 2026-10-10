defmodule CourierCMS.Execution.PlannerLoadTest do
  use CourierCMS.DataCase
  use Oban.Testing, repo: CourierCMS.Repo

  @moduletag :load
  @moduletag timeout: 300_000
  @moduletag ownership_timeout: 300_000

  alias CourierCMS.Connections.Connection
  alias CourierCMS.Execution
  alias CourierCMS.Execution.{Run, RunItem}
  alias CourierCMS.Repo

  test "plans 10k to 100k identities with bounded pages and resumable state" do
    requested = System.get_env("COURIERCMS_LOAD_ITEM_COUNT", "10000") |> String.to_integer()
    count = min(max(requested, 10_000), 100_000)
    previous_limit = Application.get_env(:couriercms, :max_run_items)
    Application.put_env(:couriercms, :max_run_items, 100_000)
    on_exit(fn -> Application.put_env(:couriercms, :max_run_items, previous_limit) end)

    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope, count)

    assert {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(run.id)

    planned = Repo.get!(Run, run.id)
    assert planned.planning_complete
    assert planned.planning_cursor == nil
    assert planned.items_discovered == count
    assert planned.planning_page == Integer.ceil_div(count, 1_000)
    assert Repo.aggregate(from(item in RunItem, where: item.run_id == ^run.id), :count) == count
  end

  defp route_fixture(scope, count) do
    source =
      connection(scope, "fake_source", %{
        "synthetic_item_count" => count,
        "synthetic_page_size" => 1_000
      })

    target = connection(scope, "fake_target", %{})
    destination = destination_fixture(scope, target)

    {:ok, route} =
      CourierCMS.Routes.create_route(
        scope,
        %{
          name: "Load route #{System.unique_integer()}",
          source_connection_id: source.id,
          target_connection_id: target.id,
          current_destination_id: destination.id,
          enabled: true
        },
        %{
          selection: CourierCMS.Adapters.Definition.default_selection("fake_source"),
          mapping: CourierCMS.Routes.default_mapping("fake_source")
        }
      )

    route
  end

  defp connection(scope, adapter, settings) do
    %Connection{}
    |> Connection.changeset(%{
      name: "#{adapter} #{System.unique_integer()}",
      adapter_key: adapter,
      extension_id: "com.couriercms.fake",
      component_id: adapter,
      endpoint: "https://#{adapter}.example",
      settings: settings,
      workspace_id: scope.workspace.id
    })
    |> Repo.insert!()
  end
end

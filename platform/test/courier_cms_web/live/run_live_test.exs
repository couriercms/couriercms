defmodule CourierCMSWeb.RunLiveTest do
  use CourierCMSWeb.ConnCase
  use Oban.Testing, repo: CourierCMS.Repo

  alias CourierCMS.Connections.Connection
  alias CourierCMS.Execution
  alias CourierCMS.Repo

  setup :register_and_log_in_user

  test "loads the Run summary before a bounded Delivery Item page", %{conn: conn, scope: scope} do
    route = route_fixture(scope)
    {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(run.id)

    {:ok, view, html} = live(conn, ~p"/runs/#{run.id}")

    assert html =~ "Browse delivery items"
    refute html =~ ~s(id="run-item-)

    view
    |> element("#show-delivery-items")
    |> render_click()

    assert has_element?(view, "#delivery-items")
    assert length(Regex.scan(~r/<tr id="run-item-/, render(view))) == 2
    assert render(view) =~ "2 matching items"
  end

  test "filters Delivery Items in the database instead of in LiveView memory", %{
    conn: conn,
    scope: scope
  } do
    route = route_fixture(scope)
    {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(run.id)

    {:ok, view, _html} = live(conn, ~p"/runs/#{run.id}")

    view
    |> element("#show-all-items")
    |> render_click()

    view
    |> form("#run-item-filters", %{
      "filters" => %{"status" => "pending", "source" => "101"}
    })
    |> render_submit()

    assert length(Regex.scan(~r/<tr id="run-item-/, render(view))) == 1
    assert render(view) =~ "1 matching item."
    assert has_element?(view, "#delivery-items td", "101")
    refute has_element?(view, "#delivery-items td", "102")
  end

  defp route_fixture(scope) do
    source = connection_fixture(scope, "Run UI source", "fake_source")
    target = connection_fixture(scope, "Run UI target", "fake_target")
    destination = destination_fixture(scope, target)

    {:ok, route} =
      CourierCMS.Routes.create_route(
        scope,
        %{
          name: "Run UI test",
          source_connection_id: source.id,
          target_connection_id: target.id,
          current_destination_id: destination.id,
          enabled: true
        },
        %{
          selection: %{"category" => "Engineering", "tags" => ["architecture"]},
          mapping: CourierCMS.Routes.default_mapping("fake_source")
        }
      )

    route
  end

  defp connection_fixture(scope, name, adapter_key) do
    %Connection{}
    |> Connection.changeset(%{
      name: name,
      adapter_key: adapter_key,
      extension_id: "com.couriercms.fake",
      component_id: adapter_key,
      endpoint: "https://#{adapter_key}.example",
      settings: %{},
      workspace_id: scope.workspace.id
    })
    |> Repo.insert!()
  end
end

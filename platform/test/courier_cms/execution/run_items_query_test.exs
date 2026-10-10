defmodule CourierCMS.Execution.RunItemsQueryTest do
  use CourierCMS.DataCase
  use Oban.Testing, repo: CourierCMS.Repo

  alias CourierCMS.Connections.Connection
  alias CourierCMS.Execution
  alias CourierCMS.Repo

  test "returns bounded, filtered pages without preloading items on the Run" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)
    {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(run.id)

    summary = Execution.get_run!(scope, run.id)
    assert %Ecto.Association.NotLoaded{} = summary.items

    first = Execution.list_run_items(scope, run.id, page_size: 1)
    assert first.total_count == 2
    assert first.total_pages == 2
    assert first.page == 1
    assert length(first.items) == 1

    second = Execution.list_run_items(scope, run.id, page: 2, page_size: 1)
    assert second.page == 2
    assert length(second.items) == 1
    refute hd(first.items).id == hd(second.items).id

    capped = Execution.list_run_items(scope, run.id, page_size: 1_000)
    assert capped.page_size == 100

    filtered =
      Execution.list_run_items(scope, run.id,
        status: :pending,
        source_query: "101",
        page_size: 50
      )

    assert filtered.total_count == 1
    assert [%{source_item_key: "101"}] = filtered.items
  end

  defp route_fixture(scope) do
    source = connection_fixture(scope, "Query source", "fake_source")
    target = connection_fixture(scope, "Query target", "fake_target")
    destination = destination_fixture(scope, target)

    {:ok, route} =
      CourierCMS.Routes.create_route(
        scope,
        %{
          name: "Query test",
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

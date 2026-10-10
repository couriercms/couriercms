defmodule CourierCMSWeb.RoutesLiveTest do
  use CourierCMSWeb.ConnCase

  alias CourierCMS.Connections.Connection
  alias CourierCMS.Repo
  alias CourierCMS.Routes

  setup :register_and_log_in_user

  test "creates a Route from Adapter-owned selection and mapping definitions", %{
    conn: conn,
    scope: scope
  } do
    source = connection_fixture(scope, "Generic source", "fake_source")
    target = connection_fixture(scope, "Generic target", "fake_target")
    destination = destination_fixture(scope, target)
    {:ok, view, html} = live(conn, ~p"/routes")

    assert html =~ "Create Route"
    refute html =~ "Create WordPress posts Route"
    assert html =~ "Content type"
    assert html =~ "Published year"

    view
    |> form("#route-form", %{
      "route" => %{
        "name" => "Definition-driven Route",
        "source_connection_id" => source.id,
        "target_connection_id" => target.id,
        "current_destination_id" => destination.id,
        "enabled" => "true",
        "selection" => %{
          "content_type" => "post",
          "state" => "published",
          "category" => "Engineering",
          "tags" => "architecture, elixir",
          "published_year" => "2026"
        },
        "mapping" => "headline=fields.title\nslug=fields.slug",
        "projections" => ""
      }
    })
    |> render_submit()

    route = Enum.find(Routes.list_routes(scope), &(&1.name == "Definition-driven Route"))
    assert_redirect(view, ~p"/routes/#{route.id}")
    assert route.enabled
    assert route.current_revision.selection["tags"] == ["architecture", "elixir"]
    assert route.current_revision.mapping["headline"] == "fields.title"
  end

  test "rejects malformed mapping instead of silently dropping it", %{conn: conn, scope: scope} do
    source = connection_fixture(scope, "Strict source", "fake_source")
    target = connection_fixture(scope, "Strict target", "fake_target")
    destination = destination_fixture(scope, target)
    {:ok, view, _html} = live(conn, ~p"/routes")

    html =
      view
      |> form("#route-form", %{
        "route" => %{
          "name" => "Invalid Route",
          "source_connection_id" => source.id,
          "target_connection_id" => target.id,
          "current_destination_id" => destination.id,
          "enabled" => "false",
          "selection" => %{"content_type" => "post", "state" => "published"},
          "mapping" => "this line has no equals sign",
          "projections" => ""
        }
      })
      |> render_submit()

    assert html =~ "must use target_path=source_path"
    refute Enum.any?(Routes.list_routes(scope), &(&1.name == "Invalid Route"))
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

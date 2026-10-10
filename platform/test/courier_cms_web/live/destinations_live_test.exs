defmodule CourierCMSWeb.DestinationsLiveTest do
  use CourierCMSWeb.ConnCase

  alias CourierCMS.Connections.Connection
  alias CourierCMS.Destinations
  alias CourierCMS.Repo

  setup :register_and_log_in_user

  test "admin registers and validates a target-defined Destination", %{conn: conn, scope: scope} do
    target = connection_fixture(scope)
    {:ok, view, html} = live(conn, ~p"/destinations")

    assert html =~ "Register Destination"
    assert html =~ "Target namespace"

    view
    |> form("#destination-form", %{
      "destination" => %{
        "name" => "Articles intake",
        "target_connection_id" => target.id,
        "scope" => %{"namespace" => "articles"}
      }
    })
    |> render_submit()

    assert [destination] = Destinations.list_destinations(scope)
    assert destination.name == "Articles intake"
    assert destination.scope == %{"namespace" => "articles"}
    assert destination.lifecycle_status == :available
    assert destination.validation_status == :valid
    assert render(view) =~ "Articles intake"
  end

  defp connection_fixture(scope) do
    %Connection{}
    |> Connection.changeset(%{
      name: "Destination UI target",
      adapter_key: "fake_target",
      extension_id: "com.couriercms.fake",
      component_id: "fake_target",
      endpoint: "https://fake-target.example",
      settings: %{},
      workspace_id: scope.workspace.id
    })
    |> Repo.insert!()
  end
end

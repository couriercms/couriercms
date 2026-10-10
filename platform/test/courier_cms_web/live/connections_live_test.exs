defmodule CourierCMSWeb.ConnectionsLiveTest do
  use CourierCMSWeb.ConnCase

  alias CourierCMS.Connections

  setup :register_and_log_in_user

  test "renders Connection fields from the selected Adapter definition", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/connections")

    html =
      view
      |> form("#connection-form", %{
        "connection" => %{
          "name" => "Source",
          "adapter_key" => "wordpress",
          "endpoint" => "https://wordpress.example",
          "enabled" => "true"
        }
      })
      |> render_change()

    assert html =~ "Site URL"
    assert html =~ "Default locale"
    assert html =~ "Application Password"
    refute html =~ "Project robot token"

    html =
      view
      |> form("#connection-form", %{
        "connection" => %{
          "name" => "Target",
          "adapter_key" => "sanity",
          "enabled" => "true"
        }
      })
      |> render_change()

    assert html =~ "Project ID"
    assert html =~ "Dataset"
    assert html =~ "Project robot token"
    refute html =~ "Site URL"
  end

  test "creates a Connection from generic nested Adapter configuration", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _html} = live(conn, ~p"/connections")

    view
    |> form("#connection-form", %{
      "connection" => %{
        "name" => "Definition-driven Sanity",
        "adapter_key" => "sanity",
        "enabled" => "true"
      }
    })
    |> render_change()

    view
    |> form("#connection-form", %{
      "connection" => %{
        "name" => "Definition-driven Sanity",
        "adapter_key" => "sanity",
        "configuration" => %{
          "organization_id" => "org123",
          "project_id" => "project123",
          "dataset" => "production",
          "api_version" => "v2026-09-24"
        },
        "credential_values" => %{"token" => "dedicated-test-token"},
        "enabled" => "true"
      }
    })
    |> render_submit()

    connection =
      scope
      |> Connections.list_connections()
      |> Enum.find(&(&1.name == "Definition-driven Sanity"))

    assert connection.endpoint == "https://project123.api.sanity.io"
    assert connection.settings["dataset"] == "production"
    assert connection.credentials["token"] == "dedicated-test-token"
  end
end

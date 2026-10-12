defmodule CourierCMSWeb.RouteLiveTest do
  use CourierCMSWeb.ConnCase

  import Ecto.Query

  alias CourierCMS.Connections.Connection
  alias CourierCMS.Execution.Run
  alias CourierCMS.Repo
  alias CourierCMS.Routes

  setup :register_and_log_in_user

  test "operator can start a forced full redelivery", %{conn: conn, scope: scope} do
    route = route_fixture(scope)

    {:ok, view, _html} = live(conn, ~p"/routes/#{route.id}")

    assert has_element?(view, "#run-route", "Run full scan")
    assert has_element?(view, "#force-redelivery", "Force full redelivery")

    view
    |> element("#force-redelivery")
    |> render_click()

    run =
      Run
      |> where([run], run.route_id == ^route.id)
      |> order_by([run], desc: run.inserted_at)
      |> Repo.one!()

    assert_redirect(view, ~p"/runs/#{run.id}")
    assert run.trigger_kind == :manual
    assert run.trigger_metadata["delivery_mode"] == "force"
    assert run.initiated_by_user_id == scope.user.id
  end

  test "admin configures incremental polling and reconciliation", %{conn: conn, scope: scope} do
    route = route_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/routes/#{route.id}")

    view
    |> form("#schedule-form", %{
      "schedule" => %{
        "enabled" => "true",
        "interval_minutes" => "15",
        "polling_mode" => "incremental",
        "reconciliation_interval_minutes" => "10080"
      }
    })
    |> render_submit()

    schedule = Routes.get_route!(scope, route.id).current_revision.trigger_settings["schedule"]

    assert schedule == %{
             "enabled" => true,
             "interval_minutes" => 15,
             "polling_mode" => "incremental",
             "reconciliation_interval_minutes" => 10_080
           }
  end

  test "admin validates projections and previews the canonical document", %{
    conn: conn,
    scope: scope
  } do
    route = route_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/routes/#{route.id}")

    view
    |> form("#projections-form", %{
      "projections" => %{
        "definitions" => "projectedTitle=payload.title:string:required"
      }
    })
    |> render_submit()

    updated = Routes.get_route!(scope, route.id)
    assert updated.current_revision.contract_version == 2
    assert hd(updated.current_revision.projections)["target_field"] == "projectedTitle"

    view
    |> element("#preview-delivery")
    |> render_click()

    assert has_element?(view, "#delivery-preview")
    assert render(view) =~ "projectedTitle"
    assert render(view) =~ "Reliable content delivery with CourierCMS"
  end

  test "admin edits Route identity and activation without replacing its Destination", %{
    conn: conn,
    scope: scope
  } do
    route = route_fixture(scope)
    destination_id = route.current_destination_id
    {:ok, view, _html} = live(conn, ~p"/routes/#{route.id}")

    view
    |> form("#route-details-form", %{
      "route" => %{"name" => "Renamed content route", "enabled" => "false"}
    })
    |> render_submit()

    updated = Routes.get_route!(scope, route.id)
    assert updated.name == "Renamed content route"
    refute updated.enabled
    assert updated.current_destination_id == destination_id
  end

  test "admin configures readable Delivery Item naming", %{
    conn: conn,
    scope: scope
  } do
    route = route_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/routes/#{route.id}")

    assert has_element?(view, "#delivery-name-form")

    view
    |> form("#delivery-name-form", %{
      "delivery_name" => %{"path" => "payload.slug"}
    })
    |> render_submit()

    updated = Routes.get_route!(scope, route.id)
    assert updated.current_revision.delivery_name_path == "payload.slug"
    assert updated.current_destination_id == route.current_destination_id
  end

  test "admin previews and saves a strictly validated mapping as a new contract", %{
    conn: conn,
    scope: scope
  } do
    route = route_fixture(scope)
    original_revision = route.current_revision.revision_number
    original_contract = route.current_revision.contract_version
    {:ok, view, _html} = live(conn, ~p"/routes/#{route.id}")

    mapping = "headline=fields.title\nslug=fields.slug"

    view
    |> form("#mapping-form", %{"mapping" => %{"definitions" => mapping}})
    |> render_change()

    view
    |> element("#mapping-form button", "Preview draft")
    |> render_click()

    assert has_element?(view, "#delivery-preview")
    assert render(view) =~ "headline"

    view
    |> form("#mapping-form", %{"mapping" => %{"definitions" => mapping}})
    |> render_submit()

    updated = Routes.get_route!(scope, route.id)
    assert updated.current_revision.revision_number == original_revision + 1
    assert updated.current_revision.contract_version == original_contract + 1

    assert updated.current_revision.mapping == %{
             "headline" => "fields.title",
             "slug" => "fields.slug"
           }
  end

  test "malformed mapping is rejected without creating a Route Revision", %{
    conn: conn,
    scope: scope
  } do
    route = route_fixture(scope)
    revision_id = route.current_revision.id
    {:ok, view, _html} = live(conn, ~p"/routes/#{route.id}")

    html =
      view
      |> form("#mapping-form", %{
        "mapping" => %{"definitions" => "author=fields.author\nauthor.name=fields.title"}
      })
      |> render_submit()

    assert html =~ "conflicts with a nested target path"
    assert Routes.get_route!(scope, route.id).current_revision.id == revision_id
  end

  test "admin previews and saves ordered built-in transformations as a new contract", %{
    conn: conn,
    scope: scope
  } do
    route = route_fixture(scope)
    original_revision = route.current_revision.revision_number
    original_contract = route.current_revision.contract_version
    {:ok, view, _html} = live(conn, ~p"/routes/#{route.id}")

    definitions = "title=title|string.trim\nslug=title|string.slug"

    view
    |> form("#transformations-form", %{
      "transformations" => %{"definitions" => definitions}
    })
    |> render_change()

    view
    |> element("#transformations-form button", "Preview draft")
    |> render_click()

    assert has_element?(view, "#delivery-preview")
    assert render(view) =~ "reliable-content-delivery-with-couriercms"

    view
    |> form("#transformations-form", %{
      "transformations" => %{"definitions" => definitions}
    })
    |> render_submit()

    updated = Routes.get_route!(scope, route.id)
    assert updated.current_revision.revision_number == original_revision + 1
    assert updated.current_revision.contract_version == original_contract + 1

    assert Enum.map(updated.current_revision.transformations, & &1["operation"]) == [
             "string.trim",
             "string.slug"
           ]
  end

  test "admin previews and saves ordered Extension Processors as a new contract", %{
    conn: conn,
    scope: scope
  } do
    route = route_fixture(scope)
    original_revision = route.current_revision.revision_number
    original_contract = route.current_revision.contract_version
    {:ok, view, html} = live(conn, ~p"/routes/#{route.id}")

    assert html =~ "Extension Processors"
    assert html =~ "com.couriercms.fake/fake_prefix"
    assert html =~ "Configuration fields are declared and validated by the installed Extension"

    view
    |> form("#processor-builder-form", %{
      "processor_builder" => %{
        "reference" => "com.couriercms.fake/fake_prefix",
        "input_path" => "title",
        "output_path" => "title"
      },
      "processor_config" => %{}
    })
    |> render_change()

    view
    |> form("#processor-builder-form", %{
      "processor_builder" => %{
        "reference" => "com.couriercms.fake/fake_prefix",
        "input_path" => "title",
        "output_path" => "title"
      },
      "processor_config" => %{"prefix" => "Processed: ", "delay_ms" => "0"}
    })
    |> render_submit()

    assert Routes.get_route!(scope, route.id).current_revision.id == route.current_revision.id

    view
    |> element("#processors-form button", "Preview draft (no target write)")
    |> render_click()

    assert has_element?(view, "#delivery-preview")
    assert render(view) =~ "Processed: Reliable content delivery with CourierCMS"
    assert Routes.get_route!(scope, route.id).current_revision.id == route.current_revision.id

    view
    |> form("#processors-form")
    |> render_submit()

    updated = Routes.get_route!(scope, route.id)
    assert updated.current_revision.revision_number == original_revision + 1
    assert updated.current_revision.contract_version == original_contract + 1
    assert [processor] = updated.current_revision.processors
    assert processor["component_id"] == "fake_prefix"
    assert processor["component_version"] == "0.1.0"
    assert processor["config"] == %{"prefix" => "Processed: ", "delay_ms" => 0}
  end

  test "guided Processor editor renders Extension-owned typed configuration", %{
    conn: conn,
    scope: scope
  } do
    route = route_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/routes/#{route.id}")

    html =
      view
      |> form("#processor-builder-form", %{
        "processor_builder" => %{
          "reference" => "com.couriercms.content/html_text_normalizer",
          "input_path" => "body.value",
          "output_path" => "body.value"
        },
        "processor_config" => %{}
      })
      |> render_change()

    assert html =~ "Normalize line endings"
    assert html =~ "Remove control characters"
    assert html =~ "Replace non-breaking spaces"
    assert html =~ "Trim surrounding whitespace"
  end

  test "admin reorders and removes Processor draft steps without changing the Route", %{
    conn: conn,
    scope: scope
  } do
    route = route_fixture(scope)
    revision_id = route.current_revision.id
    {:ok, view, _html} = live(conn, ~p"/routes/#{route.id}")

    definitions =
      Enum.join(
        [
          ~s(title=title|com.couriercms.fake/fake_prefix|{"prefix":"Title: "}),
          ~s(slug=slug|com.couriercms.fake/fake_prefix|{"prefix":"Slug: "})
        ],
        "\n"
      )

    view
    |> form("#processors-form", %{"processors" => %{"definitions" => definitions}})
    |> render_change()

    assert has_element?(view, "#draft-processor-0", "title → title")
    assert has_element?(view, "#draft-processor-1", "slug → slug")

    view
    |> element("#draft-processor-1 button", "Up")
    |> render_click()

    assert has_element?(view, "#draft-processor-0", "slug → slug")

    view
    |> element("#draft-processor-1 button", "Remove")
    |> render_click()

    assert has_element?(view, "#processor-draft-steps", "1 steps")
    refute has_element?(view, "#draft-processor-1")
    assert Routes.get_route!(scope, route.id).current_revision.id == revision_id
  end

  test "admin previews an Adapter-defined selection before saving it", %{conn: conn, scope: scope} do
    route = route_fixture(scope)
    revision_id = route.current_revision.id
    {:ok, view, _html} = live(conn, ~p"/routes/#{route.id}")

    view
    |> form("#selection-form", %{
      "selection" => %{
        "content_type" => "post",
        "state" => "published",
        "category" => "Marketing",
        "tags" => "",
        "published_year" => ""
      }
    })
    |> render_change()

    view
    |> element("#selection-form button", "Preview draft")
    |> render_click()

    assert has_element?(view, "#delivery-preview")
    assert render(view) =~ "Autumn campaign launch"
    assert Routes.get_route!(scope, route.id).current_revision.id == revision_id
  end

  defp route_fixture(scope) do
    source = connection_fixture(scope, "Route UI source", "fake_source")
    target = connection_fixture(scope, "Route UI target", "fake_target")
    destination = destination_fixture(scope, target)

    {:ok, route} =
      CourierCMS.Routes.create_route(
        scope,
        %{
          name: "Route UI test",
          source_connection_id: source.id,
          target_connection_id: target.id,
          current_destination_id: destination.id,
          enabled: true
        },
        %{
          selection: %{"category" => "Engineering"},
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

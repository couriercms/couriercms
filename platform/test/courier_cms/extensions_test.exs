defmodule CourierCMS.ExtensionsTest do
  use CourierCMS.DataCase

  alias CourierCMS.Connections.Connection
  alias CourierCMS.Execution.WorkerHeartbeat
  alias CourierCMS.{Extensions, Repo, Routes}

  test "operator inventory exposes registered components and durable references" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    assert {:ok, inventory} = Extensions.operator_inventory(scope)
    fake = Enum.find(inventory.extensions, &(&1.extension_id == "com.couriercms.fake"))

    assert fake.status == :loaded
    assert Enum.map(fake.components, & &1.id) == ["fake_source", "fake_target"]
    assert fake.references.connections >= 2
    assert fake.references.enabled_connections >= 2
    assert fake.references.routes >= 1
    assert fake.references.active_routes >= 1
    assert fake.references.unfinished_runs == 0
    assert route.enabled
  end

  test "inventory requires an owner or administrator" do
    scope = CourierCMS.AccountsFixtures.user_fixture(%{role: :viewer})
    scope = CourierCMS.Accounts.scope_for_user(scope)

    assert {:error, :forbidden} = Extensions.operator_inventory(scope)
  end

  test "inventory flags a referenced component missing from a loaded Extension" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()

    %Connection{}
    |> Connection.changeset(%{
      name: "Missing component #{System.unique_integer()}",
      adapter_key: "removed_component",
      extension_id: "com.couriercms.fake",
      component_id: "removed_component",
      endpoint: "https://missing-component.example",
      workspace_id: scope.workspace.id,
      enabled: false
    })
    |> Repo.insert!()

    assert {:ok, inventory} = Extensions.operator_inventory(scope)
    fake = Enum.find(inventory.extensions, &(&1.extension_id == "com.couriercms.fake"))

    assert fake.status == :incomplete
    assert Enum.any?(fake.components, &(&1.id == "removed_component" and not &1.available))
  end

  test "removal guard blocks enabled references and permits retained disabled history" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    extension_id = "com.example.removal#{System.unique_integer([:positive])}"

    connection =
      %Connection{}
      |> Connection.changeset(%{
        name: "Removal guard #{System.unique_integer()}",
        adapter_key: "removal_guard",
        extension_id: extension_id,
        component_id: "removal_guard",
        endpoint: "https://removal.example",
        workspace_id: scope.workspace.id
      })
      |> Repo.insert!()

    assert_raise ArgumentError, ~r/1 enabled Connection/, fn ->
      Extensions.assert_removable!(extension_id)
    end

    connection |> Ecto.Changeset.change(enabled: false) |> Repo.update!()
    assert :ok = Extensions.assert_removable!(extension_id)
  end

  test "cluster status identifies a fresh node with a different package set" do
    local = Extensions.runtime_snapshot()
    now = DateTime.utc_now()

    Repo.insert_all(WorkerHeartbeat, [
      %{
        node_id: "matching-node",
        role: "worker",
        queues: ["delivery"],
        version: "0.1.0",
        extension_fingerprint: local.fingerprint,
        extension_set: local.artifacts,
        extension_status: "ok",
        last_seen_at: now,
        inserted_at: now,
        updated_at: now
      },
      %{
        node_id: "mismatched-node",
        role: "worker",
        queues: ["delivery"],
        version: "0.1.0",
        extension_fingerprint: String.duplicate("0", 64),
        extension_set: [],
        extension_status: "ok",
        last_seen_at: now,
        inserted_at: now,
        updated_at: now
      }
    ])

    status = Extensions.cluster_status()

    refute status.consistent?
    assert Enum.any?(status.fresh_nodes, &(&1.node_id == "matching-node" and &1.matches_local))
    assert Enum.map(status.mismatched_nodes, & &1.node_id) == ["mismatched-node"]

    assert_raise RuntimeError, ~r/fresh node mismatched-node has a different/, fn ->
      Extensions.verify_runtime!()
    end
  end

  defp route_fixture(scope) do
    source = connection_fixture(scope, "Extension source", "fake_source")
    target = connection_fixture(scope, "Extension target", "fake_target")
    destination = destination_fixture(scope, target)

    {:ok, route} =
      Routes.create_route(
        scope,
        %{
          name: "Extension references #{System.unique_integer()}",
          source_connection_id: source.id,
          target_connection_id: target.id,
          current_destination_id: destination.id,
          enabled: true
        },
        %{
          selection: %{"content_type" => "post", "state" => "published"},
          mapping: Routes.default_mapping("fake_source")
        }
      )

    route
  end

  defp connection_fixture(scope, name, component_id) do
    %Connection{}
    |> Connection.changeset(%{
      name: "#{name} #{System.unique_integer()}",
      adapter_key: component_id,
      extension_id: "com.couriercms.fake",
      component_id: component_id,
      endpoint: "https://#{component_id}.example",
      workspace_id: scope.workspace.id
    })
    |> Repo.insert!()
  end
end

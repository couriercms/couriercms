alias CourierCMS.Connections.Connection
alias CourierCMS.Destinations.Destination
alias CourierCMS.Extensions.Gateway
alias CourierCMS.Repo
alias CourierCMS.Routes.Route

{:ok, workspace} = CourierCMS.Workspaces.ensure_default_workspace()

if owner_email = System.get_env("COURIERCMS_BOOTSTRAP_OWNER_EMAIL") do
  case CourierCMS.Accounts.bootstrap_owner(owner_email) do
    {:ok, _membership} -> :ok
    {:error, :owner_already_exists} -> :ok
    {:error, reason} -> raise "Could not bootstrap owner: #{inspect(reason)}"
  end
end

source =
  Repo.get_by(Connection, name: "Demo Blog Source") ||
    %Connection{}
    |> Connection.changeset(%{
      name: "Demo Blog Source",
      adapter_key: "fake_source",
      extension_id: "com.couriercms.fake",
      component_id: "fake_source",
      endpoint: "https://fake-source.couriercms.local",
      settings: %{},
      workspace_id: workspace.id,
      capabilities: Gateway.source("fake_source", :capabilities, [%{}])
    })
    |> Repo.insert!()

target =
  Repo.get_by(Connection, name: "Demo Destination") ||
    %Connection{}
    |> Connection.changeset(%{
      name: "Demo Destination",
      adapter_key: "fake_target",
      extension_id: "com.couriercms.fake",
      component_id: "fake_target",
      endpoint: "https://fake-target.couriercms.local",
      settings: %{"fail_once_for" => ["102"]},
      workspace_id: workspace.id,
      capabilities: Gateway.target("fake_target", :capabilities, [%{}])
    })
    |> Repo.insert!()

destination =
  Repo.get_by(Destination, name: "Demo Delivery Scope") ||
    case CourierCMS.Destinations.create_seed_destination(workspace.id, %{
           name: "Demo Delivery Scope",
           target_connection_id: target.id,
           scope: %{"namespace" => "couriercms-demo"}
         }) do
      {:ok, destination} -> destination
      {:error, reason} -> raise "Could not create demo Destination: #{inspect(reason)}"
    end

unless Repo.get_by(Route, name: "Engineering posts") do
  {:ok, _route} =
    CourierCMS.Routes.create_seed_route(
      workspace.id,
      %{
        name: "Engineering posts",
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
        mapping: CourierCMS.Routes.default_mapping("fake_source")
      }
    )
end

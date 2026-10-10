defmodule CourierCMS.Execution.ConnectionLimiterTest do
  use CourierCMS.DataCase

  alias CourierCMS.Connections.Connection
  alias CourierCMS.Execution.{ConnectionLimiter, OutboundRateLimiter}

  test "connection concurrency is coordinated through database leases" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()

    connection =
      %Connection{}
      |> Connection.changeset(%{
        name: "Limited source",
        adapter_key: "fake_source",
        extension_id: "com.couriercms.fake",
        component_id: "fake_source",
        endpoint: "https://source.example",
        settings: %{"max_concurrency" => 1},
        workspace_id: scope.workspace.id
      })
      |> Repo.insert!()

    first_owner = Ecto.UUID.generate()
    second_owner = Ecto.UUID.generate()

    assert {:ok, lease} = ConnectionLimiter.acquire(connection, first_owner, 60_000)
    assert :busy = ConnectionLimiter.acquire(connection, second_owner, 60_000)
    assert :ok = ConnectionLimiter.release(lease, first_owner)
    assert {:ok, _lease} = ConnectionLimiter.acquire(connection, second_owner, 60_000)
  end

  test "request rate is coordinated cluster-wide through a PostgreSQL bucket" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()

    connection =
      %Connection{}
      |> Connection.changeset(%{
        name: "Rate source",
        adapter_key: "fake_source",
        extension_id: "com.couriercms.fake",
        component_id: "fake_source",
        endpoint: "https://source.example",
        settings: %{"requests_per_second" => 1},
        workspace_id: scope.workspace.id
      })
      |> Repo.insert!()

    previous = Application.get_env(:couriercms, :outbound_rate_limiting)
    Application.put_env(:couriercms, :outbound_rate_limiting, true)
    on_exit(fn -> Application.put_env(:couriercms, :outbound_rate_limiting, previous) end)

    assert :ok = OutboundRateLimiter.check(connection)
    results = Enum.map(1..5, fn _index -> OutboundRateLimiter.check(connection) end)
    assert {:error, error} = Enum.find(results, &match?({:error, _error}, &1))
    assert error.category == :rate_limited
    assert error.retry_after_ms in 1..1_000
  end
end

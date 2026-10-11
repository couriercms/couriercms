defmodule CourierCMS.ReleaseProfileTest do
  use ExUnit.Case, async: true

  alias CourierCMS.ReleaseProfile

  test "the compiled profile exposes one coherent capability set" do
    assert ReleaseProfile.local?() != ReleaseProfile.server?()

    actual =
      {ReleaseProfile.current(), ReleaseProfile.identity_mode(),
       ReleaseProfile.connector_ingress?(), ReleaseProfile.scheduling_mode(),
       ReleaseProfile.topology()}

    assert actual in [
             {:local, :implicit_local_operator, false, :while_running, :single_instance},
             {:server, :authenticated_users, true, :continuous, :distributed}
           ]
  end

  test "the storage and job engine match the compiled profile" do
    oban = Application.fetch_env!(:couriercms, Oban)

    actual =
      {ReleaseProfile.current(), CourierCMS.Repo.__adapter__(), oban[:engine], oban[:notifier]}

    assert actual in [
             {:local, Ecto.Adapters.SQLite3, Oban.Engines.Lite, Oban.Notifiers.Isolated},
             {:server, Ecto.Adapters.Postgres, Oban.Engines.Basic, Oban.Notifiers.Postgres}
           ]
  end

  test "connector ingress is only compiled into the Server router" do
    connector_ingress? =
      Enum.any?(CourierCMSWeb.Router.__routes__(), fn route ->
        route.verb == :post and route.path == "/api/connectors/:connection_id/events"
      end)

    assert {ReleaseProfile.current(), connector_ingress?} in [
             {:local, false},
             {:server, true}
           ]
  end

  test "Local is single-process while Server also permits split roles" do
    assert ReleaseProfile.validate_deployment_role!(:all) == :all

    result =
      try do
        {:ok, ReleaseProfile.validate_deployment_role!(:worker)}
      rescue
        error in ArgumentError -> {:error, error.message}
      end

    assert {ReleaseProfile.current(), result} in [
             {:local,
              {:error, "deployment role :worker is not supported by the local release profile"}},
             {:server, {:ok, :worker}}
           ]
  end
end

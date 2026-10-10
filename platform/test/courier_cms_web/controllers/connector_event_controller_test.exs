defmodule CourierCMSWeb.ConnectorEventControllerTest do
  use CourierCMSWeb.ConnCase, async: true

  alias CourierCMS.Connectors
  alias CourierCMS.Connectors.ConnectorEvent
  alias CourierCMS.Connectors.ConnectorEventWorker
  alias CourierCMS.Connections
  alias CourierCMS.Connections.Connection
  alias CourierCMS.Repo

  setup %{conn: conn} do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()

    {:ok, connection} =
      %Connection{}
      |> Connection.changeset(%{
        name: "Webhook WordPress",
        adapter_key: "wordpress",
        extension_id: "com.couriercms.wordpress",
        component_id: "wordpress",
        endpoint: "https://wordpress.example",
        default_locale: "en-CA",
        workspace_id: scope.workspace.id
      })
      |> Repo.insert()

    {:ok, connection, secret} = Connections.configure_connector(scope, connection)

    %{conn: conn, scope: scope, connection: connection, secret: secret}
  end

  test "accepts, authenticates, and deduplicates a publish event", %{
    conn: conn,
    connection: connection,
    secret: secret
  } do
    body =
      Jason.encode!(%{
        "contract_version" => 1,
        "event_id" => "de305d54-75b4-431b-adb2-eb6b9e546014",
        "event" => "content.published",
        "source_item_id" => "101",
        "source_modified_at" => "2026-09-24T20:00:00Z"
      })

    timestamp = Integer.to_string(System.system_time(:second))
    signature = signature(secret, timestamp, body)
    path = "/api/connectors/#{connection.id}/events"

    accepted =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-couriercms-timestamp", timestamp)
      |> put_req_header("x-couriercms-signature", signature)
      |> post(path, body)

    assert %{"status" => "accepted"} = json_response(accepted, 202)
    assert Repo.aggregate(ConnectorEvent, :count) == 1
    assert Repo.aggregate(Oban.Job, :count) == 1

    duplicate =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-couriercms-timestamp", timestamp)
      |> put_req_header("x-couriercms-signature", signature)
      |> post(path, body)

    assert %{"status" => "duplicate"} = json_response(duplicate, 200)
    assert Repo.aggregate(ConnectorEvent, :count) == 1
    assert Repo.aggregate(Oban.Job, :count) == 1
  end

  test "rejects an invalid signature without storing the event", %{
    conn: conn,
    connection: connection
  } do
    body =
      Jason.encode!(%{
        "contract_version" => 1,
        "event_id" => "event-123",
        "event" => "content.updated",
        "source_item_id" => "101"
      })

    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-couriercms-timestamp", Integer.to_string(System.system_time(:second)))
      |> put_req_header("x-couriercms-signature", "sha256=" <> String.duplicate("0", 64))
      |> post("/api/connectors/#{connection.id}/events", body)

    assert %{"error" => "invalid_signature"} = json_response(response, 401)
    assert Repo.aggregate(ConnectorEvent, :count) == 0
  end

  test "rejects an unsupported connector contract version clearly", %{
    conn: conn,
    connection: connection,
    secret: secret
  } do
    body =
      Jason.encode!(%{
        "contract_version" => 2,
        "event_id" => "unsupported-version-event",
        "event" => "content.updated",
        "source_item_id" => "101"
      })

    timestamp = Integer.to_string(System.system_time(:second))

    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-couriercms-timestamp", timestamp)
      |> put_req_header("x-couriercms-signature", signature(secret, timestamp, body))
      |> post("/api/connectors/#{connection.id}/events", body)

    assert json_response(response, 422) == %{
             "error" => "unsupported_contract_version",
             "supported_versions" => [1]
           }

    assert Repo.aggregate(ConnectorEvent, :count) == 0
  end

  test "rolls back the Connector Event when Oban insertion fails", %{
    connection: connection,
    secret: secret
  } do
    params = %{
      "contract_version" => 1,
      "event_id" => "atomic-acceptance-event",
      "event" => "content.updated",
      "source_item_id" => "101"
    }

    body = Jason.encode!(params)
    timestamp = Integer.to_string(System.system_time(:second))

    failing_job_builder = fn event ->
      event.id
      |> then(&CourierCMS.Execution.JobArgs.put(%{"event_id" => &1}))
      |> ConnectorEventWorker.new()
      |> Ecto.Changeset.add_error(:worker, "forced test failure")
    end

    assert {:error, :enqueue_failed} =
             Connectors.accept_event(
               connection.id,
               timestamp,
               signature(secret, timestamp, body),
               body,
               params,
               job_builder: failing_job_builder
             )

    assert Repo.aggregate(ConnectorEvent, :count) == 0
    assert Repo.aggregate(Oban.Job, :count) == 0
  end

  test "a duplicate request repairs a legacy accepted event without a job", %{
    conn: conn,
    connection: connection,
    secret: secret
  } do
    event_id = "stranded-duplicate-event"

    %ConnectorEvent{}
    |> ConnectorEvent.changeset(%{
      contract_version: 1,
      connection_id: connection.id,
      external_event_id: event_id,
      event_kind: "content.updated",
      source_item_key: "101",
      status: :accepted,
      received_at: DateTime.utc_now()
    })
    |> Repo.insert!()

    body =
      Jason.encode!(%{
        "contract_version" => 1,
        "event_id" => event_id,
        "event" => "content.updated",
        "source_item_id" => "101"
      })

    timestamp = Integer.to_string(System.system_time(:second))

    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-couriercms-timestamp", timestamp)
      |> put_req_header("x-couriercms-signature", signature(secret, timestamp, body))
      |> post("/api/connectors/#{connection.id}/events", body)

    assert %{"status" => "duplicate"} = json_response(response, 200)
    assert Repo.aggregate(ConnectorEvent, :count) == 1
    assert Repo.aggregate(Oban.Job, :count) == 1
  end

  test "rejects CMS-native event fields at the generic boundary", %{
    conn: conn,
    connection: connection,
    secret: secret
  } do
    body =
      Jason.encode!(%{
        "contract_version" => 1,
        "event_id" => "native-wordpress-event",
        "event" => "post.updated",
        "post_id" => 101
      })

    timestamp = Integer.to_string(System.system_time(:second))

    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-couriercms-timestamp", timestamp)
      |> put_req_header("x-couriercms-signature", signature(secret, timestamp, body))
      |> post("/api/connectors/#{connection.id}/events", body)

    assert %{"error" => "invalid_event"} = json_response(response, 422)
    assert Repo.aggregate(ConnectorEvent, :count) == 0
  end

  test "rejects a Connection whose Adapter does not declare a Connector", %{
    conn: conn,
    scope: scope
  } do
    {:ok, connection} =
      %Connection{}
      |> Connection.changeset(%{
        name: "Source without Connector",
        adapter_key: "fake_source",
        extension_id: "com.couriercms.fake",
        component_id: "fake_source",
        endpoint: "https://source.example",
        default_locale: "en-CA",
        workspace_id: scope.workspace.id
      })
      |> Repo.insert()

    body =
      Jason.encode!(%{
        "contract_version" => 1,
        "event_id" => "event-for-non-connector",
        "event" => "content.updated",
        "source_item_id" => "101"
      })

    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/api/connectors/#{connection.id}/events", body)

    assert %{"error" => "connector_not_found"} = json_response(response, 404)
    assert Repo.aggregate(ConnectorEvent, :count) == 0
  end

  test "accepts the previous signing secret during the rotation grace period", %{
    conn: conn,
    scope: scope,
    connection: connection,
    secret: previous_secret
  } do
    assert {:ok, connection, new_secret} =
             Connections.configure_connector(scope, connection)

    refute new_secret == previous_secret

    body =
      Jason.encode!(%{
        "contract_version" => 1,
        "event_id" => "rotated-secret-event",
        "event" => "content.updated",
        "source_item_id" => "101"
      })

    timestamp = Integer.to_string(System.system_time(:second))

    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-couriercms-timestamp", timestamp)
      |> put_req_header("x-couriercms-signature", signature(previous_secret, timestamp, body))
      |> post("/api/connectors/#{connection.id}/events", body)

    assert %{"status" => "accepted"} = json_response(response, 202)
  end

  defp signature(secret, timestamp, body) do
    digest = :crypto.mac(:hmac, :sha256, secret, timestamp <> "." <> body)
    "sha256=" <> Base.encode16(digest, case: :lower)
  end
end

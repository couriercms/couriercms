defmodule CourierCMSWeb.HealthControllerTest do
  use CourierCMSWeb.ConnCase

  alias CourierCMS.Execution.WorkerHeartbeat
  alias CourierCMS.Repo

  test "GET /health/live reports process liveness", %{conn: conn} do
    conn = get(conn, ~p"/health/live")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end

  test "GET /health/ready verifies the database and migrations", %{conn: conn} do
    conn = get(conn, ~p"/health/ready")
    assert json_response(conn, 200) == %{"status" => "ready"}
  end

  test "GET /health/ready reports a fresh Extension package-set mismatch", %{conn: conn} do
    previous = Application.get_env(:couriercms, :require_extension_consistency)
    Application.put_env(:couriercms, :require_extension_consistency, true)
    on_exit(fn -> Application.put_env(:couriercms, :require_extension_consistency, previous) end)

    now = DateTime.utc_now()

    Repo.insert_all(WorkerHeartbeat, [
      %{
        node_id: "incompatible-worker",
        role: "worker",
        queues: ["delivery"],
        version: "0.1.0",
        extension_fingerprint: String.duplicate("f", 64),
        extension_set: [],
        extension_status: "ok",
        last_seen_at: now,
        inserted_at: now,
        updated_at: now
      }
    ])

    conn = get(conn, ~p"/health/ready")

    assert json_response(conn, 503) == %{
             "status" => "not_ready",
             "reason" => "extension_set_mismatch"
           }
  end

  test "GET /metrics exports Prometheus queue and worker gauges", %{conn: conn} do
    conn = conn |> put_req_header("accept", "text/plain") |> get(~p"/metrics")
    body = response(conn, 200)

    assert body =~ "couriercms_worker_fresh"
    assert body =~ "couriercms_queue_depth"
    assert body =~ "couriercms_extension_mismatched_nodes"
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
  end

  test "GET /metrics requires its bearer token when public metrics are disabled", %{conn: conn} do
    token = String.duplicate("m", 32)
    old_token = Application.get_env(:couriercms, :metrics_token)
    old_public = Application.get_env(:couriercms, :allow_unauthenticated_metrics)
    Application.put_env(:couriercms, :metrics_token, token)
    Application.put_env(:couriercms, :allow_unauthenticated_metrics, false)

    on_exit(fn ->
      Application.put_env(:couriercms, :metrics_token, old_token)
      Application.put_env(:couriercms, :allow_unauthenticated_metrics, old_public)
    end)

    assert conn |> get(~p"/metrics") |> response(401) == "unauthorized\n"

    body =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("accept", "text/plain")
      |> get(~p"/metrics")
      |> response(200)

    assert body =~ "couriercms_queue_depth"
  end
end

defmodule CourierCMS.ReleaseTest do
  use CourierCMS.DataCase

  test "worker health verifies the supervised worker runtime and database" do
    start_supervised!(CourierCMS.Execution.WorkerHeartbeat)
    assert :ok = CourierCMS.Release.worker_health!()
  end
end

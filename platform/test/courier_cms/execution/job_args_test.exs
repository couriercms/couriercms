defmodule CourierCMS.Execution.JobArgsTest do
  use ExUnit.Case, async: true

  alias CourierCMS.Execution.JobArgs

  test "accepts the current and legacy unversioned job formats" do
    assert JobArgs.put(%{"run_id" => "run"}) == %{"run_id" => "run", "v" => 2}
    assert :ok = JobArgs.validate(%{"v" => 1})
    assert :ok = JobArgs.validate(%{"v" => 2})
    assert :ok = JobArgs.validate(%{"run_id" => "legacy"})
  end

  test "discards future or malformed versions without executing them" do
    assert {:discard, _reason} = JobArgs.validate(%{"v" => 3})
    assert {:discard, _reason} = JobArgs.validate(%{"v" => "1"})
  end
end

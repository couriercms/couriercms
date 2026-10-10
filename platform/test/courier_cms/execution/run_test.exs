defmodule CourierCMS.Execution.RunTest do
  use ExUnit.Case, async: true

  alias CourierCMS.Execution.Run

  test "rejects negative counters and unsupported triggers" do
    changeset =
      Run.changeset(%Run{}, %{
        route_id: Ecto.UUID.generate(),
        route_revision_id: Ecto.UUID.generate(),
        trigger_kind: :unknown,
        status: :queued,
        items_discovered: -1
      })

    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :trigger_kind)
    assert Keyword.has_key?(changeset.errors, :items_discovered)
  end
end

defmodule CourierCMS.Routes.RouteTest do
  use ExUnit.Case, async: true

  alias CourierCMS.Routes.{Route, RouteRevision}

  test "requires different source and target Connections" do
    connection_id = Ecto.UUID.generate()

    changeset =
      Route.changeset(%Route{}, %{
        name: "Engineering blog",
        source_connection_id: connection_id,
        target_connection_id: connection_id
      })

    refute changeset.valid?

    assert {"must be different from the source connection", _opts} =
             changeset.errors[:target_connection_id]
  end

  test "requires positive Route and contract revision numbers" do
    changeset =
      RouteRevision.changeset(%RouteRevision{}, %{
        route_id: Ecto.UUID.generate(),
        revision_number: 0,
        contract_version: 0,
        checksum: "sha256:test"
      })

    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :revision_number)
    assert Keyword.has_key?(changeset.errors, :contract_version)
  end
end

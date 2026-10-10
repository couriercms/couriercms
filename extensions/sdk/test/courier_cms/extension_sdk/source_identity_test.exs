defmodule CourierCMS.ExtensionSDK.SourceIdentityTest do
  use ExUnit.Case, async: true

  alias CourierCMS.ExtensionSDK.SourceIdentity

  test "normalizes atom-keyed identity and produces a stable route delivery key" do
    attrs = %{
      item_key: "post-101",
      locale_key: "en",
      revision_key: "15",
      state: :published,
      modified_at: ~U[2026-09-24 14:00:00Z],
      change_token: "aggregate-v15"
    }

    assert {:ok, identity} = SourceIdentity.new(attrs)
    route_id = "9f10c9bd-b4de-4bfd-88e0-2fc86e4bf652"

    assert SourceIdentity.delivery_key(identity, route_id) ==
             SourceIdentity.delivery_key(identity, route_id)

    assert SourceIdentity.delivery_key(identity, route_id) ==
             SourceIdentity.delivery_key(%{identity | revision_key: "16"}, route_id)

    assert SourceIdentity.delivery_key(identity, route_id) ==
             SourceIdentity.delivery_key(%{identity | change_token: "aggregate-v16"}, route_id)

    refute SourceIdentity.delivery_key(identity, route_id) ==
             SourceIdentity.delivery_key(%{identity | locale_key: "fr"}, route_id)
  end

  test "accepts string-keyed adapter data" do
    assert {:ok, identity} =
             SourceIdentity.new(%{
               "item_key" => "101",
               "locale_key" => "en",
               "revision_key" => "15",
               "state" => :saved
             })

    assert identity.state == :saved
  end

  test "rejects missing, blank, and unsupported identity values" do
    assert {:error, errors} =
             SourceIdentity.new(%{
               item_key: " ",
               locale_key: nil,
               revision_key: "15",
               state: :deleted
             })

    assert {:item_key, "must not be empty"} in errors
    assert {:locale_key, "must be a string"} in errors
    assert {:state, "must be saved or published"} in errors

    assert {:error, [change_token: "must be a string"]} =
             SourceIdentity.new(%{
               item_key: "101",
               locale_key: "en",
               revision_key: "15",
               state: :published,
               change_token: 15
             })
  end
end

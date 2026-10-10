defmodule CourierCMS.ExtensionSDK.ComponentTest do
  use ExUnit.Case, async: true

  alias CourierCMS.ExtensionSDK.Component

  test "builds a stable component identity" do
    assert {:ok, component} =
             Component.new(
               extension_id: "com.couriercms.wordpress",
               component_id: "wordpress",
               kind: :adapter,
               version: "1.2.3",
               capabilities: [:source, :incremental_changes]
             )

    assert Component.key(component) == {"com.couriercms.wordpress", "wordpress"}
  end

  test "rejects unnamespaced extension IDs and versioned component IDs" do
    assert {:error, _reason} =
             Component.new(
               extension_id: "wordpress",
               component_id: "wordpress_v1.0.0",
               kind: :adapter,
               version: "latest"
             )
  end
end

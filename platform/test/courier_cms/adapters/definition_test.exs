defmodule CourierCMS.Adapters.DefinitionTest do
  use ExUnit.Case, async: true

  alias CourierCMS.Adapters.Definition
  alias CourierCMS.Extensions.Gateway

  test "every registered Adapter exposes a valid definition" do
    assert definitions = Gateway.definitions()
    assert length(definitions) == 4
    assert Enum.all?(definitions, &(Definition.validate(&1) == :ok))

    assert Enum.sort(Enum.map(definitions, & &1.key)) ==
             ~w(fake_source fake_target sanity wordpress)
  end

  test "every bundled Adapter has stable Extension component identity" do
    components = Gateway.components()

    assert Enum.map(components, &{&1.extension_id, &1.component_id}) == [
             {"com.couriercms.fake", "fake_source"},
             {"com.couriercms.fake", "fake_target"},
             {"com.couriercms.sanity", "sanity"},
             {"com.couriercms.wordpress", "wordpress"}
           ]

    assert {:ok, wordpress} = Gateway.fetch_component("wordpress")
    assert wordpress.version == "0.1.0"
    assert :source in wordpress.capabilities
  end

  test "source defaults and target projections come from Adapter definitions" do
    assert Definition.default_selection("wordpress")["content_type"] == "post"
    assert Definition.default_mapping("wordpress")["title"] == "fields.title"

    assert [%{"target_field" => "projectedTitle"} | _rest] =
             Definition.default_projections("sanity")
  end
end

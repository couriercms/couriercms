defmodule CourierCMS.MappingTest do
  use ExUnit.Case, async: true

  alias CourierCMS.ExtensionSDK.AdapterError
  alias CourierCMS.Mapping
  alias CourierCMS.ExtensionSDK.{ContentBundle, ContentNode, SourceIdentity}

  test "parses and formats a deterministic mapping" do
    assert {:ok, mapping} = Mapping.parse("title=fields.title\nauthor.name=fields.author.name")

    assert mapping == %{
             "title" => "fields.title",
             "author.name" => "fields.author.name"
           }

    assert Mapping.format(mapping) ==
             "author.name=fields.author.name\ntitle=fields.title"
  end

  test "rejects malformed, duplicate, empty, and conflicting target paths" do
    assert {:error, message} = Mapping.parse("title fields.title")
    assert message =~ "must use target_path=source_path"

    assert {:error, message} = Mapping.parse("title=fields.title\ntitle=fields.name")
    assert message =~ "defined more than once"

    assert {:error, message} = Mapping.parse("")
    assert message =~ "at least one field"

    assert {:error, message} = Mapping.parse("author=fields.author\nauthor.name=fields.name")
    assert message =~ "conflicts with a nested target path"
  end

  test "invalid mappings return a safe mapping error instead of crashing during application" do
    identity = %SourceIdentity{
      item_key: "1",
      locale_key: "en",
      revision_key: "1",
      state: :published
    }

    node = %ContentNode{identity: identity, source_type: "article", fields: %{"title" => "A"}}
    bundle = %ContentBundle{root: node}

    assert {:error, %AdapterError{category: :mapping_failed}} =
             Mapping.apply(bundle, %{
               "author" => "fields.title",
               "author.name" => "fields.title"
             })
  end
end

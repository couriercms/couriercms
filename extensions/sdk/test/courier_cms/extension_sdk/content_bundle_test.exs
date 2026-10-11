defmodule CourierCMS.ExtensionSDK.ContentBundleTest do
  use ExUnit.Case, async: true

  alias CourierCMS.ExtensionSDK.{
    AssetDescriptor,
    ContentBundle,
    ContentNode,
    ContentRelationship,
    SourceIdentity
  }

  test "normalizes a bounded bundle deterministically" do
    root = content_node("root")
    second = content_node("second")
    first = content_node("first")

    relationship = %ContentRelationship{
      name: "component",
      from: root.identity,
      to: first.identity,
      position: 0
    }

    assert {:ok, bundle} =
             ContentBundle.new(%{
               root: root,
               included: [second, first],
               relationships: [relationship],
               assets: [
                 %AssetDescriptor{source_key: "z"},
                 %AssetDescriptor{source_key: "a"}
               ]
             })

    assert Enum.map(bundle.included, & &1.identity.item_key) == ["first", "second"]
    assert Enum.map(bundle.assets, & &1.source_key) == ["a", "z"]
    assert ContentBundle.node_count(bundle) == 3
    assert :ok = ContentBundle.validate(bundle, max_nodes: 3, max_relationships: 1, max_assets: 2)
  end

  test "rejects duplicate node and asset identities" do
    root = content_node("root")

    assert {:error, errors} =
             ContentBundle.new(%{
               root: root,
               included: [root],
               assets: [
                 %AssetDescriptor{source_key: "asset"},
                 %AssetDescriptor{source_key: "asset"}
               ]
             })

    assert "content bundle contains duplicate node identities" in errors
    assert "content bundle contains duplicate asset identities" in errors
  end

  test "rejects unknown relationship endpoints and cycles" do
    root = content_node("root")
    child = content_node("child")
    missing = content_node("missing")

    assert {:error, errors} =
             ContentBundle.new(%{
               root: root,
               included: [child],
               relationships: [
                 relationship("component", root, missing)
               ]
             })

    assert "content bundle relationship references an unknown node" in errors

    assert {:error, errors} =
             ContentBundle.new(%{
               root: root,
               included: [child],
               relationships: [
                 relationship("component", root, child),
                 relationship("parent", child, root)
               ]
             })

    assert "content bundle relationships contain a cycle" in errors
  end

  test "enforces configured collection limits" do
    assert {:ok, bundle} =
             ContentBundle.new(%{
               root: content_node("root"),
               included: [content_node("child")],
               assets: [%AssetDescriptor{source_key: "asset"}]
             })

    assert {:error, errors} =
             ContentBundle.validate(bundle, max_nodes: 1, max_relationships: 0, max_assets: 0)

    assert "content bundle nodes count 2 exceeds limit 1" in errors
    assert "content bundle assets count 1 exceeds limit 0" in errors
  end

  test "rejects malformed asset descriptors before platform execution" do
    assert {:error, errors} =
             ContentBundle.new(%{
               root: content_node("root"),
               assets: [
                 %AssetDescriptor{source_key: "asset", field_path: "payload.image"}
               ]
             })

    assert "assets contains an invalid value at index 0" in errors

    assert {:error, errors} =
             ContentBundle.new(%{
               root: content_node("root"),
               assets: [
                 %AssetDescriptor{source_key: "asset", filename: 123}
               ]
             })

    assert "assets contains an invalid value at index 0" in errors
  end

  defp content_node(item_key) do
    %ContentNode{
      identity: %SourceIdentity{
        item_key: item_key,
        locale_key: "en",
        revision_key: "1",
        state: :published
      },
      source_type: "component",
      fields: %{"title" => item_key}
    }
  end

  defp relationship(name, from, to) do
    %ContentRelationship{name: name, from: from.identity, to: to.identity}
  end
end

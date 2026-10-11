defmodule CourierCMS.Assets.DeliveryAssetTest do
  use ExUnit.Case, async: true

  alias CourierCMS.Assets.{DeliveryAsset, DeliveryAssetBinding, RunAsset, RunItemAsset}

  test "Delivery Asset identity is stable and variant-aware" do
    route_id = Ecto.UUID.generate()

    assert DeliveryAsset.key(route_id, "media-501") ==
             DeliveryAsset.key(route_id, "media-501", "original")

    refute DeliveryAsset.key(route_id, "media-501") ==
             DeliveryAsset.key(route_id, "media-501", "thumbnail")

    refute DeliveryAsset.key(route_id, "media-501") ==
             DeliveryAsset.key(Ecto.UUID.generate(), "media-501")
  end

  test "Delivery Asset validates bounded logical metadata" do
    changeset =
      DeliveryAsset.changeset(%DeliveryAsset{}, %{
        route_id: Ecto.UUID.generate(),
        source_asset_key: "media-501",
        filename: "hero.jpg",
        media_type: "image/jpeg",
        byte_size: 42,
        metadata: %{"alt" => "Hero"}
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :variant_key) == "original"

    invalid =
      DeliveryAsset.changeset(%DeliveryAsset{}, %{
        route_id: Ecto.UUID.generate(),
        source_asset_key: "",
        byte_size: -1
      })

    refute invalid.valid?
    assert "can't be blank" in errors_on(invalid).source_asset_key
    assert "must be greater than or equal to 0" in errors_on(invalid).byte_size
  end

  test "Run Asset, item dependency, and target binding require their ownership scope" do
    run_asset =
      RunAsset.changeset(%RunAsset{}, %{
        run_id: Ecto.UUID.generate(),
        delivery_asset_id: Ecto.UUID.generate(),
        asset_key: "asset-key"
      })

    assert run_asset.valid?

    dependency =
      RunItemAsset.changeset(%RunItemAsset{}, %{
        run_item_id: Ecto.UUID.generate(),
        run_asset_id: Ecto.UUID.generate(),
        field_path: "payload.featured_image"
      })

    assert dependency.valid?
    assert Ecto.Changeset.get_field(dependency, :required)

    binding =
      DeliveryAssetBinding.changeset(%DeliveryAssetBinding{}, %{
        delivery_asset_id: Ecto.UUID.generate(),
        destination_id: Ecto.UUID.generate(),
        ownership_evidence: %{"installation_id" => Ecto.UUID.generate()}
      })

    assert binding.valid?
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        options |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end

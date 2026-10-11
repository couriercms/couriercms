defmodule CourierCMS.Assets.DeliveryAsset do
  @moduledoc "A Route-scoped logical media or file dependency."

  use Ecto.Schema
  import Ecto.Changeset

  @states [:pending, :delivered, :failed]
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "delivery_assets" do
    field :source_asset_key, :string
    field :variant_key, :string, default: "original"
    field :filename, :string
    field :media_type, :string
    field :byte_size, :integer
    field :source_checksum, :string
    field :metadata, :map, default: %{}
    field :state, Ecto.Enum, values: @states, default: :pending

    belongs_to :route, CourierCMS.Routes.Route
    has_many :bindings, CourierCMS.Assets.DeliveryAssetBinding
    has_many :run_assets, CourierCMS.Assets.RunAsset

    timestamps()
  end

  @type t :: %__MODULE__{}

  def changeset(asset, attrs) do
    asset
    |> cast(attrs, [
      :route_id,
      :source_asset_key,
      :variant_key,
      :filename,
      :media_type,
      :byte_size,
      :source_checksum,
      :metadata,
      :state
    ])
    |> validate_required([:route_id, :source_asset_key, :variant_key, :metadata, :state])
    |> validate_length(:source_asset_key, min: 1, max: 1_024)
    |> validate_length(:variant_key, min: 1, max: 255)
    |> validate_length(:filename, max: 1_024)
    |> validate_length(:media_type, max: 255)
    |> validate_number(:byte_size, greater_than_or_equal_to: 0)
    |> unique_constraint([:route_id, :source_asset_key, :variant_key],
      name: :delivery_assets_logical_identity_index
    )
    |> foreign_key_constraint(:route_id)
  end

  @spec key(Ecto.UUID.t(), String.t(), String.t()) :: String.t()
  def key(route_id, source_asset_key, variant_key \\ "original")
      when is_binary(route_id) and is_binary(source_asset_key) and is_binary(variant_key) do
    [route_id, source_asset_key, variant_key]
    |> Enum.join(<<0>>)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end
end

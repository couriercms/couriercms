defmodule CourierCMS.Assets.RunItemAsset do
  @moduledoc "A Run Item dependency on one Run Asset."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "run_item_assets" do
    field :field_path, :string
    field :required, :boolean, default: true

    belongs_to :run_item, CourierCMS.Execution.RunItem
    belongs_to :run_asset, CourierCMS.Assets.RunAsset

    timestamps()
  end

  @type t :: %__MODULE__{}

  def changeset(run_item_asset, attrs) do
    run_item_asset
    |> cast(attrs, [:run_item_id, :run_asset_id, :field_path, :required])
    |> validate_required([:run_item_id, :run_asset_id, :field_path, :required])
    |> validate_length(:field_path, min: 1, max: 2_048)
    |> unique_constraint([:run_item_id, :run_asset_id, :field_path])
    |> foreign_key_constraint(:run_item_id)
    |> foreign_key_constraint(:run_asset_id)
  end
end

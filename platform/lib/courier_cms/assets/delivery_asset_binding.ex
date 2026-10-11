defmodule CourierCMS.Assets.DeliveryAssetBinding do
  @moduledoc "A durable target binding for one Delivery Asset in one Destination."

  use Ecto.Schema
  import Ecto.Changeset

  @states [:pending, :delivered, :failed]
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "delivery_asset_bindings" do
    field :target_reference, :string
    field :ownership_evidence, :map, default: %{}
    field :last_content_hash, :string
    field :last_delivered_at, :utc_datetime_usec
    field :state, Ecto.Enum, values: @states, default: :pending

    belongs_to :delivery_asset, CourierCMS.Assets.DeliveryAsset
    belongs_to :destination, CourierCMS.Destinations.Destination
    belongs_to :last_successful_run, CourierCMS.Execution.Run
    belongs_to :last_route_revision, CourierCMS.Routes.RouteRevision

    timestamps()
  end

  @type t :: %__MODULE__{}

  def changeset(binding, attrs) do
    binding
    |> cast(attrs, [
      :delivery_asset_id,
      :destination_id,
      :target_reference,
      :ownership_evidence,
      :last_content_hash,
      :last_delivered_at,
      :last_successful_run_id,
      :last_route_revision_id,
      :state
    ])
    |> validate_required([:delivery_asset_id, :destination_id, :ownership_evidence, :state])
    |> unique_constraint([:delivery_asset_id, :destination_id])
    |> foreign_key_constraint(:delivery_asset_id)
    |> foreign_key_constraint(:destination_id)
    |> foreign_key_constraint(:last_successful_run_id)
    |> foreign_key_constraint(:last_route_revision_id)
  end
end

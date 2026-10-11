defmodule CourierCMS.Assets.RunAsset do
  @moduledoc "The processing result for one Delivery Asset within a Run."

  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:pending, :processing, :succeeded, :retrying, :failed, :skipped, :cancelled]
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "run_assets" do
    field :asset_key, :string
    field :planned_operation, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :attempt_count, :integer, default: 0
    field :error_category, :string
    field :error_summary, :string
    field :content_hash, :string
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :run, CourierCMS.Execution.Run
    belongs_to :delivery_asset, CourierCMS.Assets.DeliveryAsset
    has_many :run_item_assets, CourierCMS.Assets.RunItemAsset

    timestamps()
  end

  @type t :: %__MODULE__{}

  def changeset(run_asset, attrs) do
    run_asset
    |> cast(attrs, [
      :run_id,
      :delivery_asset_id,
      :asset_key,
      :planned_operation,
      :status,
      :attempt_count,
      :error_category,
      :error_summary,
      :content_hash,
      :started_at,
      :completed_at
    ])
    |> validate_required([:run_id, :delivery_asset_id, :asset_key, :status])
    |> validate_number(:attempt_count, greater_than_or_equal_to: 0)
    |> unique_constraint([:run_id, :asset_key])
    |> foreign_key_constraint(:run_id)
    |> foreign_key_constraint(:delivery_asset_id)
  end
end

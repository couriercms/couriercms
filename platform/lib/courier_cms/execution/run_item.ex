defmodule CourierCMS.Execution.RunItem do
  @moduledoc "The processing result for one Delivery Item in one Run."

  use Ecto.Schema
  import Ecto.Changeset

  alias CourierCMS.Execution.Run
  alias CourierCMS.Ownership.RouteItem

  @statuses [:pending, :processing, :succeeded, :retrying, :failed, :skipped, :cancelled]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "run_items" do
    field :delivery_key, :string
    field :source_item_key, :string
    field :locale_key, :string
    field :source_revision_key, :string
    field :source_modified_at, :utc_datetime_usec
    field :source_change_token, :string
    field :source_state, Ecto.Enum, values: [:saved, :published], default: :published
    field :planned_operation, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :attempt_count, :integer, default: 0
    field :error_category, :string
    field :error_summary, :string
    field :content_hash, :string
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :run, Run
    belongs_to :route_item, RouteItem

    timestamps()
  end

  @doc false
  def changeset(run_item, attrs) do
    run_item
    |> cast(attrs, [
      :run_id,
      :route_item_id,
      :delivery_key,
      :source_item_key,
      :locale_key,
      :source_revision_key,
      :source_modified_at,
      :source_change_token,
      :source_state,
      :planned_operation,
      :status,
      :attempt_count,
      :error_category,
      :error_summary,
      :content_hash,
      :started_at,
      :completed_at
    ])
    |> validate_required([
      :run_id,
      :delivery_key,
      :source_item_key,
      :locale_key,
      :source_revision_key,
      :source_state,
      :status
    ])
    |> validate_number(:attempt_count, greater_than_or_equal_to: 0)
    |> unique_constraint([:run_id, :delivery_key])
    |> foreign_key_constraint(:run_id)
    |> foreign_key_constraint(:route_item_id)
  end
end

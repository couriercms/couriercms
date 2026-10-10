defmodule CourierCMS.Ownership.RouteItem do
  @moduledoc "The durable binding between a source item/locale and a target Delivery Item."

  use Ecto.Schema
  import Ecto.Changeset

  alias CourierCMS.Execution.RunItem
  alias CourierCMS.Routes.Route

  @states [:pending, :delivered, :failed]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "route_items" do
    field :source_item_key, :string
    field :locale_key, :string
    field :source_revision_key, :string
    field :last_source_modified_at, :utc_datetime_usec
    field :last_source_change_token, :string
    field :state, Ecto.Enum, values: @states, default: :pending

    belongs_to :route, Route
    has_many :delivery_bindings, CourierCMS.Ownership.DeliveryBinding
    has_many :run_items, RunItem

    timestamps()
  end

  @doc false
  def changeset(route_item, attrs) do
    route_item
    |> cast(attrs, [
      :route_id,
      :source_item_key,
      :locale_key,
      :source_revision_key,
      :last_source_modified_at,
      :last_source_change_token,
      :state
    ])
    |> validate_required([
      :route_id,
      :source_item_key,
      :locale_key,
      :source_revision_key,
      :state
    ])
    |> unique_constraint(
      [:route_id, :source_item_key, :locale_key],
      name: :route_items_logical_identity_index
    )
    |> foreign_key_constraint(:route_id)
  end
end

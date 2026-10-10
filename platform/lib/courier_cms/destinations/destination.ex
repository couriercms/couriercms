defmodule CourierCMS.Destinations.Destination do
  @moduledoc "A validated receiving scope assigned exclusively to one Route."

  use Ecto.Schema
  import Ecto.Changeset

  alias CourierCMS.Connections.Connection
  alias CourierCMS.Routes.Route

  @lifecycles [:available, :reserved, :active, :retired]
  @validation_states [:unknown, :valid, :invalid]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "destinations" do
    field :name, :string
    field :scope, :map, default: %{}
    field :scope_key, :string
    field :lifecycle_status, Ecto.Enum, values: @lifecycles, default: :available
    field :validation_status, Ecto.Enum, values: @validation_states, default: :unknown
    field :ownership_evidence, :map, default: %{}
    field :last_validation_error, :string
    field :validated_at, :utc_datetime_usec
    field :first_delivered_at, :utc_datetime_usec
    field :retired_at, :utc_datetime_usec

    belongs_to :workspace, CourierCMS.Workspaces.Workspace
    belongs_to :target_connection, Connection
    belongs_to :owner_route, Route

    timestamps()
  end

  def changeset(destination, attrs) do
    destination
    |> cast(attrs, [
      :workspace_id,
      :target_connection_id,
      :owner_route_id,
      :name,
      :scope,
      :scope_key,
      :lifecycle_status,
      :validation_status,
      :ownership_evidence,
      :last_validation_error,
      :validated_at,
      :first_delivered_at,
      :retired_at
    ])
    |> validate_required([
      :workspace_id,
      :target_connection_id,
      :name,
      :scope_key,
      :lifecycle_status,
      :validation_status
    ])
    |> validate_length(:name, min: 1, max: 160)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:target_connection_id)
    |> foreign_key_constraint(:owner_route_id)
    |> unique_constraint([:target_connection_id, :scope_key],
      name: :destinations_active_scope_index
    )
  end
end

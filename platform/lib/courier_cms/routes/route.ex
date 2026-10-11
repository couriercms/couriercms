defmodule CourierCMS.Routes.Route do
  @moduledoc "A one-way definition from one source Connection to one target Connection."

  use Ecto.Schema
  import Ecto.Changeset

  alias CourierCMS.Connections.Connection
  alias CourierCMS.Destinations.Destination
  alias CourierCMS.Routes.RouteRevision

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "routes" do
    field :name, :string
    field :enabled, :boolean, default: false
    field :archived_at, :utc_datetime_usec

    belongs_to :workspace, CourierCMS.Workspaces.Workspace
    belongs_to :source_connection, Connection
    belongs_to :target_connection, Connection
    belongs_to :current_destination, Destination
    belongs_to :current_revision, RouteRevision
    has_many :revisions, RouteRevision
    has_many :delivery_assets, CourierCMS.Assets.DeliveryAsset

    timestamps()
  end

  @doc false
  def changeset(route, attrs) do
    route
    |> cast(attrs, [
      :name,
      :source_connection_id,
      :target_connection_id,
      :enabled,
      :current_destination_id,
      :archived_at,
      :workspace_id
    ])
    |> validate_required([
      :name,
      :source_connection_id,
      :target_connection_id,
      :current_destination_id,
      :workspace_id
    ])
    |> validate_length(:name, min: 1, max: 160)
    |> validate_different_connections()
    |> unique_constraint([:workspace_id, :name])
    |> unique_constraint(:current_destination_id)
    |> foreign_key_constraint(:source_connection_id)
    |> foreign_key_constraint(:target_connection_id)
    |> foreign_key_constraint(:current_destination_id)
    |> foreign_key_constraint(:workspace_id)
    |> check_constraint(:target_connection_id,
      name: :different_source_and_target_connections,
      message: "must be different from the source connection"
    )
  end

  defp validate_different_connections(changeset) do
    source_id = get_field(changeset, :source_connection_id)
    target_id = get_field(changeset, :target_connection_id)

    if source_id && source_id == target_id do
      add_error(changeset, :target_connection_id, "must be different from the source connection")
    else
      changeset
    end
  end
end

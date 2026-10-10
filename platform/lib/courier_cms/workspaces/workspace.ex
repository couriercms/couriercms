defmodule CourierCMS.Workspaces.Workspace do
  @moduledoc "The authorization and future billing boundary for one CourierCMS installation."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "workspaces" do
    field :name, :string
    field :slug, :string
    has_many :memberships, CourierCMS.Workspaces.Membership
    timestamps()
  end

  def changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:name, :slug])
    |> validate_required([:name, :slug])
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]*$/)
    |> unique_constraint(:slug)
  end
end

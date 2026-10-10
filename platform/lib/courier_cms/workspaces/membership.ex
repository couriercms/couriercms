defmodule CourierCMS.Workspaces.Membership do
  @moduledoc "A user's role and access state within a Workspace."

  use Ecto.Schema
  import Ecto.Changeset

  alias CourierCMS.Accounts.User
  alias CourierCMS.Workspaces.Workspace

  @roles [:owner, :admin, :operator, :viewer]
  @statuses [:invited, :active, :blocked]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "workspace_memberships" do
    field :role, Ecto.Enum, values: @roles
    field :status, Ecto.Enum, values: @statuses, default: :invited
    field :blocked_at, :utc_datetime_usec
    belongs_to :workspace, Workspace
    belongs_to :user, User
    belongs_to :invited_by_user, User
    belongs_to :blocked_by_user, User
    timestamps()
  end

  def roles, do: @roles

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [
      :workspace_id,
      :user_id,
      :role,
      :status,
      :invited_by_user_id,
      :blocked_by_user_id,
      :blocked_at
    ])
    |> validate_required([:workspace_id, :user_id, :role, :status])
    |> unique_constraint([:workspace_id, :user_id])
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:user_id)
  end
end

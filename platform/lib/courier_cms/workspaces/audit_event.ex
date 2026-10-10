defmodule CourierCMS.Workspaces.AuditEvent do
  @moduledoc "Immutable security and operator audit history."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "audit_events" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, :string
    field :metadata, :map, default: %{}
    belongs_to :workspace, CourierCMS.Workspaces.Workspace
    belongs_to :actor_user, CourierCMS.Accounts.User
    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :workspace_id,
      :actor_user_id,
      :action,
      :resource_type,
      :resource_id,
      :metadata
    ])
    |> validate_required([:workspace_id, :action, :resource_type])
  end
end

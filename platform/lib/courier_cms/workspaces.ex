defmodule CourierCMS.Workspaces do
  @moduledoc "Workspace lookup and immutable audit recording."

  alias CourierCMS.Accounts.Scope
  alias CourierCMS.Repo
  alias CourierCMS.Workspaces.{AuditEvent, Workspace}

  def default_workspace, do: Repo.get_by(Workspace, slug: "default")
  def get_workspace!(id), do: Repo.get!(Workspace, id)

  def ensure_default_workspace do
    case default_workspace() do
      nil ->
        %Workspace{}
        |> Workspace.changeset(%{name: "CourierCMS", slug: "default"})
        |> Repo.insert()

      workspace ->
        {:ok, workspace}
    end
  end

  def audit(%Scope{} = scope, action, resource_type, resource_id \\ nil, metadata \\ %{}) do
    %AuditEvent{}
    |> AuditEvent.changeset(%{
      workspace_id: scope.workspace.id,
      actor_user_id: scope.user.id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      metadata: metadata
    })
    |> Repo.insert()
  end
end

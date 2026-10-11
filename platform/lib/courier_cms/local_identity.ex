defmodule CourierCMS.LocalIdentity do
  @moduledoc """
  Creates and loads the single internal operator used by the Local profile.

  The operator is represented by normal User, Membership, Workspace, and Scope
  records so every context keeps its existing authorization boundary.
  """

  import Ecto.Query

  alias CourierCMS.Accounts.{Scope, User}
  alias CourierCMS.Repo
  alias CourierCMS.Workspaces
  alias CourierCMS.Workspaces.Membership

  @email "local-operator@couriercms.invalid"

  def child_spec(_options) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]},
      restart: :temporary,
      type: :worker
    }
  end

  def start_link(_options) do
    ensure_scope!()
    :ignore
  end

  def ensure_scope! do
    {:ok, workspace} = Workspaces.ensure_default_workspace()
    user = ensure_user!()
    membership = ensure_membership!(workspace.id, user.id)

    Scope.for_user(user, Repo.preload(membership, :workspace), workspace)
  end

  def scope! do
    user = Repo.get_by!(User, email: @email)
    CourierCMS.Accounts.scope_for_user(user) || ensure_scope!()
  end

  def email, do: @email

  defp ensure_user! do
    Repo.get_by(User, email: @email) ||
      %User{}
      |> User.email_changeset(%{email: @email})
      |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
      |> Repo.insert!()
  end

  defp ensure_membership!(workspace_id, user_id) do
    Repo.one(
      from membership in Membership,
        where: membership.workspace_id == ^workspace_id and membership.user_id == ^user_id
    ) ||
      %Membership{}
      |> Membership.changeset(%{
        workspace_id: workspace_id,
        user_id: user_id,
        role: :owner,
        status: :active
      })
      |> Repo.insert!()
  end
end

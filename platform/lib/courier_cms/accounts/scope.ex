defmodule CourierCMS.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `CourierCMS.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use in authorization checks,
  or to ensure specific code paths can only be accessed for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias CourierCMS.Accounts.User
  alias CourierCMS.Workspaces.{Membership, Workspace}

  defstruct user: nil, membership: nil, workspace: nil

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(%User{} = user, %Membership{} = membership, %Workspace{} = workspace) do
    %__MODULE__{user: user, membership: membership, workspace: workspace}
  end

  def for_user(nil, nil, nil), do: nil

  def role?(%__MODULE__{membership: %{status: :active, role: role}}, roles),
    do: role in List.wrap(roles)

  def role?(_scope, _roles), do: false
end

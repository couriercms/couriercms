defmodule CourierCMS.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias CourierCMS.Repo

  alias CourierCMS.Accounts.{Scope, User, UserNotifier, UserToken}
  alias CourierCMS.Workspaces
  alias CourierCMS.Workspaces.Membership

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_for_login(email) when is_binary(email) do
    User
    |> join(:inner, [user], membership in Membership, on: membership.user_id == user.id)
    |> where(
      [user, membership],
      user.email == ^email and membership.status in [:invited, :active]
    )
    |> distinct(true)
    |> Repo.one()
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  def scope_for_user(%User{} = user) do
    membership =
      Membership
      |> where([membership], membership.user_id == ^user.id and membership.status == :active)
      |> order_by([membership], asc: membership.inserted_at)
      |> preload(:workspace)
      |> Repo.one()

    case membership do
      %Membership{} -> Scope.for_user(user, membership, membership.workspace)
      nil -> nil
    end
  end

  def scope_for_user(nil), do: nil

  def authorize(%Scope{} = scope, roles) do
    if Scope.role?(scope, roles), do: :ok, else: {:error, :forbidden}
  end

  def authorize(_scope, _roles), do: {:error, :forbidden}

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `CourierCMS.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `CourierCMS.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)

    case Repo.one(query) do
      {%User{} = user, inserted_at} ->
        if scope_for_user(user), do: {user, inserted_at}, else: nil

      nil ->
        nil
    end
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        result =
          user
          |> User.confirm_changeset()
          |> update_user_and_delete_all_tokens()

        activate_invited_memberships(user.id)
        result

      {user, token} ->
        if has_accessible_membership?(user.id) do
          activate_invited_memberships(user.id)
          Repo.delete!(token)
          {:ok, {user, []}}
        else
          {:error, :not_found}
        end

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Workspace membership administration

  def list_members(%Scope{} = scope) do
    with :ok <- authorize(scope, [:owner, :admin]) do
      Membership
      |> where([membership], membership.workspace_id == ^scope.workspace.id)
      |> order_by([membership], asc: membership.inserted_at)
      |> preload(:user)
      |> Repo.all()
    end
  end

  def invite_user(%Scope{} = scope, attrs, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    role = normalize_role(Map.get(attrs, "role", Map.get(attrs, :role, :viewer)))
    email = Map.get(attrs, "email", Map.get(attrs, :email))

    with :ok <- authorize(scope, [:owner, :admin]),
         :ok <- authorize_role_assignment(scope, role),
         {:ok, {user, membership}} <- insert_invitation(scope, email, role),
         {:ok, _email} <- deliver_login_instructions(user, magic_link_url_fun) do
      Workspaces.audit(scope, "membership.invited", "membership", membership.id, %{
        "role" => to_string(role)
      })

      {:ok, membership}
    end
  end

  def bootstrap_owner(email) do
    with {:ok, workspace} <- Workspaces.ensure_default_workspace(),
         false <-
           Repo.exists?(
             from membership in Membership,
               where: membership.workspace_id == ^workspace.id and membership.role == :owner
           ),
         {:ok, user} <- register_or_get_user(email),
         {:ok, membership} <-
           %Membership{}
           |> Membership.changeset(%{
             workspace_id: workspace.id,
             user_id: user.id,
             role: :owner,
             status: :active
           })
           |> Repo.insert() do
      {:ok, membership}
    else
      true -> {:error, :owner_already_exists}
      error -> error
    end
  end

  def block_member(%Scope{} = scope, membership_id) do
    with :ok <- authorize(scope, [:owner, :admin]),
         %Membership{} = membership <- membership_in_scope(scope, membership_id),
         :ok <- can_manage_membership?(scope, membership),
         :ok <- protect_self(scope, membership),
         :ok <- protect_last_owner(membership) do
      now = DateTime.utc_now()

      Repo.transact(fn ->
        membership =
          membership
          |> Membership.changeset(%{
            status: :blocked,
            blocked_at: now,
            blocked_by_user_id: scope.user.id
          })
          |> Repo.update!()

        tokens = Repo.all_by(UserToken, user_id: membership.user_id)
        Repo.delete_all(from token in UserToken, where: token.user_id == ^membership.user_id)
        {:ok, {membership, tokens}}
      end)
      |> case do
        {:ok, {membership, tokens}} ->
          Workspaces.audit(scope, "membership.blocked", "membership", membership.id)
          {:ok, {membership, tokens}}

        error ->
          error
      end
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def unblock_member(%Scope{} = scope, membership_id) do
    with :ok <- authorize(scope, [:owner, :admin]),
         %Membership{} = membership <- membership_in_scope(scope, membership_id),
         :ok <- can_manage_membership?(scope, membership) do
      membership
      |> Membership.changeset(%{status: :active, blocked_at: nil, blocked_by_user_id: nil})
      |> Repo.update()
      |> tap(fn
        {:ok, updated} ->
          Workspaces.audit(scope, "membership.unblocked", "membership", updated.id)

        _ ->
          :ok
      end)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def change_member_role(%Scope{} = scope, membership_id, role) do
    role = normalize_role(role)

    with :ok <- authorize(scope, [:owner]),
         true <- role in Membership.roles(),
         %Membership{} = membership <- membership_in_scope(scope, membership_id),
         :ok <- protect_last_owner(membership, role) do
      membership
      |> Membership.changeset(%{role: role})
      |> Repo.update()
      |> tap(fn
        {:ok, updated} ->
          Workspaces.audit(scope, "membership.role_changed", "membership", updated.id, %{
            "role" => to_string(role)
          })

        _ ->
          :ok
      end)
    else
      false -> {:error, :invalid_role}
      nil -> {:error, :not_found}
      error -> error
    end
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  defp insert_invitation(scope, email, role) do
    Repo.transact(fn ->
      with {:ok, user} <- register_or_get_user(email),
           {:ok, membership} <-
             %Membership{}
             |> Membership.changeset(%{
               workspace_id: scope.workspace.id,
               user_id: user.id,
               role: role,
               status: :invited,
               invited_by_user_id: scope.user.id
             })
             |> Repo.insert() do
        {:ok, {user, membership}}
      end
    end)
  end

  defp register_or_get_user(email) when is_binary(email) do
    case get_user_by_email(email) do
      nil -> register_user(%{email: email})
      user -> {:ok, user}
    end
  end

  defp register_or_get_user(_email), do: {:error, :invalid_email}

  defp membership_in_scope(scope, id) do
    Repo.get_by(Membership, id: id, workspace_id: scope.workspace.id)
  end

  defp can_manage_membership?(%Scope{membership: %{role: :owner}}, _membership), do: :ok

  defp can_manage_membership?(%Scope{membership: %{role: :admin}}, %{role: role})
       when role in [:operator, :viewer],
       do: :ok

  defp can_manage_membership?(_scope, _membership), do: {:error, :forbidden}

  defp authorize_role_assignment(%Scope{membership: %{role: :owner}}, role)
       when role in [:owner, :admin, :operator, :viewer],
       do: :ok

  defp authorize_role_assignment(%Scope{membership: %{role: :admin}}, role)
       when role in [:operator, :viewer],
       do: :ok

  defp authorize_role_assignment(_scope, _role), do: {:error, :forbidden}

  defp protect_self(%Scope{user: %{id: id}}, %{user_id: id}), do: {:error, :cannot_block_self}
  defp protect_self(_scope, _membership), do: :ok

  defp protect_last_owner(%Membership{role: :owner} = membership) do
    if active_owner_count(membership.workspace_id) <= 1,
      do: {:error, :last_owner},
      else: :ok
  end

  defp protect_last_owner(_membership), do: :ok

  defp protect_last_owner(%Membership{role: :owner} = membership, new_role)
       when new_role != :owner,
       do: protect_last_owner(membership)

  defp protect_last_owner(_membership, _new_role), do: :ok

  defp active_owner_count(workspace_id) do
    Repo.aggregate(
      from(membership in Membership,
        where:
          membership.workspace_id == ^workspace_id and membership.role == :owner and
            membership.status == :active
      ),
      :count
    )
  end

  defp activate_invited_memberships(user_id) do
    from(membership in Membership,
      where: membership.user_id == ^user_id and membership.status == :invited
    )
    |> Repo.update_all(set: [status: :active, updated_at: DateTime.utc_now()])
  end

  defp has_accessible_membership?(user_id) do
    Repo.exists?(
      from membership in Membership,
        where: membership.user_id == ^user_id and membership.status in [:invited, :active]
    )
  end

  defp normalize_role(role) when is_atom(role), do: role

  defp normalize_role(role) when is_binary(role) do
    Enum.find(Membership.roles(), &(&1 |> to_string() == role))
  end

  defp normalize_role(_role), do: nil
end

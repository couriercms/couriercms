defmodule CourierCMS.AccountsMembershipTest do
  use CourierCMS.DataCase, async: true

  import CourierCMS.AccountsFixtures

  alias CourierCMS.Accounts
  alias CourierCMS.Repo
  alias CourierCMS.Workspaces.Membership

  test "an owner can invite a viewer without public registration" do
    owner = user_fixture()
    scope = Accounts.scope_for_user(owner)

    assert {:ok, membership} =
             Accounts.invite_user(
               scope,
               %{"email" => unique_user_email(), "role" => "viewer"},
               &"https://couriercms.test/users/log-in/#{&1}"
             )

    assert membership.role == :viewer
    assert membership.status == :invited
  end

  test "an admin can manage operators and viewers but cannot assign administrators" do
    admin = user_fixture(%{role: :admin})
    scope = Accounts.scope_for_user(admin)

    assert {:ok, %Membership{role: :operator}} =
             Accounts.invite_user(
               scope,
               %{"email" => unique_user_email(), "role" => "operator"},
               &"https://couriercms.test/users/log-in/#{&1}"
             )

    assert {:error, :forbidden} =
             Accounts.invite_user(
               scope,
               %{"email" => unique_user_email(), "role" => "admin"},
               &"https://couriercms.test/users/log-in/#{&1}"
             )
  end

  test "the final active owner cannot be demoted or blocked" do
    owner = user_fixture()
    scope = Accounts.scope_for_user(owner)

    assert {:error, :last_owner} =
             Accounts.change_member_role(scope, scope.membership.id, :admin)

    assert {:error, :cannot_block_self} = Accounts.block_member(scope, scope.membership.id)
  end

  test "blocking a member invalidates existing sessions" do
    owner = user_fixture()
    member = user_fixture(%{role: :viewer})
    token = Accounts.generate_user_session_token(member)
    assert Accounts.get_user_by_session_token(token)

    assert {:ok, {_membership, tokens}} =
             Accounts.block_member(Accounts.scope_for_user(owner), membership_id(member))

    assert tokens != []
    refute Accounts.get_user_by_session_token(token)
    refute Accounts.scope_for_user(member)
  end

  test "a viewer cannot administer memberships" do
    viewer = user_fixture(%{role: :viewer})

    assert {:error, :forbidden} = Accounts.list_members(Accounts.scope_for_user(viewer))
  end

  defp membership_id(user) do
    Repo.get_by!(Membership, user_id: user.id).id
  end
end

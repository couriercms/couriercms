defmodule CourierCMS.Local.ImplicitIdentityTest do
  use CourierCMSWeb.ConnCase

  if CourierCMS.ReleaseProfile.server?() do
    @moduletag skip: "Local implicit-operator behavior"
  end

  alias CourierCMS.Accounts
  alias CourierCMS.LocalIdentity

  setup do
    LocalIdentity.ensure_scope!()
    :ok
  end

  test "an anonymous loopback request receives the normal scoped Local operator", %{conn: conn} do
    scope = LocalIdentity.scope!()

    assert scope.user.email == LocalIdentity.email()
    assert scope.workspace.slug == "default"
    assert scope.membership.role == :owner
    assert scope.membership.status == :active
    assert Accounts.authorize(scope, [:owner]) == :ok

    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Local operator"
  end

  test "login and user-management screens are unavailable in Local", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/users/log-in")) == ~p"/"
    assert redirected_to(get(conn, ~p"/users")) == ~p"/"
  end
end

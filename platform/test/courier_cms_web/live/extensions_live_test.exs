defmodule CourierCMSWeb.ExtensionsLiveTest do
  use CourierCMSWeb.ConnCase

  test "owner sees node-local Extension diagnostics", %{conn: conn} do
    user = CourierCMS.AccountsFixtures.user_fixture(%{role: :owner})
    conn = log_in_user(conn, user)

    {:ok, _view, html} = live(conn, ~p"/system/extensions")

    assert html =~ "System · Extensions"
    assert html =~ "com.couriercms.fake"
    assert html =~ "fake_source"
    assert html =~ "Node-local registry"
  end

  test "viewer is redirected by role authorization", %{conn: conn} do
    user = CourierCMS.AccountsFixtures.user_fixture(%{role: :viewer})
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: "/", flash: flash}}} =
             live(conn, ~p"/system/extensions")

    assert flash["error"] == "You are not authorized to access that page."
  end
end

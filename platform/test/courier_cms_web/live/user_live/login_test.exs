defmodule CourierCMSWeb.UserLive.LoginTest do
  use CourierCMSWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CourierCMS.AccountsFixtures

  describe "login page" do
    test "renders an invite-only magic-link form", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Sign in to CourierCMS"
      assert html =~ "Access is invite-only"
      assert html =~ "Send secure sign-in link"
      refute html =~ "Sign up"
    end
  end

  describe "magic-link request" do
    test "creates a login token for a member", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "If your email has access"

      assert CourierCMS.Repo.get_by!(CourierCMS.Accounts.UserToken, user_id: user.id).context ==
               "login"
    end

    test "does not disclose whether an email has access", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", user: %{email: "unknown@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "If your email has access"
    end
  end

  describe "re-authentication" do
    test "locks the form to the signed-in user's email", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Confirm your identity"
      assert html =~ user.email
      assert html =~ "readonly"
    end
  end
end

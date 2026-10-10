defmodule CourierCMSWeb.UserSessionControllerTest do
  use CourierCMSWeb.ConnCase, async: true

  import CourierCMS.AccountsFixtures
  alias CourierCMS.Accounts

  setup do
    %{invited_user: unconfirmed_user_fixture(%{status: :invited}), user: user_fixture()}
  end

  describe "POST /users/log-in - magic link" do
    test "logs an active member in", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}})

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      response = conn |> recycle() |> get(~p"/") |> html_response(200)
      assert response =~ user.email
      assert response =~ ~p"/users/log-out"
    end

    test "confirms and activates an invited member", %{conn: conn, invited_user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)
      refute user.confirmed_at

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token},
          "_action" => "confirmed"
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "confirmed"
      assert Accounts.get_user!(user.id).confirmed_at
      assert Accounts.scope_for_user(user).membership.status == :active
    end

    test "rejects an invalid magic link", %{conn: conn} do
      conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => "invalid"}})

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "The link is invalid or it has expired."

      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "rejects password-shaped requests", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => "not-supported"}
        })

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "secure link"
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds if the user is already logged out", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
    end
  end
end

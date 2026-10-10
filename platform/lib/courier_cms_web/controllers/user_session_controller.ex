defmodule CourierCMSWeb.UserSessionController do
  use CourierCMSWeb, :controller

  alias CourierCMS.Accounts
  alias CourierCMSWeb.UserAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "User confirmed successfully.")
  end

  def create(conn, %{"user" => %{"token" => _token}} = params) do
    create(conn, params, "Welcome back!")
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Use the secure link sent to your email address.")
    |> redirect(to: ~p"/users/log-in")
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      _ ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end

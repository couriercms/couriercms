defmodule CourierCMSWeb.UserLive.Login do
  use CourierCMSWeb, :live_view

  alias CourierCMS.Accounts

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    {:ok, assign(socket, form: to_form(%{"email" => email}, as: "user"))}
  end

  @impl true
  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_for_login(email) do
      Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))
    end

    {:noreply,
     socket
     |> put_flash(
       :info,
       "If your email has access, a secure sign-in link will arrive shortly."
     )
     |> push_navigate(to: ~p"/users/log-in")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-md">
        <div class="card border border-base-300 bg-base-100 shadow-xl">
          <div class="card-body gap-5 p-8">
            <div>
              <div class="mb-5 grid size-11 place-items-center rounded-xl bg-primary text-lg font-black text-primary-content">
                J
              </div>
              <h1 class="text-2xl font-black tracking-tight">Sign in to CourierCMS</h1>
              <p class="mt-2 text-sm text-base-content/60">
                <%= if @current_scope do %>
                  Confirm your identity to continue with this sensitive action.
                <% else %>
                  Access is invite-only. Enter the email address added by your administrator.
                <% end %>
              </p>
            </div>

            <div :if={local_mail_adapter?()} class="alert alert-info text-sm">
              <.icon name="hero-information-circle" class="size-5 shrink-0" />
              <span>
                Development email appears in <.link
                  href="/dev/mailbox"
                  class="font-semibold underline"
                >the local mailbox</.link>.
              </span>
            </div>

            <.form
              :let={f}
              for={@form}
              id="login_form_magic"
              action={~p"/users/log-in"}
              phx-submit="submit_magic"
            >
              <.input
                readonly={!!@current_scope}
                field={f[:email]}
                type="email"
                label="Email address"
                autocomplete="username"
                spellcheck="false"
                required
                phx-mounted={JS.focus()}
              />
              <.button class="btn btn-primary mt-3 w-full">
                Send secure sign-in link <span aria-hidden="true">&rarr;</span>
              </.button>
            </.form>

            <p class="text-center text-xs text-base-content/45">
              No password to remember. Links are short-lived and single-use.
            </p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp local_mail_adapter? do
    Application.get_env(:couriercms, CourierCMS.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end

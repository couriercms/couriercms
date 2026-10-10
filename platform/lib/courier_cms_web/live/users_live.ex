defmodule CourierCMSWeb.UsersLive do
  use CourierCMSWeb, :live_view
  on_mount {CourierCMSWeb.UserAuth, {:require_role, [:owner, :admin]}}
  on_mount {CourierCMSWeb.UserAuth, :require_sudo_mode}

  alias CourierCMS.Accounts
  alias CourierCMS.Accounts.Scope
  alias CourierCMSWeb.UserAuth

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load(socket)}
  end

  @impl true
  def handle_event("invite", %{"invite" => params}, socket) do
    case Accounts.invite_user(
           socket.assigns.current_scope,
           params,
           &url(~p"/users/log-in/#{&1}")
         ) do
      {:ok, _membership} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invitation sent.")
         |> load()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, invitation_error(reason))}
    end
  end

  def handle_event("block", %{"id" => id}, socket) do
    case Accounts.block_member(socket.assigns.current_scope, id) do
      {:ok, {_membership, tokens}} ->
        UserAuth.disconnect_sessions(tokens)
        {:noreply, socket |> put_flash(:info, "User access blocked.") |> load()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, membership_error(reason))}
    end
  end

  def handle_event("unblock", %{"id" => id}, socket) do
    case Accounts.unblock_member(socket.assigns.current_scope, id) do
      {:ok, _membership} ->
        {:noreply, socket |> put_flash(:info, "User access restored.") |> load()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, membership_error(reason))}
    end
  end

  def handle_event("role", %{"membership_id" => id, "role" => role}, socket) do
    case Accounts.change_member_role(socket.assigns.current_scope, id, role) do
      {:ok, _membership} ->
        {:noreply, socket |> put_flash(:info, "Role updated.") |> load()}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, membership_error(reason)) |> load()}
    end
  end

  defp load(socket) do
    scope = socket.assigns.current_scope

    assign(socket,
      page_title: "Users",
      memberships: Accounts.list_members(scope),
      invite_form: to_form(%{"email" => "", "role" => "viewer"}, as: :invite),
      role_options: role_options(scope),
      owner?: Scope.role?(scope, [:owner])
    )
  end

  defp role_options(%{membership: %{role: :owner}}),
    do: [
      {"Owner", "owner"},
      {"Administrator", "admin"},
      {"Operator", "operator"},
      {"Viewer", "viewer"}
    ]

  defp role_options(_scope), do: [{"Operator", "operator"}, {"Viewer", "viewer"}]

  defp invitation_error(%Ecto.Changeset{}),
    do: "That user already belongs to this workspace or the email is invalid."

  defp invitation_error(:forbidden), do: "You cannot assign that role."
  defp invitation_error(_reason), do: "The invitation could not be sent."

  defp membership_error(:last_owner),
    do: "Promote another owner before changing the last active owner."

  defp membership_error(:cannot_block_self), do: "You cannot block your own membership."
  defp membership_error(:forbidden), do: "You cannot manage that membership."
  defp membership_error(_reason), do: "The membership could not be updated."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Users and access
        <:subtitle>
          Invite-only access to {@current_scope.workspace.name}. At least one active owner is always required.
        </:subtitle>
      </.header>

      <div class="grid gap-6 xl:grid-cols-[1.4fr_0.6fr]">
        <section class="card border border-base-300 bg-base-100 shadow-sm">
          <div class="card-body overflow-x-auto">
            <h2 class="card-title">Workspace members</h2>
            <table class="table mt-3">
              <thead>
                <tr>
                  <th>User</th><th>Role</th><th>Status</th><th>Added</th><th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={membership <- @memberships} id={"membership-#{membership.id}"}>
                  <td>
                    <p class="font-semibold">{membership.user.email}</p>
                    <p
                      :if={membership.user_id == @current_scope.user.id}
                      class="text-xs text-base-content/45"
                    >
                      Your account
                    </p>
                  </td>
                  <td>
                    <form :if={@owner?} phx-change="role">
                      <input type="hidden" name="membership_id" value={membership.id} />
                      <select
                        name="role"
                        class="select select-sm"
                        aria-label={"Role for #{membership.user.email}"}
                      >
                        {Phoenix.HTML.Form.options_for_select(@role_options, membership.role)}
                      </select>
                    </form>
                    <span :if={!@owner?} class="capitalize">{membership.role}</span>
                  </td>
                  <td>
                    <span class={[
                      "badge badge-sm capitalize",
                      membership.status == :active && "badge-success",
                      membership.status == :blocked && "badge-error",
                      membership.status == :invited && "badge-info"
                    ]}>{membership.status}</span>
                  </td>
                  <td class="text-sm text-base-content/55">
                    {Calendar.strftime(membership.inserted_at, "%Y-%m-%d")}
                  </td>
                  <td class="text-right">
                    <button
                      :if={
                        manageable?(@current_scope, membership) &&
                          membership.status != :blocked &&
                          membership.user_id != @current_scope.user.id
                      }
                      phx-click="block"
                      phx-value-id={membership.id}
                      class="btn btn-ghost btn-xs text-error"
                    >Block</button>
                    <button
                      :if={manageable?(@current_scope, membership) && membership.status == :blocked}
                      phx-click="unblock"
                      phx-value-id={membership.id}
                      class="btn btn-ghost btn-xs"
                    >Unblock</button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section class="card h-fit border border-base-300 bg-base-100 shadow-sm">
          <div class="card-body">
            <h2 class="card-title">Invite a user</h2>
            <p class="text-sm text-base-content/60">
              They will receive a single-use magic link. There is no public registration.
            </p>
            <.form for={@invite_form} id="invite-form" phx-submit="invite" class="mt-3 space-y-3">
              <.input field={@invite_form[:email]} type="email" label="Email address" required />
              <.input field={@invite_form[:role]} type="select" label="Role" options={@role_options} />
              <.button type="submit" class="btn btn-primary w-full">Send invitation</.button>
            </.form>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp manageable?(%{membership: %{role: :owner}}, _membership), do: true

  defp manageable?(%{membership: %{role: :admin}}, %{role: role}),
    do: role in [:operator, :viewer]

  defp manageable?(_scope, _membership), do: false
end

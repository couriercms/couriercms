defmodule CourierCMSWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use CourierCMSWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200/40">
      <header class="border-b border-base-300 bg-base-100">
        <div class="navbar mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
          <div class="flex-1">
            <.link navigate={~p"/"} class="flex items-center gap-3">
              <div class="grid size-9 place-items-center rounded-xl bg-primary text-primary-content font-black">
                J
              </div>
              <div>
                <div class="font-bold leading-none">CourierCMS</div>
                <div class="mt-1 text-[10px] uppercase tracking-[0.2em] text-base-content/50">
                  Content delivery
                </div>
              </div>
            </.link>
          </div>
          <nav class="hidden items-center gap-1 md:flex">
            <.link navigate={~p"/"} class="btn btn-ghost btn-sm">Overview</.link>
            <.link navigate={~p"/connections"} class="btn btn-ghost btn-sm">Connections</.link>
            <.link navigate={~p"/routes"} class="btn btn-ghost btn-sm">Routes</.link>
            <.link navigate={~p"/destinations"} class="btn btn-ghost btn-sm">Destinations</.link>
            <.link navigate={~p"/deliveries"} class="btn btn-ghost btn-sm">Deliveries</.link>
            <.link navigate={~p"/connector-events"} class="btn btn-ghost btn-sm">Events</.link>
            <.link
              :if={
                @current_scope && CourierCMS.Accounts.Scope.role?(@current_scope, [:owner, :admin])
              }
              navigate={~p"/system/extensions"}
              class="btn btn-ghost btn-sm"
            >
              Extensions
            </.link>
            <.link
              :if={
                @current_scope && CourierCMS.Accounts.Scope.role?(@current_scope, [:owner, :admin])
              }
              navigate={~p"/users"}
              class="btn btn-ghost btn-sm"
            >
              Users
            </.link>
            <.theme_toggle />
            <div :if={@current_scope} class="dropdown dropdown-end">
              <button tabindex="0" class="btn btn-ghost btn-sm gap-2">
                <span class="max-w-40 truncate">{@current_scope.user.email}</span>
                <span class="badge badge-outline badge-xs">{@current_scope.membership.role}</span>
              </button>
              <ul
                tabindex="0"
                class="menu dropdown-content z-20 mt-2 w-56 rounded-box border border-base-300 bg-base-100 p-2 shadow-xl"
              >
                <li><.link href={~p"/users/log-out"} method="delete">Sign out</.link></li>
              </ul>
            </div>
            <.link :if={!@current_scope} navigate={~p"/users/log-in"} class="btn btn-primary btn-sm">Sign in</.link>
          </nav>
        </div>
      </header>

      <main class="px-4 py-8 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-7xl space-y-6">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end

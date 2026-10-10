defmodule CourierCMSWeb.Router do
  use CourierCMSWeb, :router

  import CourierCMSWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CourierCMSWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api/connectors", CourierCMSWeb do
    pipe_through :api

    post "/:connection_id/events", ConnectorEventController, :create
  end

  scope "/health", CourierCMSWeb do
    pipe_through :api

    get "/live", HealthController, :live
    get "/ready", HealthController, :ready
  end

  scope "/", CourierCMSWeb do
    get "/metrics", MetricsController, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", CourierCMSWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:couriercms, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CourierCMSWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", CourierCMSWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{CourierCMSWeb.UserAuth, :require_authenticated}] do
      live "/", DashboardLive
      live "/connections", ConnectionsLive
      live "/routes", RoutesLive
      live "/routes/:id", RouteLive
      live "/runs/:id", RunLive
      live "/destinations", DestinationsLive
      live "/deliveries", DeliveriesLive
      live "/connector-events", ConnectorEventsLive
      live "/system/extensions", ExtensionsLive
      live "/users", UsersLive
    end
  end

  scope "/", CourierCMSWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{CourierCMSWeb.UserAuth, :mount_current_scope}] do
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end

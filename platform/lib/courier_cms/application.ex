defmodule CourierCMS.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    deployment_role = Application.fetch_env!(:couriercms, :deployment_role)

    oban_options =
      :couriercms
      |> Application.fetch_env!(Oban)
      |> CourierCMS.Deployment.oban_options!(deployment_role)

    children = [
      CourierCMSWeb.Telemetry,
      CourierCMS.Vault,
      CourierCMS.Extensions.PackageLoader,
      CourierCMS.Extensions.ComponentRegistry,
      CourierCMS.Repo,
      {Oban, oban_options},
      {DNSCluster, query: Application.get_env(:couriercms, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: CourierCMS.PubSub}
    ]

    children =
      if Application.get_env(:couriercms, :heartbeat_enabled, true),
        do: children ++ [CourierCMS.Execution.WorkerHeartbeat],
        else: children

    children =
      if deployment_role == :worker,
        do: children,
        else: children ++ [CourierCMSWeb.Endpoint]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CourierCMS.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CourierCMSWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

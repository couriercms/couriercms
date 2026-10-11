defmodule CourierCMS.ReleaseProfile do
  @moduledoc """
  Fixed behavior selected by the Local or Server release artifact.

  This is deliberately not a general feature-flag system. Values describe the
  supported operational profile and are compiled into an artifact.
  """

  @profile Application.compile_env!(:couriercms, :release_profile)

  @type profile :: :local | :server
  @type identity_mode :: :implicit_local_operator | :authenticated_users
  @type scheduling_mode :: :while_running | :continuous
  @type topology :: :single_instance | :distributed

  @spec current() :: profile()
  def current, do: @profile

  @spec local?() :: boolean()
  def local?, do: @profile == :local

  @spec server?() :: boolean()
  def server?, do: @profile == :server

  @spec identity_mode() :: identity_mode()
  def identity_mode, do: if(local?(), do: :implicit_local_operator, else: :authenticated_users)

  @spec connector_ingress?() :: boolean()
  def connector_ingress?, do: server?()

  @spec scheduling_mode() :: scheduling_mode()
  def scheduling_mode, do: if(local?(), do: :while_running, else: :continuous)

  @spec topology() :: topology()
  def topology, do: if(local?(), do: :single_instance, else: :distributed)

  @spec http_ip() :: :inet.ip_address()
  def http_ip, do: if(local?(), do: {127, 0, 0, 1}, else: {0, 0, 0, 0, 0, 0, 0, 0})

  @spec validate_deployment_role!(CourierCMS.Deployment.role()) :: CourierCMS.Deployment.role()
  def validate_deployment_role!(:all), do: :all

  def validate_deployment_role!(role) when @profile == :server and role in [:web, :worker],
    do: role

  def validate_deployment_role!(role) do
    raise ArgumentError,
          "deployment role #{inspect(role)} is not supported by the #{@profile} release profile"
  end
end

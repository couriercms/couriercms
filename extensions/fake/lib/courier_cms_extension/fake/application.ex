defmodule CourierCMSExtension.Fake.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([CourierCMSExtension.Fake.Store],
      strategy: :one_for_one,
      name: CourierCMSExtension.Fake.Supervisor
    )
  end
end

defmodule CourierCMS.Repo do
  adapter = Application.compile_env!(:couriercms, :ecto_adapter)

  use Ecto.Repo,
    otp_app: :couriercms,
    adapter: adapter
end

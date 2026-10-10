defmodule CourierCMS.Repo do
  use Ecto.Repo,
    otp_app: :couriercms,
    adapter: Ecto.Adapters.Postgres
end

ExUnit.start()
ExUnit.configure(exclude: [:load])
Ecto.Adapters.SQL.Sandbox.mode(CourierCMS.Repo, :manual)

ExUnit.start()

profile_exclusions =
  if CourierCMS.ReleaseProfile.local?(), do: [:server_only], else: [:local_only]

ExUnit.configure(exclude: [:load, :benchmark] ++ profile_exclusions)
Ecto.Adapters.SQL.Sandbox.mode(CourierCMS.Repo, :manual)

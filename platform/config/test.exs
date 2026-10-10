import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :pbkdf2_elixir, :rounds, 1
config :couriercms, CourierCMS.Mailer, adapter: Swoosh.Adapters.Test
config :couriercms, :telemetry_poller_enabled, false

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :couriercms, CourierCMS.Repo,
  username: System.get_env("POSTGRES_USER", "couriercms"),
  password: System.get_env("POSTGRES_PASSWORD", "couriercms_dev"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
  database:
    System.get_env("POSTGRES_TEST_DB", "couriercms_test") <>
      (System.get_env("MIX_TEST_PARTITION") || ""),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :couriercms, CourierCMSWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "nNHEPOTNSODbllqyS1qg3927/5YJmsVmFLbi7RI9GJQmZm4UoY4vGn3s4fkckGax",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

config :couriercms, Oban,
  testing: :manual,
  queues: false,
  plugins: false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

release_profile =
  case System.get_env("COURIERCMS_RELEASE_PROFILE", "server") do
    "local" ->
      :local

    "server" ->
      :server

    value ->
      raise "unsupported COURIERCMS_RELEASE_PROFILE=#{inspect(value)}; expected local or server"
  end

ecto_adapter =
  case release_profile do
    :local -> Ecto.Adapters.SQLite3
    :server -> Ecto.Adapters.Postgres
  end

config :couriercms,
  start_local_identity: true,
  release_profile: release_profile,
  ecto_adapter: ecto_adapter,
  allow_test_authenticated_sessions: false

config :couriercms, CourierCMS.Repo,
  priv: if(release_profile == :local, do: "priv/sqlite_repo", else: "priv/repo")

config :swoosh, :api_client, false
config :couriercms_extension_sdk, http_client: CourierCMS.Extensions.HTTPClient

config :couriercms, :scopes,
  user: [
    default: true,
    module: CourierCMS.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :binary_id,
    schema_table: :users,
    test_data_fixture: CourierCMS.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

# OTP normally loads certificate authorities from the operating system. Some
# Windows installations cannot expose the Windows certificate store to OTP.
# Allow developers to point OTP at a PEM bundle without disabling TLS checks.
if cacerts_path =
     System.get_env("COURIERCMS_CACERTS_PATH") || System.get_env("SSL_CERT_FILE") do
  config :public_key, cacerts_path: String.to_charlist(cacerts_path)
end

config :couriercms, Oban,
  engine: if(release_profile == :local, do: Oban.Engines.Lite, else: Oban.Engines.Basic),
  notifier:
    if(release_profile == :local, do: Oban.Notifiers.Isolated, else: Oban.Notifiers.Postgres),
  repo: CourierCMS.Repo,
  queues: [route_planning: 2, delivery: 10, webhooks: 5, maintenance: 1],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", CourierCMS.Execution.ScheduleWorker, queue: :maintenance},
       {"*/5 * * * *", CourierCMS.Execution.ReconcileWorker, queue: :maintenance},
       {"17 2 * * *", CourierCMS.Execution.RetentionWorker, queue: :maintenance}
     ]}
  ],
  lifeline: [rescue_after: {2, :hours}],
  pruner: [max_age: {1, :day}]

# Safe only for local development and tests. Production replaces this key in
# runtime.exs with COURIERCMS_VAULT_KEY before the supervision tree starts.
config :couriercms, CourierCMS.Vault,
  json_library: Jason,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1", key: :crypto.hash(:sha256, "couriercms-local-development-key")}
  ]

config :phoenix_live_view, :colocated_assets, disable_symlink_warning: true

config :couriercms,
  namespace: CourierCMS,
  ecto_repos: [CourierCMS.Repo],
  deployment_role: :all,
  delivery_lock_ttl_ms: 900_000,
  max_source_page_items: 1_000,
  max_run_items: 100_000,
  max_delivery_bytes: 5_000_000,
  max_planning_pages: 10_000,
  delivery_max_attempts: 3,
  planning_max_attempts: 3,
  delivery_backoff_cap_seconds: 30,
  planning_backoff_cap_seconds: 30,
  max_adapter_response_bytes: 10_000_000,
  max_webhook_bytes: 64_000,
  adapter_connect_timeout_ms: 5_000,
  adapter_receive_timeout_ms: 30_000,
  asset_receive_timeout_ms: 300_000,
  default_connection_concurrency: 5,
  default_connection_requests_per_second: 20,
  outbound_rate_limiting: config_env() != :test,
  stranded_after_ms: 1_200_000,
  retention_enabled: false,
  heartbeat_enabled: config_env() != :test,
  require_worker_readiness: false,
  require_extension_consistency: false,
  allow_unauthenticated_metrics: config_env() != :prod,
  run_retention_days: 365,
  event_retention_days: 90,
  audit_retention_days: 730,
  retention_batch_size: 500,
  failure_email_alerts: true,
  allow_http_cms_endpoints: config_env() != :prod,
  allow_private_cms_networks: config_env() != :prod,
  allow_unsafe_local_cms_endpoints: config_env() != :prod,
  allow_unresolved_cms_hosts: config_env() != :prod,
  extensions_dir: Path.expand("../../.local/extensions", __DIR__),
  extension_cache_dir: Path.expand("../../.local/extension-cache", __DIR__),
  extension_signature_policy: :optional,
  extension_trusted_keys: %{},
  extension_max_package_bytes: 50_000_000,
  extension_max_uncompressed_bytes: 200_000_000,
  extension_max_entries: 5_000,
  extension_max_packages: 100,
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  installation_id:
    System.get_env("COURIERCMS_INSTALLATION_ID", "00000000-0000-4000-8000-000000000001"),
  source_adapters: %{},
  target_adapters: %{}

# Configure the endpoint
config :couriercms, CourierCMSWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: CourierCMSWeb.ErrorHTML, json: CourierCMSWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: CourierCMS.PubSub,
  live_view: [signing_salt: "K8UfNV9M"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  couriercms: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  couriercms: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

import Config

release_profile = Application.fetch_env!(:couriercms, :release_profile)
local_production? = release_profile == :local and config_env() == :prod

deployment_role =
  case System.get_env("COURIERCMS_ROLE", "all") |> String.trim() |> String.downcase() do
    "all" -> :all
    "web" -> :web
    "worker" -> :worker
    role -> raise "COURIERCMS_ROLE must be all, web, or worker; got: #{inspect(role)}"
  end
  |> CourierCMS.ReleaseProfile.validate_deployment_role!()

config :couriercms, :deployment_role, deployment_role

config :couriercms,
       :failure_email_alerts,
       System.get_env("COURIERCMS_FAILURE_EMAIL_ALERTS", "true") in ["true", "1"]

config :couriercms,
  retention_enabled:
    System.get_env(
      "COURIERCMS_RETENTION_ENABLED",
      to_string(Application.get_env(:couriercms, :retention_enabled, false))
    ) in ["true", "1"],
  heartbeat_enabled:
    System.get_env(
      "COURIERCMS_HEARTBEAT_ENABLED",
      to_string(Application.get_env(:couriercms, :heartbeat_enabled, true))
    ) in ["true", "1"],
  require_worker_readiness:
    System.get_env(
      "COURIERCMS_REQUIRE_WORKER_READINESS",
      if(config_env() == :prod, do: "true", else: "false")
    ) in ["true", "1"],
  require_extension_consistency:
    System.get_env(
      "COURIERCMS_REQUIRE_EXTENSION_CONSISTENCY",
      if(config_env() == :prod, do: "true", else: "false")
    ) in ["true", "1"],
  metrics_token: System.get_env("COURIERCMS_METRICS_TOKEN")

signature_policy =
  case System.get_env("COURIERCMS_EXTENSION_SIGNATURE_POLICY", "optional")
       |> String.trim()
       |> String.downcase() do
    "optional" ->
      :optional

    "required" ->
      :required

    value ->
      raise "COURIERCMS_EXTENSION_SIGNATURE_POLICY must be optional or required; got: #{inspect(value)}"
  end

trusted_extension_keys =
  System.get_env("COURIERCMS_EXTENSION_TRUSTED_KEYS", "")
  |> String.split(",", trim: true)
  |> Enum.reduce(%{}, fn entry, keys ->
    case String.split(entry, ":", parts: 2) do
      [key_id, encoded_key] when key_id != "" and encoded_key != "" ->
        case Base.decode64(encoded_key) do
          {:ok, public_key} when byte_size(public_key) == 32 ->
            Map.put(keys, key_id, public_key)

          _other ->
            raise "COURIERCMS_EXTENSION_TRUSTED_KEYS contains an invalid Ed25519 public key"
        end

      _other ->
        raise "COURIERCMS_EXTENSION_TRUSTED_KEYS must contain comma-separated keyId:base64 entries"
    end
  end)

extensions_dir =
  case System.get_env("COURIERCMS_EXTENSIONS_PATH") do
    value when is_binary(value) and value != "" ->
      value

    _other when local_production? ->
      CourierCMS.LocalPaths.extensions_dir()

    _other ->
      Application.fetch_env!(:couriercms, :extensions_dir)
  end

extension_cache_dir =
  case System.get_env("COURIERCMS_EXTENSION_CACHE_DIR") do
    value when is_binary(value) and value != "" ->
      value

    _other when local_production? ->
      CourierCMS.LocalPaths.extension_cache_dir()

    _other ->
      Application.fetch_env!(:couriercms, :extension_cache_dir)
  end

config :couriercms,
  extensions_dir: Path.expand(extensions_dir),
  extension_cache_dir: Path.expand(extension_cache_dir),
  extension_signature_policy: signature_policy,
  extension_trusted_keys: trusted_extension_keys

asset_temp_dir =
  case System.get_env("COURIERCMS_ASSET_TEMP_PATH") do
    value when is_binary(value) and value != "" -> value
    _other when local_production? -> Path.join(CourierCMS.LocalPaths.temporary_dir(), "assets")
    _other -> nil
  end

if asset_temp_dir, do: config(:couriercms, :asset_temp_dir, Path.expand(asset_temp_dir))

local_secrets =
  if config_env() == :prod and release_profile == :local do
    CourierCMS.LocalSecrets.load_or_create!()
  end

if config_env() == :prod and release_profile == :server do
  config :couriercms,
    allow_http_cms_endpoints:
      System.get_env("COURIERCMS_ALLOW_HTTP_CMS_ENDPOINTS", "false") in ["true", "1"],
    allow_private_cms_networks:
      System.get_env("COURIERCMS_ALLOW_PRIVATE_NETWORKS", "false") in ["true", "1"],
    allow_unsafe_local_cms_endpoints:
      System.get_env("COURIERCMS_ALLOW_UNSAFE_LOCAL_ENDPOINTS", "false") in ["true", "1"],
    allow_unresolved_cms_hosts: false
end

if config_env() == :prod and release_profile == :local do
  config :couriercms,
    failure_email_alerts: false,
    require_extension_consistency: false,
    dns_cluster_query: nil

  config :couriercms, CourierCMS.Vault,
    json_library: Jason,
    ciphers: [
      default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: local_secrets.vault_key}
    ]

  config :couriercms, CourierCMS.Mailer, adapter: Swoosh.Adapters.Local
end

if delivery_lock_ttl = System.get_env("COURIERCMS_DELIVERY_LOCK_TTL_MS") do
  case Integer.parse(delivery_lock_ttl) do
    {milliseconds, ""} when milliseconds >= 60_000 ->
      config :couriercms, :delivery_lock_ttl_ms, milliseconds

    _other ->
      raise "COURIERCMS_DELIVERY_LOCK_TTL_MS must be an integer of at least 60000"
  end
end

runtime_config_maxima = %{
  max_planning_pages: 1_000_000,
  delivery_max_attempts: 100,
  asset_delivery_max_attempts: 100,
  planning_max_attempts: 100,
  delivery_backoff_cap_seconds: 3_600,
  asset_delivery_backoff_cap_seconds: 3_600,
  planning_backoff_cap_seconds: 3_600,
  retention_batch_size: 100_000
}

for {environment_name, application_key, minimum} <- [
      {"COURIERCMS_MAX_SOURCE_PAGE_ITEMS", :max_source_page_items, 1},
      {"COURIERCMS_MAX_RUN_ITEMS", :max_run_items, 1},
      {"COURIERCMS_MAX_DELIVERY_BYTES", :max_delivery_bytes, 1_024},
      {"COURIERCMS_MAX_ASSET_BYTES", :max_asset_bytes, 1_024},
      {"COURIERCMS_MAX_CONTENT_BUNDLE_NODES", :max_content_bundle_nodes, 1},
      {"COURIERCMS_MAX_CONTENT_BUNDLE_RELATIONSHIPS", :max_content_bundle_relationships, 0},
      {"COURIERCMS_MAX_CONTENT_BUNDLE_ASSETS", :max_content_bundle_assets, 0},
      {"COURIERCMS_MAX_PLANNING_PAGES", :max_planning_pages, 1},
      {"COURIERCMS_DELIVERY_MAX_ATTEMPTS", :delivery_max_attempts, 1},
      {"COURIERCMS_ASSET_DELIVERY_MAX_ATTEMPTS", :asset_delivery_max_attempts, 1},
      {"COURIERCMS_PLANNING_MAX_ATTEMPTS", :planning_max_attempts, 1},
      {"COURIERCMS_DELIVERY_BACKOFF_CAP_SECONDS", :delivery_backoff_cap_seconds, 1},
      {"COURIERCMS_ASSET_DELIVERY_BACKOFF_CAP_SECONDS", :asset_delivery_backoff_cap_seconds, 1},
      {"COURIERCMS_PLANNING_BACKOFF_CAP_SECONDS", :planning_backoff_cap_seconds, 1},
      {"COURIERCMS_MAX_ADAPTER_RESPONSE_BYTES", :max_adapter_response_bytes, 1_024},
      {"COURIERCMS_MAX_WEBHOOK_BYTES", :max_webhook_bytes, 1_024},
      {"COURIERCMS_ADAPTER_CONNECT_TIMEOUT_MS", :adapter_connect_timeout_ms, 100},
      {"COURIERCMS_ADAPTER_RECEIVE_TIMEOUT_MS", :adapter_receive_timeout_ms, 100},
      {"COURIERCMS_ASSET_RECEIVE_TIMEOUT_MS", :asset_receive_timeout_ms, 1_000},
      {"COURIERCMS_DEFAULT_CONNECTION_CONCURRENCY", :default_connection_concurrency, 1},
      {"COURIERCMS_DEFAULT_CONNECTION_REQUESTS_PER_SECOND",
       :default_connection_requests_per_second, 1},
      {"COURIERCMS_STRANDED_AFTER_MS", :stranded_after_ms, 60_000},
      {"COURIERCMS_RUN_RETENTION_DAYS", :run_retention_days, 1},
      {"COURIERCMS_EVENT_RETENTION_DAYS", :event_retention_days, 1},
      {"COURIERCMS_AUDIT_RETENTION_DAYS", :audit_retention_days, 1},
      {"COURIERCMS_RETENTION_BATCH_SIZE", :retention_batch_size, 1},
      {"COURIERCMS_EXTENSION_MAX_PACKAGE_BYTES", :extension_max_package_bytes, 1_024},
      {"COURIERCMS_EXTENSION_MAX_UNCOMPRESSED_BYTES", :extension_max_uncompressed_bytes, 1_024},
      {"COURIERCMS_EXTENSION_MAX_ENTRIES", :extension_max_entries, 1},
      {"COURIERCMS_EXTENSION_MAX_PACKAGES", :extension_max_packages, 1}
    ],
    value = System.get_env(environment_name),
    not is_nil(value) do
  case Integer.parse(value) do
    {integer, ""} when integer >= minimum ->
      case Map.get(runtime_config_maxima, application_key) do
        maximum when is_integer(maximum) and integer > maximum ->
          raise "#{environment_name} must not exceed #{maximum}"

        _maximum ->
          config :couriercms, application_key, integer
      end

    _other ->
      raise "#{environment_name} must be an integer of at least #{minimum}"
  end
end

if config_env() == :prod and release_profile == :server do
  vault_key_version = System.get_env("COURIERCMS_VAULT_KEY_VERSION", "1")

  if not Regex.match?(~r/^\d+$/, vault_key_version) do
    raise "COURIERCMS_VAULT_KEY_VERSION must contain only digits"
  end

  vault_key =
    "COURIERCMS_VAULT_KEY"
    |> System.fetch_env!()
    |> Base.decode64!()

  if byte_size(vault_key) != 32 do
    raise "COURIERCMS_VAULT_KEY must decode to exactly 32 bytes"
  end

  current_cipher =
    {:default, {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V#{vault_key_version}", key: vault_key}}

  previous_cipher =
    case {System.get_env("COURIERCMS_PREVIOUS_VAULT_KEY"),
          System.get_env("COURIERCMS_PREVIOUS_VAULT_KEY_VERSION")} do
      {nil, nil} ->
        []

      {encoded_key, version} when is_binary(encoded_key) and is_binary(version) ->
        key = Base.decode64!(encoded_key)

        if byte_size(key) != 32 or not Regex.match?(~r/^\d+$/, version) do
          raise "COURIERCMS_PREVIOUS_VAULT_KEY must decode to 32 bytes and its version must be numeric"
        end

        [previous: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V#{version}", key: key}]

      _other ->
        raise "set both COURIERCMS_PREVIOUS_VAULT_KEY and COURIERCMS_PREVIOUS_VAULT_KEY_VERSION"
    end

  config :couriercms, CourierCMS.Vault,
    json_library: Jason,
    ciphers: [current_cipher | previous_cipher]

  smtp_relay = System.fetch_env!("SMTP_RELAY")
  smtp_username = System.fetch_env!("SMTP_USERNAME")
  smtp_password = System.fetch_env!("SMTP_PASSWORD")

  config :couriercms, CourierCMS.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: smtp_relay,
    username: smtp_username,
    password: smtp_password,
    port: String.to_integer(System.get_env("SMTP_PORT", "587")),
    ssl: System.get_env("SMTP_SSL", "false") == "true",
    tls: :always,
    auth: :always
end

if config_env() == :prod and release_profile == :local do
  CourierCMS.LocalPaths.prepare!()

  config :couriercms, CourierCMS.Repo,
    database: CourierCMS.LocalPaths.database_path(),
    pool_size: 1,
    default_transaction_mode: :immediate,
    journal_mode: :wal,
    temp_store: :memory,
    busy_timeout: 5_000,
    foreign_keys: :on

  config :couriercms, CourierCMSWeb.Endpoint,
    url: [
      host: "localhost",
      port: String.to_integer(System.get_env("PORT", "4000")),
      scheme: "http"
    ],
    http: [ip: CourierCMS.ReleaseProfile.http_ip()],
    secret_key_base: local_secrets.cookie_secret
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/couriercms start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") && deployment_role != :worker do
  config :couriercms, CourierCMSWeb.Endpoint, server: true
end

config :couriercms, CourierCMSWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :couriercms, CourierCMSWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/courier_cms_web/router\.ex$"E,
        ~r"lib/courier_cms_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod and release_profile == :server do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  database_ssl =
    case System.get_env("DATABASE_SSL", "false") |> String.downcase() do
      value when value in ["false", "0"] ->
        false

      value when value in ["true", "1", "require"] ->
        true

      "verify_full" ->
        database_uri = URI.parse(database_url)
        ca_certfile = System.fetch_env!("DATABASE_SSL_CA_CERTFILE")

        [
          verify: :verify_peer,
          cacertfile: String.to_charlist(ca_certfile),
          server_name_indication: String.to_charlist(database_uri.host),
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]

      value ->
        raise "DATABASE_SSL must be false, true, require, or verify_full; got: #{inspect(value)}"
    end

  config :couriercms, CourierCMS.Repo,
    ssl: database_ssl,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    pool_count: String.to_integer(System.get_env("POOL_COUNT") || "1"),
    queue_target: String.to_integer(System.get_env("DB_QUEUE_TARGET_MS") || "50"),
    queue_interval: String.to_integer(System.get_env("DB_QUEUE_INTERVAL_MS") || "1000"),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :couriercms, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :couriercms, CourierCMSWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :couriercms, CourierCMSWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :couriercms, CourierCMSWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end

defmodule CourierCMS.Connections.Connection do
  @moduledoc """
  A configured instance of a CMS adapter.

  Credentials are stored as encrypted ciphertext and deliberately excluded from
  normal inspection. Credential encryption and rotation are owned by the
  Connections context rather than general changesets.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias CourierCMS.Routes.Route

  @derive {Inspect, except: [:credentials]}
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "connections" do
    field :name, :string
    field :adapter_key, :string
    field :extension_id, :string
    field :component_id, :string
    field :endpoint, :string
    field :settings, :map, default: %{}
    field :credentials, CourierCMS.EncryptedMap, redact: true
    field :configuration, :map, virtual: true, default: %{}
    field :credential_values, :map, virtual: true, default: %{}, redact: true
    field :capabilities, :map, default: %{}
    field :enabled, :boolean, default: true
    field :last_test_status, :string
    field :last_tested_at, :utc_datetime_usec

    belongs_to :workspace, CourierCMS.Workspaces.Workspace
    has_many :source_routes, Route, foreign_key: :source_connection_id
    has_many :target_routes, Route, foreign_key: :target_connection_id

    timestamps()
  end

  @doc false
  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [
      :name,
      :adapter_key,
      :extension_id,
      :component_id,
      :endpoint,
      :settings,
      :enabled,
      :workspace_id,
      :configuration,
      :credential_values
    ])
    |> validate_required([
      :name,
      :adapter_key,
      :extension_id,
      :component_id,
      :endpoint,
      :workspace_id
    ])
    |> validate_length(:name, min: 1, max: 160)
    |> validate_format(:adapter_key, ~r/^[a-z][a-z0-9_]*$/)
    |> validate_format(:extension_id, ~r/^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)+$/)
    |> validate_format(:component_id, ~r/^[a-z][a-z0-9]*(?:[_-][a-z0-9]+)*$/)
    |> validate_endpoint()
    |> unique_constraint([:workspace_id, :name])
    |> foreign_key_constraint(:workspace_id)
  end

  defp validate_endpoint(changeset) do
    validate_change(changeset, :endpoint, fn :endpoint, endpoint ->
      case URI.parse(endpoint) do
        %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
          []

        _other ->
          [endpoint: "must be an absolute HTTP or HTTPS URL"]
      end
    end)
  end
end

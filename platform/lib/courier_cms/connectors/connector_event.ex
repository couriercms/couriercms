defmodule CourierCMS.Connectors.ConnectorEvent do
  @moduledoc "A durable, deduplicated event received from an installed CMS Connector."

  use Ecto.Schema
  import Ecto.Changeset

  alias CourierCMS.Connections.Connection

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "connector_events" do
    field :contract_version, :integer
    field :external_event_id, :string
    field :event_kind, :string
    field :source_item_key, :string
    field :source_modified_at, :utc_datetime_usec
    field :status, Ecto.Enum, values: [:accepted, :processing, :processed, :ignored, :failed]
    field :runs_started, :integer, default: 0
    field :error_summary, :string
    field :received_at, :utc_datetime_usec
    field :processed_at, :utc_datetime_usec

    belongs_to :connection, Connection
    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :connection_id,
      :contract_version,
      :external_event_id,
      :event_kind,
      :source_item_key,
      :source_modified_at,
      :status,
      :runs_started,
      :error_summary,
      :received_at,
      :processed_at
    ])
    |> validate_required([
      :connection_id,
      :contract_version,
      :external_event_id,
      :event_kind,
      :status,
      :received_at
    ])
    |> validate_length(:external_event_id, min: 8, max: 160)
    |> validate_inclusion(:contract_version, [1])
    |> validate_length(:event_kind, max: 80)
    |> validate_length(:source_item_key, max: 255)
    |> validate_number(:runs_started, greater_than_or_equal_to: 0)
    |> unique_constraint([:connection_id, :external_event_id])
    |> foreign_key_constraint(:connection_id)
  end
end

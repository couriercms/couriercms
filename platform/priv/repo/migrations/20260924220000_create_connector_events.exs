defmodule CourierCMS.Repo.Migrations.CreateConnectorEvents do
  use Ecto.Migration

  def change do
    create table(:connector_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :connection_id,
          references(:connections, type: :binary_id, on_delete: :delete_all),
          null: false

      add :contract_version, :integer, null: false
      add :external_event_id, :text, null: false
      add :event_kind, :text, null: false
      add :source_item_key, :text
      add :source_modified_at, :utc_datetime_usec
      add :status, :text, null: false, default: "accepted"
      add :runs_started, :integer, null: false, default: 0
      add :error_summary, :text
      add :received_at, :utc_datetime_usec, null: false
      add :processed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:connector_events, [:connection_id, :external_event_id])
    create index(:connector_events, [:status, :received_at])

    create constraint(:connector_events, :valid_connector_event_status,
             check: "status IN ('accepted', 'processing', 'processed', 'ignored', 'failed')"
           )

    create constraint(:connector_events, :supported_connector_contract_version,
             check: "contract_version = 1"
           )
  end
end

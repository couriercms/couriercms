defmodule CourierCMS.Repo.Migrations.CreateCoreDomain do
  use Ecto.Migration

  def change do
    create table(:connections, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :text, null: false
      add :adapter_key, :text, null: false
      add :endpoint, :text, null: false
      add :settings, :map, null: false, default: %{}
      add :credentials, :binary
      add :capabilities, :map, null: false, default: %{}
      add :enabled, :boolean, null: false, default: true
      add :last_test_status, :text
      add :last_tested_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:connections, [:adapter_key])
    create unique_index(:connections, [:name])

    create table(:routes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :text, null: false

      add :source_connection_id,
          references(:connections, type: :binary_id, on_delete: :restrict),
          null: false

      add :target_connection_id,
          references(:connections, type: :binary_id, on_delete: :restrict),
          null: false

      add :enabled, :boolean, null: false, default: false
      add :destination_key, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:routes, [:name])
    create unique_index(:routes, [:destination_key])
    create index(:routes, [:source_connection_id])
    create index(:routes, [:target_connection_id])

    create constraint(:routes, :different_source_and_target_connections,
             check: "source_connection_id <> target_connection_id"
           )

    create table(:route_revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :route_id, references(:routes, type: :binary_id, on_delete: :delete_all), null: false
      add :revision_number, :integer, null: false
      add :selection, :map, null: false, default: %{}
      add :aggregation_rules, :map, null: false, default: %{}
      add :mapping, :map, null: false, default: %{}
      add :delivery_contract, :map, null: false, default: %{}
      add :contract_version, :integer, null: false
      add :transformations, {:array, :map}, null: false, default: []
      add :trigger_settings, :map, null: false, default: %{}
      add :checksum, :text, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:route_revisions, [:route_id, :revision_number])
    create unique_index(:route_revisions, [:route_id, :checksum])

    create constraint(:route_revisions, :positive_revision_number, check: "revision_number > 0")

    create constraint(:route_revisions, :positive_contract_version, check: "contract_version > 0")

    alter table(:routes) do
      add :current_revision_id,
          references(:route_revisions, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:routes, [:current_revision_id])

    create table(:runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :route_id, references(:routes, type: :binary_id, on_delete: :restrict), null: false

      add :route_revision_id,
          references(:route_revisions, type: :binary_id, on_delete: :restrict),
          null: false

      add :trigger_kind, :text, null: false
      add :trigger_metadata, :map, null: false, default: %{}
      add :status, :text, null: false, default: "queued"
      add :items_discovered, :integer, null: false, default: 0
      add :items_succeeded, :integer, null: false, default: 0
      add :items_failed, :integer, null: false, default: 0
      add :items_retrying, :integer, null: false, default: 0
      add :items_skipped, :integer, null: false, default: 0
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :cancelled_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:runs, [:route_id, :inserted_at])
    create index(:runs, [:status])

    create constraint(:runs, :valid_run_status,
             check:
               "status IN ('queued', 'planning', 'running', 'succeeded', 'partially_succeeded', 'failed', 'cancelled')"
           )

    create constraint(:runs, :valid_trigger_kind,
             check: "trigger_kind IN ('manual', 'schedule', 'polling', 'save', 'publish')"
           )

    create table(:route_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :route_id, references(:routes, type: :binary_id, on_delete: :restrict), null: false
      add :source_item_key, :text, null: false
      add :locale_key, :text, null: false
      add :source_revision_key, :text, null: false
      add :target_item_id, :text
      add :ownership_evidence, :map, null: false, default: %{}
      add :last_content_hash, :text
      add :last_delivered_at, :utc_datetime_usec
      add :state, :text, null: false, default: "pending"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(
             :route_items,
             [:route_id, :source_item_key, :locale_key, :source_revision_key],
             name: :route_items_logical_identity_index
           )

    create index(:route_items, [:target_item_id])

    create constraint(:route_items, :valid_route_item_state,
             check: "state IN ('pending', 'delivered', 'failed')"
           )

    create table(:run_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, references(:runs, type: :binary_id, on_delete: :delete_all), null: false

      add :route_item_id,
          references(:route_items, type: :binary_id, on_delete: :nilify_all)

      add :delivery_key, :text, null: false
      add :source_item_key, :text, null: false
      add :locale_key, :text, null: false
      add :source_revision_key, :text, null: false
      add :planned_operation, :text
      add :status, :text, null: false, default: "pending"
      add :attempt_count, :integer, null: false, default: 0
      add :error_category, :text
      add :error_summary, :text
      add :content_hash, :text
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:run_items, [:run_id, :delivery_key])
    create index(:run_items, [:run_id, :status])
    create index(:run_items, [:route_item_id])

    create constraint(:run_items, :valid_run_item_status,
             check:
               "status IN ('pending', 'processing', 'succeeded', 'retrying', 'failed', 'skipped', 'cancelled')"
           )

    alter table(:route_items) do
      add :last_successful_run_id,
          references(:runs, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:route_items, [:last_successful_run_id])
  end
end

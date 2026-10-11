defmodule CourierCMS.Repo.Migrations.CreateServerInitialBaseline do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS citext"
    Oban.Migration.up(version: 14)

    create table(:workspaces, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :text, null: false
      add :slug, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:workspaces, [:slug])

    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :citext, null: false
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])

    create table(:users_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :utc_datetime
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])

    create table(:workspace_memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :role, :text, null: false
      add :status, :text, null: false, default: "invited"
      add :invited_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :blocked_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :blocked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:workspace_memberships, [:workspace_id, :user_id])
    create index(:workspace_memberships, [:user_id, :status])

    create constraint(:workspace_memberships, :valid_membership_role,
             check: "role IN ('owner', 'admin', 'operator', 'viewer')"
           )

    create constraint(:workspace_memberships, :valid_membership_status,
             check: "status IN ('invited', 'active', 'blocked')"
           )

    create table(:audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :actor_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :action, :text, null: false
      add :resource_type, :text, null: false
      add :resource_id, :text
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:audit_events, [:workspace_id, :inserted_at])
    create index(:audit_events, [:actor_user_id])

    create table(:connections, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :name, :text, null: false
      add :adapter_key, :text, null: false
      add :extension_id, :text, null: false
      add :component_id, :text, null: false
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
    create index(:connections, [:extension_id, :component_id])
    create index(:connections, [:workspace_id])
    create unique_index(:connections, [:workspace_id, :name])

    create table(:routes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :name, :text, null: false

      add :source_connection_id, references(:connections, type: :binary_id, on_delete: :restrict),
        null: false

      add :target_connection_id, references(:connections, type: :binary_id, on_delete: :restrict),
        null: false

      add :enabled, :boolean, null: false, default: false
      add :archived_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:routes, [:source_connection_id])
    create index(:routes, [:target_connection_id])
    create index(:routes, [:workspace_id])
    create unique_index(:routes, [:workspace_id, :name])

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
      add :projections, {:array, :map}, null: false, default: []
      add :source_extension_id, :text, null: false
      add :source_component_id, :text, null: false
      add :target_extension_id, :text, null: false
      add :target_component_id, :text, null: false
      add :delivery_name_path, :text, null: false, default: "payload.title"
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:route_revisions, [:route_id, :revision_number])
    create unique_index(:route_revisions, [:route_id, :checksum])
    create index(:route_revisions, [:source_extension_id, :source_component_id])
    create index(:route_revisions, [:target_extension_id, :target_component_id])
    create constraint(:route_revisions, :positive_revision_number, check: "revision_number > 0")
    create constraint(:route_revisions, :positive_contract_version, check: "contract_version > 0")

    create table(:destinations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :target_connection_id, references(:connections, type: :binary_id, on_delete: :restrict),
        null: false

      add :owner_route_id, references(:routes, type: :binary_id, on_delete: :restrict)
      add :name, :text, null: false
      add :scope, :map, null: false, default: %{}
      add :scope_key, :text, null: false
      add :lifecycle_status, :text, null: false, default: "available"
      add :validation_status, :text, null: false, default: "unknown"
      add :ownership_evidence, :map, null: false, default: %{}
      add :last_validation_error, :text
      add :validated_at, :utc_datetime_usec
      add :first_delivered_at, :utc_datetime_usec
      add :retired_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:destinations, [:workspace_id, :name])
    create index(:destinations, [:target_connection_id, :lifecycle_status])
    create index(:destinations, [:owner_route_id])

    create unique_index(:destinations, [:target_connection_id, :scope_key],
             where: "lifecycle_status <> 'retired'",
             name: :destinations_active_scope_index
           )

    create constraint(:destinations, :valid_destination_lifecycle,
             check: "lifecycle_status IN ('available', 'reserved', 'active', 'retired')"
           )

    create constraint(:destinations, :valid_destination_validation,
             check: "validation_status IN ('unknown', 'valid', 'invalid')"
           )

    alter table(:routes) do
      add :current_revision_id,
          references(:route_revisions, type: :binary_id, on_delete: :nilify_all)

      add :current_destination_id,
          references(:destinations, type: :binary_id, on_delete: :restrict), null: false
    end

    create index(:routes, [:current_revision_id])

    create unique_index(:routes, [:current_destination_id],
             where: "archived_at IS NULL",
             name: :routes_current_destination_id_index
           )

    create table(:connector_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :connection_id, references(:connections, type: :binary_id, on_delete: :delete_all),
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

    create table(:runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :route_id, references(:routes, type: :binary_id, on_delete: :restrict), null: false

      add :route_revision_id,
          references(:route_revisions, type: :binary_id, on_delete: :restrict), null: false

      add :destination_id, references(:destinations, type: :binary_id, on_delete: :restrict),
        null: false

      add :initiated_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :connector_event_id,
          references(:connector_events, type: :binary_id, on_delete: :nilify_all)

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
      add :error_category, :text
      add :error_summary, :text
      add :schedule_key, :text
      add :planning_cursor, :map
      add :planning_page, :integer, null: false, default: 0
      add :planning_complete, :boolean, null: false, default: false
      add :source_artifact, :map
      add :target_artifact, :map
      add :processor_artifacts, {:array, :map}, null: false, default: []
      timestamps(type: :utc_datetime_usec)
    end

    create index(:runs, [:route_id, :inserted_at])
    create index(:runs, [:status])
    create index(:runs, [:initiated_by_user_id])
    create index(:runs, [:destination_id, :inserted_at])

    create unique_index(:runs, [:route_id, :connector_event_id],
             where: "connector_event_id IS NOT NULL"
           )

    create unique_index(:runs, [:route_id, :schedule_key],
             where: "schedule_key IS NOT NULL",
             name: :runs_route_schedule_key_index
           )

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
      add :state, :text, null: false, default: "pending"
      add :last_source_modified_at, :utc_datetime_usec
      add :last_source_change_token, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:route_items, [:route_id, :source_item_key, :locale_key],
             name: :route_items_logical_identity_index
           )

    create constraint(:route_items, :valid_route_item_state,
             check: "state IN ('pending', 'delivered', 'failed')"
           )

    create table(:delivery_assets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :route_id, references(:routes, type: :binary_id, on_delete: :restrict), null: false
      add :source_asset_key, :text, null: false
      add :variant_key, :text, null: false, default: "original"
      add :filename, :text
      add :media_type, :text
      add :byte_size, :bigint
      add :source_checksum, :text
      add :metadata, :map, null: false, default: %{}
      add :state, :text, null: false, default: "pending"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:delivery_assets, [:route_id, :source_asset_key, :variant_key],
             name: :delivery_assets_logical_identity_index
           )

    create index(:delivery_assets, [:route_id, :state])

    create constraint(:delivery_assets, :valid_delivery_asset_state,
             check: "state IN ('pending', 'delivered', 'failed')"
           )

    create table(:run_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, references(:runs, type: :binary_id, on_delete: :delete_all), null: false
      add :route_item_id, references(:route_items, type: :binary_id, on_delete: :nilify_all)
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
      add :source_modified_at, :utc_datetime_usec
      add :source_change_token, :text
      add :source_state, :text, null: false, default: "published"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:run_items, [:run_id, :delivery_key])
    create index(:run_items, [:run_id, :status])
    create index(:run_items, [:route_item_id])

    create constraint(:run_items, :valid_run_item_status,
             check:
               "status IN ('pending', 'processing', 'succeeded', 'retrying', 'failed', 'skipped', 'cancelled')"
           )

    create table(:run_assets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, references(:runs, type: :binary_id, on_delete: :delete_all), null: false

      add :delivery_asset_id,
          references(:delivery_assets, type: :binary_id, on_delete: :restrict),
          null: false

      add :asset_key, :text, null: false
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

    create unique_index(:run_assets, [:run_id, :asset_key])
    create index(:run_assets, [:run_id, :status])
    create index(:run_assets, [:delivery_asset_id])

    create constraint(:run_assets, :valid_run_asset_status,
             check:
               "status IN ('pending', 'processing', 'succeeded', 'retrying', 'failed', 'skipped', 'cancelled')"
           )

    create table(:run_item_assets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :run_item_id, references(:run_items, type: :binary_id, on_delete: :delete_all),
        null: false

      add :run_asset_id, references(:run_assets, type: :binary_id, on_delete: :delete_all),
        null: false

      add :field_path, :text, null: false
      add :required, :boolean, null: false, default: true
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:run_item_assets, [:run_item_id, :run_asset_id, :field_path])
    create index(:run_item_assets, [:run_asset_id])

    create table(:delivery_bindings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :route_item_id, references(:route_items, type: :binary_id, on_delete: :restrict),
        null: false

      add :destination_id, references(:destinations, type: :binary_id, on_delete: :restrict),
        null: false

      add :target_reference, :text
      add :ownership_evidence, :map, null: false, default: %{}
      add :last_content_hash, :text
      add :last_delivered_at, :utc_datetime_usec
      add :state, :text, null: false, default: "pending"
      add :last_successful_run_id, references(:runs, type: :binary_id, on_delete: :nilify_all)

      add :last_route_revision_id,
          references(:route_revisions, type: :binary_id, on_delete: :restrict)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:delivery_bindings, [:route_item_id, :destination_id])
    create index(:delivery_bindings, [:destination_id, :last_delivered_at])
    create index(:delivery_bindings, [:target_reference])

    create constraint(:delivery_bindings, :valid_delivery_binding_state,
             check: "state IN ('pending', 'delivered', 'failed')"
           )

    create table(:delivery_asset_bindings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :delivery_asset_id,
          references(:delivery_assets, type: :binary_id, on_delete: :restrict),
          null: false

      add :destination_id, references(:destinations, type: :binary_id, on_delete: :restrict),
        null: false

      add :target_reference, :text
      add :ownership_evidence, :map, null: false, default: %{}
      add :last_content_hash, :text
      add :last_delivered_at, :utc_datetime_usec
      add :state, :text, null: false, default: "pending"
      add :last_successful_run_id, references(:runs, type: :binary_id, on_delete: :nilify_all)

      add :last_route_revision_id,
          references(:route_revisions, type: :binary_id, on_delete: :restrict)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:delivery_asset_bindings, [:delivery_asset_id, :destination_id])
    create index(:delivery_asset_bindings, [:destination_id, :last_delivered_at])
    create index(:delivery_asset_bindings, [:target_reference])

    create constraint(:delivery_asset_bindings, :valid_delivery_asset_binding_state,
             check: "state IN ('pending', 'delivered', 'failed')"
           )

    create table(:checkpoints, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :route_id, references(:routes, type: :binary_id, on_delete: :delete_all), null: false

      add :source_connection_id, references(:connections, type: :binary_id, on_delete: :restrict),
        null: false

      add :last_run_id, references(:runs, type: :binary_id, on_delete: :nilify_all)
      add :adapter_key, :text, null: false
      add :value, :map, null: false, default: %{}
      add :last_advanced_at, :utc_datetime_usec, null: false
      add :last_full_scan_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:checkpoints, [:route_id])
    create index(:checkpoints, [:source_connection_id])
    create index(:checkpoints, [:last_run_id])

    create table(:delivery_locks, primary_key: false) do
      add :delivery_key, :text, primary_key: true
      add :owner_token, :binary_id, null: false
      add :expires_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:delivery_locks, [:expires_at])

    create table(:connection_leases, primary_key: false) do
      add :connection_id, references(:connections, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :slot_number, :integer, primary_key: true
      add :owner_token, :binary_id, null: false
      add :expires_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:connection_leases, [:expires_at])
    create constraint(:connection_leases, :positive_slot_number, check: "slot_number > 0")

    create table(:connection_rate_buckets, primary_key: false) do
      add :connection_id, references(:connections, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :bucket, :bigint, primary_key: true
      add :request_count, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create index(:connection_rate_buckets, [:bucket])

    create table(:worker_heartbeats, primary_key: false) do
      add :node_id, :text, primary_key: true
      add :role, :text, null: false
      add :queues, {:array, :text}, null: false, default: []
      add :version, :text, null: false
      add :last_seen_at, :utc_datetime_usec, null: false
      add :extension_fingerprint, :text
      add :extension_set, {:array, :map}, null: false, default: []
      add :extension_status, :text, null: false, default: "unknown"
      timestamps(type: :utc_datetime_usec)
    end

    create index(:worker_heartbeats, [:last_seen_at])
  end

  def down do
    raise "the Server initial baseline is recreated rather than rolled back"
  end
end

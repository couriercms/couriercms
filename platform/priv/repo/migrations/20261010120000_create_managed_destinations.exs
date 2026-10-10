defmodule CourierCMS.Repo.Migrations.CreateManagedDestinations do
  use Ecto.Migration

  def up do
    create table(:destinations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :target_connection_id,
          references(:connections, type: :binary_id, on_delete: :restrict),
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
      add :current_destination_id,
          references(:destinations, type: :binary_id, on_delete: :restrict)

      add :archived_at, :utc_datetime_usec
    end

    execute("""
    INSERT INTO destinations (
      id, workspace_id, target_connection_id, owner_route_id, name, scope,
      scope_key, lifecycle_status, validation_status, validated_at, inserted_at, updated_at
    )
    SELECT
      gen_random_uuid(), r.workspace_id, r.target_connection_id, r.id,
      r.name || ' Destination', COALESCE(rr.destination_settings, '{}'::jsonb),
      r.destination_key,
      CASE WHEN EXISTS (
        SELECT 1 FROM route_items ri
        WHERE ri.route_id = r.id AND ri.target_item_id IS NOT NULL
      ) THEN 'active' ELSE 'reserved' END,
      'valid', NOW(), NOW(), NOW()
    FROM routes r
    LEFT JOIN route_revisions rr ON rr.id = r.current_revision_id
    """)

    execute("""
    UPDATE routes r
    SET current_destination_id = d.id
    FROM destinations d
    WHERE d.owner_route_id = r.id
    """)

    alter table(:routes) do
      modify :current_destination_id, :binary_id, null: false
    end

    create unique_index(:routes, [:current_destination_id],
             where: "archived_at IS NULL",
             name: :routes_current_destination_id_index
           )

    alter table(:route_revisions) do
      add :delivery_name_path, :text, null: false, default: "payload.title"
    end

    alter table(:runs) do
      add :destination_id, references(:destinations, type: :binary_id, on_delete: :restrict)
    end

    execute("""
    UPDATE runs run
    SET destination_id = route.current_destination_id
    FROM routes route
    WHERE route.id = run.route_id
    """)

    alter table(:runs) do
      modify :destination_id, :binary_id, null: false
    end

    create index(:runs, [:destination_id, :inserted_at])

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

      add :last_successful_run_id,
          references(:runs, type: :binary_id, on_delete: :nilify_all)

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

    execute("""
    INSERT INTO delivery_bindings (
      id, route_item_id, destination_id, target_reference, ownership_evidence,
      last_content_hash, last_delivered_at, state, last_successful_run_id,
      last_route_revision_id, inserted_at, updated_at
    )
    SELECT
      gen_random_uuid(), ri.id, r.current_destination_id, ri.target_item_id,
      ri.ownership_evidence, ri.last_content_hash, ri.last_delivered_at, ri.state,
      ri.last_successful_run_id, ri.last_route_revision_id, NOW(), NOW()
    FROM route_items ri
    JOIN routes r ON r.id = ri.route_id
    WHERE ri.target_item_id IS NOT NULL OR ri.ownership_evidence <> '{}'::jsonb
    """)

    alter table(:route_items) do
      remove :target_item_id
      remove :ownership_evidence
      remove :last_content_hash
      remove :last_delivered_at
      remove :last_successful_run_id
      remove :last_route_revision_id
    end

    alter table(:route_revisions) do
      remove :destination_settings
    end

    alter table(:routes) do
      remove :destination_key
    end
  end

  def down do
    raise "managed Destinations are a clean-break migration and cannot be rolled back safely"
  end
end

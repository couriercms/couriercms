defmodule CourierCMS.Repo.Migrations.CreateWorkspacesAndMemberships do
  use Ecto.Migration

  def up do
    default_workspace_id = Ecto.UUID.generate()

    create table(:workspaces, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :text, null: false
      add :slug, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:workspaces, [:slug])

    execute """
    INSERT INTO workspaces (id, name, slug, inserted_at, updated_at)
    VALUES ('#{default_workspace_id}', 'CourierCMS', 'default', NOW(), NOW())
    """

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

    alter table(:connections) do
      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict)
    end

    execute "UPDATE connections SET workspace_id = '#{default_workspace_id}'"
    alter table(:connections), do: modify(:workspace_id, :binary_id, null: false)
    create index(:connections, [:workspace_id])
    drop_if_exists unique_index(:connections, [:name])
    create unique_index(:connections, [:workspace_id, :name])

    alter table(:routes) do
      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict)
    end

    execute "UPDATE routes SET workspace_id = '#{default_workspace_id}'"
    alter table(:routes), do: modify(:workspace_id, :binary_id, null: false)
    create index(:routes, [:workspace_id])
    drop_if_exists unique_index(:routes, [:name])
    create unique_index(:routes, [:workspace_id, :name])

    alter table(:runs) do
      add :initiated_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:runs, [:initiated_by_user_id])
  end

  def down do
    drop_if_exists index(:runs, [:initiated_by_user_id])
    alter table(:runs), do: remove(:initiated_by_user_id)

    drop_if_exists index(:routes, [:workspace_id])
    drop_if_exists unique_index(:routes, [:workspace_id, :name])
    create unique_index(:routes, [:name])
    alter table(:routes), do: remove(:workspace_id)

    drop_if_exists index(:connections, [:workspace_id])
    drop_if_exists unique_index(:connections, [:workspace_id, :name])
    create unique_index(:connections, [:name])
    alter table(:connections), do: remove(:workspace_id)

    drop table(:audit_events)
    drop table(:workspace_memberships)
    drop table(:workspaces)
  end
end

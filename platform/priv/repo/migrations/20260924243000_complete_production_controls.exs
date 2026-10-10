defmodule CourierCMS.Repo.Migrations.CompleteProductionControls do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      add :planning_cursor, :map
      add :planning_page, :integer, null: false, default: 0
      add :planning_complete, :boolean, null: false, default: false
    end

    create table(:connection_rate_buckets, primary_key: false) do
      add :connection_id,
          references(:connections, type: :binary_id, on_delete: :delete_all),
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
      timestamps(type: :utc_datetime_usec)
    end

    create index(:worker_heartbeats, [:last_seen_at])
  end
end

defmodule CourierCMS.Repo.Migrations.CreateCheckpoints do
  use Ecto.Migration

  def change do
    create table(:checkpoints, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :route_id, references(:routes, type: :binary_id, on_delete: :delete_all), null: false

      add :source_connection_id,
          references(:connections, type: :binary_id, on_delete: :restrict),
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
  end
end

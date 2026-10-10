defmodule CourierCMS.Repo.Migrations.HardenDeliveryExecution do
  use Ecto.Migration

  def change do
    alter table(:run_items) do
      add :source_modified_at, :utc_datetime_usec
    end

    alter table(:route_items) do
      add :last_source_modified_at, :utc_datetime_usec
    end

    create table(:delivery_locks, primary_key: false) do
      add :delivery_key, :text, primary_key: true
      add :owner_token, :binary_id, null: false
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:delivery_locks, [:expires_at])
  end
end

defmodule CourierCMS.Repo.Migrations.CreateConnectionLeases do
  use Ecto.Migration

  def change do
    create table(:connection_leases, primary_key: false) do
      add :connection_id,
          references(:connections, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :slot_number, :integer, primary_key: true
      add :owner_token, :binary_id, null: false
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:connection_leases, [:expires_at])
    create constraint(:connection_leases, :positive_slot_number, check: "slot_number > 0")
  end
end

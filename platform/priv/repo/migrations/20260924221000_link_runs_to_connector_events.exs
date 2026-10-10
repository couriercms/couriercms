defmodule CourierCMS.Repo.Migrations.LinkRunsToConnectorEvents do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      add :connector_event_id,
          references(:connector_events, type: :binary_id, on_delete: :nilify_all)
    end

    create unique_index(:runs, [:route_id, :connector_event_id],
             where: "connector_event_id IS NOT NULL"
           )
  end
end

defmodule CourierCMS.Repo.Migrations.AddDeliveryOptimizationAndDestinationSettings do
  use Ecto.Migration

  def change do
    alter table(:route_revisions) do
      add :destination_settings, :map, null: false, default: %{}
    end

    alter table(:run_items) do
      add :source_change_token, :text
      add :source_state, :text, null: false, default: "published"
    end

    alter table(:route_items) do
      add :last_source_change_token, :text

      add :last_route_revision_id,
          references(:route_revisions, type: :binary_id, on_delete: :restrict)
    end

    create index(:route_items, [:last_route_revision_id])
  end
end

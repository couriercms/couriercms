defmodule CourierCMS.Repo.Migrations.AddCanonicalDocumentsAndProjections do
  use Ecto.Migration

  def change do
    alter table(:route_revisions) do
      add :projections, {:array, :map}, null: false, default: []
    end
  end
end

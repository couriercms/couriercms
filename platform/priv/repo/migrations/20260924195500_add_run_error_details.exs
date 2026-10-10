defmodule CourierCMS.Repo.Migrations.AddRunErrorDetails do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      add :error_category, :text
      add :error_summary, :text
    end
  end
end

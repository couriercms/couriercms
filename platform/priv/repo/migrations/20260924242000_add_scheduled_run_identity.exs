defmodule CourierCMS.Repo.Migrations.AddScheduledRunIdentity do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      add :schedule_key, :text
    end

    create unique_index(:runs, [:route_id, :schedule_key],
             where: "schedule_key IS NOT NULL",
             name: :runs_route_schedule_key_index
           )
  end
end

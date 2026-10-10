defmodule CourierCMS.Repo.Migrations.AddExtensionStateToWorkerHeartbeats do
  use Ecto.Migration

  def change do
    alter table(:worker_heartbeats) do
      add :extension_fingerprint, :text
      add :extension_set, {:array, :map}, null: false, default: []
      add :extension_status, :text, null: false, default: "unknown"
    end
  end
end

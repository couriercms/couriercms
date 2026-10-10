defmodule CourierCMS.Repo.Migrations.PersistExtensionArtifacts do
  use Ecto.Migration

  def up do
    alter table(:connections) do
      add :extension_id, :text
      add :component_id, :text
    end

    alter table(:connections) do
      modify :extension_id, :text, null: false
      modify :component_id, :text, null: false
    end

    create index(:connections, [:extension_id, :component_id])

    alter table(:route_revisions) do
      add :source_extension_id, :text
      add :source_component_id, :text
      add :target_extension_id, :text
      add :target_component_id, :text
    end

    flush()

    execute("""
    UPDATE route_revisions AS revision
    SET source_extension_id = source.extension_id,
        source_component_id = source.component_id,
        target_extension_id = target.extension_id,
        target_component_id = target.component_id
    FROM routes AS route
    JOIN connections AS source ON source.id = route.source_connection_id
    JOIN connections AS target ON target.id = route.target_connection_id
    WHERE revision.route_id = route.id
    """)

    alter table(:route_revisions) do
      modify :source_extension_id, :text, null: false
      modify :source_component_id, :text, null: false
      modify :target_extension_id, :text, null: false
      modify :target_component_id, :text, null: false
    end

    create index(:route_revisions, [:source_extension_id, :source_component_id])
    create index(:route_revisions, [:target_extension_id, :target_component_id])

    alter table(:runs) do
      add :source_artifact, :map
      add :target_artifact, :map
      add :processor_artifacts, {:array, :map}, null: false, default: []
    end
  end

  def down do
    alter table(:runs) do
      remove :source_artifact
      remove :target_artifact
      remove :processor_artifacts
    end

    drop index(:route_revisions, [:target_extension_id, :target_component_id])
    drop index(:route_revisions, [:source_extension_id, :source_component_id])

    alter table(:route_revisions) do
      remove :source_extension_id
      remove :source_component_id
      remove :target_extension_id
      remove :target_component_id
    end

    drop index(:connections, [:extension_id, :component_id])

    alter table(:connections) do
      remove :extension_id
      remove :component_id
    end
  end
end

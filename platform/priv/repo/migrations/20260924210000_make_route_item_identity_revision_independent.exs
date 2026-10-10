defmodule CourierCMS.Repo.Migrations.MakeRouteItemIdentityRevisionIndependent do
  use Ecto.Migration

  def up do
    execute("""
    WITH ranked AS (
      SELECT
        id,
        first_value(id) OVER (
          PARTITION BY route_id, source_item_key, locale_key
          ORDER BY last_delivered_at DESC NULLS LAST, inserted_at DESC, id
        ) AS retained_id,
        row_number() OVER (
          PARTITION BY route_id, source_item_key, locale_key
          ORDER BY last_delivered_at DESC NULLS LAST, inserted_at DESC, id
        ) AS position
      FROM route_items
    )
    UPDATE run_items
    SET route_item_id = ranked.retained_id
    FROM ranked
    WHERE run_items.route_item_id = ranked.id
      AND ranked.position > 1
    """)

    execute("""
    WITH ranked AS (
      SELECT
        id,
        row_number() OVER (
          PARTITION BY route_id, source_item_key, locale_key
          ORDER BY last_delivered_at DESC NULLS LAST, inserted_at DESC, id
        ) AS position
      FROM route_items
    )
    DELETE FROM route_items
    USING ranked
    WHERE route_items.id = ranked.id
      AND ranked.position > 1
    """)

    drop index(:route_items, [], name: :route_items_logical_identity_index)

    create unique_index(
             :route_items,
             [:route_id, :source_item_key, :locale_key],
             name: :route_items_logical_identity_index
           )
  end

  def down do
    drop index(:route_items, [], name: :route_items_logical_identity_index)

    create unique_index(
             :route_items,
             [:route_id, :source_item_key, :locale_key, :source_revision_key],
             name: :route_items_logical_identity_index
           )
  end
end

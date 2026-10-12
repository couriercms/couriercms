defmodule CourierCMS.Storage.SchemaParityTest do
  use CourierCMS.DataCase, async: false

  alias CourierCMS.Repo
  alias CourierCMS.ReleaseProfile

  @domain_tables ~w(
    audit_events checkpoints connection_leases connection_rate_buckets
    connections connector_events delivery_asset_bindings delivery_assets
    delivery_bindings delivery_locks destinations route_items route_revisions
    routes processor_executions run_assets run_item_assets run_items runs users users_tokens
    worker_heartbeats workspace_memberships workspaces
  )

  @columns %{
    "audit_events" =>
      ~w(id workspace_id actor_user_id action resource_type resource_id metadata inserted_at),
    "checkpoints" =>
      ~w(id route_id source_connection_id last_run_id adapter_key value last_advanced_at last_full_scan_at inserted_at updated_at),
    "connection_leases" =>
      ~w(connection_id slot_number owner_token expires_at inserted_at updated_at),
    "connection_rate_buckets" => ~w(connection_id bucket request_count inserted_at updated_at),
    "connections" =>
      ~w(id workspace_id name adapter_key extension_id component_id endpoint settings credentials capabilities enabled last_test_status last_tested_at inserted_at updated_at),
    "connector_events" =>
      ~w(id connection_id contract_version external_event_id event_kind source_item_key source_modified_at status runs_started error_summary received_at processed_at inserted_at),
    "delivery_asset_bindings" =>
      ~w(id delivery_asset_id destination_id target_reference ownership_evidence last_content_hash last_delivered_at state last_successful_run_id last_route_revision_id inserted_at updated_at),
    "delivery_assets" =>
      ~w(id route_id source_asset_key variant_key filename media_type byte_size source_checksum metadata state inserted_at updated_at),
    "delivery_bindings" =>
      ~w(id route_item_id destination_id target_reference ownership_evidence last_content_hash last_delivered_at state last_successful_run_id last_route_revision_id inserted_at updated_at),
    "delivery_locks" => ~w(delivery_key owner_token expires_at inserted_at updated_at),
    "destinations" =>
      ~w(id workspace_id target_connection_id owner_route_id name scope scope_key lifecycle_status validation_status ownership_evidence last_validation_error validated_at first_delivered_at retired_at inserted_at updated_at),
    "route_items" =>
      ~w(id route_id source_item_key locale_key source_revision_key state last_source_modified_at last_source_change_token inserted_at updated_at),
    "processor_executions" =>
      ~w(id run_item_id attempt position extension_id component_id component_version input_path output_path config_hash input_hash output_hash input_bytes output_bytes duration_us status error_category error_summary retryable started_at completed_at inserted_at updated_at),
    "route_revisions" =>
      ~w(id route_id revision_number selection aggregation_rules mapping delivery_contract contract_version transformations processors trigger_settings checksum projections source_extension_id source_component_id target_extension_id target_component_id delivery_name_path inserted_at),
    "routes" =>
      ~w(id workspace_id name source_connection_id target_connection_id enabled archived_at inserted_at updated_at current_revision_id current_destination_id),
    "run_assets" =>
      ~w(id run_id delivery_asset_id asset_key planned_operation status attempt_count error_category error_summary content_hash started_at completed_at inserted_at updated_at),
    "run_item_assets" =>
      ~w(id run_item_id run_asset_id field_path required inserted_at updated_at),
    "run_items" =>
      ~w(id run_id route_item_id delivery_key source_item_key locale_key source_revision_key planned_operation status attempt_count error_category error_summary content_hash started_at completed_at source_modified_at source_change_token source_state inserted_at updated_at),
    "runs" =>
      ~w(id route_id route_revision_id destination_id initiated_by_user_id connector_event_id trigger_kind trigger_metadata status items_discovered items_succeeded items_failed items_retrying items_skipped assets_discovered assets_succeeded assets_failed assets_retrying assets_skipped started_at completed_at cancelled_at error_category error_summary schedule_key planning_cursor planning_page planning_complete source_artifact target_artifact processor_artifacts inserted_at updated_at),
    "users" => ~w(id email hashed_password confirmed_at inserted_at updated_at),
    "users_tokens" => ~w(id user_id token context sent_to authenticated_at inserted_at),
    "worker_heartbeats" =>
      ~w(node_id role queues version last_seen_at extension_fingerprint extension_set extension_status inserted_at updated_at),
    "workspace_memberships" =>
      ~w(id workspace_id user_id role status invited_by_user_id blocked_by_user_id blocked_at inserted_at updated_at),
    "workspaces" => ~w(id name slug inserted_at updated_at)
  }

  @indexes ~w(
    audit_events_actor_user_id_index audit_events_workspace_id_inserted_at_index
    checkpoints_last_run_id_index checkpoints_route_id_index checkpoints_source_connection_id_index
    connection_leases_expires_at_index connection_rate_buckets_bucket_index
    connections_adapter_key_index connections_extension_id_component_id_index
    connections_workspace_id_index connections_workspace_id_name_index
    connector_events_connection_id_external_event_id_index
    connector_events_status_received_at_index
    delivery_asset_bindings_delivery_asset_id_destination_id_index
    delivery_asset_bindings_destination_id_last_delivered_at_index
    delivery_asset_bindings_target_reference_index
    delivery_assets_logical_identity_index delivery_assets_route_id_state_index
    delivery_bindings_destination_id_last_delivered_at_index
    delivery_bindings_route_item_id_destination_id_index
    delivery_bindings_target_reference_index delivery_locks_expires_at_index
    destinations_active_scope_index
    destinations_owner_route_id_index destinations_target_connection_id_lifecycle_status_index
    destinations_workspace_id_name_index
    route_items_logical_identity_index
    processor_executions_run_item_id_attempt_position_index
    processor_executions_run_item_id_status_index
    route_revisions_route_id_checksum_index route_revisions_route_id_revision_number_index
    route_revisions_source_extension_id_source_component_id_index
    route_revisions_target_extension_id_target_component_id_index
    routes_current_destination_id_index
    routes_current_revision_id_index routes_source_connection_id_index
    routes_target_connection_id_index routes_workspace_id_index routes_workspace_id_name_index
    run_assets_delivery_asset_id_index run_assets_run_id_asset_key_index
    run_assets_run_id_status_index
    run_item_assets_run_asset_id_index
    run_item_assets_run_item_id_run_asset_id_field_path_index
    run_items_route_item_id_index run_items_run_id_delivery_key_index run_items_run_id_status_index
    runs_destination_id_inserted_at_index runs_initiated_by_user_id_index
    runs_route_id_connector_event_id_index
    runs_route_id_inserted_at_index runs_route_schedule_key_index runs_status_index
    users_email_index users_tokens_context_token_index users_tokens_user_id_index
    worker_heartbeats_last_seen_at_index workspace_memberships_user_id_status_index
    workspace_memberships_workspace_id_user_id_index workspaces_slug_index
  )

  @checks ~w(
    different_source_and_target_connections positive_contract_version positive_revision_number
    positive_slot_number supported_connector_contract_version valid_connector_event_status
    valid_delivery_asset_binding_state valid_delivery_asset_state
    valid_delivery_binding_state valid_destination_lifecycle valid_destination_validation
    valid_membership_role valid_membership_status valid_processor_execution_status
    valid_route_item_state valid_run_item_status
    valid_run_asset_status valid_run_status valid_trigger_kind
  )

  @foreign_keys [
    {"users_tokens", "user_id", "users", "CASCADE"},
    {"workspace_memberships", "workspace_id", "workspaces", "CASCADE"},
    {"workspace_memberships", "user_id", "users", "RESTRICT"},
    {"workspace_memberships", "invited_by_user_id", "users", "SET NULL"},
    {"workspace_memberships", "blocked_by_user_id", "users", "SET NULL"},
    {"audit_events", "workspace_id", "workspaces", "RESTRICT"},
    {"audit_events", "actor_user_id", "users", "SET NULL"},
    {"connections", "workspace_id", "workspaces", "RESTRICT"},
    {"routes", "workspace_id", "workspaces", "RESTRICT"},
    {"routes", "source_connection_id", "connections", "RESTRICT"},
    {"routes", "target_connection_id", "connections", "RESTRICT"},
    {"routes", "current_revision_id", "route_revisions", "SET NULL"},
    {"routes", "current_destination_id", "destinations", "RESTRICT"},
    {"route_revisions", "route_id", "routes", "CASCADE"},
    {"destinations", "workspace_id", "workspaces", "RESTRICT"},
    {"destinations", "target_connection_id", "connections", "RESTRICT"},
    {"destinations", "owner_route_id", "routes", "RESTRICT"},
    {"connector_events", "connection_id", "connections", "CASCADE"},
    {"runs", "route_id", "routes", "RESTRICT"},
    {"runs", "route_revision_id", "route_revisions", "RESTRICT"},
    {"runs", "destination_id", "destinations", "RESTRICT"},
    {"runs", "initiated_by_user_id", "users", "SET NULL"},
    {"runs", "connector_event_id", "connector_events", "SET NULL"},
    {"route_items", "route_id", "routes", "RESTRICT"},
    {"run_items", "run_id", "runs", "CASCADE"},
    {"run_items", "route_item_id", "route_items", "SET NULL"},
    {"processor_executions", "run_item_id", "run_items", "CASCADE"},
    {"delivery_assets", "route_id", "routes", "RESTRICT"},
    {"run_assets", "run_id", "runs", "CASCADE"},
    {"run_assets", "delivery_asset_id", "delivery_assets", "RESTRICT"},
    {"run_item_assets", "run_item_id", "run_items", "CASCADE"},
    {"run_item_assets", "run_asset_id", "run_assets", "CASCADE"},
    {"delivery_bindings", "route_item_id", "route_items", "RESTRICT"},
    {"delivery_bindings", "destination_id", "destinations", "RESTRICT"},
    {"delivery_bindings", "last_successful_run_id", "runs", "SET NULL"},
    {"delivery_bindings", "last_route_revision_id", "route_revisions", "RESTRICT"},
    {"delivery_asset_bindings", "delivery_asset_id", "delivery_assets", "RESTRICT"},
    {"delivery_asset_bindings", "destination_id", "destinations", "RESTRICT"},
    {"delivery_asset_bindings", "last_successful_run_id", "runs", "SET NULL"},
    {"delivery_asset_bindings", "last_route_revision_id", "route_revisions", "RESTRICT"},
    {"checkpoints", "route_id", "routes", "CASCADE"},
    {"checkpoints", "source_connection_id", "connections", "RESTRICT"},
    {"checkpoints", "last_run_id", "runs", "SET NULL"},
    {"connection_leases", "connection_id", "connections", "CASCADE"},
    {"connection_rate_buckets", "connection_id", "connections", "CASCADE"}
  ]

  @nullable_columns ~w(
    audit_events.actor_user_id audit_events.resource_id
    checkpoints.last_run_id checkpoints.last_full_scan_at
    connections.credentials connections.last_test_status connections.last_tested_at
    connector_events.source_item_key connector_events.source_modified_at
    connector_events.error_summary connector_events.processed_at
    delivery_asset_bindings.target_reference delivery_asset_bindings.last_content_hash
    delivery_asset_bindings.last_delivered_at delivery_asset_bindings.last_successful_run_id
    delivery_asset_bindings.last_route_revision_id
    delivery_assets.filename delivery_assets.media_type delivery_assets.byte_size
    delivery_assets.source_checksum
    delivery_bindings.target_reference delivery_bindings.last_content_hash
    delivery_bindings.last_delivered_at delivery_bindings.last_successful_run_id
    delivery_bindings.last_route_revision_id
    destinations.owner_route_id destinations.last_validation_error destinations.validated_at
    destinations.first_delivered_at destinations.retired_at
    route_items.last_source_modified_at route_items.last_source_change_token
    routes.current_revision_id routes.archived_at
    processor_executions.output_hash processor_executions.output_bytes
    processor_executions.duration_us processor_executions.error_category
    processor_executions.error_summary processor_executions.completed_at
    run_items.route_item_id run_items.planned_operation run_items.error_category
    run_items.error_summary run_items.content_hash run_items.started_at run_items.completed_at
    run_items.source_modified_at run_items.source_change_token
    run_assets.planned_operation run_assets.error_category run_assets.error_summary
    run_assets.content_hash run_assets.started_at run_assets.completed_at
    runs.initiated_by_user_id runs.connector_event_id runs.started_at runs.completed_at
    runs.cancelled_at runs.error_category runs.error_summary runs.schedule_key
    runs.planning_cursor runs.source_artifact runs.target_artifact
    users.hashed_password users.confirmed_at
    users_tokens.sent_to users_tokens.authenticated_at
    worker_heartbeats.extension_fingerprint
    workspace_memberships.invited_by_user_id workspace_memberships.blocked_by_user_id
    workspace_memberships.blocked_at
  )

  @defaults %{
    "audit_events.metadata" => :empty_map,
    "workspace_memberships.status" => "invited",
    "connections.settings" => :empty_map,
    "connections.capabilities" => :empty_map,
    "connections.enabled" => true,
    "routes.enabled" => false,
    "route_revisions.selection" => :empty_map,
    "route_revisions.aggregation_rules" => :empty_map,
    "route_revisions.mapping" => :empty_map,
    "route_revisions.delivery_contract" => :empty_map,
    "route_revisions.transformations" => :empty_list,
    "route_revisions.processors" => :empty_list,
    "route_revisions.trigger_settings" => :empty_map,
    "route_revisions.projections" => :empty_list,
    "route_revisions.delivery_name_path" => "payload.title",
    "destinations.scope" => :empty_map,
    "destinations.lifecycle_status" => "available",
    "destinations.validation_status" => "unknown",
    "destinations.ownership_evidence" => :empty_map,
    "connector_events.status" => "accepted",
    "connector_events.runs_started" => 0,
    "delivery_assets.variant_key" => "original",
    "delivery_assets.metadata" => :empty_map,
    "delivery_assets.state" => "pending",
    "runs.trigger_metadata" => :empty_map,
    "runs.status" => "queued",
    "runs.items_discovered" => 0,
    "runs.items_succeeded" => 0,
    "runs.items_failed" => 0,
    "runs.items_retrying" => 0,
    "runs.items_skipped" => 0,
    "runs.assets_discovered" => 0,
    "runs.assets_succeeded" => 0,
    "runs.assets_failed" => 0,
    "runs.assets_retrying" => 0,
    "runs.assets_skipped" => 0,
    "runs.planning_page" => 0,
    "runs.planning_complete" => false,
    "runs.processor_artifacts" => :empty_list,
    "route_items.state" => "pending",
    "processor_executions.status" => "processing",
    "processor_executions.retryable" => false,
    "run_items.status" => "pending",
    "run_items.attempt_count" => 0,
    "run_items.source_state" => "published",
    "run_assets.status" => "pending",
    "run_assets.attempt_count" => 0,
    "run_item_assets.required" => true,
    "delivery_asset_bindings.ownership_evidence" => :empty_map,
    "delivery_asset_bindings.state" => "pending",
    "delivery_bindings.ownership_evidence" => :empty_map,
    "delivery_bindings.state" => "pending",
    "checkpoints.value" => :empty_map,
    "connection_rate_buckets.request_count" => 0,
    "worker_heartbeats.queues" => :empty_list,
    "worker_heartbeats.extension_set" => :empty_list,
    "worker_heartbeats.extension_status" => "unknown"
  }

  @binary_id_columns ~w(
    workspace_id actor_user_id user_id invited_by_user_id blocked_by_user_id
    source_connection_id target_connection_id current_revision_id current_destination_id
    route_id owner_route_id connection_id run_id route_revision_id destination_id
    initiated_by_user_id connector_event_id route_item_id run_item_id delivery_asset_id run_asset_id
    last_successful_run_id last_route_revision_id last_run_id owner_token
  )

  @integer_columns ~w(
    revision_number contract_version runs_started items_discovered items_succeeded
    items_failed items_retrying items_skipped assets_discovered assets_succeeded
    assets_failed assets_retrying assets_skipped planning_page attempt_count slot_number
    request_count attempt position
  )

  @map_columns ~w(
    metadata settings capabilities selection aggregation_rules mapping delivery_contract
    trigger_settings scope ownership_evidence trigger_metadata planning_cursor
    source_artifact target_artifact value
  )

  @list_map_columns ~w(transformations processors projections processor_artifacts extension_set)
  @list_text_columns ~w(queues)

  test "the selected database exposes the shared logical schema contract" do
    tables = names(table_query())

    assert MapSet.subset?(MapSet.new(@domain_tables), tables),
           "#{ReleaseProfile.current()} is missing domain tables"

    for {table, expected} <- @columns do
      actual = columns(table)

      assert MapSet.new(expected) == actual,
             "#{ReleaseProfile.current()} #{table} columns differ: expected #{inspect(expected)}, got #{inspect(actual)}"
    end

    indexes = names(index_query())

    missing_indexes = MapSet.difference(MapSet.new(@indexes), indexes)

    assert MapSet.size(missing_indexes) == 0,
           "#{ReleaseProfile.current()} is missing indexes: #{inspect(missing_indexes)}"

    missing_checks = MapSet.difference(MapSet.new(@checks), checks())

    assert MapSet.size(missing_checks) == 0,
           "#{ReleaseProfile.current()} is missing checks: #{inspect(missing_checks)}"

    assert MapSet.new(@foreign_keys) == foreign_keys(),
           "#{ReleaseProfile.current()} foreign keys or deletion behavior differ from the baseline"

    metadata = column_metadata()
    expected_keys = all_column_keys()

    assert MapSet.new(Map.keys(metadata)) == MapSet.new(expected_keys)

    actual_nullable =
      metadata
      |> Enum.filter(fn {_key, value} -> value.nullable end)
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()

    assert actual_nullable == MapSet.new(@nullable_columns),
           "#{ReleaseProfile.current()} nullability differs from the logical schema"

    actual_defaults =
      metadata
      |> Enum.reject(fn {_key, value} -> is_nil(value.default) end)
      |> Map.new(fn {key, value} ->
        {key, normalize_default(value.default, logical_type(key))}
      end)

    assert actual_defaults == @defaults,
           "#{ReleaseProfile.current()} defaults differ: expected #{inspect(@defaults)}, got #{inspect(actual_defaults)}"

    for {key, value} <- metadata do
      logical_type = logical_type(key)

      assert native_type_matches?(value, logical_type),
             "#{ReleaseProfile.current()} #{key} has #{inspect(value.native_type)}, expected #{logical_type}"
    end
  end

  defp table_query do
    if ReleaseProfile.local?() do
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
    else
      "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'"
    end
  end

  defp index_query do
    if ReleaseProfile.local?() do
      "SELECT name FROM sqlite_master WHERE type = 'index'"
    else
      "SELECT indexname FROM pg_indexes WHERE schemaname = 'public'"
    end
  end

  defp columns(table) do
    rows =
      if ReleaseProfile.local?() do
        Repo.query!("PRAGMA table_info(#{table})").rows
        |> Enum.map(&Enum.at(&1, 1))
      else
        Repo.query!(
          "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1",
          [table]
        ).rows
        |> Enum.map(&List.first/1)
      end

    MapSet.new(rows)
  end

  defp checks do
    if ReleaseProfile.local?() do
      Repo.query!("SELECT sql FROM sqlite_master WHERE type = 'table' AND sql IS NOT NULL").rows
      |> List.flatten()
      |> Enum.flat_map(
        &Regex.scan(~r/CONSTRAINT\s+[\"`]?([a-z0-9_]+)/i, &1, capture: :all_but_first)
      )
      |> List.flatten()
      |> MapSet.new()
    else
      Repo.query!("SELECT conname FROM pg_constraint WHERE contype = 'c'").rows
      |> Enum.map(&List.first/1)
      |> MapSet.new()
    end
  end

  defp foreign_keys do
    rows =
      if ReleaseProfile.local?() do
        Enum.flat_map(@domain_tables, fn table ->
          Repo.query!("PRAGMA foreign_key_list(#{table})").rows
          |> Enum.map(fn row ->
            {table, Enum.at(row, 3), Enum.at(row, 2), Enum.at(row, 6)}
          end)
        end)
      else
        Repo.query!(
          """
          SELECT tc.table_name, kcu.column_name, ccu.table_name, rc.delete_rule
          FROM information_schema.table_constraints tc
          JOIN information_schema.key_column_usage kcu
            ON tc.constraint_name = kcu.constraint_name
           AND tc.constraint_schema = kcu.constraint_schema
          JOIN information_schema.referential_constraints rc
            ON tc.constraint_name = rc.constraint_name
           AND tc.constraint_schema = rc.constraint_schema
          JOIN information_schema.constraint_column_usage ccu
            ON rc.unique_constraint_name = ccu.constraint_name
           AND rc.unique_constraint_schema = ccu.constraint_schema
          WHERE tc.constraint_type = 'FOREIGN KEY'
            AND tc.table_schema = 'public'
            AND tc.table_name = ANY($1)
          """,
          [@domain_tables]
        ).rows
        |> Enum.map(&List.to_tuple/1)
      end

    MapSet.new(rows)
  end

  defp column_metadata do
    if ReleaseProfile.local?() do
      Map.new(@domain_tables, fn table ->
        rows = Repo.query!("PRAGMA table_info(#{table})").rows

        entries =
          Map.new(rows, fn row ->
            column = Enum.at(row, 1)
            primary_key? = Enum.at(row, 5) > 0

            {"#{table}.#{column}",
             %{
               native_type: String.upcase(Enum.at(row, 2)),
               nullable: Enum.at(row, 3) == 0 and not primary_key?,
               default: Enum.at(row, 4)
             }}
          end)

        {table, entries}
      end)
      |> Enum.flat_map(fn {_table, entries} -> entries end)
      |> Map.new()
    else
      Repo.query!(
        """
        SELECT table_name, column_name, data_type, udt_name, is_nullable, column_default
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = ANY($1)
        """,
        [@domain_tables]
      ).rows
      |> Map.new(fn [table, column, data_type, udt_name, nullable, default] ->
        {"#{table}.#{column}",
         %{
           native_type: {String.downcase(data_type), String.downcase(udt_name)},
           nullable: nullable == "YES",
           default: default
         }}
      end)
    end
  end

  defp all_column_keys do
    Enum.flat_map(@columns, fn {table, columns} ->
      Enum.map(columns, &"#{table}.#{&1}")
    end)
  end

  defp logical_type(key) do
    [_table, column] = String.split(key, ".", parts: 2)

    cond do
      column == "id" or column in @binary_id_columns -> :binary_id
      String.ends_with?(column, "_at") -> :datetime
      column in @integer_columns -> :integer
      column in ["bucket", "byte_size", "input_bytes", "output_bytes", "duration_us"] -> :bigint
      column in ["enabled", "planning_complete", "required", "retryable"] -> :boolean
      column in ["credentials", "token"] -> :binary
      column in @map_columns -> :map
      column in @list_map_columns -> :list_map
      column in @list_text_columns -> :list_text
      key == "users.email" -> :case_insensitive_text
      true -> :text
    end
  end

  defp native_type_matches?(%{native_type: native}, logical_type) do
    if ReleaseProfile.local?() do
      case logical_type do
        :binary_id -> native == "TEXT"
        :binary -> native == "BLOB"
        type when type in [:integer, :bigint, :boolean] -> native == "INTEGER"
        _type -> native == "TEXT"
      end
    else
      case logical_type do
        :binary_id -> native == {"uuid", "uuid"}
        :binary -> native == {"bytea", "bytea"}
        :integer -> native == {"integer", "int4"}
        :bigint -> native == {"bigint", "int8"}
        :boolean -> native == {"boolean", "bool"}
        :datetime -> native == {"timestamp without time zone", "timestamp"}
        :map -> native == {"jsonb", "jsonb"}
        :list_map -> native == {"array", "_jsonb"}
        :list_text -> native == {"array", "_text"}
        :case_insensitive_text -> native == {"user-defined", "citext"}
        :text -> elem(native, 0) in ["text", "character varying"]
      end
    end
  end

  defp normalize_default(raw, logical_type) when logical_type in [:map] do
    if String.contains?(raw, "{}"), do: :empty_map, else: raw
  end

  defp normalize_default(raw, logical_type) when logical_type in [:list_map, :list_text] do
    if String.contains?(raw, "{}") or String.contains?(raw, "[]"), do: :empty_list, else: raw
  end

  defp normalize_default(raw, :boolean) do
    case raw |> String.downcase() |> trim_quotes() do
      value when value in ["true", "1"] -> true
      value when value in ["false", "0"] -> false
      value -> value
    end
  end

  defp normalize_default(raw, type) when type in [:integer, :bigint] do
    case Integer.parse(raw) do
      {integer, _rest} -> integer
      :error -> raw
    end
  end

  defp normalize_default(raw, _type) do
    raw
    |> String.replace(~r/::[a-zA-Z0-9_\[\] ]+$/, "")
    |> trim_quotes()
  end

  defp trim_quotes(value), do: value |> String.trim("'") |> String.trim("\"")

  defp names(query) do
    query
    |> Repo.query!()
    |> Map.fetch!(:rows)
    |> Enum.map(&List.first/1)
    |> MapSet.new()
  end
end

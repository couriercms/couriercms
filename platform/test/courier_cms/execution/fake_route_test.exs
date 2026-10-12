defmodule CourierCMS.Execution.FakeRouteTest do
  use CourierCMS.DataCase
  use Oban.Testing, repo: CourierCMS.Repo
  import Swoosh.TestAssertions

  alias CourierCMS.Connections.Connection
  alias CourierCMS.Connectors.ConnectorEvent
  alias CourierCMS.Destinations
  alias CourierCMS.Assets
  alias CourierCMS.Assets.{DeliveryAsset, DeliveryAssetBinding, RunAsset, RunItemAsset}
  alias CourierCMS.Execution
  alias CourierCMS.Execution.{ProcessorExecution, RunItem}
  alias CourierCMS.ExtensionSDK.AssetDescriptor
  alias CourierCMS.Ownership.DeliveryBinding
  alias CourierCMS.Ownership.RouteItem
  alias CourierCMS.Routes
  alias CourierCMSExtension.Fake.Store

  test "delivers filtered items independently, retries a transient failure, and skips replay" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    assert route.current_revision.source_extension_id == "com.couriercms.fake"
    assert route.current_revision.source_component_id == "fake_source"
    assert route.current_revision.target_component_id == "fake_target"

    {:ok, first_run} = Execution.start_manual_run(scope, route.id)
    assert first_run.source_artifact["extension_id"] == "com.couriercms.fake"
    assert first_run.source_artifact["component_id"] == "fake_source"
    assert first_run.target_artifact["component_id"] == "fake_target"
    assert is_binary(first_run.source_artifact["checksum"])
    assert :ok = Execution.plan_run(first_run.id)

    first_items = items(first_run.id)
    assert Enum.map(first_items, & &1.source_item_key) == ["101", "102"]

    Enum.each(first_items, &process_item_with_retry/1)

    completed = Execution.get_run!(scope, first_run.id)
    assert completed.status == :succeeded
    assert completed.items_discovered == 2
    assert completed.items_succeeded == 2
    assert Repo.aggregate(RouteItem, :count) == 2
    assert Repo.aggregate(DeliveryBinding, :count) == 2
    assert Repo.aggregate(DeliveryAsset, :count) == 1
    assert Repo.aggregate(RunAsset, :count) == 1
    assert Repo.aggregate(RunItemAsset, :count) == 1
    assert Repo.aggregate(DeliveryAssetBinding, :count) == 1
    assert Repo.one!(RunAsset).status == :succeeded
    assert Enum.all?(Repo.all(DeliveryBinding), &is_binary(&1.target_reference))

    delivered_item = Enum.find(first_items, &(&1.source_item_key == "101"))

    stored =
      Store.fetch(
        route.target_connection_id,
        route.current_destination_id,
        delivered_item.delivery_key
      )

    assert stored.payload["featured_image"]["target_reference"] =~ "fake-asset:"
    assert [asset_reference] = stored.canonical_document["assets"]
    assert asset_reference["sourceKey"] == "501"
    assert asset_reference["targetReference"] =~ "fake-asset:"
    assert asset_reference["couriercmsAssetKey"]

    asset_item =
      first_items
      |> Enum.find(&(&1.source_item_key == "101"))
      |> Repo.preload(run: :route)

    descriptor = %AssetDescriptor{
      source_key: "501",
      field_path: "fields.featured_image",
      filename: "delivery-pipeline.jpg",
      media_type: "image/jpeg"
    }

    assert {:ok, [_asset]} = Assets.plan_dependencies(asset_item, [descriptor])
    assert {:ok, [_asset]} = Assets.plan_dependencies(asset_item, [descriptor])
    assert Repo.aggregate(DeliveryAsset, :count) == 1
    assert Repo.aggregate(RunAsset, :count) == 1
    assert Repo.aggregate(RunItemAsset, :count) == 1

    {:ok, replay} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(replay.id)
    Enum.each(items(replay.id), &process_item_with_retry/1)

    replayed = Execution.get_run!(scope, replay.id)
    assert replayed.status == :succeeded
    assert replayed.items_skipped == 2
    assert Repo.aggregate(RouteItem, :count) == 2

    {:ok, forced} = Execution.start_manual_run(scope, route.id, force_redelivery: true)
    assert forced.trigger_metadata["delivery_mode"] == "force"
    assert :ok = Execution.plan_run(forced.id)
    Enum.each(items(forced.id), &process_item_with_retry/1)

    redelivered = Execution.get_run!(scope, forced.id)
    assert redelivered.status == :succeeded
    assert redelivered.items_succeeded == 2
    assert redelivered.items_skipped == 0
    assert Enum.all?(items(forced.id), &(&1.planned_operation == "update"))
    assert Repo.aggregate(RouteItem, :count) == 2

    route.source_connection
    |> Ecto.Changeset.change(
      settings: %{
        "fail_once_for" => ["102"],
        "revision_overrides" => %{"101" => "8"},
        "title_overrides" => %{"101" => "Reliable content delivery, updated"}
      }
    )
    |> Repo.update!()

    {:ok, changed_run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(changed_run.id)
    Enum.each(items(changed_run.id), &process_item_with_retry/1)

    changed_items = items(changed_run.id)
    changed = Enum.find(changed_items, &(&1.source_item_key == "101"))
    unchanged = Enum.find(changed_items, &(&1.source_item_key == "102"))

    assert changed.planned_operation == "update"
    assert changed.source_revision_key == "8"
    assert unchanged.planned_operation == "skip"
    assert Repo.aggregate(RouteItem, :count) == 2

    updated_item = Repo.get_by!(RouteItem, route_id: route.id, source_item_key: "101")

    updated_binding =
      Repo.get_by!(DeliveryBinding,
        route_item_id: updated_item.id,
        destination_id: route.current_destination_id
      )

    assert updated_item.source_revision_key == "8"
    assert updated_binding.last_content_hash == changed.content_hash
  end

  test "a projection contract change updates existing items without duplicating them" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    {:ok, initial} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(initial.id)
    process_items_with_retry(initial.id)

    original_contract = route.current_revision.contract_version

    assert {:ok, updated_route} =
             CourierCMS.Routes.update_projections(scope, route, [
               %{
                 "target_field" => "projectedTitle",
                 "source_path" => "payload.title",
                 "type" => "string"
               }
             ])

    assert updated_route.current_revision.contract_version == original_contract + 1

    {:ok, projected_run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(projected_run.id)
    process_items_with_retry(projected_run.id)

    projected_run = Execution.get_run!(scope, projected_run.id)
    assert projected_run.items_succeeded == 2
    assert projected_run.items_skipped == 0
    assert Repo.aggregate(RouteItem, :count) == 2

    assert Enum.all?(Repo.all(DeliveryBinding), fn binding ->
             binding.last_route_revision_id == updated_route.current_revision_id
           end)
  end

  test "applies the immutable transformation chain before hashing and delivery" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()

    transformations = [
      %{
        "kind" => "builtin",
        "operation" => "string.slug",
        "version" => 1,
        "input_path" => "title",
        "output_path" => "slug",
        "config" => %{}
      }
    ]

    route = route_fixture(scope, %{transformations: transformations})

    {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(run.id)
    process_items_with_retry(run.id)

    delivered_item = items(run.id) |> Enum.find(&(&1.source_item_key == "101"))

    stored =
      Store.fetch(
        route.target_connection_id,
        route.current_destination_id,
        delivered_item.delivery_key
      )

    assert stored.payload["slug"] == "reliable-content-delivery-with-couriercms"

    assert stored.canonical_document["payload"]["slug"] ==
             "reliable-content-delivery-with-couriercms"
  end

  test "pins and executes ordered Extension Processors before hashing and delivery" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()

    processors = [
      %{
        "kind" => "processor",
        "extension_id" => "com.couriercms.fake",
        "component_id" => "fake_prefix",
        "input_path" => "title",
        "output_path" => "title",
        "config" => %{"prefix" => "Processed: "},
        "failure_policy" => "fail"
      }
    ]

    route = route_fixture(scope, %{processors: processors})
    assert [processor] = route.current_revision.processors
    assert processor["component_version"] == "0.1.0"

    {:ok, preview} = Execution.preview_route(scope, route.id)

    assert preview.canonical_document["payload"]["title"] ==
             "Processed: Reliable content delivery with CourierCMS"

    {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert [artifact] = run.processor_artifacts
    assert artifact["component_id"] == "fake_prefix"
    assert artifact["version"] == "0.1.0"
    assert is_binary(artifact["checksum"])

    assert :ok = Execution.plan_run(run.id)
    process_items_with_retry(run.id)

    delivered_item = items(run.id) |> Enum.find(&(&1.source_item_key == "101"))

    stored =
      Store.fetch(
        route.target_connection_id,
        route.current_destination_id,
        delivered_item.delivery_key
      )

    assert stored.payload["title"] == "Processed: Reliable content delivery with CourierCMS"
    assert stored.canonical_document["payload"]["title"] == stored.payload["title"]

    assert [execution] =
             Repo.all(
               from(execution in ProcessorExecution,
                 where: execution.run_item_id == ^delivered_item.id
               )
             )

    assert execution.attempt > 0
    assert execution.position == 1
    assert execution.extension_id == "com.couriercms.fake"
    assert execution.component_id == "fake_prefix"
    assert execution.component_version == "0.1.0"
    assert execution.status == :succeeded
    assert execution.input_bytes > 0
    assert execution.output_bytes > 0
    assert execution.duration_us >= 0
    assert execution.input_hash =~ "sha256:"
    assert execution.output_hash =~ "sha256:"
    refute execution.error_summary
  end

  test "records failed Processor evidence and closes interrupted attempts" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()

    processors = [
      %{
        "kind" => "processor",
        "extension_id" => "com.couriercms.fake",
        "component_id" => "fake_prefix",
        "input_path" => "title",
        "output_path" => "title",
        "config" => %{"delay_ms" => 25, "prefix" => "Processed: "},
        "failure_policy" => "fail"
      }
    ]

    route = route_fixture(scope, %{processors: processors})
    {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(run.id)
    item = items(run.id) |> Enum.find(&(&1.source_item_key == "102"))

    interrupted =
      %ProcessorExecution{}
      |> ProcessorExecution.changeset(%{
        run_item_id: item.id,
        attempt: 1,
        position: 1,
        extension_id: "com.couriercms.fake",
        component_id: "fake_prefix",
        component_version: "0.1.0",
        input_path: "title",
        output_path: "title",
        config_hash: "sha256:interrupted",
        input_hash: "sha256:interrupted",
        input_bytes: 1,
        status: :processing,
        started_at: DateTime.utc_now()
      })
      |> Repo.insert!()

    item
    |> RunItem.changeset(%{attempt_count: 1})
    |> Repo.update!()

    previous_timeout = Application.fetch_env!(:couriercms, :processor_timeout_ms)
    Application.put_env(:couriercms, :processor_timeout_ms, 5)

    on_exit(fn ->
      Application.put_env(:couriercms, :processor_timeout_ms, previous_timeout)
    end)

    assert {:discard, _message} = Execution.process_run_item(item.id, 1, 1)

    interrupted = Repo.reload!(interrupted)
    assert interrupted.status == :failed
    assert interrupted.error_category == "interrupted"
    assert interrupted.retryable
    assert interrupted.completed_at

    assert failed =
             Repo.get_by!(ProcessorExecution,
               run_item_id: item.id,
               attempt: 2,
               position: 1
             )

    assert failed.status == :failed
    assert failed.error_category == "timeout"
    assert failed.error_summary == "Processor execution timed out"
    assert failed.retryable
    assert failed.completed_at
  end

  test "executes the official target-independent Content Processor chain" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()

    processors = [
      %{
        "kind" => "processor",
        "extension_id" => "com.couriercms.content",
        "component_id" => "exact_token_replacer",
        "input_path" => "title",
        "output_path" => "title",
        "config" => %{
          "replacements" => %{"CourierCMS" => "Courier CMS", "Reliable" => " Reliable"}
        },
        "failure_policy" => "fail"
      },
      %{
        "kind" => "processor",
        "extension_id" => "com.couriercms.content",
        "component_id" => "html_text_normalizer",
        "input_path" => "title",
        "output_path" => "title",
        "config" => %{},
        "failure_policy" => "fail"
      }
    ]

    route = route_fixture(scope, %{processors: processors})
    {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(run.id)
    process_items_with_retry(run.id)

    delivered_item = items(run.id) |> Enum.find(&(&1.source_item_key == "101"))

    stored =
      Store.fetch(
        route.target_connection_id,
        route.current_destination_id,
        delivered_item.delivery_key
      )

    assert stored.payload["title"] == "Reliable content delivery with Courier CMS"

    assert [first, second | _retry_history] =
             Repo.all(
               from(execution in ProcessorExecution,
                 where: execution.run_item_id == ^delivered_item.id,
                 order_by: [asc: execution.attempt, asc: execution.position]
               )
             )

    assert first.component_id == "exact_token_replacer"
    assert second.component_id == "html_text_normalizer"
  end

  test "an authoritative enumeration token skips the source read when nothing changed" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    {:ok, initial} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(initial.id)
    process_items_with_retry(initial.id)

    route.source_connection
    |> Ecto.Changeset.change(settings: %{"fail_read_for" => ["101", "102"]})
    |> Repo.update!()

    {:ok, replay} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(replay.id)
    process_items_with_retry(replay.id)

    replay = Execution.get_run!(scope, replay.id)
    assert replay.status == :succeeded
    assert replay.items_skipped == 2
    assert replay.items_failed == 0
  end

  test "moving a Route retires an active Destination and preserves its delivery bindings" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(run.id)
    process_items_with_retry(run.id)

    old_destination_id = route.current_destination_id
    old_bindings = Repo.aggregate(DeliveryBinding, :count)

    assert {:ok, new_destination} =
             Destinations.create_destination(scope, %{
               name: "Replacement Destination",
               target_connection_id: route.target_connection_id,
               scope: %{"namespace" => "site-b"}
             })

    assert {:ok, moved} = Routes.move_destination(scope, route, new_destination.id)
    assert moved.current_destination_id == new_destination.id
    assert moved.current_destination.lifecycle_status == :reserved
    assert moved.current_destination.owner_route_id == route.id

    old_destination = Destinations.get_destination!(scope, old_destination_id)
    assert old_destination.lifecycle_status == :retired
    assert old_destination.owner_route_id == route.id
    assert Repo.aggregate(DeliveryBinding, :count) == old_bindings

    refute Repo.exists?(
             from(binding in DeliveryBinding,
               where: binding.destination_id == ^new_destination.id
             )
           )

    event =
      %ConnectorEvent{}
      |> ConnectorEvent.changeset(%{
        contract_version: 1,
        connection_id: route.source_connection_id,
        external_event_id: Ecto.UUID.generate(),
        event_kind: "content.updated",
        source_item_key: "101",
        status: :accepted,
        received_at: DateTime.utc_now()
      })
      |> Repo.insert!()

    assert {:ok, [baseline]} = Execution.start_connector_runs(event)
    assert baseline.trigger_metadata["source_item_key"] == nil
    assert baseline.trigger_metadata["retrieval_reason"] == "destination_changed"
    assert :ok = Execution.plan_run(baseline.id)
    assert length(items(baseline.id)) == 2
    process_items_with_retry(baseline.id)

    assert Repo.aggregate(
             from(binding in DeliveryBinding,
               where: binding.destination_id == ^new_destination.id
             ),
             :count
           ) == 2
  end

  test "archiving an undelivered Route releases its Destination for another Route" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    assert {:ok, archived} = Routes.archive_route(scope, route)
    assert archived.archived_at
    refute archived.enabled

    destination = Destinations.get_destination!(scope, route.current_destination_id)
    assert destination.lifecycle_status == :available
    assert is_nil(destination.owner_route_id)

    assert {:ok, replacement} =
             Routes.create_route(
               scope,
               %{
                 name: "Replacement Route #{System.unique_integer()}",
                 source_connection_id: route.source_connection_id,
                 target_connection_id: route.target_connection_id,
                 current_destination_id: destination.id,
                 enabled: false
               },
               %{
                 selection: %{"category" => "Engineering", "tags" => []},
                 mapping: Routes.default_mapping("fake_source")
               }
             )

    assert replacement.current_destination_id == destination.id
    assert replacement.current_destination.lifecycle_status == :reserved
    assert replacement.current_destination.owner_route_id == replacement.id
  end

  test "blocks planning when the exact pinned source artifact is unavailable" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    {:ok, run} = Execution.start_manual_run(scope, route.id)

    run
    |> CourierCMS.Execution.Run.changeset(%{
      source_artifact: Map.put(run.source_artifact, "checksum", String.duplicate("0", 64))
    })
    |> Repo.update!()

    message = "The Run requires an Extension artifact that is not installed on this node"
    assert {:discard, ^message} = Execution.plan_run(run.id)

    failed = Execution.get_run!(scope, run.id)
    assert failed.status == :failed
    assert failed.error_category == "unsupported"
    assert failed.error_summary == message
  end

  test "pins unfinished legacy Runs before resuming execution" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    {:ok, run} = Execution.start_manual_run(scope, route.id)

    run
    |> Ecto.Changeset.change(source_artifact: nil, target_artifact: nil)
    |> Repo.update!()

    assert :ok = Execution.plan_run(run.id)

    pinned = Execution.get_run!(scope, run.id)
    assert pinned.source_artifact["component_id"] == "fake_source"
    assert pinned.target_artifact["component_id"] == "fake_target"
  end

  test "cancelling a Run prevents pending items from being delivered" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    assert {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(run.id)
    assert {:ok, cancelled} = Execution.cancel_run(scope, run.id)
    assert cancelled.status == :cancelled

    for item <- items(run.id) do
      assert item.status == :cancelled
      assert :ok = Execution.process_run_item(item.id, 1, 3)
    end

    cancelled = Execution.get_run!(scope, run.id)
    assert cancelled.status == :cancelled
    assert Repo.aggregate(DeliveryBinding, :count) == 0
  end

  test "a terminal item failure queues and delivers a safe operator alert" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    assert_email_sent()
    route = route_fixture(scope)

    assert {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(run.id)
    failing_item = Enum.find(items(run.id), &(&1.source_item_key == "102"))

    assert {:discard, "Simulated temporary target outage"} =
             Execution.process_run_item(failing_item.id, 1, 1)

    assert_enqueued(
      worker: CourierCMS.Execution.FailureAlertWorker,
      args: %{"run_item_id" => failing_item.id}
    )

    assert :ok = CourierCMS.Alerts.deliver_terminal_failure(failing_item.id)
    assert_email_sent(subject: "CourierCMS delivery failed", to: [{nil, scope.user.email}])
  end

  test "a required Delivery Asset retries independently and blocks its Delivery Item" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    route.source_connection
    |> Ecto.Changeset.change(settings: %{"fail_asset_for" => ["501"]})
    |> Repo.update!()

    assert {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(run.id)
    item = Enum.find(items(run.id), &(&1.source_item_key == "101"))

    assert {:snooze, _seconds} = Execution.process_run_item(item.id, 1, 3)
    asset = Repo.get_by!(RunAsset, run_id: run.id)

    assert {:error, "Fake asset read failed"} = Execution.process_run_asset(asset.id, 1, 2)
    assert Repo.get!(RunAsset, asset.id).status == :retrying

    assert {:discard, "Fake asset read failed"} = Execution.process_run_asset(asset.id, 2, 2)
    assert Repo.get!(RunAsset, asset.id).status == :failed

    assert {:discard, "A required Delivery Asset could not be delivered"} =
             Execution.process_run_item(item.id, 2, 3)

    assert Repo.get!(RunItem, item.id).status == :failed
    assert Repo.aggregate(DeliveryAssetBinding, :count) == 0

    assert {:ok, %{asset_job: _job, item_jobs: [_item_job]}} =
             Execution.retry_run_asset(scope, asset.id)

    assert Repo.get!(RunAsset, asset.id).status == :pending
    assert Repo.get!(RunItem, item.id).status == :pending

    assert_enqueued(
      worker: CourierCMS.Execution.AssetWorker,
      args: %{"run_asset_id" => asset.id}
    )

    assert_enqueued(
      worker: CourierCMS.Execution.DeliveryWorker,
      args: %{"run_item_id" => item.id}
    )
  end

  test "a required Delivery Asset cannot be accepted without its verified binding" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    assert {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(run.id)
    item = Enum.find(items(run.id), &(&1.source_item_key == "101"))

    assert {:snooze, _seconds} = Execution.process_run_item(item.id, 1, 3)
    asset = Repo.get_by!(RunAsset, run_id: run.id)
    assert :ok = Execution.process_run_asset(asset.id, 1, 3)

    Repo.get_by!(DeliveryAssetBinding,
      delivery_asset_id: asset.delivery_asset_id,
      destination_id: run.destination_id
    )
    |> Repo.delete!()

    assert {:discard, "A required Delivery Asset has no verified target binding"} =
             Execution.process_run_item(item.id, 2, 3)

    assert Repo.get!(RunItem, item.id).status == :failed
  end

  test "multiple Delivery Items share one Route-scoped asset and one target binding" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    shared_image = %{
      "source_id" => "501",
      "filename" => "delivery-pipeline.jpg",
      "media_type" => "image/jpeg",
      "alt" => "A shared delivery pipeline"
    }

    route.source_connection
    |> Ecto.Changeset.change(settings: %{"featured_image_overrides" => %{"102" => shared_image}})
    |> Repo.update!()

    assert {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(run.id)

    for item <- items(run.id) do
      assert {:snooze, _seconds} = Execution.process_run_item(item.id, 1, 3)
    end

    assert Repo.aggregate(DeliveryAsset, :count) == 1
    assert Repo.aggregate(RunAsset, :count) == 1
    assert Repo.aggregate(RunItemAsset, :count) == 2

    process_assets(run.id)

    Enum.each(items(run.id), &process_item_with_retry/1)

    completed = Execution.get_run!(scope, run.id)
    assert completed.status == :succeeded
    assert completed.assets_succeeded == 1
    assert completed.items_succeeded == 2
    assert Repo.aggregate(DeliveryAssetBinding, :count) == 1
  end

  test "changed asset bytes at the same logical source identity update the target asset" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    assert {:ok, first_run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(first_run.id)
    process_items_with_retry(first_run.id)

    first_binding = Repo.one!(DeliveryAssetBinding)
    first_hash = first_binding.last_content_hash

    route.source_connection
    |> Ecto.Changeset.change(
      settings: %{
        "revision_overrides" => %{"101" => "8"},
        "asset_content_versions" => %{"501" => "v2"}
      }
    )
    |> Repo.update!()

    assert {:ok, second_run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(second_run.id)
    process_items_with_retry(second_run.id)

    second_asset = Repo.get_by!(RunAsset, run_id: second_run.id)
    second_binding = Repo.get!(DeliveryAssetBinding, first_binding.id)

    assert second_asset.status == :succeeded
    assert second_asset.planned_operation == "update"
    refute second_binding.last_content_hash == first_hash

    stored =
      Store.fetch_asset(
        route.target_connection_id,
        route.current_destination_id,
        second_asset.asset_key
      )

    assert stored.bytes == "fake-asset:501:original:v2"
  end

  test "asset update refuses target ownership belonging to another Route" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)

    assert {:ok, first_run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(first_run.id)
    process_items_with_retry(first_run.id)

    first_asset = Repo.get_by!(RunAsset, run_id: first_run.id)

    stored =
      Store.fetch_asset(
        route.target_connection_id,
        route.current_destination_id,
        first_asset.asset_key
      )

    tampered = put_in(stored, [:ownership, "route_id"], Ecto.UUID.generate())

    assert :ok =
             Store.replace_asset(
               route.target_connection_id,
               route.current_destination_id,
               first_asset.asset_key,
               stored.target_reference,
               tampered
             )

    route.source_connection
    |> Ecto.Changeset.change(
      settings: %{
        "revision_overrides" => %{"101" => "8"},
        "asset_content_versions" => %{"501" => "v2"}
      }
    )
    |> Repo.update!()

    assert {:ok, second_run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(second_run.id)

    item = Enum.find(items(second_run.id), &(&1.source_item_key == "101"))
    assert {:snooze, _seconds} = Execution.process_run_item(item.id, 1, 3)

    second_asset = Repo.get_by!(RunAsset, run_id: second_run.id)

    assert {:discard, "Target asset ownership metadata does not match"} =
             Execution.process_run_asset(second_asset.id, 1, 1)

    assert Repo.get!(RunAsset, second_asset.id).status == :failed

    assert Repo.get!(DeliveryAssetBinding, Repo.one!(DeliveryAssetBinding).id).last_content_hash ==
             first_asset.content_hash
  end

  test "asset discovery rolls back when its Oban job cannot be inserted" do
    scope = CourierCMS.AccountsFixtures.user_scope_fixture()
    route = route_fixture(scope)
    assert {:ok, run} = Execution.start_manual_run(scope, route.id)
    assert :ok = Execution.plan_run(run.id)

    item =
      run.id
      |> items()
      |> Enum.find(&(&1.source_item_key == "101"))
      |> Repo.preload(run: :route)

    descriptor = %AssetDescriptor{
      source_key: "501",
      field_path: "fields.featured_image",
      filename: "delivery-pipeline.jpg",
      media_type: "image/jpeg"
    }

    previous = Application.fetch_env!(:couriercms, :asset_delivery_max_attempts)
    Application.put_env(:couriercms, :asset_delivery_max_attempts, 0)

    try do
      assert {:error, _reason} = Assets.plan_dependencies(item, [descriptor])
      assert Repo.aggregate(DeliveryAsset, :count) == 0
      assert Repo.aggregate(RunAsset, :count) == 0
      assert Repo.aggregate(RunItemAsset, :count) == 0
    after
      Application.put_env(:couriercms, :asset_delivery_max_attempts, previous)
    end
  end

  defp items(run_id) do
    RunItem
    |> where([item], item.run_id == ^run_id)
    |> order_by([item], asc: item.source_item_key)
    |> Repo.all()
  end

  defp process_items_with_retry(run_id) do
    Enum.each(items(run_id), &process_item_with_retry/1)
  end

  defp process_item_with_retry(item, attempt \\ 1) do
    case Execution.process_run_item(item.id, attempt, 3) do
      :ok ->
        :ok

      {:snooze, _seconds} ->
        process_assets(item.run_id)
        process_item_with_retry(item, attempt)

      {:error, _message} ->
        process_item_with_retry(item, attempt + 1)
    end
  end

  defp process_assets(run_id) do
    RunAsset
    |> where([asset], asset.run_id == ^run_id and asset.status in [:pending, :retrying])
    |> Repo.all()
    |> Enum.each(fn asset ->
      case Execution.process_run_asset(asset.id, 1, 3) do
        :ok -> :ok
        {:error, _message} -> assert :ok = Execution.process_run_asset(asset.id, 2, 3)
      end
    end)
  end

  defp route_fixture(scope, revision_overrides \\ %{}) do
    source =
      connection_fixture(scope, "Source #{System.unique_integer()}", "fake_source", %{})

    target =
      connection_fixture(scope, "Target #{System.unique_integer()}", "fake_target", %{
        "fail_once_for" => ["102"]
      })

    destination = destination_fixture(scope, target)

    {:ok, route} =
      CourierCMS.Routes.create_route(
        scope,
        %{
          name: "Route #{System.unique_integer()}",
          source_connection_id: source.id,
          target_connection_id: target.id,
          current_destination_id: destination.id,
          enabled: true
        },
        Map.merge(
          %{
            selection: %{
              "category" => "Engineering",
              "tags" => ["architecture"],
              "published_year" => ""
            },
            mapping: CourierCMS.Routes.default_mapping("fake_source")
          },
          revision_overrides
        )
      )

    route
  end

  defp connection_fixture(scope, name, adapter_key, settings) do
    %Connection{}
    |> Connection.changeset(%{
      name: name,
      adapter_key: adapter_key,
      extension_id: "com.couriercms.fake",
      component_id: adapter_key,
      endpoint: "https://#{adapter_key}.example",
      settings: settings,
      workspace_id: scope.workspace.id
    })
    |> Repo.insert!()
  end
end

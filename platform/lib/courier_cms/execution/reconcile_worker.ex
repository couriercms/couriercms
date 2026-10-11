defmodule CourierCMS.Execution.ReconcileWorker do
  @moduledoc "Repairs stale CourierCMS execution state independently of Oban's lifeline."

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [period: 240, fields: [:worker], states: [:available, :scheduled, :executing]]

  import Ecto.Query

  alias CourierCMS.Connectors.{ConnectorEvent, ConnectorEventWorker}
  alias CourierCMS.Assets.RunAsset

  alias CourierCMS.Execution.{
    AssetWorker,
    DeliveryWorker,
    JobArgs,
    PlanRunWorker,
    Run,
    RunItem
  }

  alias CourierCMS.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    with :ok <- JobArgs.validate(job.args) do
      cutoff =
        DateTime.add(
          DateTime.utc_now(),
          -Application.fetch_env!(:couriercms, :stranded_after_ms),
          :millisecond
        )

      connector_event_count = reconcile_connector_events(cutoff)
      asset_count = reconcile_assets(cutoff)
      item_count = reconcile_items(cutoff)
      run_count = reconcile_planners(cutoff)

      :telemetry.execute(
        [:couriercms, :reconciliation, :requeued],
        %{
          connector_events: connector_event_count,
          assets: asset_count,
          items: item_count,
          planners: run_count
        },
        %{}
      )

      :ok
    end
  end

  defp reconcile_assets(cutoff) do
    RunAsset
    |> where(
      [asset],
      asset.status in [:pending, :processing, :retrying] and asset.updated_at < ^cutoff
    )
    |> order_by([asset], asc: asset.updated_at)
    |> limit(500)
    |> Repo.all()
    |> Enum.count(&requeue_asset_if_stranded/1)
  end

  defp requeue_asset_if_stranded(asset) do
    if active_job?(AssetWorker, "run_asset_id", asset.id) do
      false
    else
      result =
        Ecto.Multi.new()
        |> Ecto.Multi.update(
          :asset,
          RunAsset.changeset(asset, %{status: :pending, completed_at: nil})
        )
        |> Oban.insert(
          :job,
          AssetWorker.new(JobArgs.put(%{"run_asset_id" => asset.id}),
            max_attempts: Application.fetch_env!(:couriercms, :asset_delivery_max_attempts)
          )
        )
        |> Repo.transaction()

      match?({:ok, _changes}, result)
    end
  end

  defp reconcile_connector_events(cutoff) do
    ConnectorEvent
    |> where(
      [event],
      event.status in [:accepted, :processing] and event.received_at < ^cutoff
    )
    |> order_by([event], asc: event.received_at)
    |> limit(100)
    |> Repo.all()
    |> Enum.count(&requeue_connector_event_if_stranded/1)
  end

  defp requeue_connector_event_if_stranded(event) do
    if active_job?(ConnectorEventWorker, "event_id", event.id) do
      false
    else
      result =
        Ecto.Multi.new()
        |> Ecto.Multi.update(
          :event,
          ConnectorEvent.changeset(event, %{
            status: :accepted,
            error_summary: nil,
            processed_at: nil
          })
        )
        |> Oban.insert(
          :job,
          ConnectorEventWorker.new(JobArgs.put(%{"event_id" => event.id}))
        )
        |> Repo.transaction()

      match?({:ok, _changes}, result)
    end
  end

  defp reconcile_items(cutoff) do
    RunItem
    |> where(
      [item],
      item.status in [:pending, :processing, :retrying] and item.updated_at < ^cutoff
    )
    |> order_by([item], asc: item.updated_at)
    |> limit(500)
    |> Repo.all()
    |> Enum.count(&requeue_item_if_stranded/1)
  end

  defp requeue_item_if_stranded(item) do
    if active_job?(DeliveryWorker, "run_item_id", item.id) do
      false
    else
      result =
        Ecto.Multi.new()
        |> Ecto.Multi.update(
          :item,
          RunItem.changeset(item, %{status: :pending, completed_at: nil})
        )
        |> Oban.insert(
          :job,
          DeliveryWorker.new(JobArgs.put(%{"run_item_id" => item.id}),
            max_attempts: Application.fetch_env!(:couriercms, :delivery_max_attempts)
          )
        )
        |> Repo.transaction()

      case result do
        {:ok, _changes} ->
          CourierCMS.Execution.reconcile_run(item.run_id)
          true

        {:error, _operation, _reason, _changes} ->
          false
      end
    end
  end

  defp reconcile_planners(cutoff) do
    Run
    |> where([run], run.status in [:queued, :planning] and run.updated_at < ^cutoff)
    |> order_by([run], asc: run.updated_at)
    |> limit(100)
    |> Repo.all()
    |> Enum.count(&requeue_plan_if_stranded/1)
  end

  defp requeue_plan_if_stranded(run) do
    if active_job?(PlanRunWorker, "run_id", run.id) do
      false
    else
      case Oban.insert(
             PlanRunWorker.new(JobArgs.put(%{"run_id" => run.id}),
               max_attempts: Application.fetch_env!(:couriercms, :planning_max_attempts)
             )
           ) do
        {:ok, _job} -> true
        {:error, _reason} -> false
      end
    end
  end

  defp active_job?(worker, key, id) do
    worker_name = worker |> Module.split() |> Enum.join(".")

    from(job in Oban.Job,
      where:
        job.worker == ^worker_name and
          job.state in ["available", "scheduled", "executing", "retryable"] and
          fragment("?->>? = ?", job.args, ^key, ^id)
    )
    |> Repo.exists?()
  end
end

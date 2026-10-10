defmodule CourierCMS.Observability do
  @moduledoc "Operational measurements shared by telemetry, readiness, and Prometheus scraping."

  alias CourierCMS.Execution.WorkerHeartbeat
  alias CourierCMS.Repo

  def emit_metrics do
    snapshot = snapshot()

    Enum.each(snapshot.queues, fn queue ->
      :telemetry.execute(
        [:couriercms, :queue, :snapshot],
        %{depth: queue.depth, oldest_age_seconds: queue.oldest_age_seconds},
        %{queue: queue.queue}
      )
    end)

    :telemetry.execute(
      [:couriercms, :worker, :snapshot],
      %{fresh: snapshot.fresh_workers},
      %{}
    )

    :telemetry.execute(
      [:couriercms, :extension, :cluster, :snapshot],
      %{mismatched_nodes: snapshot.extension_mismatched_nodes},
      %{}
    )

    :telemetry.execute(
      [:couriercms, :checkpoint, :snapshot],
      %{lag_seconds: snapshot.checkpoint_lag_seconds},
      %{}
    )

    :ok
  rescue
    _exception -> :ok
  end

  def snapshot do
    %{
      queues: queue_snapshot(),
      fresh_workers: scalar(fresh_workers_sql()),
      extension_mismatched_nodes: extension_mismatched_nodes(),
      failed_run_items: scalar(failed_items_sql()),
      checkpoint_lag_seconds: scalar(checkpoint_lag_sql())
    }
  end

  def prometheus do
    snapshot = snapshot()

    queue_lines =
      Enum.flat_map(snapshot.queues, fn queue ->
        label = label(queue.queue)

        [
          ~s(couriercms_queue_depth{queue="#{label}"} #{queue.depth}),
          ~s(couriercms_queue_oldest_job_age_seconds{queue="#{label}"} #{queue.oldest_age_seconds})
        ]
      end)

    ([
       "# TYPE couriercms_worker_fresh gauge",
       "couriercms_worker_fresh #{snapshot.fresh_workers}",
       "# TYPE couriercms_failed_run_items gauge",
       "couriercms_failed_run_items #{snapshot.failed_run_items}",
       "# TYPE couriercms_extension_mismatched_nodes gauge",
       "couriercms_extension_mismatched_nodes #{snapshot.extension_mismatched_nodes}",
       "# TYPE couriercms_checkpoint_lag_seconds gauge",
       "couriercms_checkpoint_lag_seconds #{snapshot.checkpoint_lag_seconds}",
       "# TYPE couriercms_queue_depth gauge",
       "# TYPE couriercms_queue_oldest_job_age_seconds gauge"
     ] ++ queue_lines)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp queue_snapshot do
    sql = """
    SELECT queue,
           COUNT(*)::bigint AS depth,
           COALESCE(EXTRACT(EPOCH FROM (NOW() - MIN(scheduled_at))), 0)::bigint AS oldest_age
    FROM oban_jobs
    WHERE state IN ('available', 'scheduled', 'retryable', 'executing')
    GROUP BY queue
    ORDER BY queue
    """

    %{rows: rows} = Ecto.Adapters.SQL.query!(Repo, sql, [])

    Enum.map(rows, fn [queue, depth, oldest_age] ->
      %{queue: queue, depth: depth, oldest_age_seconds: max(oldest_age, 0)}
    end)
  end

  defp fresh_workers_sql do
    cutoff = DateTime.add(DateTime.utc_now(), -90, :second)

    {"SELECT COUNT(*)::bigint FROM worker_heartbeats WHERE role IN ('all', 'worker') AND last_seen_at >= $1",
     [cutoff]}
  end

  defp failed_items_sql do
    {"SELECT COUNT(*)::bigint FROM run_items WHERE status = 'failed'", []}
  end

  defp checkpoint_lag_sql do
    {"SELECT COALESCE(EXTRACT(EPOCH FROM (NOW() - MIN(last_advanced_at))), 0)::bigint FROM checkpoints",
     []}
  end

  defp scalar({sql, params}) do
    case Ecto.Adapters.SQL.query!(Repo, sql, params).rows do
      [[value]] when is_integer(value) -> max(value, 0)
      [[%Decimal{} = value]] -> value |> Decimal.to_integer() |> max(0)
      _other -> 0
    end
  end

  def worker_ready?, do: WorkerHeartbeat.fresh_worker?()

  def extension_cluster_ready?, do: CourierCMS.Extensions.cluster_status().consistent?

  defp extension_mismatched_nodes do
    CourierCMS.Extensions.cluster_status().mismatched_nodes |> length()
  end

  defp label(value), do: value |> to_string() |> String.replace(~r/[^a-zA-Z0-9_:.-]/, "_")
end

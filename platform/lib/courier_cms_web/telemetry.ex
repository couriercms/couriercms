defmodule CourierCMSWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children =
      if Application.get_env(:couriercms, :telemetry_poller_enabled, true) do
        [{:telemetry_poller, measurements: periodic_measurements(), period: 10_000}]
      else
        []
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("couriercms.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("couriercms.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("couriercms.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("couriercms.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("couriercms.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # CourierCMS execution metrics
      sum("couriercms.planning.page.items", tags: [:adapter]),
      counter("couriercms.delivery.completed.count", tags: [:adapter, :status]),
      counter("couriercms.delivery.failed.count", tags: [:adapter, :category, :terminal]),
      summary("couriercms.delivery.duration.duration",
        tags: [:adapter, :status],
        unit: {:native, :millisecond}
      ),
      counter("couriercms.processor.execute.count",
        tags: [:component_id, :status, :error_category]
      ),
      summary("couriercms.processor.execute.duration",
        tags: [:component_id, :status],
        unit: {:native, :millisecond}
      ),
      summary("couriercms.processor.execute.input_bytes", tags: [:component_id, :status]),
      summary("couriercms.processor.execute.output_bytes", tags: [:component_id, :status]),
      counter("couriercms.delivery.lock_contention.count"),
      counter("couriercms.connection.saturated.count"),
      counter("couriercms.alert.enqueue_failed.count"),
      sum("couriercms.alert.delivered.count", tags: [:kind]),
      sum("couriercms.schedule.dispatch.routes_due"),
      counter("couriercms.checkpoint.advanced.count", tags: [:adapter, :retrieval_mode]),
      last_value("couriercms.queue.snapshot.depth", tags: [:queue]),
      last_value("couriercms.queue.snapshot.oldest_age_seconds", tags: [:queue]),
      last_value("couriercms.worker.snapshot.fresh"),
      last_value("couriercms.extension.cluster.snapshot.mismatched_nodes"),
      last_value("couriercms.checkpoint.snapshot.lag_seconds"),
      sum("couriercms.reconciliation.requeued.items"),
      sum("couriercms.reconciliation.requeued.planners"),
      counter("couriercms.connection.rate_limited.count", tags: [:adapter]),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [{CourierCMS.Observability, :emit_metrics, []}]
  end
end

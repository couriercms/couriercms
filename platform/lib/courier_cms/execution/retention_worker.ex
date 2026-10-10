defmodule CourierCMS.Execution.RetentionWorker do
  @moduledoc "Batched cleanup for configured CourierCMS history retention."

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [period: 3_600, fields: [:worker], states: [:available, :scheduled, :executing]]

  import Ecto.Query

  alias CourierCMS.Connectors.ConnectorEvent
  alias CourierCMS.Execution.{DeliveryLock, JobArgs, Run, WorkerHeartbeat}
  alias CourierCMS.Repo
  alias CourierCMS.Workspaces.AuditEvent

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    with :ok <- JobArgs.validate(job.args) do
      clean_ephemeral()

      if Application.get_env(:couriercms, :retention_enabled, false) do
        batch_size = Application.fetch_env!(:couriercms, :retention_batch_size)
        delete_old(Run, :completed_at, retention_days(:run_retention_days), batch_size)

        delete_old(
          ConnectorEvent,
          :received_at,
          retention_days(:event_retention_days),
          batch_size
        )

        delete_old(AuditEvent, :inserted_at, retention_days(:audit_retention_days), batch_size)
      end

      :ok
    end
  end

  defp clean_ephemeral do
    now = DateTime.utc_now()
    heartbeat_cutoff = DateTime.add(now, -86_400, :second)
    rate_bucket_cutoff = System.system_time(:second) - 10

    Repo.delete_all(from(lock in DeliveryLock, where: lock.expires_at < ^now))

    Repo.delete_all(
      from(heartbeat in WorkerHeartbeat, where: heartbeat.last_seen_at < ^heartbeat_cutoff)
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      "DELETE FROM connection_rate_buckets WHERE bucket < $1",
      [rate_bucket_cutoff]
    )
  end

  defp delete_old(schema, timestamp_field, days, batch_size) do
    cutoff = DateTime.add(DateTime.utc_now(), -days, :day)

    ids =
      schema
      |> where([record], field(record, ^timestamp_field) < ^cutoff)
      |> where([record], not is_nil(field(record, ^timestamp_field)))
      |> select([record], record.id)
      |> limit(^batch_size)
      |> Repo.all()

    if ids != [], do: Repo.delete_all(from(record in schema, where: record.id in ^ids))
  end

  defp retention_days(key), do: Application.fetch_env!(:couriercms, key)
end

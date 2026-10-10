defmodule CourierCMS.Connectors.ConnectorEventWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :webhooks,
    max_attempts: 5,
    unique: [period: 86_400, fields: [:worker, :args], keys: [:event_id]]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => event_id}} = job) do
    with :ok <- CourierCMS.Execution.JobArgs.validate(job.args) do
      CourierCMS.Connectors.process_event(event_id)
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: CourierCMS.Execution.Retry.backoff(attempt, 60)
end

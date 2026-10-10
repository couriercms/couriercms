defmodule CourierCMS.Execution.FailureAlertWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 5,
    unique: [period: :infinity, fields: [:worker, :args], keys: [:run_item_id]]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_item_id" => run_item_id}} = job) do
    with :ok <- CourierCMS.Execution.JobArgs.validate(job.args) do
      CourierCMS.Alerts.deliver_terminal_failure(run_item_id)
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}),
    do: CourierCMS.Execution.Retry.backoff(attempt + 4, 1_800)
end

defmodule CourierCMS.Execution.AssetWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :delivery,
    max_attempts: 3,
    unique: [
      period: :infinity,
      fields: [:worker, :args],
      keys: [:run_asset_id],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args: %{"run_asset_id" => run_asset_id},
          attempt: attempt,
          max_attempts: max_attempts
        } = job
      ) do
    with :ok <- CourierCMS.Execution.JobArgs.validate(job.args) do
      CourierCMS.Execution.process_run_asset(run_asset_id, attempt, max_attempts)
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    CourierCMS.Execution.Retry.backoff(
      attempt,
      Application.fetch_env!(:couriercms, :asset_delivery_backoff_cap_seconds)
    )
  end
end

defmodule CourierCMS.Execution.PlanRunWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :route_planning,
    max_attempts: 3,
    unique: [
      period: :infinity,
      fields: [:worker, :args],
      keys: [:run_id],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args: %{"run_id" => run_id},
          attempt: attempt,
          max_attempts: max_attempts
        } = job
      ) do
    with :ok <- CourierCMS.Execution.JobArgs.validate(job.args) do
      CourierCMS.Execution.plan_run(run_id, attempt, max_attempts)
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    CourierCMS.Execution.Retry.backoff(
      attempt,
      Application.fetch_env!(:couriercms, :planning_backoff_cap_seconds)
    )
  end
end

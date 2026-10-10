defmodule CourierCMS.Execution.ScheduleWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: 55, fields: [:worker]]

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    with :ok <- CourierCMS.Execution.JobArgs.validate(job.args) do
      CourierCMS.Execution.enqueue_due_schedules()
    end
  end
end

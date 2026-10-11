defmodule CourierCMS.LocalRecovery do
  @moduledoc """
  Recovers jobs interrupted by an abrupt Local-process shutdown.

  Local permits exactly one application instance, so any job still marked as
  executing before Oban starts is necessarily orphaned. Server never invokes
  this recovery path because another node may legitimately own the job.
  """

  import Ecto.Query

  alias CourierCMS.Repo

  def child_spec(_options) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]},
      restart: :temporary,
      type: :worker
    }
  end

  def start_link(_options) do
    recover_orphaned_jobs()
    :ignore
  end

  def recover_orphaned_jobs do
    now = DateTime.utc_now()

    {count, _jobs} =
      Oban.Job
      |> where([job], job.state == "executing")
      |> update([job],
        set: [
          state: "available",
          scheduled_at: ^now,
          attempted_by: [],
          max_attempts: fragment("MAX(?, ? + 1)", job.max_attempts, job.attempt)
        ]
      )
      |> Repo.update_all([])

    :telemetry.execute([:couriercms, :local, :jobs_recovered], %{count: count}, %{})
    {:ok, count}
  end
end

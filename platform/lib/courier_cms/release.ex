defmodule CourierCMS.Release do
  @moduledoc false

  @app :couriercms

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _function_result, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()

    {:ok, _function_result, _apps} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def assert_job_compatibility! do
    load_app()

    for repo <- repos() do
      {:ok, versions, _apps} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          %{rows: rows} =
            Ecto.Adapters.SQL.query!(
              repo,
              """
              SELECT DISTINCT args->>'v'
              FROM oban_jobs
              WHERE state IN ('available', 'scheduled', 'executing', 'retryable')
              """,
              []
            )

          Enum.map(rows, &List.first/1)
        end)

      unsupported = Enum.reject(versions, &(&1 in [nil, "1", "2"]))

      if unsupported != [] do
        raise "active jobs use unsupported argument versions: #{Enum.join(unsupported, ", ")}"
      end
    end

    :ok
  end

  @doc "Verifies loaded Extension packages and active component references on this node."
  def verify_extensions! do
    CourierCMS.Extensions.verify_runtime!()
  end

  @doc "Refuses removal while active configuration or unfinished Runs reference an Extension."
  def assert_extension_removable!(extension_id) do
    CourierCMS.Extensions.assert_removable!(extension_id)
  end

  @doc "Fails unless this release node has its worker runtime and database available."
  def worker_health! do
    require_pid!(Oban.whereis(Oban), "Oban")

    require_pid!(
      Process.whereis(CourierCMS.Execution.WorkerHeartbeat),
      "worker heartbeat"
    )

    Ecto.Adapters.SQL.query!(CourierCMS.Repo, "SELECT 1", [])
    :ok
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    Application.load(@app)
  end

  defp require_pid!(pid, _label) when is_pid(pid), do: :ok
  defp require_pid!(_pid, label), do: raise("#{label} process is not running")
end

defmodule CourierCMS.Release do
  @moduledoc false

  @app :couriercms

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _function_result, _apps} =
        Ecto.Migrator.with_repo(
          repo,
          &Ecto.Migrator.run(&1, :up, all: true),
          pool_size: migration_pool_size()
        )
    end
  end

  def rollback(repo, version) do
    load_app()

    {:ok, _function_result, _apps} =
      Ecto.Migrator.with_repo(
        repo,
        &Ecto.Migrator.run(&1, :down, to: version),
        pool_size: migration_pool_size()
      )
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

  @doc "Returns a non-sensitive fingerprint of a Local installation's durable identity."
  def local_state_fingerprint do
    load_app()

    unless Application.fetch_env!(@app, :release_profile) == :local do
      raise "local_state_fingerprint is available only in a Local release"
    end

    {:ok, durable_identity, _apps} =
      Ecto.Migrator.with_repo(
        CourierCMS.Repo,
        fn repo ->
          for {table, column} <- [
                {"workspaces", "id"},
                {"users", "id"},
                {"workspace_memberships", "id"},
                {"schema_migrations", "version"}
              ] do
            %{rows: rows} =
              Ecto.Adapters.SQL.query!(
                repo,
                "SELECT #{column} FROM #{table} ORDER BY #{column}",
                []
              )

            {table, rows}
          end
        end,
        pool_size: 1
      )

    :sha256
    |> :crypto.hash(:erlang.term_to_binary(durable_identity))
    |> Base.encode16(case: :lower)
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  # Ecto's release migrator defaults to a two-connection pool. SQLite can only
  # have one migration writer, and each new connection also applies journal
  # pragmas, so Local deliberately starts a single migration connection.
  defp migration_pool_size do
    if Application.fetch_env!(@app, :release_profile) == :local, do: 1, else: 2
  end

  defp load_app do
    Application.load(@app)
  end

  defp require_pid!(pid, _label) when is_pid(pid), do: :ok
  defp require_pid!(_pid, label), do: raise("#{label} process is not running")
end

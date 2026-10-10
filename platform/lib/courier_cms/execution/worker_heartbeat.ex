defmodule CourierCMS.Execution.WorkerHeartbeat do
  @moduledoc false

  use Ecto.Schema
  use GenServer

  import Ecto.Query
  require Logger

  alias CourierCMS.Repo

  @primary_key {:node_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "worker_heartbeats" do
    field :role, :string
    field :queues, {:array, :string}, default: []
    field :version, :string
    field :extension_fingerprint, :string
    field :extension_set, {:array, :map}, default: []
    field :extension_status, :string, default: "unknown"
    field :last_seen_at, :utc_datetime_usec
    timestamps()
  end

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(state) do
    send(self(), :heartbeat)
    {:ok, state}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    write_heartbeat()
    Process.send_after(self(), :heartbeat, 30_000)
    {:noreply, state}
  end

  def fresh_worker?(max_age_seconds \\ 90) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_seconds, :second)

    __MODULE__
    |> where(
      [heartbeat],
      heartbeat.role in ["all", "worker"] and heartbeat.last_seen_at >= ^cutoff
    )
    |> Repo.exists?()
  end

  def write_now, do: write_heartbeat()

  defp write_heartbeat do
    now = DateTime.utc_now()
    extension_snapshot = CourierCMS.Extensions.runtime_snapshot()

    Repo.insert_all(
      __MODULE__,
      [
        %{
          node_id: node_id(),
          role: to_string(Application.fetch_env!(:couriercms, :deployment_role)),
          queues: configured_queues(),
          version: Application.spec(:couriercms, :vsn) |> to_string(),
          extension_fingerprint: extension_snapshot.fingerprint,
          extension_set: extension_snapshot.artifacts,
          extension_status: extension_snapshot.status,
          last_seen_at: now,
          inserted_at: now,
          updated_at: now
        }
      ],
      conflict_target: [:node_id],
      on_conflict: [
        set: [
          role: to_string(Application.fetch_env!(:couriercms, :deployment_role)),
          queues: configured_queues(),
          version: Application.spec(:couriercms, :vsn) |> to_string(),
          extension_fingerprint: extension_snapshot.fingerprint,
          extension_set: extension_snapshot.artifacts,
          extension_status: extension_snapshot.status,
          last_seen_at: now,
          updated_at: now
        ]
      ]
    )

    :ok
  rescue
    exception ->
      Logger.warning("worker heartbeat write failed", reason: Exception.message(exception))
      :ok
  end

  defp node_id do
    System.get_env("COURIERCMS_NODE_ID") ||
      "#{node()}:#{System.pid()}"
  end

  defp configured_queues do
    role = Application.fetch_env!(:couriercms, :deployment_role)

    if role == :web do
      []
    else
      :couriercms
      |> Application.fetch_env!(Oban)
      |> CourierCMS.Deployment.oban_options!(role)
      |> Keyword.get(:queues, [])
      |> Keyword.keys()
      |> Enum.map(&to_string/1)
    end
  end
end

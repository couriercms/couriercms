defmodule CourierCMS.Execution.Checkpoint do
  @moduledoc "Durable, Adapter-specific progress for incremental Route discovery."

  use Ecto.Schema
  import Ecto.Changeset

  alias CourierCMS.Connections.Connection
  alias CourierCMS.Execution.Run
  alias CourierCMS.Routes.Route

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "checkpoints" do
    field :adapter_key, :string
    field :value, :map, default: %{}
    field :last_advanced_at, :utc_datetime_usec
    field :last_full_scan_at, :utc_datetime_usec

    belongs_to :route, Route
    belongs_to :source_connection, Connection
    belongs_to :last_run, Run

    timestamps()
  end

  def changeset(checkpoint, attrs) do
    checkpoint
    |> cast(attrs, [
      :route_id,
      :source_connection_id,
      :last_run_id,
      :adapter_key,
      :value,
      :last_advanced_at,
      :last_full_scan_at
    ])
    |> validate_required([
      :route_id,
      :source_connection_id,
      :adapter_key,
      :value,
      :last_advanced_at
    ])
    |> unique_constraint(:route_id)
    |> foreign_key_constraint(:route_id)
    |> foreign_key_constraint(:source_connection_id)
    |> foreign_key_constraint(:last_run_id)
  end
end

defmodule CourierCMS.Execution.ProcessorExecution do
  @moduledoc "Content-free execution evidence for one Processor step and Delivery Item attempt."

  use Ecto.Schema
  import Ecto.Changeset

  alias CourierCMS.Execution.RunItem

  @statuses [:processing, :succeeded, :failed]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "processor_executions" do
    field :attempt, :integer
    field :position, :integer
    field :extension_id, :string
    field :component_id, :string
    field :component_version, :string
    field :input_path, :string
    field :output_path, :string
    field :config_hash, :string
    field :input_hash, :string
    field :output_hash, :string
    field :input_bytes, :integer
    field :output_bytes, :integer
    field :duration_us, :integer
    field :status, Ecto.Enum, values: @statuses, default: :processing
    field :error_category, :string
    field :error_summary, :string
    field :retryable, :boolean, default: false
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :run_item, RunItem

    timestamps()
  end

  @doc false
  def changeset(execution, attrs) do
    execution
    |> cast(attrs, [
      :run_item_id,
      :attempt,
      :position,
      :extension_id,
      :component_id,
      :component_version,
      :input_path,
      :output_path,
      :config_hash,
      :input_hash,
      :output_hash,
      :input_bytes,
      :output_bytes,
      :duration_us,
      :status,
      :error_category,
      :error_summary,
      :retryable,
      :started_at,
      :completed_at
    ])
    |> validate_required([
      :run_item_id,
      :attempt,
      :position,
      :extension_id,
      :component_id,
      :component_version,
      :input_path,
      :output_path,
      :config_hash,
      :input_hash,
      :input_bytes,
      :status,
      :started_at
    ])
    |> validate_number(:attempt, greater_than: 0)
    |> validate_number(:position, greater_than: 0)
    |> validate_number(:input_bytes, greater_than_or_equal_to: 0)
    |> validate_number(:output_bytes, greater_than_or_equal_to: 0)
    |> validate_number(:duration_us, greater_than_or_equal_to: 0)
    |> unique_constraint([:run_item_id, :attempt, :position])
    |> foreign_key_constraint(:run_item_id)
  end
end

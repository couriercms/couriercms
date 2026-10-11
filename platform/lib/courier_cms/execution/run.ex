defmodule CourierCMS.Execution.Run do
  @moduledoc "One durable execution of an immutable Route Revision."

  use Ecto.Schema
  import Ecto.Changeset

  alias CourierCMS.Execution.RunItem
  alias CourierCMS.Destinations.Destination
  alias CourierCMS.Routes.{Route, RouteRevision}

  @statuses [
    :queued,
    :planning,
    :running,
    :succeeded,
    :partially_succeeded,
    :failed,
    :cancelled
  ]
  @trigger_kinds [:manual, :schedule, :polling, :save, :publish]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "runs" do
    field :trigger_kind, Ecto.Enum, values: @trigger_kinds
    field :trigger_metadata, :map, default: %{}
    field :source_artifact, :map
    field :target_artifact, :map
    field :processor_artifacts, {:array, :map}, default: []
    field :schedule_key, :string
    field :planning_cursor, :map
    field :planning_page, :integer, default: 0
    field :planning_complete, :boolean, default: false
    field :status, Ecto.Enum, values: @statuses, default: :queued
    field :items_discovered, :integer, default: 0
    field :items_succeeded, :integer, default: 0
    field :items_failed, :integer, default: 0
    field :items_retrying, :integer, default: 0
    field :items_skipped, :integer, default: 0
    field :assets_discovered, :integer, default: 0
    field :assets_succeeded, :integer, default: 0
    field :assets_failed, :integer, default: 0
    field :assets_retrying, :integer, default: 0
    field :assets_skipped, :integer, default: 0
    field :error_category, :string
    field :error_summary, :string
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :cancelled_at, :utc_datetime_usec

    belongs_to :route, Route
    belongs_to :route_revision, RouteRevision
    belongs_to :destination, Destination
    belongs_to :initiated_by_user, CourierCMS.Accounts.User
    belongs_to :connector_event, CourierCMS.Connectors.ConnectorEvent
    has_many :items, RunItem
    has_many :assets, CourierCMS.Assets.RunAsset

    timestamps()
  end

  @doc false
  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :route_id,
      :route_revision_id,
      :destination_id,
      :trigger_kind,
      :trigger_metadata,
      :source_artifact,
      :target_artifact,
      :processor_artifacts,
      :schedule_key,
      :planning_cursor,
      :planning_page,
      :planning_complete,
      :status,
      :items_discovered,
      :items_succeeded,
      :items_failed,
      :items_retrying,
      :items_skipped,
      :assets_discovered,
      :assets_succeeded,
      :assets_failed,
      :assets_retrying,
      :assets_skipped,
      :error_category,
      :error_summary,
      :started_at,
      :completed_at,
      :cancelled_at,
      :initiated_by_user_id,
      :connector_event_id
    ])
    |> validate_required([:route_id, :route_revision_id, :destination_id, :trigger_kind, :status])
    |> validate_artifact(:source_artifact)
    |> validate_artifact(:target_artifact)
    |> validate_processor_artifacts()
    |> validate_counts()
    |> foreign_key_constraint(:route_id)
    |> foreign_key_constraint(:route_revision_id)
    |> foreign_key_constraint(:destination_id)
    |> foreign_key_constraint(:initiated_by_user_id)
    |> foreign_key_constraint(:connector_event_id)
    |> unique_constraint([:route_id, :connector_event_id])
    |> unique_constraint([:route_id, :schedule_key], name: :runs_route_schedule_key_index)
  end

  defp validate_counts(changeset) do
    Enum.reduce(
      [
        :planning_page,
        :items_discovered,
        :items_succeeded,
        :items_failed,
        :items_retrying,
        :items_skipped,
        :assets_discovered,
        :assets_succeeded,
        :assets_failed,
        :assets_retrying,
        :assets_skipped
      ],
      changeset,
      &validate_number(&2, &1, greater_than_or_equal_to: 0)
    )
  end

  defp validate_artifact(changeset, field) do
    validate_change(changeset, field, fn ^field, artifact ->
      case CourierCMS.Extensions.Artifact.validate(artifact) do
        :ok -> []
        {:error, message} -> [{field, message}]
      end
    end)
  end

  defp validate_processor_artifacts(changeset) do
    validate_change(changeset, :processor_artifacts, fn :processor_artifacts, artifacts ->
      if is_list(artifacts) and
           Enum.all?(artifacts, &(CourierCMS.Extensions.Artifact.validate(&1) == :ok)),
         do: [],
         else: [processor_artifacts: "contains invalid Extension artifact evidence"]
    end)
  end
end

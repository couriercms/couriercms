defmodule CourierCMS.Routes.RouteRevision do
  @moduledoc "An immutable executable snapshot of Route configuration."

  use Ecto.Schema
  import Ecto.Changeset

  alias CourierCMS.Routes.Route

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "route_revisions" do
    field :revision_number, :integer
    field :source_extension_id, :string
    field :source_component_id, :string
    field :target_extension_id, :string
    field :target_component_id, :string
    field :selection, :map, default: %{}
    field :aggregation_rules, :map, default: %{}
    field :mapping, :map, default: %{}
    field :projections, {:array, :map}, default: []
    field :delivery_name_path, :string, default: "payload.title"
    field :delivery_contract, :map, default: %{}
    field :contract_version, :integer
    field :transformations, {:array, :map}, default: []
    field :trigger_settings, :map, default: %{}
    field :checksum, :string

    belongs_to :route, Route

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(revision, attrs) do
    revision
    |> cast(attrs, [
      :route_id,
      :revision_number,
      :source_extension_id,
      :source_component_id,
      :target_extension_id,
      :target_component_id,
      :selection,
      :aggregation_rules,
      :mapping,
      :projections,
      :delivery_name_path,
      :delivery_contract,
      :contract_version,
      :transformations,
      :trigger_settings,
      :checksum
    ])
    |> validate_required([
      :route_id,
      :revision_number,
      :source_extension_id,
      :source_component_id,
      :target_extension_id,
      :target_component_id,
      :contract_version,
      :delivery_name_path,
      :checksum
    ])
    |> validate_number(:revision_number, greater_than: 0)
    |> validate_number(:contract_version, greater_than: 0)
    |> validate_length(:delivery_name_path, min: 1, max: 255)
    |> validate_mapping()
    |> validate_projections()
    |> unique_constraint([:route_id, :revision_number])
    |> unique_constraint([:route_id, :checksum])
    |> foreign_key_constraint(:route_id)
  end

  defp validate_projections(changeset) do
    case CourierCMS.Transport.Projection.validate_definitions(get_field(changeset, :projections)) do
      :ok -> changeset
      {:error, message} -> add_error(changeset, :projections, message)
    end
  end

  defp validate_mapping(changeset) do
    case CourierCMS.Mapping.validate(get_field(changeset, :mapping)) do
      :ok -> changeset
      {:error, message} -> add_error(changeset, :mapping, message)
    end
  end
end

defmodule CourierCMS.ExtensionSDK.ContentBundle do
  @moduledoc """
  Bounded, normalized content assembled by one source Adapter for a root item.

  CMS-specific discovery stays inside the Adapter. CourierCMS consumes this
  portable result and validates its generic safety invariants.
  """

  alias CourierCMS.ExtensionSDK.{
    AssetDescriptor,
    ContentNode,
    ContentRelationship,
    SourceIdentity
  }

  @enforce_keys [:root]
  defstruct root: nil,
            included: [],
            relationships: [],
            assets: [],
            metadata: %{}

  @type t :: %__MODULE__{
          root: ContentNode.t(),
          included: [ContentNode.t()],
          relationships: [ContentRelationship.t()],
          assets: [AssetDescriptor.t()],
          metadata: map()
        }

  @type limit_options :: [
          max_nodes: pos_integer(),
          max_relationships: non_neg_integer(),
          max_assets: non_neg_integer()
        ]

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, [String.t()]}
  def new(attrs) do
    attrs = Map.new(attrs)

    bundle = %__MODULE__{
      root: fetch(attrs, :root),
      included: fetch(attrs, :included, []),
      relationships: fetch(attrs, :relationships, []),
      assets: fetch(attrs, :assets, []),
      metadata: fetch(attrs, :metadata, %{})
    }

    case validate(bundle) do
      :ok -> {:ok, normalize(bundle)}
      {:error, errors} -> {:error, errors}
    end
  end

  @spec validate(t(), limit_options()) :: :ok | {:error, [String.t()]}
  def validate(bundle, limits \\ [])

  def validate(%__MODULE__{} = bundle, limits) do
    errors =
      []
      |> validate_root(bundle.root)
      |> validate_collection(:included, bundle.included, &valid_node?/1)
      |> validate_collection(:relationships, bundle.relationships, &valid_relationship?/1)
      |> validate_collection(:assets, bundle.assets, &valid_asset?/1)
      |> validate_metadata(bundle.metadata)
      |> validate_duplicate_nodes(bundle)
      |> validate_duplicate_assets(bundle)
      |> validate_relationship_endpoints(bundle)
      |> validate_cycles(bundle)
      |> validate_limits(bundle, limits)

    case Enum.reverse(errors) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  def validate(_bundle, _limits), do: {:error, ["content bundle must be a ContentBundle"]}

  @spec node_count(t()) :: pos_integer()
  def node_count(%__MODULE__{included: included}), do: length(included) + 1

  defp normalize(bundle) do
    %{
      bundle
      | included: Enum.sort_by(bundle.included, &node_key/1),
        relationships: Enum.sort_by(bundle.relationships, &ContentRelationship.identity/1),
        assets: Enum.sort_by(bundle.assets, &AssetDescriptor.identity/1)
    }
  end

  defp validate_root(errors, root) do
    if valid_node?(root), do: errors, else: ["root must be a valid ContentNode" | errors]
  end

  defp validate_collection(errors, name, values, validator) when is_list(values) do
    case Enum.find_index(values, &(not validator.(&1))) do
      nil -> errors
      index -> ["#{name} contains an invalid value at index #{index}" | errors]
    end
  end

  defp validate_collection(errors, name, _values, _validator),
    do: ["#{name} must be a list" | errors]

  defp validate_metadata(errors, metadata) when is_map(metadata), do: errors
  defp validate_metadata(errors, _metadata), do: ["metadata must be a map" | errors]

  defp validate_duplicate_nodes(errors, %__MODULE__{} = bundle) do
    if valid_node?(bundle.root) and is_list(bundle.included) and
         Enum.all?(bundle.included, &valid_node?/1) do
      keys = Enum.map([bundle.root | bundle.included], &node_key/1)

      if length(keys) == MapSet.size(MapSet.new(keys)),
        do: errors,
        else: ["content bundle contains duplicate node identities" | errors]
    else
      errors
    end
  end

  defp validate_duplicate_assets(errors, %__MODULE__{assets: assets}) when is_list(assets) do
    if Enum.all?(assets, &valid_asset?/1) do
      keys = Enum.map(assets, &AssetDescriptor.identity/1)

      if length(keys) == MapSet.size(MapSet.new(keys)),
        do: errors,
        else: ["content bundle contains duplicate asset identities" | errors]
    else
      errors
    end
  end

  defp validate_duplicate_assets(errors, _bundle), do: errors

  defp validate_relationship_endpoints(errors, %__MODULE__{} = bundle) do
    if valid_nodes_and_relationships?(bundle) do
      node_keys = MapSet.new([bundle.root | bundle.included], &node_key/1)

      case Enum.find(bundle.relationships, fn relationship ->
             not MapSet.member?(node_keys, node_key(relationship.from)) or
               not MapSet.member?(node_keys, node_key(relationship.to))
           end) do
        nil -> errors
        _relationship -> ["content bundle relationship references an unknown node" | errors]
      end
    else
      errors
    end
  end

  defp validate_cycles(errors, %__MODULE__{} = bundle) do
    if valid_nodes_and_relationships?(bundle) and relationships_known?(bundle) and
         cyclic?(bundle) do
      ["content bundle relationships contain a cycle" | errors]
    else
      errors
    end
  end

  defp validate_limits(errors, %__MODULE__{} = bundle, limits) do
    errors
    |> over_limit(:nodes, safe_length(bundle.included) + 1, Keyword.get(limits, :max_nodes))
    |> over_limit(
      :relationships,
      safe_length(bundle.relationships),
      Keyword.get(limits, :max_relationships)
    )
    |> over_limit(:assets, safe_length(bundle.assets), Keyword.get(limits, :max_assets))
  end

  defp over_limit(errors, _name, _count, nil), do: errors

  defp over_limit(errors, name, count, maximum)
       when is_integer(maximum) and maximum >= 0 and count > maximum,
       do: ["content bundle #{name} count #{count} exceeds limit #{maximum}" | errors]

  defp over_limit(errors, _name, _count, _maximum), do: errors

  defp valid_nodes_and_relationships?(bundle) do
    valid_node?(bundle.root) and is_list(bundle.included) and
      Enum.all?(bundle.included, &valid_node?/1) and is_list(bundle.relationships) and
      Enum.all?(bundle.relationships, &valid_relationship?/1)
  end

  defp relationships_known?(bundle) do
    keys = MapSet.new([bundle.root | bundle.included], &node_key/1)

    Enum.all?(bundle.relationships, fn relationship ->
      MapSet.member?(keys, node_key(relationship.from)) and
        MapSet.member?(keys, node_key(relationship.to))
    end)
  end

  defp cyclic?(bundle) do
    keys = Enum.map([bundle.root | bundle.included], &node_key/1)
    adjacency = Map.new(keys, &{&1, []})
    indegrees = Map.new(keys, &{&1, 0})

    {adjacency, indegrees} =
      Enum.reduce(bundle.relationships, {adjacency, indegrees}, fn relationship,
                                                                   {adjacency, indegrees} ->
        from = node_key(relationship.from)
        to = node_key(relationship.to)

        {
          Map.update!(adjacency, from, &[to | &1]),
          Map.update!(indegrees, to, &(&1 + 1))
        }
      end)

    queue = for {key, 0} <- indegrees, do: key
    visited_count(queue, adjacency, indegrees, 0) < length(keys)
  end

  defp visited_count([], _adjacency, _indegrees, count), do: count

  defp visited_count([key | rest], adjacency, indegrees, count) do
    {indegrees, ready} =
      Enum.reduce(Map.fetch!(adjacency, key), {indegrees, []}, fn target, {degrees, ready} ->
        degrees = Map.update!(degrees, target, &(&1 - 1))
        ready = if Map.fetch!(degrees, target) == 0, do: [target | ready], else: ready
        {degrees, ready}
      end)

    visited_count(rest ++ Enum.reverse(ready), adjacency, indegrees, count + 1)
  end

  defp valid_node?(%ContentNode{
         identity: %SourceIdentity{},
         source_type: source_type,
         fields: fields,
         metadata: metadata
       })
       when is_binary(source_type) and source_type != "" and is_map(fields) and is_map(metadata),
       do: true

  defp valid_node?(_node), do: false

  defp valid_relationship?(%ContentRelationship{
         name: name,
         from: %SourceIdentity{},
         to: %SourceIdentity{},
         position: position,
         required: required,
         metadata: metadata
       })
       when is_binary(name) and name != "" and
              (is_nil(position) or (is_integer(position) and position >= 0)) and
              is_boolean(required) and is_map(metadata),
       do: true

  defp valid_relationship?(_relationship), do: false

  defp valid_asset?(%AssetDescriptor{
         source_key: source_key,
         variant_key: variant_key,
         field_path: field_path,
         filename: filename,
         media_type: media_type,
         size: size,
         checksum: checksum,
         required: required,
         retrieval: retrieval,
         metadata: metadata
       })
       when is_binary(source_key) and source_key != "" and is_binary(variant_key) and
              variant_key != "" and (is_nil(size) or (is_integer(size) and size >= 0)) and
              (is_nil(field_path) or is_binary(field_path)) and
              (is_nil(filename) or is_binary(filename)) and
              (is_nil(media_type) or is_binary(media_type)) and
              (is_nil(checksum) or is_binary(checksum)) and
              is_boolean(required) and is_map(retrieval) and is_map(metadata),
       do: valid_asset_path?(field_path)

  defp valid_asset?(_asset), do: false

  defp valid_asset_path?(nil), do: true

  defp valid_asset_path?("fields." <> path) do
    path != "" and
      path
      |> String.split(".")
      |> Enum.all?(&(&1 != ""))
  end

  defp valid_asset_path?(_path), do: false

  defp node_key(%ContentNode{identity: identity}), do: node_key(identity)
  defp node_key(%SourceIdentity{} = identity), do: SourceIdentity.logical_key(identity)

  defp safe_length(values) when is_list(values), do: length(values)
  defp safe_length(_values), do: 0

  defp fetch(attrs, key, default \\ nil),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
end

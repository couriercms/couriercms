defmodule CourierCMS.Mapping do
  @moduledoc "Applies declarative source-path to payload-path mappings."

  alias CourierCMS.ExtensionSDK.{AdapterError, ContentBundle}

  @path_pattern ~r/^[A-Za-z_][A-Za-z0-9_-]*(?:\.[A-Za-z_][A-Za-z0-9_-]*)*$/

  def parse(text) do
    lines =
      text
      |> to_string()
      |> String.split(~r/\R/, trim: false)
      |> Enum.with_index(1)
      |> Enum.reject(fn {line, _number} -> String.trim(line) == "" end)

    with {:ok, entries} <- parse_lines(lines),
         mapping <- Map.new(entries),
         :ok <- validate(mapping) do
      {:ok, mapping}
    end
  end

  def format(mapping) when is_map(mapping) do
    mapping
    |> Enum.sort()
    |> Enum.map_join("\n", fn {target, source} -> "#{target}=#{source}" end)
  end

  def validate(mapping) when is_map(mapping) and map_size(mapping) > 0 do
    with :ok <- validate_paths(mapping),
         :ok <- validate_target_conflicts(Map.keys(mapping)) do
      :ok
    end
  end

  def validate(_mapping), do: {:error, "Mapping must contain at least one field."}

  def apply(%ContentBundle{root: node}, mapping) when is_map(mapping) do
    source = %{
      "fields" => node.fields,
      "metadata" => node.metadata,
      "source_type" => node.source_type,
      "name" => node.name,
      "path" => node.path
    }

    with :ok <- mapping_result(validate(mapping)) do
      Enum.reduce_while(mapping, {:ok, %{}}, fn {target_path, source_path}, {:ok, payload} ->
        case fetch_path(source, source_path) do
          {:ok, value} ->
            {:cont, {:ok, put_path(payload, target_path, value)}}

          :error ->
            error = AdapterError.new(:mapping_failed, "Source field #{source_path} was not found")
            {:halt, {:error, error}}
        end
      end)
    end
  end

  defp parse_lines(lines) do
    Enum.reduce_while(lines, {:ok, [], MapSet.new()}, fn {line, number},
                                                         {:ok, entries, targets} ->
      case String.split(line, "=", parts: 2) do
        [target, source] ->
          target = String.trim(target)
          source = String.trim(source)

          cond do
            target == "" or source == "" ->
              {:halt, {:error, "Mapping line #{number} requires both target and source paths."}}

            MapSet.member?(targets, target) ->
              {:halt, {:error, "Mapping target #{target} is defined more than once."}}

            true ->
              {:cont, {:ok, [{target, source} | entries], MapSet.put(targets, target)}}
          end

        _other ->
          {:halt, {:error, "Mapping line #{number} must use target_path=source_path."}}
      end
    end)
    |> case do
      {:ok, entries, _targets} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp validate_paths(mapping) do
    Enum.reduce_while(mapping, :ok, fn {target, source}, :ok ->
      cond do
        not is_binary(target) or not Regex.match?(@path_pattern, target) ->
          {:halt, {:error, "Target path #{inspect(target)} is invalid."}}

        not is_binary(source) or not Regex.match?(@path_pattern, source) ->
          {:halt, {:error, "Source path #{inspect(source)} is invalid."}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp validate_target_conflicts(paths) do
    sorted = Enum.sort(paths)

    case Enum.find(sorted, fn path ->
           Enum.any?(sorted, &(&1 != path and String.starts_with?(&1, path <> ".")))
         end) do
      nil -> :ok
      path -> {:error, "Target path #{path} conflicts with a nested target path."}
    end
  end

  defp mapping_result(:ok), do: :ok
  defp mapping_result({:error, message}), do: {:error, AdapterError.new(:mapping_failed, message)}

  defp fetch_path(value, path) do
    path
    |> String.split(".", trim: true)
    |> Enum.reduce_while({:ok, value}, fn key, {:ok, current} ->
      case current do
        %{} ->
          if Map.has_key?(current, key),
            do: {:cont, {:ok, Map.fetch!(current, key)}},
            else: {:halt, :error}

        _ ->
          {:halt, :error}
      end
    end)
  end

  defp put_path(map, path, value) do
    keys = String.split(path, ".", trim: true)
    put_nested(map, keys, value)
  end

  defp put_nested(map, [key], value), do: Map.put(map, key, value)

  defp put_nested(map, [key | rest], value) do
    Map.put(map, key, put_nested(Map.get(map, key, %{}), rest, value))
  end
end

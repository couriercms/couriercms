defmodule CourierCMS.Execution.JobArgs do
  @moduledoc "Version gate for persisted Oban job arguments."

  @current 2
  @supported [1, 2]

  def current, do: @current
  def put(args) when is_map(args), do: Map.put(args, "v", @current)

  def validate(%{"v" => version}) when version in @supported, do: :ok
  def validate(args) when is_map(args) and not is_map_key(args, "v"), do: :ok
  def validate(_args), do: {:discard, "Unsupported CourierCMS job argument version"}
end

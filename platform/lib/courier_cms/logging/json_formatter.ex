defmodule CourierCMS.Logging.JSONFormatter do
  @moduledoc false

  def format(level, message, timestamp, metadata) do
    entry = %{
      timestamp: format_timestamp(timestamp),
      level: to_string(level),
      message: IO.chardata_to_string(message),
      metadata: Map.new(metadata, fn {key, value} -> {to_string(key), safe(value)} end)
    }

    [Jason.encode!(entry), ?\n]
  rescue
    _exception -> [inspect({level, message, metadata}), ?\n]
  end

  defp format_timestamp({date, {hour, minute, second, millisecond}}) do
    {year, month, day} = date

    :io_lib.format(
      ~c"~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B.~3..0BZ",
      [year, month, day, hour, minute, second, millisecond]
    )
    |> IO.iodata_to_binary()
  end

  defp safe(value) when is_binary(value) or is_number(value) or is_boolean(value), do: value
  defp safe(value) when is_atom(value), do: to_string(value)
  defp safe(value), do: inspect(value, limit: 20, printable_limit: 500)
end

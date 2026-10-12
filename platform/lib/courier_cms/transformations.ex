defmodule CourierCMS.Transformations do
  @moduledoc """
  Validates and applies ordered, deterministic built-in payload transformations.

  Route configuration contains identifiers and data only. It never contains
  executable source code.
  """

  alias CourierCMS.ExtensionSDK.AdapterError

  @version 1
  @maximum_transformations 25
  @path_pattern ~r/^[A-Za-z_][A-Za-z0-9_-]*(?:\.[A-Za-z_][A-Za-z0-9_-]*)*$/
  @operations ~w(string.trim string.lowercase string.slug datetime.iso8601 url.normalize)

  def operations, do: @operations

  def parse(text) do
    text
    |> to_string()
    |> String.split(~r/\R/, trim: false)
    |> Enum.with_index(1)
    |> Enum.reject(fn {line, _number} -> String.trim(line) == "" end)
    |> Enum.reduce_while({:ok, []}, fn {line, number}, {:ok, transformations} ->
      case parse_line(line, number) do
        {:ok, transformation} -> {:cont, {:ok, [transformation | transformations]}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
    |> case do
      {:ok, transformations} ->
        transformations = Enum.reverse(transformations)

        case validate(transformations) do
          :ok -> {:ok, transformations}
          {:error, message} -> {:error, message}
        end

      error ->
        error
    end
  end

  def format(transformations) when is_list(transformations) do
    Enum.map_join(transformations, "\n", fn transformation ->
      output_path = value(transformation, "output_path")
      input_path = value(transformation, "input_path")
      operation = value(transformation, "operation")
      "#{output_path}=#{input_path}|#{operation}"
    end)
  end

  def validate(transformations) when is_list(transformations) do
    cond do
      length(transformations) > @maximum_transformations ->
        {:error, "At most #{@maximum_transformations} transformations are allowed."}

      true ->
        transformations
        |> Enum.with_index(1)
        |> Enum.reduce_while(:ok, fn {transformation, index}, :ok ->
          case validate_transformation(transformation, index) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
        end)
    end
  end

  def validate(_transformations), do: {:error, "Transformations must be an ordered list."}

  def apply(payload, transformations) when is_map(payload) and is_list(transformations) do
    with :ok <- validation_result(validate(transformations)) do
      Enum.reduce_while(transformations, {:ok, payload}, fn transformation, {:ok, current} ->
        case apply_one(current, transformation) do
          {:ok, transformed} -> {:cont, {:ok, transformed}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end
  end

  def apply(_payload, _transformations),
    do: transformation_error("Transformation input must be a payload object")

  defp parse_line(line, number) do
    with [output_path, remainder] <- String.split(line, "=", parts: 2),
         [input_path, operation] <- String.split(remainder, "|", parts: 2),
         output_path <- String.trim(output_path),
         input_path <- String.trim(input_path),
         operation <- String.trim(operation),
         true <- output_path != "" and input_path != "" and operation != "" do
      {:ok,
       %{
         "kind" => "builtin",
         "operation" => operation,
         "version" => @version,
         "input_path" => input_path,
         "output_path" => output_path,
         "config" => %{}
       }}
    else
      _other ->
        {:error, "Transformation line #{number} must use output_path=input_path|operation."}
    end
  end

  defp validate_transformation(transformation, index) when is_map(transformation) do
    kind = value(transformation, "kind")
    operation = value(transformation, "operation")
    version = value(transformation, "version")
    input_path = value(transformation, "input_path")
    output_path = value(transformation, "output_path")
    config = value(transformation, "config")

    cond do
      kind != "builtin" ->
        {:error, "Transformation #{index} must be a built-in operation."}

      version != @version ->
        {:error, "Transformation #{index} uses an unsupported version."}

      operation not in @operations ->
        {:error, "Transformation #{index} uses unsupported operation #{inspect(operation)}."}

      not valid_path?(input_path) ->
        {:error, "Transformation #{index} has an invalid input path."}

      not valid_path?(output_path) ->
        {:error, "Transformation #{index} has an invalid output path."}

      config != %{} ->
        {:error, "Transformation #{index} does not accept configuration."}

      true ->
        :ok
    end
  end

  defp validate_transformation(_transformation, index),
    do: {:error, "Transformation #{index} must be an object."}

  defp apply_one(payload, transformation) do
    operation = value(transformation, "operation")
    input_path = value(transformation, "input_path")
    output_path = value(transformation, "output_path")

    with {:ok, input} <- fetch_path(payload, input_path),
         {:ok, output} <- transform(operation, input),
         {:ok, transformed} <- put_path(payload, output_path, output) do
      {:ok, transformed}
    else
      :error ->
        transformation_error(
          "Transformation #{operation} could not find input path #{input_path}"
        )

      {:error, :invalid_value} ->
        transformation_error("Transformation #{operation} rejected input path #{input_path}")

      {:error, :blocked_output_path} ->
        transformation_error(
          "Transformation #{operation} could not write output path #{output_path}"
        )
    end
  end

  defp transform("string.trim", value) when is_binary(value), do: {:ok, String.trim(value)}

  defp transform("string.lowercase", value) when is_binary(value),
    do: {:ok, String.downcase(value)}

  defp transform("string.slug", value) when is_binary(value) do
    slug =
      value
      |> String.normalize(:nfc)
      |> String.downcase()
      |> String.replace(~r/[^\p{L}\p{N}]+/u, "-")
      |> String.trim("-")

    {:ok, slug}
  end

  defp transform("datetime.iso8601", value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, DateTime.to_iso8601(datetime)}
      _other -> {:error, :invalid_value}
    end
  end

  defp transform("url.normalize", value) when is_binary(value) do
    with {:ok, uri} <- URI.new(String.trim(value)),
         true <- uri.scheme in ["http", "https"],
         true <- is_binary(uri.host) and uri.host != "",
         true <- is_nil(uri.userinfo) do
      {:ok,
       URI.to_string(%{
         uri
         | scheme: String.downcase(uri.scheme),
           host: String.downcase(uri.host)
       })}
    else
      _other -> {:error, :invalid_value}
    end
  end

  defp transform(_operation, _value), do: {:error, :invalid_value}

  defp fetch_path(value, path) do
    path
    |> String.split(".", trim: true)
    |> Enum.reduce_while({:ok, value}, fn key, {:ok, current} ->
      case current do
        %{} ->
          if Map.has_key?(current, key),
            do: {:cont, {:ok, Map.fetch!(current, key)}},
            else: {:halt, :error}

        _other ->
          {:halt, :error}
      end
    end)
  end

  defp put_path(map, path, value) do
    path
    |> String.split(".", trim: true)
    |> then(&put_nested(map, &1, value))
  end

  defp put_nested(map, [key], value), do: {:ok, Map.put(map, key, value)}

  defp put_nested(map, [key | rest], value) do
    case Map.get(map, key, %{}) do
      current when is_map(current) ->
        with {:ok, nested} <- put_nested(current, rest, value) do
          {:ok, Map.put(map, key, nested)}
        end

      _other ->
        {:error, :blocked_output_path}
    end
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, String.to_atom(key)))

  defp valid_path?(path),
    do: is_binary(path) and byte_size(path) <= 255 and Regex.match?(@path_pattern, path)

  defp validation_result(:ok), do: :ok
  defp validation_result({:error, message}), do: transformation_error(message)

  defp transformation_error(message),
    do: {:error, AdapterError.new(:transformation_failed, message)}
end

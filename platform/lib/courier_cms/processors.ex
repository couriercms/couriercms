defmodule CourierCMS.Processors do
  @moduledoc "Validates and executes ordered Extension Processor steps."

  alias CourierCMS.ExtensionSDK.AdapterError
  alias CourierCMS.Extensions.Gateway

  @maximum_processors 10
  @path_pattern ~r/^[A-Za-z_][A-Za-z0-9_-]*(?:\.[A-Za-z_][A-Za-z0-9_-]*)*$/
  @identity_pattern ~r/^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)+$/
  @component_pattern ~r/^[a-z][a-z0-9]*(?:[_-][a-z0-9]+)*$/

  def definitions, do: Gateway.processor_definitions()

  def parse(text) do
    text
    |> to_string()
    |> String.split(~r/\R/, trim: false)
    |> Enum.with_index(1)
    |> Enum.reject(fn {line, _number} -> String.trim(line) == "" end)
    |> Enum.reduce_while({:ok, []}, fn {line, number}, {:ok, processors} ->
      case parse_line(line, number) do
        {:ok, processor} -> {:cont, {:ok, [processor | processors]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, processors} -> processors |> Enum.reverse() |> prepare()
      error -> error
    end
  end

  def format(processors) when is_list(processors) do
    Enum.map_join(processors, "\n", fn processor ->
      reference = "#{value(processor, "extension_id")}/#{value(processor, "component_id")}"
      config = processor |> value("config") |> Jason.encode!()

      "#{value(processor, "output_path")}=#{value(processor, "input_path")}|#{reference}|#{config}"
    end)
  end

  def prepare(processors) when is_list(processors) do
    cond do
      length(processors) > @maximum_processors ->
        {:error, "At most #{@maximum_processors} Processors are allowed."}

      true ->
        processors
        |> Enum.with_index(1)
        |> Enum.reduce_while({:ok, []}, fn {processor, index}, {:ok, prepared} ->
          with {:ok, processor} <- prepare_one(processor, index) do
            {:cont, {:ok, [processor | prepared]}}
          else
            error -> {:halt, error}
          end
        end)
        |> case do
          {:ok, prepared} -> {:ok, Enum.reverse(prepared)}
          error -> error
        end
    end
  end

  def prepare(_processors), do: {:error, "Processors must be an ordered list."}

  def validate(processors) when is_list(processors) do
    cond do
      length(processors) > @maximum_processors ->
        {:error, "At most #{@maximum_processors} Processors are allowed."}

      true ->
        processors
        |> Enum.with_index(1)
        |> Enum.reduce_while(:ok, fn {processor, index}, :ok ->
          case validate_one(processor, index) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
        end)
    end
  end

  def validate(_processors), do: {:error, "Processors must be an ordered list."}

  def apply(payload, processors, artifacts \\ nil)

  def apply(payload, processors, artifacts), do: apply(payload, processors, artifacts, [])

  def apply(payload, processors, artifacts, opts) when is_list(processors) and is_list(opts) do
    observer = Keyword.get(opts, :observer, fn _event, _evidence -> :ok end)

    with :ok <- runtime_validation(validate(processors)),
         {:ok, artifacts} <- execution_artifacts(processors, artifacts) do
      processors
      |> Enum.zip(artifacts)
      |> Enum.with_index(1)
      |> Enum.reduce_while({:ok, payload}, fn {{processor, artifact}, position}, {:ok, current} ->
        case apply_one(current, processor, artifact, position, observer) do
          {:ok, transformed} -> {:cont, {:ok, transformed}}
          error -> {:halt, error}
        end
      end)
    end
  end

  def apply(_payload, _processors, _artifacts, _opts),
    do: processor_error(:transformation_failed, "Processor input must be valid payload data")

  defp parse_line(line, number) do
    with [output_path, remainder] <- String.split(line, "=", parts: 2),
         [input_path, reference, config_json] <- split_processor_parts(remainder),
         [extension_id, component_id] <- String.split(String.trim(reference), "/", parts: 2),
         {:ok, config} <- Jason.decode(String.trim(config_json)),
         true <- is_map(config) do
      {:ok,
       %{
         "kind" => "processor",
         "extension_id" => String.trim(extension_id),
         "component_id" => String.trim(component_id),
         "input_path" => String.trim(input_path),
         "output_path" => String.trim(output_path),
         "config" => config,
         "failure_policy" => "fail"
       }}
    else
      _other ->
        {:error,
         "Processor line #{number} must use output_path=input_path|extension_id/component_id|{JSON config}."}
    end
  end

  defp split_processor_parts(remainder) do
    case String.split(remainder, "|", parts: 3) do
      [input_path, reference] -> [input_path, reference, "{}"]
      parts -> parts
    end
  end

  defp prepare_one(processor, index) when is_map(processor) do
    reference = %{
      extension_id: value(processor, "extension_id"),
      component_id: value(processor, "component_id")
    }

    with {:ok, definition} <- fetch_definition(reference, index),
         prepared <-
           processor
           |> stringify_keys()
           |> Map.put("kind", "processor")
           |> Map.put("component_version", definition.version)
           |> Map.put_new("config", %{})
           |> Map.put_new("failure_policy", "fail"),
         :ok <- validate_one(prepared, index),
         :ok <- validate_config(reference, prepared["config"], index) do
      {:ok, prepared}
    end
  end

  defp prepare_one(_processor, index), do: {:error, "Processor #{index} must be an object."}

  defp fetch_definition(reference, index) do
    case Gateway.processor_definition(reference) do
      {:ok, definition} -> {:ok, definition}
      :error -> {:error, "Processor #{index} is not installed on this node."}
    end
  end

  defp validate_config(reference, config, index) do
    case Gateway.processor(reference, :validate_config, [config]) do
      :ok -> :ok
      {:error, %AdapterError{} = error} -> {:error, "Processor #{index}: #{error.message}"}
      _other -> {:error, "Processor #{index} rejected its configuration."}
    end
  rescue
    _exception -> {:error, "Processor #{index} could not validate its configuration."}
  catch
    _kind, _reason -> {:error, "Processor #{index} could not validate its configuration."}
  end

  defp validate_one(processor, index) when is_map(processor) do
    cond do
      value(processor, "kind") != "processor" ->
        {:error, "Processor #{index} has an invalid kind."}

      not valid_identity?(value(processor, "extension_id"), @identity_pattern) ->
        {:error, "Processor #{index} has an invalid Extension identifier."}

      not valid_identity?(value(processor, "component_id"), @component_pattern) ->
        {:error, "Processor #{index} has an invalid component identifier."}

      not valid_version?(value(processor, "component_version")) ->
        {:error, "Processor #{index} has an invalid component version."}

      not valid_path?(value(processor, "input_path")) ->
        {:error, "Processor #{index} has an invalid input path."}

      not valid_path?(value(processor, "output_path")) ->
        {:error, "Processor #{index} has an invalid output path."}

      not is_map(value(processor, "config")) ->
        {:error, "Processor #{index} configuration must be an object."}

      value(processor, "failure_policy") != "fail" ->
        {:error, "Processor #{index} must use the fail policy."}

      true ->
        :ok
    end
  end

  defp validate_one(_processor, index), do: {:error, "Processor #{index} must be an object."}

  defp execution_artifacts(processors, nil) do
    Enum.reduce_while(processors, {:ok, []}, fn processor, {:ok, artifacts} ->
      reference = reference(processor)

      with {:ok, artifact} <- Gateway.artifact(reference),
           true <- artifact["version"] == value(processor, "component_version"),
           {:ok, _reference} <- Gateway.validate_artifact(artifact, :processor) do
        {:cont, {:ok, [artifact | artifacts]}}
      else
        _other -> {:halt, unavailable_error()}
      end
    end)
    |> reverse_artifacts()
  end

  defp execution_artifacts(processors, artifacts) when is_list(artifacts) do
    if length(processors) == length(artifacts) do
      processors
      |> Enum.zip(artifacts)
      |> Enum.reduce_while({:ok, []}, fn {processor, artifact}, {:ok, validated} ->
        with {:ok, _reference} <- Gateway.validate_artifact(artifact, :processor),
             true <- artifact["extension_id"] == value(processor, "extension_id"),
             true <- artifact["component_id"] == value(processor, "component_id"),
             true <- artifact["version"] == value(processor, "component_version") do
          {:cont, {:ok, [artifact | validated]}}
        else
          _other -> {:halt, unavailable_error()}
        end
      end)
      |> reverse_artifacts()
    else
      unavailable_error()
    end
  end

  defp execution_artifacts(_processors, _artifacts), do: unavailable_error()
  defp reverse_artifacts({:ok, artifacts}), do: {:ok, Enum.reverse(artifacts)}
  defp reverse_artifacts(error), do: error

  defp apply_one(payload, processor, artifact, position, observer) do
    input_path = value(processor, "input_path")
    output_path = value(processor, "output_path")

    with {:ok, input} <- fetch_path(payload, input_path),
         :ok <- within_size_limit(input),
         {:ok, output} <- invoke(processor, artifact, input, position, observer),
         :ok <- within_size_limit(output),
         {:ok, transformed} <- put_path(payload, output_path, output) do
      {:ok, transformed}
    else
      :error ->
        processor_error(:transformation_failed, "Processor input path was not found")

      {:error, :too_large} ->
        processor_error(
          :invalid_content,
          "Processor input or output exceeded the configured limit"
        )

      {:error, :blocked_output_path} ->
        processor_error(:transformation_failed, "Processor output path could not be written")

      {:error, %AdapterError{} = error} ->
        {:error, %{error | message: "Processor #{processor_label(processor)}: #{error.message}"}}
    end
  end

  defp invoke(processor, artifact, input, position, observer) do
    reference = reference(processor)
    config = value(processor, "config")
    timeout = Application.fetch_env!(:couriercms, :processor_timeout_ms)
    caller = self()
    message_ref = make_ref()
    started_at = System.monotonic_time()
    input_bytes = encoded_size(input)
    input_hash = hash(input)

    evidence = %{
      position: position,
      extension_id: value(processor, "extension_id"),
      component_id: value(processor, "component_id"),
      component_version: artifact["version"],
      input_path: value(processor, "input_path"),
      output_path: value(processor, "output_path"),
      config_hash: hash(config),
      input_hash: input_hash,
      input_bytes: input_bytes,
      status: :processing,
      started_at: DateTime.utc_now()
    }

    with :ok <- observe(observer, :started, evidence) do
      invoke_monitored(
        processor,
        artifact,
        reference,
        input,
        config,
        timeout,
        caller,
        message_ref,
        started_at,
        input_bytes,
        input_hash,
        evidence,
        observer
      )
    end
  end

  defp invoke_monitored(
         processor,
         artifact,
         reference,
         input,
         config,
         timeout,
         caller,
         message_ref,
         started_at,
         input_bytes,
         input_hash,
         evidence,
         observer
       ) do
    {pid, monitor} =
      spawn_monitor(fn ->
        result = safe_process(reference, input, config)
        send(caller, {message_ref, result})
      end)

    result =
      receive do
        {^message_ref, result} ->
          Process.demonitor(monitor, [:flush])
          result

        {:DOWN, ^monitor, :process, ^pid, _reason} ->
          processor_error(:internal, "Processor execution failed", retryable: true)
      after
        timeout ->
          Process.exit(pid, :kill)

          receive do
            {:DOWN, ^monitor, :process, ^pid, _reason} -> :ok
          after
            100 -> :ok
          end

          processor_error(:timeout, "Processor execution timed out", retryable: true)
      end

    duration = System.monotonic_time() - started_at
    emit(processor, artifact, result, duration, input_bytes, input_hash)

    completed_evidence = complete_evidence(evidence, result, duration)

    case observe(observer, :finished, completed_evidence) do
      :ok -> result
      {:error, %AdapterError{} = error} -> {:error, error}
    end
  end

  defp complete_evidence(evidence, result, duration) do
    common = %{
      duration_us: System.convert_time_unit(duration, :native, :microsecond),
      completed_at: DateTime.utc_now()
    }

    case result do
      {:ok, output} ->
        evidence
        |> Map.merge(common)
        |> Map.merge(%{
          status: :succeeded,
          output_bytes: encoded_size(output),
          output_hash: hash(output),
          error_category: nil,
          error_summary: nil,
          retryable: false
        })

      {:error, %AdapterError{} = error} ->
        evidence
        |> Map.merge(common)
        |> Map.merge(%{
          status: :failed,
          output_bytes: nil,
          output_hash: nil,
          error_category: to_string(error.category),
          error_summary: error.message,
          retryable: error.retryable
        })
    end
  end

  defp observe(observer, event, evidence) when is_function(observer, 2) do
    case observer.(event, evidence) do
      :ok ->
        :ok

      {:error, %AdapterError{} = error} ->
        {:error, error}

      _other ->
        processor_error(:internal, "Processor execution evidence could not be recorded",
          retryable: true
        )
    end
  rescue
    _exception ->
      processor_error(:internal, "Processor execution evidence could not be recorded",
        retryable: true
      )
  catch
    _kind, _reason ->
      processor_error(:internal, "Processor execution evidence could not be recorded",
        retryable: true
      )
  end

  defp observe(_observer, _event, _evidence),
    do: processor_error(:internal, "Processor execution observer is invalid")

  defp safe_process(reference, input, config) do
    case Gateway.processor(reference, :process, [input, config]) do
      {:ok, output} ->
        {:ok, output}

      {:error, %AdapterError{} = error} ->
        {:error, error}

      _other ->
        processor_error(:internal, "Processor returned an invalid result")
    end
  rescue
    _exception -> processor_error(:internal, "Processor execution failed", retryable: true)
  catch
    _kind, _reason -> processor_error(:internal, "Processor execution failed", retryable: true)
  end

  defp emit(processor, artifact, result, duration, input_bytes, input_hash) do
    {status, output_bytes, output_hash, error_category, retryable} =
      case result do
        {:ok, output} ->
          {:ok, encoded_size(output), hash(output), nil, false}

        {:error, %AdapterError{} = error} ->
          {:error, 0, nil, error.category, error.retryable}
      end

    :telemetry.execute(
      [:couriercms, :processor, :execute],
      %{duration: duration, input_bytes: input_bytes, output_bytes: output_bytes},
      %{
        extension_id: value(processor, "extension_id"),
        component_id: value(processor, "component_id"),
        version: artifact["version"],
        config_hash: hash(value(processor, "config")),
        input_hash: input_hash,
        output_hash: output_hash,
        status: status,
        error_category: error_category,
        retryable: retryable
      }
    )
  end

  defp within_size_limit(value) do
    if encoded_size(value) <= Application.fetch_env!(:couriercms, :max_delivery_bytes),
      do: :ok,
      else: {:error, :too_large}
  end

  defp encoded_size(value) do
    case Jason.encode(value) do
      {:ok, encoded} -> byte_size(encoded)
      {:error, _reason} -> Application.fetch_env!(:couriercms, :max_delivery_bytes) + 1
    end
  end

  defp hash(value),
    do:
      value
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> then(&("sha256:" <> &1))

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

  defp put_path(map, path, value),
    do: path |> String.split(".", trim: true) |> put_nested(map, value)

  defp put_nested([key], map, value), do: {:ok, Map.put(map, key, value)}

  defp put_nested([key | rest], map, value) do
    case Map.get(map, key, %{}) do
      current when is_map(current) ->
        with {:ok, nested} <- put_nested(rest, current, value) do
          {:ok, Map.put(map, key, nested)}
        end

      _other ->
        {:error, :blocked_output_path}
    end
  end

  defp reference(processor) do
    %{
      extension_id: value(processor, "extension_id"),
      component_id: value(processor, "component_id")
    }
  end

  defp processor_label(processor),
    do: "#{value(processor, "extension_id")}/#{value(processor, "component_id")}"

  defp unavailable_error do
    processor_error(
      :unsupported,
      "The Route requires a Processor artifact that is not installed on this node"
    )
  end

  defp runtime_validation(:ok), do: :ok
  defp runtime_validation({:error, message}), do: processor_error(:unsupported, message)

  defp processor_error(category, message, opts \\ []),
    do: {:error, AdapterError.new(category, message, opts)}

  defp stringify_keys(map),
    do:
      Map.new(map, fn {key, value} ->
        {if(is_atom(key), do: Atom.to_string(key), else: key), value}
      end)

  defp value(map, key), do: Map.get(map, key, Map.get(map, String.to_atom(key)))
  defp valid_path?(path), do: valid_identity?(path, @path_pattern)

  defp valid_identity?(value, pattern),
    do: is_binary(value) and byte_size(value) <= 255 and Regex.match?(pattern, value)

  defp valid_version?(value) when is_binary(value), do: match?({:ok, _}, Version.parse(value))
  defp valid_version?(_value), do: false
end

defmodule CourierCMS.Deployment do
  @moduledoc """
  Builds role-specific runtime configuration for CourierCMS processes.

  All nodes keep an Oban instance so web nodes can insert jobs. Web nodes don't
  execute queues, while worker nodes can restrict the queues they consume.
  """

  @default_queues [route_planning: 2, delivery: 10, webhooks: 5, maintenance: 1]
  @queue_names Map.new(@default_queues, fn {name, _limit} -> {Atom.to_string(name), name} end)
  @scheduler_plugin {Oban.Plugins.Cron,
                     crontab: [
                       {"* * * * *", CourierCMS.Execution.ScheduleWorker, queue: :maintenance},
                       {"*/5 * * * *", CourierCMS.Execution.ReconcileWorker, queue: :maintenance},
                       {"17 2 * * *", CourierCMS.Execution.RetentionWorker, queue: :maintenance}
                     ]}

  @type role :: :all | :web | :worker

  @spec oban_options!(keyword(), role(), map()) :: keyword()
  def oban_options!(base_options, role, env \\ System.get_env())

  def oban_options!(base_options, :web, _env) do
    base_options
    |> Keyword.put(:queues, false)
    |> Keyword.put(:plugins, false)
  end

  def oban_options!(base_options, role, env) when role in [:all, :worker] do
    base_options
    |> Keyword.put(:queues, configured_queues!(base_options, env))
    |> Keyword.put(:plugins, configured_plugins!(base_options, role, env))
    |> configure_shutdown_grace_period!(env)
  end

  def oban_options!(_base_options, role, _env) do
    raise ArgumentError, "unsupported CourierCMS deployment role: #{inspect(role)}"
  end

  @spec parse_queues!(String.t()) :: keyword(pos_integer())
  def parse_queues!(value) when is_binary(value) do
    queues =
      value
      |> String.split(",", trim: true)
      |> Enum.map(&parse_queue!/1)

    if queues == [] do
      raise ArgumentError, "COURIERCMS_QUEUES must contain at least one queue"
    end

    if length(queues) != queues |> Keyword.keys() |> Enum.uniq() |> length() do
      raise ArgumentError, "COURIERCMS_QUEUES cannot contain duplicate queue names"
    end

    queues
  end

  defp configured_queues!(base_options, env) do
    case blank_to_nil(env["COURIERCMS_QUEUES"]) do
      nil -> Keyword.get(base_options, :queues, @default_queues)
      value -> parse_queues!(value)
    end
  end

  defp configured_plugins!(base_options, role, env) do
    plugins = Keyword.get(base_options, :plugins, false)

    case scheduler_enabled!(role, env["COURIERCMS_SCHEDULER_ENABLED"]) do
      :preserve -> plugins
      true -> enable_scheduler(plugins)
      false -> disable_scheduler(plugins)
    end
  end

  defp scheduler_enabled!(:all, nil), do: :preserve
  defp scheduler_enabled!(:worker, nil), do: false
  defp scheduler_enabled!(_role, value), do: parse_boolean!("COURIERCMS_SCHEDULER_ENABLED", value)

  defp enable_scheduler(false), do: [@scheduler_plugin]

  defp enable_scheduler(plugins) do
    [@scheduler_plugin | Enum.reject(plugins, &scheduler_plugin?/1)]
  end

  defp disable_scheduler(false), do: false

  defp disable_scheduler(plugins) do
    case Enum.reject(plugins, &scheduler_plugin?/1) do
      [] -> false
      remaining -> remaining
    end
  end

  defp scheduler_plugin?({Oban.Plugins.Cron, _options}), do: true
  defp scheduler_plugin?(Oban.Plugins.Cron), do: true
  defp scheduler_plugin?(_plugin), do: false

  defp configure_shutdown_grace_period!(options, env) do
    case blank_to_nil(env["COURIERCMS_SHUTDOWN_GRACE_PERIOD_MS"]) do
      nil -> options
      value -> Keyword.put(options, :shutdown_grace_period, parse_non_negative_integer!(value))
    end
  end

  defp parse_queue!(definition) do
    case definition |> String.trim() |> String.split(":", parts: 2) do
      [name, limit] ->
        queue =
          Map.get(@queue_names, String.trim(name)) ||
            raise ArgumentError,
                  "unsupported queue #{inspect(String.trim(name))}; expected one of #{Enum.join(Map.keys(@queue_names), ", ")}"

        {queue, parse_positive_integer!(String.trim(limit), "queue concurrency")}

      _other ->
        raise ArgumentError,
              "invalid COURIERCMS_QUEUES entry #{inspect(definition)}; expected queue:concurrency"
    end
  end

  defp parse_boolean!(_name, value) when value in [true, false], do: value

  defp parse_boolean!(name, value) do
    case value |> to_string() |> String.trim() |> String.downcase() do
      value when value in ["true", "1"] -> true
      value when value in ["false", "0"] -> false
      _other -> raise ArgumentError, "#{name} must be true or false"
    end
  end

  defp parse_positive_integer!(value, label) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _other -> raise ArgumentError, "#{label} must be a positive integer"
    end
  end

  defp parse_non_negative_integer!(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 ->
        integer

      _other ->
        raise ArgumentError, "COURIERCMS_SHUTDOWN_GRACE_PERIOD_MS must be a non-negative integer"
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)
end

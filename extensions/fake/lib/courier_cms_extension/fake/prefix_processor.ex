defmodule CourierCMSExtension.Fake.PrefixProcessor do
  @moduledoc "Development-only deterministic Processor used by contract tests."

  @behaviour CourierCMS.ExtensionSDK.Processor

  alias CourierCMS.ExtensionSDK.{AdapterError, Component}

  @impl true
  def component do
    Component.new!(
      extension_id: "com.couriercms.fake",
      component_id: "fake_prefix",
      kind: :processor,
      version: "0.1.0",
      capabilities: [:processor]
    )
  end

  @impl true
  def definition do
    %{
      label: "Fake prefix",
      description: "Adds a configured prefix to a string for development and contract tests.",
      config_fields: [
        %{
          key: :prefix,
          label: "Prefix",
          type: :text,
          default: "",
          description: "Text prepended to the input value."
        },
        %{
          key: :delay_ms,
          label: "Delay (milliseconds)",
          type: :integer,
          default: 0,
          description: "Development-only simulated processing delay from 0 to 1000 milliseconds."
        }
      ]
    }
  end

  @impl true
  def validate_config(config) when is_map(config) do
    prefix = Map.get(config, "prefix", "")
    delay_ms = Map.get(config, "delay_ms", 0)

    cond do
      not (is_binary(prefix) and byte_size(prefix) <= 100) ->
        {:error, AdapterError.new(:invalid_content, "prefix must be a short string")}

      not (is_integer(delay_ms) and delay_ms in 0..1_000) ->
        {:error, AdapterError.new(:invalid_content, "delay_ms must be between 0 and 1000")}

      true ->
        :ok
    end
  end

  def validate_config(_config),
    do: {:error, AdapterError.new(:invalid_content, "Processor configuration must be an object")}

  @impl true
  def process(value, config) when is_binary(value) do
    Process.sleep(Map.get(config, "delay_ms", 0))
    {:ok, Map.get(config, "prefix", "") <> value}
  end

  def process(_value, _config),
    do: {:error, AdapterError.new(:transformation_failed, "Fake prefix requires a string")}
end

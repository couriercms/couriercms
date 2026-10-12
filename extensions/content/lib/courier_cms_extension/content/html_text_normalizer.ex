defmodule CourierCMSExtension.Content.HtmlTextNormalizer do
  @moduledoc "Performs conservative text normalization without parsing or sanitizing HTML."

  @behaviour CourierCMS.ExtensionSDK.Processor

  alias CourierCMS.ExtensionSDK.{AdapterError, Component}

  @allowed_keys ~w(normalize_line_endings trim remove_control_characters replace_non_breaking_spaces)
  @control_characters ~r/[\x{0000}-\x{0008}\x{000B}\x{000C}\x{000E}-\x{001F}\x{007F}]/u

  @impl true
  def component do
    Component.new!(
      extension_id: "com.couriercms.content",
      component_id: "html_text_normalizer",
      kind: :processor,
      version: "0.1.0",
      capabilities: [:processor]
    )
  end

  @impl true
  def definition do
    %{
      label: "HTML text normalizer",
      description:
        "Normalizes text-level details in an HTML fragment without parsing, repairing, or sanitizing markup.",
      config_fields: [
        %{
          key: :normalize_line_endings,
          label: "Normalize line endings",
          type: :checkbox,
          default: true,
          description: "Convert CRLF and CR line endings to LF."
        },
        %{
          key: :remove_control_characters,
          label: "Remove control characters",
          type: :checkbox,
          default: true,
          description: "Remove non-printing ASCII controls while preserving tabs and newlines."
        },
        %{
          key: :replace_non_breaking_spaces,
          label: "Replace non-breaking spaces",
          type: :checkbox,
          default: false,
          description: "Replace Unicode non-breaking spaces with ordinary spaces."
        },
        %{
          key: :trim,
          label: "Trim surrounding whitespace",
          type: :checkbox,
          default: true,
          description: "Remove whitespace from the beginning and end of the value."
        }
      ]
    }
  end

  @impl true
  def validate_config(config) when is_map(config) do
    unknown_keys = Map.keys(config) -- @allowed_keys

    cond do
      unknown_keys != [] ->
        config_error("HTML text normalizer configuration contains unsupported options")

      Enum.any?(@allowed_keys, fn key ->
        Map.has_key?(config, key) and not is_boolean(config[key])
      end) ->
        config_error("HTML text normalizer options must be boolean")

      true ->
        :ok
    end
  end

  def validate_config(_config), do: config_error("Processor configuration must be an object")

  @impl true
  def process(value, config) when is_binary(value) do
    if String.valid?(value) do
      normalized =
        value
        |> maybe_normalize_line_endings(option(config, "normalize_line_endings", true))
        |> maybe_remove_control_characters(option(config, "remove_control_characters", true))
        |> maybe_replace_non_breaking_spaces(option(config, "replace_non_breaking_spaces", false))
        |> maybe_trim(option(config, "trim", true))

      {:ok, normalized}
    else
      processing_error("HTML text normalizer requires valid UTF-8 text")
    end
  end

  def process(_value, _config), do: processing_error("HTML text normalizer requires a string")

  defp option(config, key, default), do: Map.get(config, key, default)

  defp maybe_normalize_line_endings(value, true),
    do: value |> String.replace("\r\n", "\n") |> String.replace("\r", "\n")

  defp maybe_normalize_line_endings(value, false), do: value

  defp maybe_remove_control_characters(value, true),
    do: Regex.replace(@control_characters, value, "")

  defp maybe_remove_control_characters(value, false), do: value

  defp maybe_replace_non_breaking_spaces(value, true), do: String.replace(value, "\u00A0", " ")
  defp maybe_replace_non_breaking_spaces(value, false), do: value
  defp maybe_trim(value, true), do: String.trim(value)
  defp maybe_trim(value, false), do: value

  defp config_error(message), do: {:error, AdapterError.new(:invalid_content, message)}
  defp processing_error(message), do: {:error, AdapterError.new(:transformation_failed, message)}
end

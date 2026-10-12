defmodule CourierCMSExtension.Content.ExactTokenReplacer do
  @moduledoc "Replaces explicitly configured literal tokens in one deterministic pass."

  @behaviour CourierCMS.ExtensionSDK.Processor

  alias CourierCMS.ExtensionSDK.{AdapterError, Component}

  @maximum_replacements 50
  @maximum_token_bytes 500
  @maximum_replacement_bytes 10_000

  @impl true
  def component do
    Component.new!(
      extension_id: "com.couriercms.content",
      component_id: "exact_token_replacer",
      kind: :processor,
      version: "0.1.0",
      capabilities: [:processor]
    )
  end

  @impl true
  def definition do
    %{
      label: "Exact token replacer",
      description:
        "Replaces declared literal tokens, including known complete shortcode forms, without interpreting attributes or nesting.",
      config_fields: [
        %{
          key: :replacements,
          label: "Literal replacements",
          type: :json_object,
          required: true,
          default: %{},
          description:
            "A JSON object whose keys are exact tokens and values are their replacements."
        }
      ]
    }
  end

  @impl true
  def validate_config(%{"replacements" => replacements} = config) when is_map(replacements) do
    cond do
      Map.keys(config) != ["replacements"] ->
        config_error("Exact token replacer accepts only the replacements option")

      map_size(replacements) == 0 ->
        config_error("replacements must contain at least one literal token")

      map_size(replacements) > @maximum_replacements ->
        config_error("replacements may contain at most #{@maximum_replacements} tokens")

      Enum.any?(replacements, fn {token, replacement} ->
        not valid_token?(token) or not valid_replacement?(replacement)
      end) ->
        config_error("replacement tokens and values must be bounded strings")

      true ->
        :ok
    end
  end

  def validate_config(_config),
    do: config_error("Exact token replacer requires a replacements object")

  @impl true
  def process(value, %{"replacements" => replacements}) when is_binary(value) do
    if String.valid?(value) do
      pattern =
        replacements
        |> Map.keys()
        |> Enum.sort_by(&{-byte_size(&1), &1})
        |> Enum.map_join("|", &Regex.escape/1)
        |> Regex.compile!("u")

      {:ok, Regex.replace(pattern, value, &Map.fetch!(replacements, &1))}
    else
      processing_error("Exact token replacer requires valid UTF-8 text")
    end
  end

  def process(_value, _config), do: processing_error("Exact token replacer requires a string")

  defp valid_token?(token),
    do: is_binary(token) and byte_size(token) in 1..@maximum_token_bytes and String.valid?(token)

  defp valid_replacement?(replacement),
    do:
      is_binary(replacement) and byte_size(replacement) <= @maximum_replacement_bytes and
        String.valid?(replacement)

  defp config_error(message), do: {:error, AdapterError.new(:invalid_content, message)}
  defp processing_error(message), do: {:error, AdapterError.new(:transformation_failed, message)}
end

defmodule CourierCMS.ExtensionSDK.ProjectionDefinition do
  @moduledoc "Validation for target Projection definitions crossing the Extension boundary."

  @types ~w(string number boolean datetime)
  @field_pattern ~r/^[A-Za-z][A-Za-z0-9_]*$/

  def validate(definitions) when is_list(definitions) do
    with :ok <- validate_each(definitions),
         :ok <- validate_unique_fields(definitions) do
      :ok
    end
  end

  def validate(_definitions), do: {:error, "must be a list"}

  defp validate_each(definitions) do
    Enum.reduce_while(definitions, :ok, fn definition, :ok ->
      case validate_definition(definition) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_definition(
         %{"target_field" => field, "source_path" => path, "type" => type} = definition
       )
       when is_binary(field) and is_binary(path) and type in @types do
    cond do
      not Regex.match?(@field_pattern, field) ->
        {:error, "target field #{inspect(field)} is invalid"}

      not (String.starts_with?(path, "payload.") or String.starts_with?(path, "couriercms.")) ->
        {:error, "source path #{inspect(path)} must start with payload. or couriercms."}

      Map.has_key?(definition, "required") and not is_boolean(definition["required"]) ->
        {:error, "required must be true or false"}

      true ->
        :ok
    end
  end

  defp validate_definition(_definition),
    do: {:error, "each projection requires target_field, source_path, and a supported type"}

  defp validate_unique_fields(definitions) do
    fields = Enum.map(definitions, & &1["target_field"])
    if Enum.uniq(fields) == fields, do: :ok, else: {:error, "target fields must be unique"}
  end
end

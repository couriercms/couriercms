defmodule CourierCMSWeb.AdapterComponents do
  @moduledoc "Generic form controls rendered from built-in Adapter definitions."

  use Phoenix.Component

  attr :field, :map, required: true
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :disabled, :boolean, default: false

  def adapter_field(assigns) do
    ~H"""
    <input
      :if={Map.get(@field, :hidden, false)}
      type="hidden"
      name={@name}
      value={format_value(@value, @field.type)}
    />
    <label :if={!Map.get(@field, :hidden, false)} class="form-control">
      <span class="label-text text-sm font-medium">
        {@field.label}{if Map.get(@field, :required, false), do: " *", else: ""}
      </span>
      <select
        :if={@field.type == :select}
        name={@name}
        class="select select-bordered w-full"
        disabled={@disabled}
      >
        <option
          :for={{label, option} <- @field.options}
          value={option}
          selected={to_string(option) == to_string(@value)}
        >
          {label}
        </option>
      </select>
      <div :if={@field.type == :checkbox} class="mt-2 flex items-center gap-2">
        <input type="hidden" name={@name} value="false" />
        <input
          type="checkbox"
          name={@name}
          value="true"
          checked={@value in [true, "true", "1", "on"]}
          disabled={@disabled}
          class="checkbox checkbox-sm"
        />
      </div>
      <input
        :if={@field.type not in [:select, :checkbox]}
        type={html_type(@field.type)}
        name={@name}
        value={format_value(@value, @field.type)}
        placeholder={Map.get(@field, :placeholder)}
        autocomplete={Map.get(@field, :autocomplete)}
        disabled={@disabled}
        class="input input-bordered w-full"
      />
      <span :if={Map.get(@field, :help)} class="mt-1 text-xs text-base-content/55">
        {@field.help}
      </span>
    </label>
    """
  end

  defp html_type(:password), do: "password"
  defp html_type(:url), do: "url"
  defp html_type(:integer), do: "number"
  defp html_type(_type), do: "text"

  defp format_value(value, :list) when is_list(value), do: Enum.join(value, ", ")
  defp format_value(nil, _type), do: ""
  defp format_value(value, _type), do: value
end

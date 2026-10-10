defmodule CourierCMS.ExtensionSDK.SourceIdentity do
  @moduledoc "Normalized identity of one source item, locale, and observed revision."

  @enforce_keys [:item_key, :locale_key, :revision_key, :state]
  defstruct [:item_key, :locale_key, :revision_key, :state, :modified_at, :change_token]

  @type state :: :saved | :published
  @type t :: %__MODULE__{
          item_key: String.t(),
          locale_key: String.t(),
          revision_key: String.t(),
          state: state(),
          modified_at: DateTime.t() | nil,
          change_token: String.t() | nil
        }

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, keyword()}
  def new(attrs) do
    attrs = Map.new(attrs)

    errors =
      []
      |> require_string(:item_key, attrs)
      |> require_string(:locale_key, attrs)
      |> require_string(:revision_key, attrs)
      |> require_state(attrs)
      |> require_datetime(attrs)
      |> optional_string(:change_token, attrs)

    if errors == [] do
      {:ok,
       %__MODULE__{
         item_key: fetch(attrs, :item_key),
         locale_key: fetch(attrs, :locale_key),
         revision_key: fetch(attrs, :revision_key),
         state: fetch(attrs, :state),
         modified_at: fetch(attrs, :modified_at),
         change_token: fetch(attrs, :change_token)
       }}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  @spec delivery_key(t(), String.t()) :: String.t()
  def delivery_key(%__MODULE__{} = identity, route_id) when is_binary(route_id) do
    [route_id, identity.item_key, identity.locale_key]
    |> Enum.join(<<0>>)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

  defp require_string(errors, field, attrs) do
    case fetch(attrs, field) do
      value when is_binary(value) ->
        if String.trim(value) == "", do: [{field, "must not be empty"} | errors], else: errors

      _other ->
        [{field, "must be a string"} | errors]
    end
  end

  defp require_state(errors, attrs) do
    if fetch(attrs, :state) in [:saved, :published],
      do: errors,
      else: [{:state, "must be saved or published"} | errors]
  end

  defp require_datetime(errors, attrs) do
    case fetch(attrs, :modified_at) do
      nil -> errors
      %DateTime{} -> errors
      _other -> [{:modified_at, "must be a DateTime"} | errors]
    end
  end

  defp optional_string(errors, field, attrs) do
    case fetch(attrs, field) do
      nil ->
        errors

      value when is_binary(value) ->
        if String.trim(value) == "", do: [{field, "must not be empty"} | errors], else: errors

      _other ->
        [{field, "must be a string"} | errors]
    end
  end

  defp fetch(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end

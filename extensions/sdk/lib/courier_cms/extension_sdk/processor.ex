defmodule CourierCMS.ExtensionSDK.Processor do
  @moduledoc """
  Behaviour implemented by a bounded target-independent Processor component.

  `definition/0` may declare generic `config_fields` metadata using `:text`,
  `:integer`, `:checkbox`, and `:json_object` field types. CourierCMS uses that
  metadata only to build a guided editor; `validate_config/1` remains the
  authoritative component-owned validation boundary.

  Processor configuration is persisted in immutable Route Revisions and must
  never contain credentials or other secrets.
  """

  alias CourierCMS.ExtensionSDK.{Component, Types}

  @type config_field :: %{
          required(:key) => atom() | String.t(),
          required(:label) => String.t(),
          required(:type) => :text | :integer | :checkbox | :json_object,
          optional(:required) => boolean(),
          optional(:default) => term(),
          optional(:description) => String.t()
        }

  @type definition :: %{
          required(:label) => String.t(),
          required(:description) => String.t(),
          optional(:config_fields) => [config_field()]
        }

  @callback component() :: Component.t()
  @callback definition() :: definition()
  @callback validate_config(map()) :: :ok | {:error, Types.adapter_error()}
  @callback process(term(), map()) :: {:ok, term()} | {:error, Types.adapter_error()}
end

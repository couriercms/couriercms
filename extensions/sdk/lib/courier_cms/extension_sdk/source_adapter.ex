defmodule CourierCMS.ExtensionSDK.SourceAdapter do
  @moduledoc "Behaviour implemented by a source Adapter component."

  alias CourierCMS.ExtensionSDK.{Component, Types}

  @callback component() :: Component.t()
  @callback definition() :: map()
  @callback capabilities(Types.connection()) :: map()
  @callback test_connection(Types.connection()) :: :ok | {:error, Types.adapter_error()}
  @callback enumerate(Types.connection(), Types.selection(), Types.cursor() | nil) ::
              {:ok, %{items: [Types.normalized_identity()], cursor: Types.cursor() | nil}}
              | {:error, Types.adapter_error()}
  @callback changes_since(
              Types.connection(),
              Types.selection(),
              map(),
              Types.cursor() | nil
            ) ::
              {:ok, %{items: [Types.normalized_identity()], cursor: Types.cursor() | nil}}
              | {:error, Types.adapter_error()}
  @callback read_root(Types.connection(), Types.normalized_identity(), map()) ::
              {:ok, Types.normalized_content()} | {:error, Types.adapter_error()}

  @optional_callbacks changes_since: 4
end

defmodule CourierCMS.ExtensionSDK.Processor do
  @moduledoc "Behaviour implemented by a bounded target-independent Processor component."

  alias CourierCMS.ExtensionSDK.{Component, Types}

  @callback component() :: Component.t()
  @callback definition() :: map()
  @callback process(map(), map()) :: {:ok, map()} | {:error, Types.adapter_error()}
end
